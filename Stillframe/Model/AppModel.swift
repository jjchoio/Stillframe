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

    /// Where the current (or last) export stands. Milestone 7 makes this per-item for batches.
    private(set) var exportStatus: ExportStatus = .idle

    @ObservationIgnored private var exportTask: Task<Void, Never>?

    enum ExportStatus {
        case idle
        case running(done: Int, total: Int)
        case finished(count: Int, folder: URL)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
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

    /// Frames the selected video will produce with the current settings.
    /// Reads the same helper the exporter uses, so the estimate can't disagree with the result.
    var plannedFrameCount: Int {
        guard let metadata = selectedItem?.metadata else { return 0 }
        return FrameExporter.frameCount(
            start: 0, end: metadata.seconds, interval: settings.interval)
    }

    var canStartExport: Bool {
        selectedItem?.metadata != nil && !exportStatus.isRunning
    }

    /// Exports the selected video. Milestone 7 turns this into a queue.
    func startExport() {
        guard let item = selectedItem, let metadata = item.metadata else { return }

        // Prompt rather than fail when there's nowhere to write yet.
        if outputFolder.folder == nil, outputFolder.choose() == nil { return }
        guard let destination = outputFolder.folder else { return }

        guard outputFolder.isWritable else {
            exportStatus = .failed(
                "Can't write to \(destination.lastPathComponent). Choose the folder again.")
            return
        }

        let request = FrameExporter.Request(
            url: item.url,
            baseName: item.baseName,
            start: 0,
            end: metadata.seconds,
            interval: settings.interval,
            format: settings.format,
            quality: settings.jpegQuality,
            destination: destination)

        exportStatus = .running(done: 0, total: FrameExporter.frameCount(
            start: 0, end: metadata.seconds, interval: settings.interval))

        exportTask = Task { [weak self] in
            let exporter = FrameExporter()
            do {
                let outcome = try await exporter.export(request) { done, total in
                    self?.exportStatus = .running(done: done, total: total)
                }
                self?.exportStatus = .finished(count: outcome.written, folder: outcome.folder)
            } catch {
                self?.exportStatus = .failed(error.localizedDescription)
            }
        }
    }

    func clearExportStatus() {
        exportStatus = .idle
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
