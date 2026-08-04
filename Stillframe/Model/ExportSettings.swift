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

/// The sampling interval, as offered in the UI.
enum IntervalPreset: String, CaseIterable, Codable, Sendable {
    case quarter
    case half
    case one
    case two
    case custom

    /// Seconds between frames, or nil for `.custom` (which reads the typed value instead).
    var seconds: Double? {
        switch self {
        case .quarter: 0.25
        case .half: 0.5
        case .one: 1
        case .two: 2
        case .custom: nil
        }
    }

    var label: String {
        switch self {
        case .quarter: "0.25s"
        case .half: "0.5s"
        case .one: "1s"
        case .two: "2s"
        case .custom: "Custom"
        }
    }
}

/// Settings that apply to the whole queue.
///
/// Crop and trim are deliberately *not* here — they belong to individual videos, because clips
/// differ in aspect ratio and length (see product.md).
@MainActor
@Observable
final class ExportSettings {
    /// Smallest and largest intervals we'll accept. The lower bound is a guard rail: 0.001 s on
    /// a one-minute clip is 60,000 files, which is almost never what someone meant to ask for.
    static let minimumInterval = 0.01
    static let maximumInterval = 3600.0

    var intervalPreset: IntervalPreset = .half {
        didSet { defaults.set(intervalPreset.rawValue, forKey: Keys.preset) }
    }

    /// Raw text of the custom field, kept as typed so a half-finished entry isn't clobbered.
    var customIntervalText: String = "0.5" {
        didSet { defaults.set(customIntervalText, forKey: Keys.customText) }
    }

    var format: ImageFormat = .jpg {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }

    /// 0.1…1.0, only meaningful for JPG.
    var jpegQuality: Double = 0.9 {
        didSet { defaults.set(jpegQuality, forKey: Keys.quality) }
    }

    /// Seconds between frames, or **nil when the custom field doesn't hold a usable number**.
    /// Callers must treat nil as "can't export yet" rather than substituting a default —
    /// silently exporting at some other interval than the one on screen is worse than refusing.
    var interval: Double? {
        if let preset = intervalPreset.seconds { return preset }
        return Self.parseInterval(customIntervalText)
    }

    var isIntervalValid: Bool { interval != nil }

    /// Parses a typed interval, tolerating the user's locale decimal separator.
    static func parseInterval(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var value = Double(trimmed)
        if value == nil {
            // "0,3" in locales that use a comma.
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            value = formatter.number(from: trimmed)?.doubleValue
        }

        guard let value, value.isFinite,
              value >= minimumInterval, value <= maximumInterval
        else { return nil }
        return value
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let preset = "exportIntervalPreset"
        static let customText = "exportCustomInterval"
        static let format = "exportFormat"
        static let quality = "exportJPEGQuality"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Keys.preset),
           let stored = IntervalPreset(rawValue: raw) {
            intervalPreset = stored
        }
        if let stored = defaults.string(forKey: Keys.customText) {
            customIntervalText = stored
        }
        if let raw = defaults.string(forKey: Keys.format), let stored = ImageFormat(rawValue: raw) {
            format = stored
        }
        if let stored = defaults.object(forKey: Keys.quality) as? Double {
            jpegQuality = min(max(stored, 0.1), 1.0)
        }
    }
}
