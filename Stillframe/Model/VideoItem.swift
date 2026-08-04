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

    init(url: URL) {
        self.url = url
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
