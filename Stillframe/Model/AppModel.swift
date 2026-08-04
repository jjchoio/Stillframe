//
//  AppModel.swift
//  Stillframe
//

import Foundation
import UniformTypeIdentifiers

/// Owns the queue and the selection. Media work lives in `Services/`.
@MainActor
@Observable
final class AppModel {
    private(set) var items: [VideoItem] = []
    var selection: VideoItem.ID?

    let settings = ExportSettings()
    let outputFolder = OutputFolderStore()

    private(set) var isExporting = false

    /// Result of the last completed run, for the summary and Reveal in Finder.
    private(set) var lastRun: RunSummary?

    /// Set when a run couldn't start at all (no output folder, folder gone).
    private(set) var startupError: String?

    @ObservationIgnored private var exportTask: Task<Void, Never>?

    struct RunSummary {
        var imageCount: Int
        var folders: [URL]
        var failedCount: Int
        var wasCancelled: Bool
    }

    var selectedItem: VideoItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    // MARK: - Accepted files

    /// Types we actually accept, deliberately narrower than `UTType.movie`.
    ///
    /// `.mkv`, `.avi` and `.webm` all conform to `public.movie`, but AVFoundation can't open
    /// them — a `.movie` check would let them into the queue only to fail on load. An
    /// allowlist refuses them at the drop instead, which is what the user expects to see.
    private static let acceptedTypes: [UTType] = {
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType("com.apple.m4v-video") { types.append(m4v) }
        return types
    }()

    /// File types offered by the "Add Videos…" panel.
    static var importerTypes: [UTType] { acceptedTypes }

