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
