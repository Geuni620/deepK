import Foundation

@main
struct TranslationProviderTests {
    static func main() {
        let suite = "deepk-provider-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = TranslationSelection.load(from: defaults)
        precondition(initial.provider == .codex && initial.model == "gpt-5.6-luna")
        defaults.set("gpt-5.6-terra", forKey: "translationModel")
        precondition(TranslationSelection.load(from: defaults).model == "gpt-5.6-terra")
        let claude = TranslationSelection(provider: .claude, model: TranslationProvider.claude.defaultModel)
        claude.save(to: defaults)
        precondition(TranslationSelection.load(from: defaults) == claude)
        precondition(TranslationSelection.model(for: .codex, in: defaults) == "gpt-5.6-terra")
        let codex = TranslationSelection(provider: .codex, model: "gpt-5.6-luna")
        codex.save(to: defaults)
        precondition(TranslationSelection.load(from: defaults) == codex)
        precondition(TranslationSelection.model(for: .claude, in: defaults) == claude.model)
        precondition(TranslationProvider.claude.defaultModel == "claude-haiku-5-5")
        TranslationSelection(provider: .claude, model: "claude-haiku-4-5-20251001").save(to: defaults)
        precondition(
            TranslationSelection.load(from: defaults).model == "claude-haiku-5-5",
            "a saved Haiku 4.5 selection should move to the current default"
        )
        TranslationSelection(provider: .claude, model: "claude-model-removed-later").save(to: defaults)
        precondition(
            TranslationSelection.load(from: defaults).model == "claude-haiku-5-5",
            "any saved Claude model outside the fixed options should fall back to the default"
        )
        TranslationSelection(provider: .claude, model: "claude-sonnet-5-5").save(to: defaults)
        precondition(TranslationSelection.load(from: defaults).model == "claude-sonnet-5-5")
        precondition(TranslationProvider.claude.fixedModels?.first?.model == TranslationProvider.claude.defaultModel)
        TranslationSelection(provider: .codex, model: "gpt-account-specific").save(to: defaults)
        precondition(
            TranslationSelection.load(from: defaults).model == "gpt-account-specific",
            "Codex keeps any saved model because its options come from the account"
        )
        let missing = ProviderState.cliMissing(message: "Claude Code CLI가 없습니다")
        precondition(missing.message == "Claude Code CLI가 없습니다")
        precondition(!missing.isConnected && !missing.isConnecting)
        let connected = ProviderState.connected(message: "Codex 구독 연결됨")
        precondition(connected.isConnected && !connected.isConnecting)
        print("TranslationProviderTests passed")
    }
}
