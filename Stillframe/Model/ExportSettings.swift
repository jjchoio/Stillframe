//
//  ExportSettings.swift
//  Stillframe
//

import Foundation
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Codable, Sendable {
    case jpg
    case png

    var fileExtension: String { rawValue }
    var displayName: String { rawValue.uppercased() }

    var utType: UTType {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        }
    }

    var isLossy: Bool { self == .jpg }
}

/// Settings that apply to the whole queue.
///
/// Crop and trim are deliberately *not* here — they belong to individual videos, because clips
/// differ in aspect ratio and length (see product.md).
@MainActor
@Observable
final class ExportSettings {
    /// Seconds between sampled frames. The picker that exposes this arrives in milestone 4.
    var interval: Double = 0.5 {
        didSet { defaults.set(interval, forKey: Keys.interval) }
    }

    var format: ImageFormat = .jpg {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }

    /// 0.1…1.0, only meaningful for JPG.
    var jpegQuality: Double = 0.9 {
        didSet { defaults.set(jpegQuality, forKey: Keys.quality) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let interval = "exportInterval"
        static let format = "exportFormat"
        static let quality = "exportJPEGQuality"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.object(forKey: Keys.interval) as? Double, stored > 0 {
            interval = stored
        }
        if let raw = defaults.string(forKey: Keys.format), let stored = ImageFormat(rawValue: raw) {
            format = stored
        }
        if let stored = defaults.object(forKey: Keys.quality) as? Double {
            jpegQuality = min(max(stored, 0.1), 1.0)
        }
    }
}
