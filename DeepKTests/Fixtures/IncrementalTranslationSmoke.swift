import Foundation

/// Opt-in live check using public, synthetic sentences only. No app windows,
/// defaults writes, credential reads, login changes or external insertion.
private actor RequestAudit {
    var inputs: [String] = []
    func record(_ input: String) { inputs.append(input) }
    func matches(_ expected: [String]) -> Bool { inputs == expected }
}

@main
private struct IncrementalTranslationSmoke {
    @MainActor static func main() async {
        guard ProcessInfo.processInfo.environment["DEEPK_RUN_LIVE_TRANSLATION_TESTS"] == "1",
              CommandLine.arguments.contains("--synthetic-fixture") else {
            print("Live subscription calls require DEEPK_RUN_LIVE_TRANSLATION_TESTS=1 and --synthetic-fixture")
            exit(64)
        }
        let codex = CodexTranslationClient()
        let claudePath = UserDefaults(suiteName: "com.deepk.app")?.string(forKey: "claudeExecutablePath")
        let claude = ClaudeTranslationClient(configuration: .init(executableURL: claudePath.map { URL(fileURLWithPath: $0) }, translationTimeout: 30))
        let a = "The meeting starts at 3 in the afternoon."
        let b = "Please bring 12 printed copies of the report."
        let c = "Do not share the document outside the team."
        var failed = false
        let selected = ProcessInfo.processInfo.environment["DEEPK_LIVE_PROVIDER"]
        guard selected == nil || TranslationProvider(rawValue: selected!) != nil else { exit(64) }
        for provider in TranslationProvider.allCases where selected == nil || selected == provider.rawValue {
            let audit = RequestAudit()
            let model = provider.defaultModel
            let store = TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: .seconds(40)), engineReady: true,
                cacheContext: "v1|\(provider.rawValue)|\(model)", translator: { request in
                    await audit.record(request.input)
                    switch provider {
                    case .codex:
                        return try await codex.translate(text: request.input, source: "en", target: "ko", model: model)
                    case .claude:
                        return try await claude.translate(text: request.input, source: "en", target: "ko", model: model)
                    }
                })
            store.setTranslationContext(cacheContext: "v1|\(provider.rawValue)|\(model)", provider: provider.rawValue, model: model, modelLabel: model)
            store.setDirection(.englishToKorean)
            let start = ContinuousClock.now
            store.invokeCopiedText(a)
            guard await waitForCompletion(store), let first = store.resultText else {
                report("\(provider.rawValue): FAIL initial translation (\(store.status))")
                failed = true
                continue
            }
            let firstDuration = start.duration(to: .now)
            store.invokeCopiedText(a + "\n\n" + b)
            precondition(store.displayedText == first && !store.canCopy)
            // Add C while B owns its immutable prefix, before the provider returns.
            store.invokeCopiedText(a + "\n\n" + b + "\n\n" + c)
            precondition(store.displayedText == first && !store.canInsert)
            guard await waitForCompletion(store) else {
                report("\(provider.rawValue): FAIL appended translation (\(store.status))")
                failed = true
                continue
            }
            let correctPayloads = await audit.matches([a, b, c])
            precondition(correctPayloads && store.displaySegments.count == 3)
            precondition(store.displaySegments[0].text == first && store.canCopy)
            store.editSource("", isComposing: false)
            report("\(provider.rawValue): PASS requests=3 payloadCharacters=[\(a.count),\(b.count),\(c.count)] prefixPreserved=true first=\(firstDuration) total=\(start.duration(to: .now))")
        }
        await codex.disconnect()
        await claude.disconnect()
        exit(failed ? 1 : 0)
    }

    @MainActor private static func waitForCompletion(_ store: TranslationStore) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while ContinuousClock.now < deadline {
            if store.canCopy { return true }
            if case .error = store.status { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func report(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}
