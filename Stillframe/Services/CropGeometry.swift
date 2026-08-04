//
//  CropGeometry.swift
//  Stillframe
//

import CoreGraphics
import Foundation

/// Which part of the crop rectangle a drag is moving.
enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeftEdge: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRightEdge: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTopEdge: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottomEdge: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: true
        default: false
        }
    }

    /// Where the handle sits, as a unit position within the rect.
    var unitPoint: CGPoint {
        CGPoint(
            x: movesLeftEdge ? 0 : (movesRightEdge ? 1 : 0.5),
            y: movesTopEdge ? 0 : (movesBottomEdge ? 1 : 0.5))
    }
}

/// Aspect ratios the crop rectangle can be locked to.
enum AspectLock: String, CaseIterable, Codable, Sendable, Identifiable {
    case free, square, wide16x9, tall9x16, portrait4x5, classic4x3

    var id: String { rawValue }

    /// width ÷ height, or nil when unconstrained.
    var ratio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .wide16x9: 16.0 / 9.0
        case .tall9x16: 9.0 / 16.0
        case .portrait4x5: 4.0 / 5.0
        case .classic4x3: 4.0 / 3.0
        }
    }

    var label: String {
        switch self {
        case .free: "Free"
        case .square: "1:1"
        case .wide16x9: "16:9"
        case .tall9x16: "9:16"
        case .portrait4x5: "4:5"
        case .classic4x3: "4:3"
        }
    }
}

/// Conversions between the three spaces a crop rectangle lives in.
///
/// 1. **Normalized** — `0…1`, origin top-left, stored on the `VideoItem`. Survives window
///    resizing because it's relative to the video, not the screen.
/// 2. **Screen** — points inside the on-screen video rect. Where dragging happens.
/// 3. **Pixel** — the exported `CGImage`'s coordinates. Origin is top-left there too, which is
///    why normalized space uses that convention rather than Core Graphics' bottom-left.
///
/// Aspect-ratio work happens in *screen* space, never normalized: normalized space is
/// anisotropic (x and y have different scales unless the video is square), so a "1:1" rectangle
/// in normalized coordinates would not be square on screen or in the export.
enum CropGeometry {
    /// Smallest crop as a fraction of the frame, so a rectangle can't be dragged to nothing.
    static let minimumNormalizedExtent: CGFloat = 0.02

    /// The default rectangle when crop is switched on: centred, 80% of the frame.
    static let defaultRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    // MARK: - Space conversions

    static func screenRect(_ normalized: CGRect, in videoRect: CGRect) -> CGRect {
        CGRect(
            x: videoRect.minX + normalized.minX * videoRect.width,
            y: videoRect.minY + normalized.minY * videoRect.height,
            width: normalized.width * videoRect.width,
            height: normalized.height * videoRect.height)
    }

    static func normalizedRect(_ screen: CGRect, in videoRect: CGRect) -> CGRect {
        guard videoRect.width > 0, videoRect.height > 0 else { return defaultRect }
        return CGRect(
            x: (screen.minX - videoRect.minX) / videoRect.width,
            y: (screen.minY - videoRect.minY) / videoRect.height,
            width: screen.width / videoRect.width,
            height: screen.height / videoRect.height)
    }

    /// The pixel rectangle to cut from an exported frame.
    ///
    /// Rounds origin and size independently rather than using `.integral`, which expands to the
    /// *enclosing* integer rect and can turn a locked 1:1 selection into e.g. 1080×1081. The
    /// readout in the UI calls this same function, so what's on screen is what's on disk.
    static func pixelRect(normalized: CGRect, pixelSize: CGSize) -> CGRect {
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return .zero }

        var width = (normalized.width * pixelSize.width).rounded()
        var height = (normalized.height * pixelSize.height).rounded()
        width = min(max(width, 1), pixelSize.width)
        height = min(max(height, 1), pixelSize.height)

