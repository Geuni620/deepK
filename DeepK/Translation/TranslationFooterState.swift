import Foundation

/// What the translation window's single footer bar says (2026-10-13, user feedback: the bottom area was cluttered).
/// Pure, so the priority and the hidden noise are tested without a view.
///
/// The left slot holds one line: the capture message, then actionable feedback (errors, failures), then an unfinished
/// store status, then the shortcut monitor's standing failure, then the retranslation hint, then the warning that a
/// retried answer still echoes the source, then an abnormal shortcut state. '완료', '저장된 번역', '기존 번역 유지 · 추가 번역 완료', the normal '⌘C 두 번 · 감지 중' and double copy
/// turned off in the settings are not shown; a successful copy is confirmed on the 복사 pill and why insertion is
/// unavailable is that pill's tooltip, not footer text. While the result pane has no text, the translation state
/// appears where the text will appear (`pane`) and the footer does not repeat it.
struct TranslationFooterState: Equatable {
    /// One line of status, optionally with a small spinner after it or a warning sign before it.
    struct Line: Equatable {
        var text: String
        var showsProgress = false
        var isWarning = false
    }

    /// The footer's contextual text action. '전체 다시 번역' is otherwise in the result context menu; it is here only
    /// for an answer that still echoes the source after its retry, the one result the user is told to redo.
    enum Action: Equatable {
        case connectProvider
        case retranslate(enabled: Bool)
        case retry
        case revealNewContent
        case retranslateWholeDocument(enabled: Bool)
    }

    struct Input {
        var captureMessage: String?
        /// `AppModel.feedback`: errors, failures and the insert confirmation that clears itself.
        var feedback = ""
        /// The feedback restates a standing failure (the shortcut monitor's), raised again on every activation.
        /// It yields to a translation that is running or failed and shows again once it is done.
        var feedbackIsStanding = false
        var status: TranslationStatus = .idle
        /// The shown result belongs to the current source; the translation is done.
        var canCopy = false
        var hasPartialResult = false
        var isShowingSupersededText = false
        var connecting = false
        var requiresRetranslation = false
        var engineReady = true
        var isComposing = false
        var shortcutMessage = TranslationFooterState.shortcutWatching
        /// Whether the result pane shows any text. Without it the pane itself shows the state.
        var resultShowsText = false
        /// Appended translation sits below the visible area.
        var newContentBelow = false
        /// "<provider> · <model>" of the shown result, which survives a provider change.
        var modelLabel = ""
        var elapsedMilliseconds: Int?
        var resultWasCached = false
        /// The second answer still echoed the source (`TranslationOutputNotice.unresolvedEcho`).
        var unresolvedEcho = false
        /// The first answer echoed the source and the second is on its way.
        var isRetryingAfterEcho = false
        var canRetranslateWholeDocument = false
    }

    /// The footer's left slot. Empty (nil) shows nothing until the pointer rests there and reveals `detail`.
    var status: Line?
    /// The state shown at the top left of an empty result pane; nil while the pane shows text.
    var pane: Line?
    /// "<provider> · <model> · 5.8초": revealed by hovering an empty slot, the tooltip of a non-empty one.
    var detail: String
    var detailHasElapsedTime: Bool
    var action: Action?

    /// The shortcut messages the footer stays quiet about: the normal states and double copy turned off in the
    /// settings, which is the user's choice rather than a fault. AppModel sets these.
    static let shortcutChecking = "단축키 확인 중"
    static let shortcutWatching = "⌘C 두 번 · 감지 중"
    static let shortcutDisabled = "두 번 복사 꺼짐"
    static let retranslationMessage = "선택한 제공자·모델로 다시 번역할 수 있습니다"
    /// Copy and insertion stay available; the user is only told.
    static let unresolvedEchoMessage = "원문이 그대로 남아 있을 수 있습니다"
    /// What an idle, empty result pane says where the translation will appear.
    static let resultPlaceholder = "번역 결과"

    init(_ input: Input) {
        let capture = input.captureMessage.map { Line(text: $0, showsProgress: true) }
        let feedback = input.feedback.isEmpty ? nil : Line(text: input.feedback)
        let event = input.feedbackIsStanding ? nil : feedback, standing = input.feedbackIsStanding ? feedback : nil
        let unfinished = Self.unfinishedStatus(input)
        let retranslation = input.requiresRetranslation ? Line(text: Self.retranslationMessage) : nil
        let echo = input.unresolvedEcho ? Line(text: Self.unresolvedEchoMessage, isWarning: true) : nil
        let quietShortcut = [Self.shortcutWatching, Self.shortcutChecking, Self.shortcutDisabled].contains(input.shortcutMessage)
        let shortcut = quietShortcut ? nil : Line(text: input.shortcutMessage)
        if input.resultShowsText {
            status = capture ?? event ?? unfinished ?? standing ?? retranslation ?? echo ?? shortcut
            pane = nil
        } else {
            // The empty pane shows the translation state where the text will appear; the footer keeps the rest.
            status = feedback ?? shortcut
            pane = capture ?? unfinished ?? retranslation
                ?? (input.status == .idle ? Line(text: Self.resultPlaceholder) : nil)
        }
        let elapsed = input.status == .success && !input.resultWasCached
            ? input.elapsedMilliseconds.map(Self.seconds(fromMilliseconds:)) : nil
        detail = [input.modelLabel, elapsed ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        detailHasElapsedTime = elapsed != nil
        action = Self.action(input)
    }

    /// Seconds with one decimal, rounded half up: 5,811 ms → "5.8초".
    static func seconds(fromMilliseconds milliseconds: Int) -> String {
        let tenths = (max(0, milliseconds) + 50) / 100
        return tenths == 0 ? "0.1초 미만" : "\(tenths / 10).\(tenths % 10)초"
    }

    /// The store's state while the translation is not done. A copyable result is done, so nothing is said.
    private static func unfinishedStatus(_ input: Input) -> Line? {
        guard !input.canCopy else { return nil }
        let text: String? = switch input.status {
        case .idle: input.hasPartialResult ? "추가 내용이 번역되지 않았습니다"
            : input.isShowingSupersededText ? "번역이 완료되지 않았습니다" : nil
        case .disconnected: input.connecting ? "연결 확인 중…" : "번역 제공자 연결 전"
        case .waiting: input.hasPartialResult ? "추가 내용 입력 중…" : "입력 중…"
        case .translating: input.isRetryingAfterEcho ? "원문이 그대로 나와 다시 번역하는 중…"
            : input.hasPartialResult ? "추가 내용 번역 중…" : "번역 중…"
        case .success: nil
        case .error(let error): error.localizedDescription
        }
        return text.map { Line(text: $0, showsProgress: input.status == .translating) }
    }

    private static func action(_ input: Input) -> Action? {
        if input.status == .disconnected { return .connectProvider }
        if input.requiresRetranslation {
            return .retranslate(enabled: input.engineReady && !input.isComposing && input.status != .translating)
        }
        if case .error = input.status { return .retry }
        if input.status == .idle && (input.hasPartialResult || input.isShowingSupersededText) { return .retry }
        // New translation appended below the warned document must stay reachable; the warning stays on the left.
        if input.newContentBelow { return .revealNewContent }
        if input.unresolvedEcho { return .retranslateWholeDocument(enabled: input.canRetranslateWholeDocument) }
        return nil
    }
}
