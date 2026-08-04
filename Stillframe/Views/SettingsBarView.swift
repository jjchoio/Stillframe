//
//  SettingsBarView.swift
//  Stillframe
//

import AppKit
import SwiftUI

/// Export controls, pinned below the detail pane.
///
/// Batch progress and Cancel join this in milestone 7.
struct SettingsBarView: View {
    @Bindable var model: AppModel
    @FocusState private var customFieldFocused: Bool

    private var settings: ExportSettings { model.settings }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Centre alignment, not .firstTextBaseline: reconciling a segmented picker, a
            // slider and plain text by baseline shifts controls vertically as the row's
            // contents change. The fixed height then guarantees that showing or hiding the
            // quality slider can't resize the bar.
            HStack(spacing: 16) {
                intervalControl
                Divider().frame(height: 22)
                formatControl
                if settings.format.isLossy {
                    qualityControl
                }
                Spacer(minLength: 8)
            }
            .frame(height: 30)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()

            // Also pinned: the status area cycles through an estimate, a progress bar, a
            // success label and an error, and the bar must not jump as it does.
            HStack(spacing: 14) {
                folderControl
                Spacer(minLength: 8)
                status
                startButton
            }
            .frame(height: 32)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Interval

    private var intervalControl: some View {
        HStack(spacing: 8) {
            Text("Every")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

            Picker("Interval", selection: Bindable(settings).intervalPreset) {
                ForEach(IntervalPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if settings.intervalPreset == .custom {
                TextField("0.5", text: Bindable(settings).customIntervalText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .focused($customFieldFocused)
                    .overlay {
                        // A red ring is quieter than an alert but still unmissable, and the
                        // Start button is already disabled underneath it.
                        if !settings.isIntervalValid {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.red, lineWidth: 1.5)
                        }
                    }
                    .help(invalidIntervalHelp)

                Text("s")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.intervalPreset) { _, preset in
            customFieldFocused = preset == .custom
        }
    }

    private var invalidIntervalHelp: String {
        """
        Enter a number of seconds between \
        \(ExportSettings.minimumInterval.formatted()) and \
        \(Int(ExportSettings.maximumInterval)).
        """
    }

    // MARK: - Format

    private var formatControl: some View {
        HStack(spacing: 8) {
            Text("Format")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

            Picker("Format", selection: Bindable(settings).format) {
                ForEach(ImageFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var qualityControl: some View {
        HStack(spacing: 8) {
            Text("Quality")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

            Slider(value: Bindable(settings).jpegQuality, in: 0.1...1.0)
                .frame(width: 110)

            Text(settings.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    // MARK: - Output

    private var folderControl: some View {
        HStack(spacing: 8) {
            Text("Save to")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

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

    private var startButton: some View {
        Button(action: model.startExport) {
            Text("Start")
                .frame(minWidth: 54)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(.borderedProminent)
        .disabled(!model.canStartExport)
    }

    // MARK: - Status

    @ViewBuilder
    private var status: some View {
        switch model.exportStatus {
        case .idle:
            estimate

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
            // One line, with the full text in the tooltip — a long error must not grow the bar.
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(message)
        }
    }

    /// The promise the export has to keep — same helper the exporter counts with.
    @ViewBuilder
    private var estimate: some View {
        if !settings.isIntervalValid {
            Label("Enter an interval", systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let metadata = model.selectedItem?.metadata {
            Text("→ ^[\(model.plannedFrameCount) image](inflect: true) from \(metadata.durationText)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
