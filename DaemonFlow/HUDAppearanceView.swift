//
//  HUDAppearanceView.swift
//  DaemonFlow
//
//  Size and colour controls for the floating pill, with live previews of
//  all three states above the sliders — the numbers alone don't tell you
//  whether a given size or palette reads well above the Dock.
//

import SwiftUI

struct HUDAppearanceView: View {
    var onClose: (() -> Void)?

    @EnvironmentObject private var settings: HUDSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                previewStrip
                sliders
                colors
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pill appearance")
                    .font(Theme.Font.headerTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("The pill morphs between two sizes — the transcript size is derived from the active one — and carries its own colours.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.cardSurface, in: Circle())
                        .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// All three states side by side and live — changing a slider morphs
    /// these with the same animation the real pill uses, so the feel of
    /// the transition is part of what you're adjusting.
    private var previewStrip: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 28) {
                preview(label: "Resting", state: .idle)
                preview(label: "Speaking", state: .recording)
                preview(label: "Transcribing", state: .processing)
            }
            .frame(maxWidth: .infinity)

            preview(label: "With live transcript", state: .recording, liveText: "this is roughly what a line and a half of live dictation looks like")
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func preview(label: String, state: HUDState, liveText: String = "") -> some View {
        VStack(spacing: 10) {
            HUDPreviewPill(appearance: settings.appearance, state: state, liveText: liveText)
            Text(label)
                .font(Theme.Font.monoLabel)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Resting")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Reset sizes") {
                    settings.resetSizes()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(settings.areSizesDefault ? Theme.textSecondary.opacity(0.5) : Theme.accent)
                .disabled(settings.areSizesDefault)
            }

            slider("Width", value: $settings.appearance.restingWidth, range: HUDAppearance.restingWidthRange)
            slider("Height", value: $settings.appearance.restingHeight, range: HUDAppearance.restingHeightRange)

            Divider().overlay(Theme.cardBorder)

            Text("Active")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            slider("Width", value: $settings.appearance.activeWidth, range: HUDAppearance.activeWidthRange)
            slider("Height", value: $settings.appearance.activeHeight, range: HUDAppearance.activeHeightRange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    /// The outline is drawn in every state, so it gets two colours rather
    /// than a toggle: one for the resting sliver, one for when the pill is
    /// actually doing something. Set both the same for a single fixed
    /// outline; set the width to 0 to drop it entirely.
    private var colors: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Colours")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Reset colours") {
                    settings.resetColors()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(settings.areColorsDefault ? Theme.textSecondary.opacity(0.5) : Theme.accent)
                .disabled(settings.areColorsDefault)
            }

            colorRow("Background", value: $settings.appearance.backgroundColor)
            colorRow("Waveform", value: $settings.appearance.waveformColor)

            Divider().overlay(Theme.cardBorder)

            Text("Border")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            colorRow("Active", value: $settings.appearance.borderColor)
            colorRow("Resting", value: $settings.appearance.restingBorderColor)
            slider("Width", value: $settings.appearance.borderWidth, range: HUDAppearance.borderWidthRange, step: 0.5, unit: "pt")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func colorRow(_ title: String, value: Binding<HUDColor>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 88, alignment: .leading)

            // Opacity is part of the picker rather than a separate slider:
            // the background is translucent by default, and splitting the
            // two would let them drift apart.
            ColorPicker(
                "",
                selection: Binding(
                    get: { value.wrappedValue.color },
                    set: { value.wrappedValue = HUDColor($0) }
                ),
                supportsOpacity: true
            )
            .labelsHidden()

            Spacer()
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        unit: String = "pt"
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 88, alignment: .leading)

            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)

            Text(step < 1
                 ? String(format: "%.1f %@", value.wrappedValue, unit)
                 : "\(Int(value.wrappedValue)) \(unit)")
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// Wraps `HUDPill` with its own throwaway model. The real pill is driven
/// by AppState through a shared HUDModel; a preview needs to pin one state
/// and fake the mic, so it gets a model of its own.
private struct HUDPreviewPill: View {
    let appearance: HUDAppearance
    let state: HUDState
    let liveText: String

    @StateObject private var model = HUDModel()

    var body: some View {
        HUDPill(model: model, level: { Float.random(in: 0.15...0.95) })
            .onAppear { sync() }
            .onChange(of: appearance) { _, _ in sync() }
            .onChange(of: state) { _, _ in sync() }
    }

    private func sync() {
        model.appearance = appearance
        model.state = state
        model.liveText = liveText
    }
}
