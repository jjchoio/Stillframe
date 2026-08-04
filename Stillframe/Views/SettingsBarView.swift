//
//  SettingsBarView.swift
//  Stillframe
//

import AppKit
import SwiftUI

/// Export controls, pinned below the detail pane.
///
/// Milestone 3 shows the output folder and Start. The interval picker, format, and quality
/// slider join it in milestone 4; batch progress and Cancel in milestone 7.
struct SettingsBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 14) {
                folderControl

                Spacer(minLength: 8)

                status

                Button(action: model.startExport) {
                    Text("Start")
                        .frame(minWidth: 54)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartExport)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Pieces

    private var folderControl: some View {
        HStack(spacing: 8) {
            Text("Save to")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                model.outputFolder.choose()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(model.outputFolder.folder?.lastPathComponent ?? "Choose…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .help(model.outputFolder.folder?.path ?? "Choose an output folder")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.exportStatus {
        case .idle:
            if model.plannedFrameCount > 0 {
                Text("^[\(model.plannedFrameCount) image](inflect: true)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .running(let done, let total):
            HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 130)
                Text("\(done)/\(total)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

        case .finished(let count, let folder):
            HStack(spacing: 8) {
                Label("^[\(count) image](inflect: true)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .buttonStyle(.link)
            }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .help(message)
        }
    }
}
