//
//  TrimRangeSlider.swift
//  Stillframe
//

import SwiftUI

/// The timeline: playhead, scrubbing, and the two trim handles on one track.
///
/// Deliberately not a separate slider below the transport bar — a second timeline invites the
/// question of which one is "the" position. Dragging a handle seeks the preview to that time,
/// so you can see the frame you're cutting on rather than guessing from a number.
struct TrimRangeSlider: View {
    @Bindable var item: VideoItem
    let player: PlayerController
    /// Handles can't close nearer than this — one sampling interval, so a trimmed range always
    /// yields at least one frame.
    let minimumSpan: Double

    @State private var dragAnchor: Double?

    private let trackHeight: CGFloat = 6
    private let handleWidth: CGFloat = 9
    private let handleHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - handleWidth, 1)

            ZStack(alignment: .leading) {
                track(usable: usable)
                selectedSpan(usable: usable)
                playhead(usable: usable)
                handle(isStart: true, usable: usable)
                handle(isStart: false, usable: usable)
            }
            .frame(width: width, height: handleHeight)
        }
        .frame(height: handleHeight)
    }

    // MARK: - Geometry

    private var duration: Double { max(item.durationSeconds, 0.001) }

    /// Time → x, in a space inset by half a handle at each end so handles never overhang.
    private func x(for time: Double, usable: CGFloat) -> CGFloat {
        CGFloat(min(max(time / duration, 0), 1)) * usable + handleWidth / 2
    }

    private func time(forX position: CGFloat, usable: CGFloat) -> Double {
        let fraction = (position - handleWidth / 2) / usable
        return min(max(Double(fraction), 0), 1) * duration
    }

    // MARK: - Pieces

    private func track(usable: CGFloat) -> some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: trackHeight)
            .contentShape(Rectangle().inset(by: -8))
            // Clicking or dragging the bare track scrubs, matching a normal slider.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.seek(to: time(forX: value.location.x, usable: usable))
                    })
    }

    private func selectedSpan(usable: CGFloat) -> some View {
        let start = x(for: item.trimStart, usable: usable)
        let end = x(for: item.trimEnd, usable: usable)
        return Capsule()
            .fill(Color.accentColor.opacity(item.isTrimmed ? 0.85 : 0.55))
            .frame(width: max(end - start, 1), height: trackHeight)
            .offset(x: start)
            .allowsHitTesting(false)
    }

    /// A thin line with a cap on top — deliberately unlike the two filled trim handles, so at a
    /// glance you can tell the position marker from the range you're setting.
    private func playhead(usable: CGFloat) -> some View {
        let position = x(for: player.currentTime, usable: usable)
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(.primary)
                .frame(width: 1.5, height: handleHeight)
            Circle()
                .fill(.primary)
                .frame(width: 5, height: 5)
                .offset(y: -1)
        }
        .offset(x: position - 0.75)
        .allowsHitTesting(false)
    }

    private func handle(isStart: Bool, usable: CGFloat) -> some View {
        let time = isStart ? item.trimStart : item.trimEnd
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1))
            .frame(width: handleWidth, height: handleHeight)
            // Generous hit area so the handles win over the track's scrub gesture.
            .contentShape(Rectangle().inset(by: -7))
            .offset(x: x(for: time, usable: usable) - handleWidth / 2)
            .gesture(dragGesture(isStart: isStart, usable: usable))
            .help(isStart ? "Trim start" : "Trim end")
    }

    // MARK: - Dragging

    private func dragGesture(isStart: Bool, usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let anchor = dragAnchor ?? (isStart ? item.trimStart : item.trimEnd)
                if dragAnchor == nil { dragAnchor = anchor }

                let delta = Double(value.translation.width / usable) * duration
                let proposed = anchor + delta

                // The model owns the clamping rule, including "handles can't cross".
                let applied = isStart
                    ? item.setTrimStart(proposed, minimumSpan: minimumSpan)
                    : item.setTrimEnd(proposed, minimumSpan: minimumSpan)

                // Seek so the frame under the handle is visible while dragging.
                player.pause()
                player.seek(to: applied)
            }
            .onEnded { _ in dragAnchor = nil }
    }
}
