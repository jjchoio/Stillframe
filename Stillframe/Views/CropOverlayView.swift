//
//  CropOverlayView.swift
//  Stillframe
//

import SwiftUI

/// The draggable crop rectangle, drawn over the video.
///
/// Positioned from the same `videoRect` that sizes the player view, so the selection and the
/// frame it selects cannot drift apart. All dragging happens in screen points and is converted
/// back to normalized coordinates on release — which is what lets the rectangle stay put on the
/// image when the window is resized.
struct CropOverlayView: View {
    @Bindable var item: VideoItem
    /// The video's on-screen rect, in the coordinate space of this overlay's parent.
    let videoRect: CGRect

    /// Rect being dragged, in screen points. Non-nil only for the duration of a gesture.
    @State private var liveRect: CGRect?
    /// Where the current gesture started, so translations apply to a stable base.
    @State private var gestureStartRect: CGRect?

    private let handleVisualSize: CGFloat = 10
    private let handleHitSize: CGFloat = 24
    private let minimumScreenSize: CGFloat = 24

    private var screenRect: CGRect {
        liveRect ?? CropGeometry.screenRect(item.cropRect ?? CropGeometry.defaultRect, in: videoRect)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimming
            border
            thirdsGuides
            handles
        }
        .animation(nil, value: screenRect)
    }

    // MARK: - Chrome

    private var dimming: some View {
        // Even-odd fill punches the selection out of the dim layer in one pass.
        CutoutShape(hole: screenRect)
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
    }

    private var border: some View {
        Rectangle()
            .strokeBorder(.white, lineWidth: 1.5)
            .frame(width: screenRect.width, height: screenRect.height)
            .offset(x: screenRect.minX, y: screenRect.minY)
            .contentShape(Rectangle())
            .gesture(moveGesture)
    }

    /// Rule-of-thirds guides — cheap to draw and genuinely useful for framing.
    private var thirdsGuides: some View {
        Path { path in
            for i in 1...2 {
                let x = screenRect.minX + screenRect.width * CGFloat(i) / 3
                let y = screenRect.minY + screenRect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: screenRect.minY))
                path.addLine(to: CGPoint(x: x, y: screenRect.maxY))
                path.move(to: CGPoint(x: screenRect.minX, y: y))
                path.addLine(to: CGPoint(x: screenRect.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.35), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private var handles: some View {
        ForEach(CropHandle.allCases, id: \.self) { handle in
            let point = position(of: handle)
            Rectangle()
                .fill(.white)
                .frame(width: handleVisualSize, height: handleVisualSize)
                .shadow(radius: 1)
                // Hit area is larger than the dot, and sits above the move gesture in the
                // ZStack, so grabbing a corner never starts a move by accident.
                .frame(width: handleHitSize, height: handleHitSize)
                .contentShape(Rectangle())
                .position(x: point.x, y: point.y)
                .gesture(resizeGesture(for: handle))
        }
    }

    private func position(of handle: CropHandle) -> CGPoint {
        let unit = handle.unitPoint
        return CGPoint(
            x: screenRect.minX + screenRect.width * unit.x,
            y: screenRect.minY + screenRect.height * unit.y)
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = gestureStartRect ?? screenRect
                if gestureStartRect == nil { gestureStartRect = base }
                liveRect = CropGeometry.moved(base, by: value.translation, in: videoRect)
            }
            .onEnded { _ in commit() }
    }

    private func resizeGesture(for handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = gestureStartRect ?? screenRect
                if gestureStartRect == nil { gestureStartRect = base }
                liveRect = CropGeometry.resized(
                    base,
                    handle: handle,
                    translation: value.translation,
                    in: videoRect,
                    aspect: item.aspectLock.ratio,
                    minimumSize: minimumScreenSize)
            }
            .onEnded { _ in commit() }
    }

    /// Converts the dragged rect back to normalized storage and ends the gesture.
    private func commit() {
        if let liveRect {
            item.cropRect = CropGeometry.normalizedRect(liveRect, in: videoRect)
        }
        liveRect = nil
        gestureStartRect = nil
    }
}

/// A rect with a rectangular hole, for even-odd filling.
private struct CutoutShape: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(hole)
        return path
    }
}
