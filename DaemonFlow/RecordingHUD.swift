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
    case recording
    case processing
    /// ⌥1 selection refine in flight — shows a shimmering "Refining" label.
    case refining
    /// Refine finished and pasted — brief "Done" confirmation before hiding.
    case done
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
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

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 118, height: 42),
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
            y: visible.minY + 8
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - HUD view

struct RecordingHUDView: View {
    @ObservedObject var model: HUDModel
    let audio: AudioCaptureManager

    private static let barCount = 14

    @State private var levelHistory: [Float] = Array(repeating: 0, count: barCount)

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            switch model.state {
            case .recording:
                waveform
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            case .processing:
                HUDSpinner()
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            case .refining:
                ShimmerText(text: "Refining")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            case .done:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.successGreen)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            case .hidden:
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.state)
        .frame(width: 96, height: 26)
        .background(
            Capsule()
                .fill(Theme.cardSurface.opacity(0.97))
        )
        .overlay(
            Capsule()
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 7, x: 0, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(meterTick) { _ in
            guard model.state == .recording else { return }
            levelHistory.removeFirst()
            levelHistory.append(audio.currentLevel())
        }
        .onChange(of: model.state) { _, newState in
            if newState != .recording {
                levelHistory = Array(repeating: 0, count: Self.barCount)
            }
        }
    }

    /// Scrolling level history, newest bar on the right — reads as a live
    /// waveform of the last ~0.7s of speech.
    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 2.5 + CGFloat(levelHistory[index]) * 12)
            }
        }
        .animation(.easeOut(duration: 0.08), value: levelHistory)
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
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}
