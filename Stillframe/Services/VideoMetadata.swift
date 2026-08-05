//
//  VideoMetadata.swift
//  Stillframe
//

import AVFoundation
import Foundation

/// Everything Stillframe needs to know about a video file up front.
///
/// `displaySize` is the single definition of *display space* for the whole app — see the
/// crop gotcha in CLAUDE.md. Nothing downstream should touch `naturalSize` directly.
struct VideoMetadata: Sendable, Equatable {
    let duration: CMTime

    /// Rotation-corrected size, i.e. how the video actually appears on screen.
    ///
    /// A portrait clip from a phone reports a landscape `naturalSize` and carries a 90°
    /// `preferredTransform`; only the two together give the truth. `AVAssetImageGenerator`
    /// with `appliesPreferredTrackTransform = true` produces images in *this* space, so
    /// preview geometry and crop math must use it too.
    let displaySize: CGSize

    let frameRate: Float

    var seconds: Double { duration.seconds }

    var resolutionText: String {
        "\(Int(displaySize.width.rounded()))×\(Int(displaySize.height.rounded()))"
    }

    var durationText: String { seconds.durationText }

    var frameRateText: String {
        frameRate > 0 ? String(format: "%.2f fps", frameRate) : "— fps"
    }
}

extension Double {
    /// A span of seconds: `21.7 s`, or `1:05.4` once past a minute.
    /// Used for both a clip's duration and a trimmed span, so the two always read alike.
    var durationText: String {
        guard isFinite, self >= 0 else { return "—" }
        if self < 60 { return String(format: "%.1f s", self) }
        let minutes = Int(self) / 60
        let remainder = self - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainder)
    }
}

enum VideoMetadataError: LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track in this file."
        }
    }
}

extension VideoMetadata {
    /// Loads metadata for `url`. Throws if the file can't be opened or has no video track.
    static func load(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoMetadataError.noVideoTrack
        }

        let (naturalSize, transform, frameRate) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate)

        // Rotation lives in the transform, so apply it and take magnitudes — a 90° rotation
        // produces negative components that would otherwise read as a negative size.
        let transformed = naturalSize.applying(transform)

        return VideoMetadata(
            duration: duration,
            displaySize: CGSize(width: abs(transformed.width), height: abs(transformed.height)),
            frameRate: frameRate)
    }
}
