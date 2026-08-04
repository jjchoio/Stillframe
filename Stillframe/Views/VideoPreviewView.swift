//
//  VideoPreviewView.swift
//  Stillframe
//

import AVFoundation
import SwiftUI

/// The video preview plus its transport controls.
///
/// The important part is `videoRect(displaySize:in:)`. It is the single definition of *where
/// the video actually is* inside the pane, and both the player and every future overlay are
/// positioned from it — so the crop rectangle in milestone 5 cannot drift away from the frame
/// it is supposed to be selecting.
struct VideoPreviewView: View {
    let item: VideoItem
    let player: PlayerController
    /// One sampling interval — the closest the trim handles may approach each other, so a
    /// trimmed range always yields at least one frame.
    let minimumTrimSpan: Double

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let container = CGRect(origin: .zero, size: geo.size)
                let rect = Self.videoRect(displaySize: item.metadata?.displaySize, in: container)

                ZStack(alignment: .topLeading) {
                    Color.black

                    if let rect {
                        PlayerLayerView(player: player.player)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)

                        // Same rect, same GeometryReader — the selection and the frame it
                        // selects are positioned from one source.
                        if item.isCropEnabled {
                            CropOverlayView(item: item, videoRect: rect)
                        }
                    } else {
                        placeholder
                            .frame(width: container.width, height: container.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            transportBar
        }
        .onChange(of: item.id, initial: true) {
            player.load(item)
            if let seconds = item.metadata?.seconds { player.updateDuration(seconds) }
        }
        .onChange(of: item.metadata) { _, metadata in
            // Metadata usually lands after the item is already showing.
            if let metadata { player.updateDuration(metadata.seconds) }
        }
        .onDisappear { player.pause() }
    }

    // MARK: - Geometry

    /// The rect the video occupies inside `container`, honouring its aspect ratio.
    ///
    /// `AVMakeRect` performs exactly the fit that `.resizeAspect` does, so sizing the player
    /// view to this rect leaves the layer nothing to letterbox.
    static func videoRect(displaySize: CGSize?, in container: CGRect) -> CGRect? {
        guard let displaySize,
              displaySize.width > 0, displaySize.height > 0,
              container.width > 0, container.height > 0
        else { return nil }
        return AVMakeRect(aspectRatio: displaySize, insideRect: container)
    }

    // MARK: - Pieces

    private var placeholder: some View {
        VStack(spacing: 10) {
            switch item.state {
            case .loading:
                ProgressView()
                Text("Reading video…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
            case .ready:
                EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding()
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .disabled(item.metadata == nil)
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isPlaying ? "Pause" : "Play")

            Text(player.currentTime.playbackTimeText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            TrimRangeSlider(item: item, player: player, minimumSpan: minimumTrimSpan)
                .disabled(item.metadata == nil)

            trimReadout

            Button(action: player.toggleMute) {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(player.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help(player.isMuted ? "Unmute preview (⇧⌘M)" : "Mute preview (⇧⌘M)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(height: 42)
        .background(.bar)
    }

    /// Shows the trimmed range in place of the duration once it's been narrowed, with a way
    /// back to the whole clip.
    @ViewBuilder
    private var trimReadout: some View {
        if item.isTrimmed {
            HStack(spacing: 4) {
                Text("\(item.trimStart.trimTimeText)–\(item.trimEnd.trimTimeText)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)

                Button {
                    item.resetTrim()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Use the whole video")
            }
            .fixedSize()
        } else {
            Text(player.duration.playbackTimeText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
