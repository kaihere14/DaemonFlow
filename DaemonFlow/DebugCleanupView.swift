//
//  DebugCleanupView.swift
//  DaemonFlow
//
//  Playground: run the selected cleanup model against canned filler-heavy
//  dictation samples (or your own text) and compare before and after
//  without having to dictate each time.
//

import SwiftUI

struct DebugCleanupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    @State private var results: [Int: Result<String, Error>] = [:]
    @State private var runningCases: Set<Int> = []
    @State private var customInput = ""
    @State private var customResult: Result<String, Error>?
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
        Form {
            Section {
                LabeledContent("Cleanup model", value: modelName)
            } footer: {
                Text("Runs the same prompt and model as a real dictation.")
            }

            Section("Your text") {
                TextEditor(text: $customInput)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64)

                HStack {
                    resultView(customResult)
                    Spacer(minLength: 16)
                    runControl(isRunning: customRunning, disabled: trimmedCustomInput.isEmpty, action: runCustom)
                }
            }

            Section("Samples") {
                ForEach(Array(Self.testCases.enumerated()), id: \.offset) { index, testCase in
                    sampleRow(index: index, testCase: testCase)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Run All Samples", action: runAll)
                    .disabled(!runningCases.isEmpty)
            }
        }
    }

    private var modelName: String {
        let repoID = cleanupManager.effectiveHubRepoID
        return CleanupModelCatalog.model(forHubRepoID: repoID)?.displayName ?? repoID
    }

    private var trimmedCustomInput: String {
        customInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sampleRow(index: Int, testCase: TestCase) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(testCase.name)
                    .fontWeight(.medium)
                Text(testCase.input)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                resultView(results[index])
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            runControl(isRunning: runningCases.contains(index), disabled: false) {
                run(index: index, input: testCase.input)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func resultView(_ result: Result<String, Error>?) -> some View {
        switch result {
        case .success(let cleaned):
            Label {
                Text(cleaned)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tint)
            }
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        case nil:
            EmptyView()
        }
    }

    /// Fixed width so a row doesn't shift when Run turns into a spinner.
    private func runControl(isRunning: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        ZStack {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Run", action: action)
                    .disabled(disabled)
            }
        }
        .frame(width: 56, alignment: .trailing)
    }

    private func run(index: Int, input: String) {
        runningCases.insert(index)
        Task {
            do {
                results[index] = .success(try await appState.runCleanup(input))
            } catch {
                results[index] = .failure(error)
            }
            runningCases.remove(index)
        }
    }

    private func runAll() {
        for (index, testCase) in Self.testCases.enumerated() {
            run(index: index, input: testCase.input)
        }
    }

    private func runCustom() {
        customRunning = true
        let input = trimmedCustomInput
        Task {
            do {
                customResult = .success(try await appState.runCleanup(input))
            } catch {
                customResult = .failure(error)
            }
            customRunning = false
        }
    }
}
