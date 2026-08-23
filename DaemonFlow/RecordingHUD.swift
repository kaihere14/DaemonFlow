//
//  RecordingHUD.swift
//  DaemonFlow
//
//  Floating pill above the Dock: live waveform while recording, a spinner
//  while transcribing, hidden otherwise. Lives in a borderless
//  non-activating panel so it never steals focus from the app being
//  dictated into.
//

import AppKit
import Combine
import SwiftUI

nonisolated enum HUDState: Equatable {
    case hidden
    /// Nothing happening, but the user has asked for the pill to stay on
    /// screen — a thin empty capsule above the Dock that grows into the
    /// recording pill the moment they speak.
    case idle
    case recording
    case processing
    /// ⌥1 is being held — the user is speaking an edit instruction. Shows
    /// the live meter behind a wand glyph, so it reads as "listening, but
    /// not dictation".
    case instructing
    /// ⌥1 selection refine in flight — shows a shimmering "Refining" label.
    case refining
    /// Refine finished and pasted — brief "Done" confirmation before hiding.
    case done

    /// States where the microphone is open and the waveform should track it.
    var showsLiveMeter: Bool {
        self == .recording || self == .instructing
    }
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden

    /// Raw, uncleaned transcription of what has been heard so far in the
    /// current dictation. Empty until the first partial lands; cleared on
    /// Fn release — the cleaned text is injected into the app, not shown
    /// here.
    @Published var liveText: String = ""

    /// Mirrored from HUDSettingsStore by AppState. The pill lives in an
    /// NSPanel rather than the app's view hierarchy, so it has no
    /// environment to read the settings out of.
    @Published var appearance = HUDAppearance()
}

// MARK: - Panel controller

@MainActor
final class RecordingHUDController {
    private let model: HUDModel
    private let panel: NSPanel
    private var stateCancellable: AnyCancellable?
    private var hideWorkItem: DispatchWorkItem?

    init(model: HUDModel, audio: AudioCaptureManager) {
        self.model = model

        // Sized for the largest pill the settings allow, plus room for the
        // shadow and the resting gap above the Dock. The panel is
        // transparent and ignores mouse events, so oversizing it costs
        // nothing and saves resizing the window mid-morph.
        let maximum = HUDAppearance.maximumSize
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: maximum.width + 60, height: maximum.height + 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: RecordingHUDView(model: model, audio: audio))
        panel.alphaValue = 0