        var x = (normalized.minX * pixelSize.width).rounded()
        var y = (normalized.minY * pixelSize.height).rounded()
        // Shift back inside rather than shrinking, so a locked ratio survives the clamp.
        x = min(max(x, 0), pixelSize.width - width)
        y = min(max(y, 0), pixelSize.height - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether a normalized rect covers the whole frame (within rounding), i.e. crops nothing.
    static func isFullFrame(_ rect: CGRect) -> Bool {
        rect.minX <= 0.001 && rect.minY <= 0.001
            && rect.maxX >= 0.999 && rect.maxY >= 0.999
    }

    // MARK: - Dragging

    /// Moves `rect` by `translation`, keeping it entirely inside `bounds`.
    static func moved(_ rect: CGRect, by translation: CGSize, in bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: translation.width, dy: translation.height)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// Resizes `rect` by dragging `handle`, honouring an optional aspect ratio, never leaving
    /// `bounds`, and never collapsing below `minimumSize`.
    static func resized(
        _ rect: CGRect,
        handle: CropHandle,
        translation: CGSize,
        in bounds: CGRect,
        aspect: Double?,
        minimumSize: CGFloat
    ) -> CGRect {
        guard let aspect else {
            return resizedFreely(
                rect, handle: handle, translation: translation, in: bounds,
                minimumSize: minimumSize)
        }
        return resizedLocked(
            rect, handle: handle, translation: translation, in: bounds,
            aspect: aspect, minimumSize: minimumSize)
    }

    private static func resizedFreely(
        _ rect: CGRect, handle: CropHandle, translation: CGSize,
        in bounds: CGRect, minimumSize: CGFloat
    ) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX
        var minY = rect.minY, maxY = rect.maxY

        if handle.movesLeftEdge {
            minX = min(max(minX + translation.width, bounds.minX), maxX - minimumSize)
        }
        if handle.movesRightEdge {
            maxX = max(min(maxX + translation.width, bounds.maxX), minX + minimumSize)
        }
        if handle.movesTopEdge {
            minY = min(max(minY + translation.height, bounds.minY), maxY - minimumSize)
        }
        if handle.movesBottomEdge {
            maxY = max(min(maxY + translation.height, bounds.maxY), minY + minimumSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func resizedLocked(
        _ rect: CGRect, handle: CropHandle, translation: CGSize,
        in bounds: CGRect, aspect: Double, minimumSize: CGFloat
    ) -> CGRect {
        // The edge or corner that stays put while the opposite side follows the drag.
        let anchorX = handle.movesLeftEdge ? rect.maxX : rect.minX
        let anchorY = handle.movesTopEdge ? rect.maxY : rect.minY
        let growsRight = !handle.movesLeftEdge
        let growsDown = !handle.movesTopEdge

        // How far the anchor can extend before leaving the bounds.
        let availableWidth = growsRight ? bounds.maxX - anchorX : anchorX - bounds.minX
        let availableHeight = growsDown ? bounds.maxY - anchorY : anchorY - bounds.minY

        var width: CGFloat
        var height: CGFloat

        if handle.isCorner || !handle.movesTopEdge && !handle.movesBottomEdge {
            // Corners and the left/right edges are driven by the horizontal drag.
            let proposed = handle.movesLeftEdge
                ? rect.width - translation.width
                : rect.width + translation.width
            width = proposed
            height = width / aspect
        } else {
            // Top/bottom edges are driven by the vertical drag.
            let proposed = handle.movesTopEdge
                ? rect.height - translation.height
                : rect.height + translation.height
            height = proposed
            width = height * aspect
        }

        // Fit inside the available space without breaking the ratio.
        if width > availableWidth {
            width = availableWidth
            height = width / aspect
        }
        if height > availableHeight {
            height = availableHeight
            width = height * aspect
        }

        // Respect the minimum, still without breaking the ratio.
        if width < minimumSize {
            width = minimumSize
            height = width / aspect
        }
        if height < minimumSize {
            height = minimumSize
            width = height * aspect
        }
        // A minimum bump could have pushed it back outside; give up on the minimum, not bounds.
        width = min(width, max(availableWidth, 0))
        height = min(height, max(availableHeight, 0))

        var result = CGRect(
            x: growsRight ? anchorX : anchorX - width,
            y: growsDown ? anchorY : anchorY - height,
            width: width, height: height)

        // Edge handles keep the crop centred on the axis they don't control.
        if !handle.isCorner {
            if handle.movesLeftEdge || handle.movesRightEdge {
                result.origin.y = rect.midY - height / 2
            } else {
                result.origin.x = rect.midX - width / 2
            }
            result = moved(result, by: .zero, in: bounds)
        }

        return result
    }
}
