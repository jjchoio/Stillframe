//
//  DropZoneView.swift
//  Stillframe
//

import SwiftUI

/// Full-window empty state: the app's front door.
struct DropZoneView: View {
    let isTargeted: Bool
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isTargeted ? "square.and.arrow.down.fill" : "film.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 6) {
                Text(isTargeted ? "Drop to add" : "Drop videos here")
                    .font(.title2.weight(.medium))
                Text("MP4, MOV, and M4V")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Add Videos…", action: onBrowse)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [10, 7]))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear))
                .padding(24)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

#Preview("Idle") {
    DropZoneView(isTargeted: false, onBrowse: {})
        .frame(width: 900, height: 600)
}

#Preview("Targeted") {
    DropZoneView(isTargeted: true, onBrowse: {})
        .frame(width: 900, height: 600)
}