        stateCancellable = model.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.stateChanged(to: state)
            }
    }

    private func stateChanged(to state: HUDState) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if state == .hidden {
            // Small grace period: on Fn release the state blips through
            // .hidden before .processing lands — don't flicker for that.
            let workItem = DispatchWorkItem { [weak self] in
                self?.fadeOut()
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        } else {
            show()
        }
    }

    private func show() {
        positionAboveDock()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.model.state == .hidden else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func positionAboveDock() {
        guard let screen = NSScreen.main else { return }
        // visibleFrame already excludes the Dock, so minY sits right on
        // top of it.
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - HUD view

/// Panel-level wrapper: pins the pill to the bottom of an oversized
/// transparent panel so it grows upward from a fixed line above the Dock
/// rather than drifting as it resizes.
struct RecordingHUDView: View {
    @ObservedObject var model: HUDModel
    let audio: AudioCaptureManager

    var body: some View {
        HUDPill(model: model, level: { audio.currentLevel() })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
    }
}

/// The pill itself, sized entirely from `model.appearance`. Split out from
/// the panel wrapper so the settings sheet can render live previews of it
/// at any state without an NSPanel involved.
struct HUDPill: View {
    @ObservedObject var model: HUDModel

    /// Current 0…1 input level. A closure rather than the capture manager
    /// itself so the settings preview can feed it synthetic movement.
    var level: @MainActor () -> Float

    private static let barCount = 14

    /// One curve for the whole morph. `.smooth` is a spring with no
    /// overshoot — the pill settles into each size instead of snapping to
    /// it, and the same animation runs on the way back down.
    private static let morph = Animation.smooth(duration: 0.34)

    @State private var levelHistory: [Float] = Array(repeating: 0, count: barCount)

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var appearance: HUDAppearance { model.appearance }

    /// The pill only grows for the transcript once there is something
    /// heard to show — an empty expanded pill would read as a layout bug.
    private var isExpanded: Bool {
        model.state == .recording && !model.liveText.isEmpty
    }

    /// Resting and hidden share the sleep colour: `.hidden` is only ever
    /// on screen mid-fade, and switching the outline on the way out would
    /// flash the wrong colour.
    private var borderColor: Color {
        switch model.state {
        case .idle, .hidden: appearance.restingBorderColor.color
        default: appearance.borderColor.color
        }
    }

    private var pillSize: CGSize {
        if model.state == .idle {
            return CGSize(width: appearance.restingWidth, height: appearance.restingHeight)
        }
        if isExpanded {
            return CGSize(width: appearance.expandedWidth, height: appearance.expandedHeight)
        }
        return CGSize(width: appearance.activeWidth, height: appearance.activeHeight)
    }

    var body: some View {
        ZStack {
            // Plain crossfades. The capsule is already morphing its
            // size — scaling the contents on top of that is what made
            // state changes read as a pop rather than a shape change.
            switch model.state {
            case .recording:
                recordingContent
                    .transition(.opacity)
            case .processing:
                HUDSpinner(tint: appearance.waveformColor.color)
                    .transition(.opacity)
            case .instructing:
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(appearance.waveformColor.color)
                    waveform
                }
                .transition(.opacity)
            case .refining:
                ShimmerText(text: "Refining")
                    .transition(.opacity)
            case .done:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.successGreen)
                .transition(.opacity)
            case .idle, .hidden:
                Color.clear
            }
        }
        .frame(width: pillSize.width, height: pillSize.height)
        .background(
            Capsule()
                .fill(appearance.backgroundColor.color)
        )
        // Drawn in every state, resting included — the outline is what
        // makes the sliver above the Dock read as the same object that
        // grows into the recording pill. Its colour switches with the
        // state so "asleep" and "listening" can be told apart at a glance.
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: appearance.borderWidth)
        )
        // Softer and dimmer at rest: this one sits above the Dock all day,
        // so it has to stay out of the way until there's something to say.
        .shadow(color: .black.opacity(0.35), radius: model.state == .idle ? 4 : 7, x: 0, y: 3)
        .opacity(model.state == .idle ? 0.9 : 1)
        // Size, contents, shadow and dimming all animate on one curve, so
        // the pill morphs as a single object in both directions.
        .animation(Self.morph, value: model.state)
        .animation(Self.morph, value: borderColor)
        .animation(Self.morph, value: isExpanded)
        .animation(Self.morph, value: appearance)
        .onReceive(meterTick) { _ in
            guard model.state.showsLiveMeter else { return }
            levelHistory.removeFirst()
            levelHistory.append(level())
        }
        .onChange(of: model.state) { _, newState in
            if !newState.showsLiveMeter {
                levelHistory = Array(repeating: 0, count: Self.barCount)
            }
        }
    }

    /// Waveform alone until the first partial transcription arrives, then
    /// waveform plus the raw live transcript. This is deliberately the
    /// uncleaned text — the cleaned version is what gets injected after Fn
    /// is released, and never appears here.
    @ViewBuilder
    private var recordingContent: some View {
        if model.liveText.isEmpty {
            waveform
        } else {
            HStack(spacing: HUDAppearance.contentSpacing) {
                waveform
                Text(model.liveText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    // Overflow drops the oldest words, so the newest ones —
                    // the ones the user is saying right now — stay visible.
                    .truncationMode(.head)
                    .multilineTextAlignment(.leading)
                    .frame(width: HUDAppearance.liveTextWidth, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: model.liveText)
            }
        }
    }

    /// Scrolling level history, newest bar on the right — reads as a live
    /// waveform of the last ~0.7s of speech.
    private var waveform: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(appearance.waveformColor.color)
                    .frame(
                        width: barWidth,
                        height: Self.minimumBarHeight
                            + CGFloat(levelHistory[index]) * (maximumBarHeight - Self.minimumBarHeight)
                    )
            }
        }
        .frame(width: waveformWidth)
        .animation(.easeOut(duration: 0.08), value: levelHistory)
    }

    // MARK: - Waveform metrics
    //
    // Derived from the configured pill size rather than hard-coded, so the
    // meter stays inside the capsule at every setting. Bars and gaps share
    // the leftover width evenly until the bars hit their cap, after which
    // the gaps absorb the rest.

    private static let minimumBarHeight: CGFloat = 2.5
    private static let maximumBarWidth: CGFloat = 3

    private var waveformWidth: CGFloat {
        max(10, appearance.activeWidth - HUDAppearance.horizontalPadding * 2)
    }

    private var barWidth: CGFloat {
        min(Self.maximumBarWidth, waveformWidth / CGFloat(Self.barCount * 2 - 1))
    }

    private var barSpacing: CGFloat {
        max(0.5, (waveformWidth - barWidth * CGFloat(Self.barCount)) / CGFloat(Self.barCount - 1))
    }

    private var maximumBarHeight: CGFloat {
        max(Self.minimumBarHeight + 1, appearance.activeHeight * 0.55)
    }
}

/// Left-to-right light sweep across the label — the standard "working on
/// text" shimmer. A bright gradient band, masked by the text itself,
/// loops across a dimmed base label.
private struct ShimmerText: View {
    let text: String
    @State private var animate = false

    private var label: Text {
        Text(text).font(.system(size: 11, weight: .semibold))
    }

    var body: some View {
        label
            .foregroundStyle(Theme.textSecondary.opacity(0.55))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Theme.textPrimary, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.9)
                    .offset(x: animate ? geo.size.width * 1.1 : -geo.size.width * 0.9)
                }
                .mask(label)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

private struct HUDSpinner: View {
    let tint: Color

    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}
