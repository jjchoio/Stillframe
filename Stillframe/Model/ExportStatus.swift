//
//  ExportStatus.swift
//  Stillframe
//

import Foundation

/// Where one video stands in an export run.
///
/// Per-item rather than per-app: a batch needs to show three different things at once, and a
/// failure has to be attributable to the video that caused it.
enum ExportStatus {
    case pending
    case exporting(done: Int, total: Int)
    case finished(count: Int, folder: URL)
    case failed(String)
    /// Stopped part-way. The frames already written stay on disk.
    case cancelled(partial: Int)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
    }

    /// Frames written so far, for the overall progress bar.
    var completedCount: Int {
        switch self {
        case .pending, .failed: 0
        case .exporting(let done, _): done
        case .finished(let count, _): count
        case .cancelled(let partial): partial
        }
    }

    var folder: URL? {
        if case .finished(_, let folder) = self { return folder }
        return nil
    }

    /// Short text for a queue row.
    var rowSummary: String? {
        switch self {
        case .pending: nil
        case .exporting(let done, let total): "\(done)/\(total)"
        case .finished(let count, _): "^[\(count) image](inflect: true)"
        case .failed(let message): message
        case .cancelled(let partial): "Cancelled at \(partial)"
        }
    }
}
