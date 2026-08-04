//
//  QueueSidebarView.swift
//  Stillframe
//

import SwiftUI

/// The queue of dropped videos.
struct QueueSidebarView: View {
    @Bindable var model: AppModel
    let onBrowse: () -> Void

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                QueueRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            model.remove(ids: [item.id])
                        }
                    }
            }
        }
        .onDeleteCommand(perform: model.removeSelected)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button(action: onBrowse) {
                    Label("Add", systemImage: "plus")
                }
                .help("Add videos…")

                Button(action: model.removeSelected) {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(model.selection == nil)
                .help("Remove the selected video")

                Spacer()

                Text("^[\(model.items.count) video](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private struct QueueRow: View {
    let item: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.middle)

            switch item.state {
            case .loading:
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .ready(let metadata):
                Text("\(metadata.durationText) · \(metadata.resolutionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}
