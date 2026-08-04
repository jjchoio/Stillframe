//
//  VideoDetailView.swift
//  Stillframe
//

import SwiftUI

/// Detail pane for the selected video.
///
/// Milestone 1 shows metadata only — the player preview and the crop overlay land in
/// milestones 2 and 5.
struct VideoDetailView: View {
    let item: VideoItem

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 40, weight: .light))
                        Text("Preview arrives in milestone 2")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                row("File", item.displayName)

                switch item.state {
                case .loading:
                    row("Status", "Loading…")

                case .ready(let metadata):
                    row("Duration", metadata.durationText)
                    row("Resolution", metadata.resolutionText)
                    row("Frame rate", metadata.frameRateText)

                case .failed(let message):
                    row("Status", message, tint: .orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(item.displayName)
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .monospacedDigit()
        }
        .font(.callout)
    }
}
