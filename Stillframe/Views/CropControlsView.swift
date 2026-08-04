//
//  CropControlsView.swift
//  Stillframe
//

import SwiftUI

/// Crop toggle, aspect lock, pixel readout, and reset — the row under the preview.
struct CropControlsView: View {
    @Bindable var item: VideoItem

    var body: some View {
        HStack(spacing: 14) {
            Toggle("Crop", isOn: cropEnabled)
                .toggleStyle(.checkbox)
                .disabled(item.metadata == nil)
                .fixedSize()

            if item.isCropEnabled {
                Picker("Aspect", selection: $item.aspectLock) {
                    ForEach(AspectLock.allCases) { lock in
                        Text(lock.label).tag(lock)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: item.aspectLock) { _, lock in
                    applyAspect(lock)
                }

                readout

                Button("Reset") {
                    item.cropRect = CropGeometry.defaultRect
                }
                .help("Reset the crop to the full frame")
            }

            Spacer(minLength: 0)
        }
        // Fixed height so toggling crop on and off can't resize the pane.
        .frame(height: 26)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var cropEnabled: Binding<Bool> {
        Binding(
            get: { item.isCropEnabled },
            set: { isOn in
                item.cropRect = isOn ? CropGeometry.defaultRect : nil
                if isOn { applyAspect(item.aspectLock) }
            })
    }

    /// Source-pixel readout — the numbers the export will actually use, from the same helper.
    @ViewBuilder
    private var readout: some View {
        if let pixels = item.cropPixelRect {
            Text(String(
                format: "%d×%d @ (%d, %d)",
                Int(pixels.width), Int(pixels.height), Int(pixels.minX), Int(pixels.minY)))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Re-shapes the current selection to a newly chosen ratio, keeping it centred and inside
    /// the frame. Without this, switching to 1:1 would leave a rectangle that isn't square
    /// until the user happens to drag a handle.
    private func applyAspect(_ lock: AspectLock) {
        guard let ratio = lock.ratio,
              let metadata = item.metadata,
              let current = item.cropRect
        else { return }

        // Ratios are defined in pixels, so convert through the frame's real dimensions.
        let frame = metadata.displaySize
        let widthPx = current.width * frame.width
        let heightPx = current.height * frame.height

        // Keep the area roughly the same rather than snapping to one dimension.
        var newWidthPx = (widthPx * heightPx * ratio).squareRoot()
        var newHeightPx = newWidthPx / ratio

        if newWidthPx > frame.width {
            newWidthPx = frame.width
            newHeightPx = newWidthPx / ratio
        }
        if newHeightPx > frame.height {
            newHeightPx = frame.height
            newWidthPx = newHeightPx * ratio
        }

        let width = newWidthPx / frame.width
        let height = newHeightPx / frame.height
        let x = min(max(current.midX - width / 2, 0), 1 - width)
        let y = min(max(current.midY - height / 2, 0), 1 - height)

        item.cropRect = CGRect(x: x, y: y, width: width, height: height)
    }
}
