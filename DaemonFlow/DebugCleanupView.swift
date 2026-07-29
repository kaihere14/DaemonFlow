//
//  DebugCleanupView.swift
//  DaemonFlow
//
//  Cleanup lab: run the selected cleanup LLM against canned filler-heavy
//  dictation samples (or custom text) and inspect before/after without
//  having to dictate each time.
//

import SwiftUI

struct DebugCleanupView: View {
    var onClose: (() -> Void)?

    @EnvironmentObject private var appState: AppState

    @State private var results: [Int: Result<String, Error>] = [:]
    @State private var runningCases: Set<Int> = []
    @State private var customInput: String = ""
    @State private var customResult: String?
    @State private var customRunning = false

    struct TestCase {
        let name: String
        let input: String
    }

    /// Internal (not private) so AppState's env-var-gated self-test can run
    /// the exact same cases from the command line — see
    /// AppState.runCleanupSelfTestIfRequested().
    static let testCases: [TestCase] = [
        TestCase(name: "Filler words", input: "um so basically I think we should uh we should go with the second option"),
        TestCase(name: "Self-correction", input: "send it to John no wait actually send it to Sarah"),
        TestCase(name: "Fillers + self-correction", input: "can you like schedule the meeting for uh Thursday I mean Friday at 3pm"),
        TestCase(name: "Casual filler quantifiers", input: "the quarterly numbers are you know pretty solid we grew like twenty percent"),
        TestCase(name: "Casual tone preservation", input: "hey man can we schedule a meeting for tomorrow umm not tomorrow but today at 3pm"),
        TestCase(name: "Doesn't answer as chat", input: "hey man how are you"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ForEach(Array(Self.testCases.enumerated()), id: \.offset) { index, testCase in
                    testCaseRow(index: index, testCase: testCase)
                }

                customSection
            }
            .padding(28)
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cleanup lab")
                    .font(Theme.Font.headerTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Model: \(appState.cleanupModelManager.effectiveHubRepoID)")
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textSecondary)
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

    private func testCaseRow(index: Int, testCase: TestCase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(testCase.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("RAW")
                        .font(Theme.Font.monoLabel)
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                Spacer()
                if runningCases.contains(index) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run") {
                        run(index: index, input: testCase.input)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            Text(testCase.input)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)

            if let result = results[index] {
                Divider().overlay(Theme.cardBorder)
                switch result {
                case .success(let cleaned):
                    Text("CLEANED")
                        .font(Theme.Font.monoLabel)
                        .foregroundStyle(Theme.successGreen.opacity(0.8))
                    Text(cleaned)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                case .failure(let error):
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CUSTOM INPUT")
                .font(Theme.Font.monoLabel)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            TextEditor(text: $customInput)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(8)
                .background(Theme.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                if customRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run") {
                        runCustom()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(customInput.isEmpty ? Theme.textSecondary : Theme.accent)
                    .disabled(customInput.isEmpty)
                }
            }

            if let customResult {
                Text(customResult)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func run(index: Int, input: String) {
        runningCases.insert(index)
        Task {
            do {
                let cleaned = try await appState.runCleanup(input)
                results[index] = .success(cleaned)
            } catch {
                results[index] = .failure(error)
            }
            runningCases.remove(index)
        }
    }

    private func runCustom() {
        customRunning = true
        Task {
            do {
                customResult = try await appState.runCleanup(customInput)
            } catch {
                customResult = "Error: \(error.localizedDescription)"
            }
            customRunning = false
        }
    }
}