    static func isAcceptedVideo(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return acceptedTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Queue

    /// Adds every accepted video among `urls`, skipping duplicates.
    /// - Returns: `true` if at least one file was accepted, so a drop can be refused cleanly.
    @discardableResult
    func add(urls: [URL]) -> Bool {
        let candidates = urls.filter(Self.isAcceptedVideo)
        guard !candidates.isEmpty else { return false }

        var newItems: [VideoItem] = []
        for url in candidates where !items.contains(where: { $0.url == url }) {
            let item = VideoItem(url: url)
            items.append(item)
            newItems.append(item)
        }

        if selection == nil { selection = items.first?.id }
        for item in newItems { loadMetadata(for: item) }

        return true
    }

    func remove(ids: Set<VideoItem.ID>) {
        guard !ids.isEmpty else { return }

        // Keep a sensible selection: fall to the item that slides into the first removed slot.
        let firstRemovedIndex = items.firstIndex { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }

        if let selection, ids.contains(selection) {
            if let index = firstRemovedIndex, !items.isEmpty {
                self.selection = items[min(index, items.count - 1)].id
            } else {
                self.selection = items.first?.id
            }
        }
    }

    func removeSelected() {
        guard let selection else { return }
        remove(ids: [selection])
    }

    // MARK: - Export

    /// Frames `item` will produce with the current settings.
    /// Reads the same helper the exporter uses, so the estimate can't disagree with the result.
    func plannedFrameCount(for item: VideoItem) -> Int {
        guard item.metadata != nil, let interval = settings.interval else { return 0 }
        // Trim boundaries, not the whole clip — the estimate must reflect what Start will do.
        return FrameExporter.frameCount(
            start: item.trimStart, end: item.trimEnd, interval: interval)
    }

    var plannedFrameCount: Int {
        guard let selectedItem else { return 0 }
        return plannedFrameCount(for: selectedItem)
    }

    /// Frames the whole queue will produce.
    var queuedFrameCount: Int {
        items.reduce(0) { $0 + plannedFrameCount(for: $1) }
    }

    var completedFrameCount: Int {
        items.reduce(0) { $0 + $1.exportStatus.completedCount }
    }

    var exportableItems: [VideoItem] {
        items.filter { $0.metadata != nil }
    }

    var canStartExport: Bool {
        !exportableItems.isEmpty && settings.isIntervalValid && !isExporting
    }

    // MARK: Running the queue

    /// Exports every video in the queue, one after another.
    ///
    /// Sequential on purpose: `images(for:)` already parallelizes internally, so running clips
    /// concurrently would compete for the same decoders while making progress illegible and
    /// memory use spiky.
    func startExport() {
        guard !isExporting, settings.isIntervalValid else { return }

        startupError = nil
        lastRun = nil

        // Prompt rather than fail when there's nowhere to write yet.
        if outputFolder.folder == nil, outputFolder.choose() == nil { return }
        guard let destination = outputFolder.folder else { return }

        guard outputFolder.isWritable else {
            startupError = "Can't write to \(destination.lastPathComponent). Choose it again."
            return
        }

        for item in items { item.exportStatus = .pending }
        isExporting = true

        exportTask = Task { [weak self] in
            await self?.runQueue(destination: destination)
        }
    }

    private func runQueue(destination: URL) async {
        let exporter = FrameExporter()
        var summary = RunSummary(imageCount: 0, folders: [], failedCount: 0, wasCancelled: false)

        // Taking the next pending item each pass rather than iterating a snapshot means a video
        // dropped mid-run joins the same run instead of sitting there looking queued.
        while let item = items.first(where: { $0.exportStatus.isPending }) {
            if Task.isCancelled { break }

            guard item.metadata != nil, let interval = settings.interval else {
                item.exportStatus = .failed(item.failureMessage ?? "Couldn't read this video.")
                summary.failedCount += 1
                continue
            }

            let total = plannedFrameCount(for: item)
            guard total > 0 else {
                item.exportStatus = .failed("This interval produces no frames for this video.")
                summary.failedCount += 1
                continue
            }

            item.exportStatus = .exporting(done: 0, total: total)

            let request = FrameExporter.Request(
                url: item.url,
                baseName: item.baseName,
                start: item.trimStart,
                end: item.trimEnd,
                interval: interval,
                cropRect: item.cropRect,
                format: settings.format,
                quality: settings.jpegQuality,
                destination: destination)

            do {
                let outcome = try await exporter.export(request) { done, total in
                    item.exportStatus = .exporting(done: done, total: total)
                }

                if outcome.wasCancelled {
                    item.exportStatus = .cancelled(partial: outcome.written)
                    summary.imageCount += outcome.written
                    summary.wasCancelled = true
                    break
                }

                item.exportStatus = .finished(count: outcome.written, folder: outcome.folder)
                summary.imageCount += outcome.written
                summary.folders.append(outcome.folder)
            } catch is CancellationError {
                item.exportStatus = .cancelled(partial: 0)
                summary.wasCancelled = true
                break
            } catch {
                // One bad video must not take the rest of the queue down with it.
                item.exportStatus = .failed(error.localizedDescription)
                summary.failedCount += 1
            }
        }

        if Task.isCancelled { summary.wasCancelled = true }
        lastRun = summary
        isExporting = false
        exportTask = nil
    }

    /// Stops between frames. Everything already written stays on disk.
    func cancelExport() {
        exportTask?.cancel()
    }

    /// Clears the queue and returns to the drop zone.
    func startOver() {
        items.removeAll()
        selection = nil
        lastRun = nil
        startupError = nil
    }

    /// Every folder this run produced, for Reveal in Finder.
    var revealTargets: [URL] {
        let folders = items.compactMap { $0.exportStatus.folder }
        return folders.isEmpty ? (outputFolder.folder.map { [$0] } ?? []) : folders
    }

    // MARK: - Loading

    private func loadMetadata(for item: VideoItem) {
        Task { [weak item] in
            guard let item else { return }
            // The security-scoped claim is held by VideoItem for its whole lifetime.
            do {
                item.state = .ready(try await VideoMetadata.load(url: item.url))
            } catch {
                item.state = .failed(error.localizedDescription)
            }
        }
    }
}
