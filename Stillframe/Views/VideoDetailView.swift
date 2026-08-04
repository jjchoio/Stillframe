//
//  VideoDetailView.swift
//  Stillframe
//

import SwiftUI

/// Detail pane for the selected video: preview on top, file facts underneath.
///
/// Crop and trim controls join this pane in milestones 5 and 6.
struct VideoDetailView: View {
    let item: VideoItem
    let player: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            VideoPreviewView(item: item, player: player)

            Divider()
            CropControlsView(item: item)

            Divider()
            infoBar
        }
        .navigationTitle(item.displayName)
        .navigationSubtitle(item.metadata.map { "\($0.durationText) · \($0.resolutionText)" } ?? "")
    }

    private var infoBar: some View {
        HStack(spacing: 0) {
            fact("File", item.displayName)

            switch item.state {
            case .loading:
                Divider().frame(height: 26)
                fact("Status", "Loading…")

            case .ready(let metadata):
                Divider().frame(height: 26)
                fact("Duration", metadata.durationText)
                Divider().frame(height: 26)
                fact("Resolution", metadata.resolutionText)
                Divider().frame(height: 26)
                fact("Frame rate", metadata.frameRateText)

            case .failed(let message):
                Divider().frame(height: 26)
                fact("Status", message, tint: .orange)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fact(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.callout)
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
    }
}
