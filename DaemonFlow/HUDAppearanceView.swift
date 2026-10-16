//
//  HUDAppearanceView.swift
//  DaemonFlow
//
//  Size and colour controls for the floating pill, with live previews of
//  every state above the controls — the numbers alone don't tell you
//  whether a given size or palette reads well above the Dock.
//

import SwiftUI

struct HUDAppearanceView: View {
    @EnvironmentObject private var settings: HUDSettingsStore

    var body: some View {
        Form {
            Section {
                previews
            }

            Section {
                Toggle("Always show the pill", isOn: $settings.alwaysVisible)
            } footer: {
                Text("Keeps a thin bar above the Dock between dictations. It grows into the waveform when you start speaking.")
            }

            Section {
                slider("Resting width", value: $settings.appearance.restingWidth, range: HUDAppearance.restingWidthRange)
                slider("Resting height", value: $settings.appearance.restingHeight, range: HUDAppearance.restingHeightRange)
                slider("Active width", value: $settings.appearance.activeWidth, range: HUDAppearance.activeWidthRange)
                slider("Active height", value: $settings.appearance.activeHeight, range: HUDAppearance.activeHeightRange)
            } header: {
                sectionHeader("Size", resetDisabled: settings.areSizesDefault, reset: settings.resetSizes)
            } footer: {
                Text("The transcript size is derived from the active one.")
            }

            // The outline is drawn in every state, so it gets two colours
            // rather than a toggle: one for the resting sliver, one for when
            // the pill is doing something. Set the width to 0 to drop it.
            Section {
                colorPicker("Background", value: $settings.appearance.backgroundColor)
                colorPicker("Waveform", value: $settings.appearance.waveformColor)
                colorPicker("Border while active", value: $settings.appearance.borderColor)
                colorPicker("Border while resting", value: $settings.appearance.restingBorderColor)
                slider("Border width", value: $settings.appearance.borderWidth, range: HUDAppearance.borderWidthRange, step: 0.5)
            } header: {
                sectionHeader("Colors", resetDisabled: settings.areColorsDefault, reset: settings.resetColors)
            }
        }
        .formStyle(.grouped)
    }

    /// Every state side by side and live — changing a control morphs these
    /// with the same animation the real pill uses, so the feel of the
    /// transition is part of what's being adjusted.
    private var previews: some View {
        VStack(spacing: 20) {
            HStack(alignment: .bottom, spacing: 32) {
                preview("Resting", state: .idle)
                preview("Listening", state: .recording)
                preview("Transcribing", state: .processing)
            }
            preview("Live transcript", state: .recording, liveText: "this is roughly what a line and a half of live dictation looks like")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func preview(_ label: String, state: HUDState, liveText: String = "") -> some View {
        VStack(spacing: 8) {
            HUDPreviewPill(appearance: settings.appearance, state: state, liveText: liveText)
                .frame(minHeight: 44)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, resetDisabled: Bool, reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Reset", action: reset)
                .buttonStyle(.link)
                .font(.callout)
                .disabled(resetDisabled)
        }
    }

    private func colorPicker(_ title: String, value: Binding<HUDColor>) -> some View {
        // Opacity is part of the picker rather than a separate slider: the
        // background is translucent by default, and splitting the two
        // would let them drift apart.
        ColorPicker(
            title,
            selection: Binding(
                get: { value.wrappedValue.color },
                set: { value.wrappedValue = HUDColor($0) }
            ),
            supportsOpacity: true
        )
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        // Snapping happens in the binding rather than through `step:`,
        // which would draw a tick mark for every point in the range.
        let snapped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 / step).rounded() * step }
        )
        return LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: snapped, in: range)
                    .frame(maxWidth: 220)
                Text(step < 1
                     ? String(format: "%.1f pt", value.wrappedValue)
                     : "\(Int(value.wrappedValue)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
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
