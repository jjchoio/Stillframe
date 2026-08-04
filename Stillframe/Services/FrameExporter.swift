//
//  FrameExporter.swift
//  Stillframe
//

import AVFoundation
import CoreGraphics
import Foundation

enum FrameExporterError: LocalizedError {
    case noVideoTrack
    case noFrames
    case cannotCreateFolder(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track in this file."
        case .noFrames: "The chosen interval produces no frames for this video."
        case .cannotCreateFolder(let reason): "Couldn't create the output folder. \(reason)"
        }
    }
}

/// Turns one video into a folder of stills.
///
/// An actor so decoding and encoding stay off the main thread; progress is reported back to the
/// main actor frame by frame.
actor FrameExporter {

    struct Request: Sendable {
        let url: URL
        let baseName: String
        let start: Double
        let end: Double
        let interval: Double
        /// Normalized 0…1, top-left origin, in display space. `nil` exports the full frame.
        let cropRect: CGRect?
        let format: ImageFormat
        let quality: Double
        /// The user-chosen parent folder; a per-video subfolder is created inside it.
        let destination: URL
    }

    struct Outcome: Sendable {
        let folder: URL
        let written: Int
        let requested: Int
        let wasCancelled: Bool
    }

    // MARK: - Sampling

    /// How many frames a range yields — **the only place this is computed.**
    ///
    /// Sampling is half-open: times run `start, start + interval, …` while `t < end`, so the
    /// closing boundary is never sampled. A 10 s video at 0.5 s gives 0.0…9.5 = 20 frames, not
    /// 21. See product.md for why.
    ///
    /// The epsilon matters: `(10.0 - 0.0) / 0.5` can land a hair above 20.0 in binary floating
    /// point, and a bare `ceil` would then quietly produce 21 files against a UI promising 20.
    static func frameCount(start: Double, end: Double, interval: Double) -> Int {
        guard interval > 0, end > start else { return 0 }
        let exact = (end - start) / interval
        return max(0, Int(ceil(exact - 1e-9)))
    }

    /// The sample times for a range, built from the same rule as `frameCount`.
    static func sampleTimes(start: Double, end: Double, interval: Double) -> [CMTime] {
        let count = frameCount(start: start, end: end, interval: interval)
        // Multiply rather than accumulate, so rounding error can't drift across a long clip.
        return (0..<count).map {
            CMTime(seconds: start + Double($0) * interval, preferredTimescale: 600)
        }
    }

    // MARK: - Export

    func export(
        _ request: Request,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> Outcome {
        let asset = AVURLAsset(url: request.url)
        guard try await asset.loadTracks(withMediaType: .video).first != nil else {
            throw FrameExporterError.noVideoTrack
        }

        let times = Self.sampleTimes(
            start: request.start, end: request.end, interval: request.interval)
        guard !times.isEmpty else { throw FrameExporterError.noFrames }

        let generator = AVAssetImageGenerator(asset: asset)
        // Produces display-oriented images, so a rotated clip exports upright.
        generator.appliesPreferredTrackTransform = true
        // Exact timestamps. Slower than tolerant sampling, and the entire premise of the app —
        // "one image per 0.5 second" has to mean it. Do not loosen.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let folder = try Self.makeUniqueFolder(
            in: request.destination, named: "\(request.baseName)_frames")

        // Wide enough for the count, never narrower than 4, so files sort correctly.
        let padding = max(4, String(times.count).count)

        var written = 0
        var wasCancelled = false

        for await result in generator.images(for: times) {
            if Task.isCancelled {
                wasCancelled = true
                generator.cancelAllCGImageGeneration()
                break
            }

            switch result {
            // Note the order: requestedTime comes first, then the image.
            case .success(requestedTime: let requestedTime, image: let image, actualTime: _):
                let index = Self.index(of: requestedTime, in: request) ?? written
                let name = "\(request.baseName)_\(String(format: "%0\(padding)d", index + 1))"
                    + ".\(request.format.fileExtension)"

                // The generated image is already display-oriented, so the normalized crop —
                // which was drawn in display space — maps straight onto its pixels.
                let output = Self.cropped(image, to: request.cropRect)

                try ImageWriter.write(
                    output,
                    to: folder.appendingPathComponent(name),
                    format: request.format,
                    quality: request.quality)
                written += 1

            case .failure(requestedTime: let requestedTime, error: let error):
                // One unreadable frame shouldn't discard an otherwise good export.
                print("Stillframe: skipped frame at \(requestedTime.seconds)s — \(error.localizedDescription)")

            @unknown default:
                break
            }

            await onProgress(written, times.count)
        }

        return Outcome(
            folder: folder, written: written, requested: times.count, wasCancelled: wasCancelled)
    }

    /// Cuts `normalized` out of `image`, or returns it untouched when there's no crop.
    ///
    /// The rect is denormalized against the image's **actual pixel dimensions**, not the
    /// metadata's — they agree, but reading them from the image itself removes any chance of a
    /// mismatch cropping the wrong region.
    static func cropped(_ image: CGImage, to normalized: CGRect?) -> CGImage {
        guard let normalized, !CropGeometry.isFullFrame(normalized) else { return image }

        let pixelSize = CGSize(width: image.width, height: image.height)
        let rect = CropGeometry.pixelRect(normalized: normalized, pixelSize: pixelSize)
        guard rect.width >= 1, rect.height >= 1 else { return image }

        // Fails only if the rect escapes the image, which pixelRect already prevents.
        return image.cropping(to: rect) ?? image
    }

    /// Recovers a frame's ordinal from its requested time, so numbering follows the timeline
    /// even if a frame in the middle fails.
    private static func index(of time: CMTime, in request: Request) -> Int? {
        guard request.interval > 0 else { return nil }
        let offset = time.seconds - request.start
        guard offset.isFinite, offset >= 0 else { return nil }
        return Int((offset / request.interval).rounded())
    }

    // MARK: - Output folder

    /// Creates `<parent>/<name>/`, appending " 2", " 3", … if that name is taken.
    /// A re-run must never silently overwrite a previous export.
    static func makeUniqueFolder(in parent: URL, named name: String) throws -> URL {
        let manager = FileManager.default
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2

        while manager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try manager.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            throw FrameExporterError.cannotCreateFolder(error.localizedDescription)
        }
        return candidate
    }
}
