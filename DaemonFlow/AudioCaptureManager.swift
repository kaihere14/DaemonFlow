//
//  AudioCaptureManager.swift
//  DaemonFlow
//

import AVFoundation
import AppKit
import Combine
import os

/// Captures microphone audio via AVAudioEngine and accumulates it as
/// 16kHz mono Float32 PCM — the exact format WhisperEngine expects.
@MainActor
final class AudioCaptureManager: ObservableObject {
    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "audio")

    @Published private(set) var micAuthorizationStatus: AVAuthorizationStatus
    @Published private(set) var isCapturing = false

    /// Convenience for call sites that only care about the yes/no answer.
    var micPermissionGranted: Bool { micAuthorizationStatus == .authorized }

    private let engine = AVAudioEngine()
    private let accumulator = SampleAccumulator()
    private var permissionMonitorTimer: Timer?

    init() {
        micAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        startPermissionMonitor()
    }

    deinit {
        permissionMonitorTimer?.invalidate()
    }

    /// Triggers the native system prompt. Only has an effect the first
    /// time (status == .notDetermined) — macOS silently no-ops this after
    /// the first ask, same constraint AXIsProcessTrusted has for Accessibility.
    func requestMicPermission() {
        guard micAuthorizationStatus == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.micAuthorizationStatus = granted ? .authorized : .denied
            }
        }
    }

    /// Re-reads the current authorization status. Call after the user
    /// returns from System Settings.
    func recheckMicPermission() {
        micAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Mirrors HotkeyManager's trust monitor: polls so a permission grant
    /// made in System Settings is picked up automatically, without
    /// requiring the user to click back into the app first.
    private func startPermissionMonitor() {
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recheckMicPermission()
            }
        }
    }

    func startRecording() {
        guard micPermissionGranted else {
            logger.warning("startRecording called without mic permission")
            return
        }
        guard !isCapturing else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Sample rate can be 0 if no input device is available.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("No usable input device (format \(inputFormat.sampleRate, privacy: .public)Hz/\(inputFormat.channelCount, privacy: .public)ch)")
            return
        }
        guard accumulator.prepare(inputFormat: inputFormat) else {
            logger.error("Could not create AVAudioConverter for input format")
            return
        }

        // The macOS 27 SDK deprecates the classic installTap in favor of a
        // fallible variant that is NS_REFINED_FOR_SWIFT but has no Swift
        // overlay yet, so it only imports under the raw __ name.
        do {
            try input.__installTap(onBus: 0, bufferSize: 4096, format: inputFormat, error: ()) { @Sendable [accumulator] buffer, _ in
                accumulator.process(buffer)
            }
        } catch {
            logger.error("installTap failed: \(error.localizedDescription, privacy: .public)")
            _ = accumulator.drain()
            return
        }

        engine.prepare()
        do {
            try engine.start()
            isCapturing = true
            logger.info("Capture started (\(inputFormat.sampleRate, privacy: .public)Hz \(inputFormat.channelCount, privacy: .public)ch → 16kHz mono)")
        } catch {
            logger.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
            input.removeTap(onBus: 0)
            _ = accumulator.drain()
        }
    }

    /// Smoothed 0…1 input level for UI metering (waveform HUD).
    func currentLevel() -> Float {
        accumulator.latestLevel()
    }

    /// Stops capture and returns everything accumulated since startRecording,
    /// clearing the internal buffer for the next utterance.
    func stopRecording() -> [Float] {
        guard isCapturing else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        let samples = accumulator.drain()
        logger.info("Capture stopped — \(samples.count, privacy: .public) samples (\(String(format: "%.2f", Double(samples.count) / 16000), privacy: .public)s)")
        return samples
    }

    func openMicrophoneSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Converts incoming mic buffers to 16kHz mono and accumulates samples.
/// Called from the audio render thread, drained from the main actor, so
/// all state is guarded by a lock.
private final class SampleAccumulator: @unchecked Sendable {
    private static let targetSampleRate: Double = 16000

    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var level: Float = 0

    /// Must be called before installing the tap. Returns false if a
    /// converter can't be built for the device's input format.
    func prepare(inputFormat: AVAudioFormat) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let newConverter = AVAudioConverter(from: inputFormat, to: format) else {
            return false
        }

        converter = newConverter
        outputFormat = format
        samples.removeAll()
        return true
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let converter, let outputFormat else { return }

        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // Feed the converter exactly this one buffer, then report starvation
        // so it flushes what it can and returns.
        var fed = false
        let status = converter.convert(to: outBuffer, error: nil) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let channelData = outBuffer.floatChannelData else { return }
        let frameCount = Int(outBuffer.frameLength)
        let chunk = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        samples.append(contentsOf: chunk)

        // RMS with fast attack / slow decay, normalized so typical speech
        // fills most of the meter range.
        if frameCount > 0 {
            let sumOfSquares = chunk.reduce(Float(0)) { $0 + $1 * $1 }
            let rms = (sumOfSquares / Float(frameCount)).squareRoot()
            let normalized = min(1, rms * 8)
            level = max(normalized, level * 0.7)
        }
    }

    func latestLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let drained = samples
        samples = []
        level = 0
        converter?.reset()
        return drained
    }
}
