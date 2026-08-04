// MakeTestAssets.swift
//
// Generates the deterministic test clips described in planning.md.
// Run from the repo root:   swift Tools/MakeTestAssets.swift
// Output lands in ./TestAssets (gitignored).
//
// NOTE: this file lives in Tools/, deliberately OUTSIDE the Stillframe/ folder.
// Stillframe/ is a file-system-synchronized Xcode group, so any .swift placed
// there is compiled into the app — a second @main would break the build.
//
// Each frame carries a burned-in timestamp so "the frame at 3.0 s really is the
// frame at 3.0 s" is verifiable by eye, plus corner labels so a crop region can
// be identified in an exported still.

import AVFoundation
import AppKit
import CoreText
import Foundation

// MARK: - Drawing

/// Draws one frame into `canvas`-sized logical space (CG default: origin bottom-left, y up).
func drawFrame(_ ctx: CGContext, canvas: CGSize, time: Double, frame: Int, label: String) {
    let w = canvas.width, h = canvas.height

    // Background shifts each second, so a wrong frame is obvious at a glance.
    let secondIndex = Int(floor(time))
    let shade = 0.10 + Double(secondIndex % 5) * 0.04
    ctx.setFillColor(CGColor(red: shade, green: shade, blue: shade + 0.03, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: canvas))

    // 10% grid — makes it easy to judge where a crop landed.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(max(1, w / 960))
    for i in 1..<10 {
        let x = w * CGFloat(i) / 10, y = h * CGFloat(i) / 10
        ctx.move(to: CGPoint(x: x, y: 0));  ctx.addLine(to: CGPoint(x: x, y: h))
        ctx.move(to: CGPoint(x: 0, y: y));  ctx.addLine(to: CGPoint(x: w, y: y))
    }
    ctx.strokePath()

    // A bar sweeping left→right over the clip: motion you can see between frames.
    let progress = CGFloat(time.truncatingRemainder(dividingBy: 2.0) / 2.0)
    ctx.setFillColor(CGColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 0.9))
    ctx.fill(CGRect(x: progress * (w - w / 12), y: h * 0.06, width: w / 12, height: h * 0.04))

    func draw(_ s: String, size: CGFloat, color: NSColor, at p: CGPoint, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        var origin = p
        if centered {
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            origin.x -= bounds.width / 2
            origin.y -= bounds.height / 2
        }
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }

    // The timestamp — the whole point of these clips.
    draw(String(format: "%.2f s", time), size: h * 0.14, color: .white,
         at: CGPoint(x: w / 2, y: h * 0.52), centered: true)
    draw("frame \(frame)", size: h * 0.045, color: NSColor(white: 0.75, alpha: 1),
         at: CGPoint(x: w / 2, y: h * 0.42), centered: true)
    draw(label, size: h * 0.035, color: NSColor(white: 0.55, alpha: 1),
         at: CGPoint(x: w / 2, y: h * 0.34), centered: true)

    // Corner markers: identify orientation and locate a crop in an exported still.
    let inset = min(w, h) * 0.03
    let corner = h * 0.05
    draw("TL", size: corner, color: .systemRed,    at: CGPoint(x: inset, y: h - inset - corner))
    draw("TR", size: corner, color: .systemGreen,  at: CGPoint(x: w - inset - corner * 1.6, y: h - inset - corner))
    draw("BL", size: corner, color: .systemYellow, at: CGPoint(x: inset, y: inset))
    draw("BR", size: corner, color: .systemPurple, at: CGPoint(x: w - inset - corner * 1.6, y: inset))
}

// MARK: - Writing

/// - Parameters:
///   - bufferSize: the encoded frame size (what `naturalSize` will report).
///   - rotated: when true, applies a 90° display transform and pre-rotates the drawing so it
///     still reads upright. This reproduces real portrait iPhone footage, where `naturalSize`
///     is landscape and only `preferredTransform` reveals the true orientation.
func makeVideo(url: URL, bufferSize: CGSize, seconds: Double, fps: Int, rotated: Bool) throws {
    try? FileManager.default.removeItem(at: url)

    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(bufferSize.width),
        AVVideoHeightKey: Int(bufferSize.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
    ])
    input.expectsMediaDataInRealTime = false
    if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(bufferSize.width),
            kCVPixelBufferHeightKey as String: Int(bufferSize.height),
        ])

    guard writer.canAdd(input) else { throw NSError(domain: "make", code: 1) }
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // The logical canvas we draw into: portrait when the display transform rotates it.
    let canvas = rotated ? CGSize(width: bufferSize.height, height: bufferSize.width) : bufferSize
    let label = rotated
        ? "buffer \(Int(bufferSize.width))x\(Int(bufferSize.height)) + 90 rotation"
        : "buffer \(Int(bufferSize.width))x\(Int(bufferSize.height))"

    let total = Int(seconds * Double(fps))
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    for frame in 0..<total {
        while !input.isReadyForMoreMediaData { usleep(2_000) }

        guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "make", code: 2) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { throw NSError(domain: "make", code: 3) }

        CVPixelBufferLockBaseAddress(buffer, [])
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(bufferSize.width), height: Int(bufferSize.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw NSError(domain: "make", code: 4) }

        if rotated {
            // The buffer must hold the display content pre-rotated so the player's
            // transform cancels it out. Note the sign: preferredTransform is applied in
            // video coordinate space (y down), while CGContext here is y up, so the
            // cancelling rotation is +90°, not −90°. Getting this backwards leaves the
            // content upside down — verified by eye, not by reasoning.
            //   (dx,dy) → (−dy + bufferWidth, dx)
            ctx.translateBy(x: bufferSize.width, y: 0)
            ctx.rotate(by: .pi / 2)
        }

        let t = Double(frame) / Double(fps)
        drawFrame(ctx, canvas: canvas, time: t, frame: frame, label: label)

        CVPixelBufferUnlockBaseAddress(buffer, [])

        let pts = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        if !adaptor.append(buffer, withPresentationTime: pts) {
            throw writer.error ?? NSError(domain: "make", code: 5)
        }
    }

    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()

    if writer.status != .completed { throw writer.error ?? NSError(domain: "make", code: 6) }
}

// MARK: - Main

let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("TestAssets")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

print("Writing test assets to \(out.path)")

print("  test_landscape.mp4  10s 1920x1080 @30fps")
try makeVideo(url: out.appendingPathComponent("test_landscape.mp4"),
              bufferSize: CGSize(width: 1920, height: 1080), seconds: 10, fps: 30, rotated: false)

print("  test_portrait.mp4   10s 1920x1080 buffer + 90 rotation -> displays 1080x1920")
try makeVideo(url: out.appendingPathComponent("test_portrait.mp4"),
              bufferSize: CGSize(width: 1920, height: 1080), seconds: 10, fps: 30, rotated: true)

print("  test_long.mp4       60s 1920x1080 @30fps")
try makeVideo(url: out.appendingPathComponent("test_long.mp4"),
              bufferSize: CGSize(width: 1920, height: 1080), seconds: 60, fps: 30, rotated: false)

// Truncating the tail removes the moov atom, so AVFoundation cannot open it —
// exactly the failure path the app has to survive.
print("  test_broken.mp4     truncated copy of test_landscape.mp4")
let good = try Data(contentsOf: out.appendingPathComponent("test_landscape.mp4"))
try good.prefix(50_000).write(to: out.appendingPathComponent("test_broken.mp4"))

print("Done.")
