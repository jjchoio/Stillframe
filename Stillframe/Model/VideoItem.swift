//
//  VideoItem.swift
//  Stillframe
//

import Foundation

/// One video in the queue.
///
/// Crop, trim, and export status arrive in later milestones; for now an item is a URL plus
/// whatever we've managed to learn about it.
@Observable
final class VideoItem: Identifiable {
    enum LoadState {
        case loading
        case ready(VideoMetadata)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var state: LoadState = .loading

    /// Where this video stands in the current export run.
    var exportStatus: ExportStatus = .pending

    /// The crop region, **normalized 0…1 with a top-left origin, in display space**.
    /// `nil` means export the full frame.
    ///
    /// Per-video, not global: clips in a queue differ in aspect ratio, so one shared rectangle
    /// would land somewhere different on each of them (see product.md).
    var cropRect: CGRect?

    /// Aspect constraint applied while dragging. Per-video for the same reason.
    var aspectLock: AspectLock = .free

    /// Start of the range to sample, in seconds.
    var trimStart: Double = 0

    /// End of the range, or nil meaning "to the end of the video".
    ///
    /// Stored as an override rather than eagerly set to the duration, so an item created before
    /// its metadata arrives doesn't get pinned to a bogus end of 0.
    var trimEndOverride: Double?

    var durationSeconds: Double { metadata?.seconds ?? 0 }

    /// End of the range to sample, always within the video.
    var trimEnd: Double {
        get { min(trimEndOverride ?? durationSeconds, durationSeconds) }
        set { trimEndOverride = newValue }
    }

    var trimDuration: Double { max(0, trimEnd - trimStart) }

    var isTrimmed: Bool {
        trimStart > 0.001 || trimEnd < durationSeconds - 0.001
    }

    func resetTrim() {
        trimStart = 0
        trimEndOverride = nil
    }

    /// Moves the start handle, keeping it inside the clip and at least `minimumSpan` before the
    /// end handle. Lives here rather than in the drag gesture so the rule is one definition and
    /// can be tested without driving the UI.
    /// - Returns: the value actually applied, for seeking the preview.
    @discardableResult
    func setTrimStart(_ seconds: Double, minimumSpan: Double) -> Double {
        let upperBound = max(trimEnd - minimumSpan, 0)
        trimStart = min(max(seconds, 0), upperBound)
        return trimStart
    }

    /// Moves the end handle, keeping it inside the clip and at least `minimumSpan` after the
    /// start handle.
    @discardableResult
    func setTrimEnd(_ seconds: Double, minimumSpan: Double) -> Double {
        let lowerBound = min(trimStart + minimumSpan, durationSeconds)
        trimEnd = min(max(seconds, lowerBound), durationSeconds)
        return trimEnd
    }

    var isCropEnabled: Bool { cropRect != nil }

    /// The crop in source pixels — what the export will actually cut.
    /// Computed by the same helper the exporter uses, so the readout can't lie.
    var cropPixelRect: CGRect? {
        guard let cropRect, let metadata else { return nil }
        return CropGeometry.pixelRect(normalized: cropRect, pixelSize: metadata.displaySize)
    }

    /// Whether we took a security-scoped claim on `url` that we owe a matching release.
    ///
    /// Held for the item's whole lifetime rather than per-operation: metadata loading,
    /// playback, and export all need to read the file, and a dropped URL's implicit sandbox
    /// extension is not something to re-derive at each use site.
    private let hasScopedAccess: Bool

    init(url: URL) {
        self.url = url
        // Returns false for URLs that don't need it (e.g. plain drag-and-drop, which arrives
        // with an implicit extension). Only balance the call when it actually succeeded.
        self.hasScopedAccess = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
    }

    /// Filename with extension, e.g. `test_landscape.mp4`.
    var displayName: String { url.lastPathComponent }

    /// Filename without extension — the basis for output folder and file names.
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    var metadata: VideoMetadata? {
        if case .ready(let metadata) = state { return metadata }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }
}
