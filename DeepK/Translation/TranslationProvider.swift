import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude Code" }
    var defaultModel: String {
        switch self {
        case .codex: "gpt-5.6-luna"
        case .claude: Self.claudeModels[0].model
        }
    }
    /// 앱이 직접 관리하는 고정 선택지이며 첫 항목이 기본 모델이다. Claude Code CLI에는
    /// 무비용 모델 목록 명령이 없다. Codex는 연결한 계정의 목록을 쓰므로 nil이다.
    var fixedModels: [TranslationModelOption]? {
        self == .claude ? Self.claudeModels : nil
    }
    private static let claudeModels = [
        TranslationModelOption(id: "claude-haiku-5-5", model: "claude-haiku-5-5", displayName: "Haiku 5.5"),
        TranslationModelOption(id: "claude-sonnet-5-5", model: "claude-sonnet-5-5", displayName: "Sonnet 5.5"),
        TranslationModelOption(id: "claude-opus-5-5", model: "claude-opus-5-5", displayName: "Opus 5.5"),
        TranslationModelOption(id: "claude-fable-5-1", model: "claude-fable-5-1", displayName: "Fable 5.1")
    ]
    var modelKey: String { "translationModel.\(rawValue)" }
}

/// 제공자 선택값과 실제 계정 연결 상태를 분리해 표현한다.
/// 선택된 제공자가 아니어도 각 상태를 독립적으로 확인할 수 있어야 한다.
enum ProviderState: Equatable, Sendable {
    case notChecked(message: String)
    case cliMissing(message: String)
    case authenticationRequired(message: String)
    case connecting(message: String)
    case connected(message: String)
    case failure(message: String)

    var message: String {
        switch self {
        case let .notChecked(message), let .cliMissing(message),
             let .authenticationRequired(message), let .connecting(message),
             let .connected(message), let .failure(message):
            message
        }
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// 상태 이름을 더 구체적으로 사용할 곳을 위한 호환 별칭이다.
typealias ProviderConnectionState = ProviderState

struct TranslationModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String

    init(id: String, model: String, displayName: String) {
        self.id = id
        self.model = model
        self.displayName = displayName
    }
}

struct TranslationSelection: Equatable, Sendable {
    let provider: TranslationProvider
    let model: String

    var cacheContext: String { "v1|\(provider.rawValue)|\(model)" }

    var label: String { "\(provider.title) · \(model)" }

    static func load(from defaults: UserDefaults) -> Self {
        let provider = TranslationProvider(rawValue: defaults.string(forKey: "translationProvider") ?? "") ?? .codex
        return Self(provider: provider, model: model(for: provider, in: defaults))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(provider.rawValue, forKey: "translationProvider")
        defaults.set(model, forKey: provider.modelKey)
    }

    /// 기존에 직접 고른 모델은 보존한다. 저장된 선택이 없거나 고정 선택지에서 빠진 모델이면 기본값을 쓴다.
    static func model(for provider: TranslationProvider, in defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: provider.modelKey)
            ?? (provider == .codex ? defaults.string(forKey: "translationModel") : nil)
        guard let stored else { return provider.defaultModel }
        if let fixed = provider.fixedModels, !fixed.contains(where: { $0.model == stored }) {
            return provider.defaultModel
        }
        return stored
    }
}
