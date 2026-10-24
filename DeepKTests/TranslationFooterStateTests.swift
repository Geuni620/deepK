import Foundation

/// The footer's one status slot, its quiet detail and its text action (2026-10-13 user feedback: the bottom area
/// was cluttered). Pure: no views, no windows, no pasteboard.
@main
private struct TranslationFooterStateTests {
    typealias State = TranslationFooterState
    typealias Line = TranslationFooterState.Line

    static func main() {
        priorityOrder()
        noiseStaysHidden()
        abnormalShortcutShows()
        disabledShortcutIsQuiet()
        standingFeedbackYieldsToTheTranslation()
        unfinishedStatusTexts()
        progressBelongsToItsLine()
        emptyResultShowsStateInThePane()
        detailLine()
        secondsFormat()
        actions()
        unresolvedEchoWarns()
        print("TranslationFooterStateTests passed")
    }

    /// An answer that still echoes the source after its retry is shown and copyable, but warned about with a way to redo
    /// it; while the retry runs, the footer says why it is translating again.
    private static func unresolvedEchoWarns() {
        func echoed(_ input: inout State.Input) {
            input.status = .success
            input.canCopy = true
            input.unresolvedEcho = true
            input.canRetranslateWholeDocument = true
        }
        let warned = shown(echoed)
        check(warned.status == Line(text: State.unresolvedEchoMessage, isWarning: true), "the echo warning shows with its sign")
        check(warned.action == .retranslateWholeDocument(enabled: true), "the warning offers a whole retranslation")
        check(shown { echoed(&$0); $0.canRetranslateWholeDocument = false }.action == .retranslateWholeDocument(enabled: false),
              "the action is disabled while a retranslation cannot start")
        check(shown { echoed(&$0); $0.newContentBelow = true }.action == .revealNewContent,
              "new translation appended below stays reachable before the warning's action")
        check(shown { echoed(&$0); $0.newContentBelow = true }.status?.isWarning == true, "the warning stays on the left meanwhile")
        check(shown { echoed(&$0); $0.requiresRetranslation = true }.status?.text == State.retranslationMessage,
              "the retranslation hint comes before the warning")
        check(shown { echoed(&$0); $0.unresolvedEcho = false }.status == nil && shown { echoed(&$0); $0.unresolvedEcho = false }.action == nil,
              "a clean result says nothing")
        let retrying = shown {
            $0.status = .translating
            $0.isRetryingAfterEcho = true
        }
        check(retrying.status == Line(text: "원문이 그대로 나와 다시 번역하는 중…", showsProgress: true), "the retry says why it runs")
    }

    /// A result is on screen, so the footer carries the state.
    private static func shown(_ change: (inout State.Input) -> Void = { _ in }) -> State {
        var input = State.Input()
        input.resultShowsText = true
        input.modelLabel = "Claude Code · claude-haiku-5-5"
        change(&input)
        return State(input)
    }

    private static func empty(_ change: (inout State.Input) -> Void = { _ in }) -> State {
        var input = State.Input()
        input.resultShowsText = false
        input.modelLabel = "Claude Code · claude-haiku-5-5"
        change(&input)
        return State(input)
    }

    private static func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        precondition(condition, message, file: file, line: line)
    }

    /// captureMessage > feedback > unfinished store status > standing feedback > retranslation > abnormal shortcut > nothing.
    private static func priorityOrder() {
        func everything(_ input: inout State.Input) {
            input.captureMessage = "복사한 텍스트를 확인하는 중…"
            input.feedback = "결과가 변경되어 삽입을 중단했습니다"
            input.status = .waiting
            input.canCopy = false
            input.requiresRetranslation = true
            input.shortcutMessage = "단축키 감시 연결 안 됨"
        }
        check(shown(everything).status?.text == "복사한 텍스트를 확인하는 중…", "the capture message comes first")
        check(shown { everything(&$0); $0.captureMessage = nil }.status?.text == "결과가 변경되어 삽입을 중단했습니다",
              "actionable feedback beats the store status")
        check(shown { everything(&$0); $0.captureMessage = nil; $0.feedback = "" }.status?.text == "입력 중…",
              "an unfinished store status beats the retranslation hint")
        check(shown { everything(&$0); $0.captureMessage = nil; $0.feedback = ""; $0.status = .success; $0.canCopy = true }
                .status?.text == State.retranslationMessage, "the retranslation hint beats the shortcut state")
        check(shown { $0.status = .success; $0.canCopy = true; $0.shortcutMessage = "단축키 감시 연결 안 됨" }
                .status?.text == "단축키 감시 연결 안 됨", "an abnormal shortcut state shows when nothing else does")
        check(shown { $0.status = .success; $0.canCopy = true }.status == nil, "a finished result leaves the slot empty")
        // A failed copy is feedback and stays; a successful one is confirmed on the 복사 pill, not here (AppModel).
        check(shown { $0.status = .success; $0.canCopy = true; $0.feedback = "복사하지 못했습니다" }.status?.text == "복사하지 못했습니다",
              "a failed copy shows")
    }

    /// '완료', '저장된 번역', '기존 번역 유지 · 추가 번역 완료', the normal shortcut state and the
    /// result placeholder never reach the footer.
    private static func noiseStaysHidden() {
        let finished = shown { $0.status = .success; $0.canCopy = true }
        check(finished.status == nil, "'완료' is not shown")
        check(shown { $0.status = .success; $0.canCopy = true; $0.resultWasCached = true }.status == nil,
              "'저장된 번역' is not shown")
        check(shown { $0.status = .success; $0.canCopy = true; $0.shortcutMessage = State.shortcutWatching }.status == nil,
              "the normal '⌘C 두 번 · 감지 중' is not shown")
        check(shown { $0.status = .success; $0.canCopy = true; $0.shortcutMessage = State.shortcutChecking }.status == nil,
              "the start-up check is not shown")
        check(shown { $0.status = .idle }.status == nil, "the '번역 결과' placeholder stays in the result pane")
        // Old labels must not come back through any input.
        let noise: Set<String> = ["완료", "저장된 번역", "기존 번역 유지 · 추가 번역 완료", "번역 결과", State.shortcutWatching,
                                  State.shortcutDisabled]
        for status in [TranslationStatus.idle, .waiting, .translating, .success, .disconnected] {
            for canCopy in [false, true] {
                for cached in [false, true] {
                    for shows in [false, true] {
                        var input = State.Input()
                        input.shortcutMessage = State.shortcutDisabled
                        input.status = status
                        input.canCopy = canCopy
                        input.resultWasCached = cached
                        input.resultShowsText = shows
                        let state = State(input)
                        if let text = state.status?.text { check(!noise.contains(text), "noise in the footer: \(text)") }
                    }
                }
            }
        }
    }

    private static func abnormalShortcutShows() {
        for message in ["단축키 감시 연결 안 됨", "단축키 감시 시작 실패", "단축키 감시 연결 확인 필요"] {
            check(shown { $0.status = .success; $0.canCopy = true; $0.shortcutMessage = message }.status?.text == message,
                  "\(message) is shown")
            check(empty { $0.shortcutMessage = message }.status?.text == message, "\(message) is shown beside an empty result")
        }
    }

    /// Double copy turned off in the settings is the user's choice, not a fault: the footer does not repeat it.
    private static func disabledShortcutIsQuiet() {
        check(State.shortcutDisabled == "두 번 복사 꺼짐", "the message AppModel sets")
        check(shown { $0.status = .success; $0.canCopy = true; $0.shortcutMessage = State.shortcutDisabled }.status == nil,
              "a disabled shortcut leaves a finished result's slot empty")
        check(empty { $0.shortcutMessage = State.shortcutDisabled }.status == nil, "and the slot beside an empty result")
    }

    /// The shortcut monitor's failure is raised again on every activation. It must not hide a translation that is
    /// running or failed; it shows again once the translation is done. A fresh event (insert failed, copy failed)
    /// still comes first.
    private static func standingFeedbackYieldsToTheTranslation() {
        let permission = "현재 앱의 키 입력 감시가 연결되지 않았습니다. 이미 허용했다면 앱을 다시 열어 주세요"
        func standing(_ change: (inout State.Input) -> Void) -> State {
            shown {
                $0.feedback = permission
                $0.feedbackIsStanding = true
                $0.shortcutMessage = "단축키 감시 연결 안 됨"
                change(&$0)
            }
        }
        check(standing { $0.status = .translating }.status == Line(text: "번역 중…", showsProgress: true),
              "a running translation and its spinner show over the standing failure")
        check(standing { $0.status = .waiting; $0.hasPartialResult = true }.status?.text == "추가 내용 입력 중…", "typing too")
        check(standing { $0.status = .error(.timedOut) }.status?.text == TranslationStoreError.timedOut.localizedDescription,
              "the next error is not hidden")
        check(standing { $0.status = .success; $0.canCopy = true }.status?.text == permission, "it shows again when done")
        check(standing { $0.status = .success; $0.canCopy = true; $0.requiresRetranslation = true }.status?.text == permission,
              "it still comes before the retranslation hint")
        check(standing { $0.status = .translating; $0.captureMessage = "복사한 텍스트를 확인하는 중…" }.status?.text
                == "복사한 텍스트를 확인하는 중…", "the capture comes first")
        check(shown { $0.feedback = "삽입을 확인하지 못했습니다. 원래 내용을 확인해 주세요"; $0.status = .translating }.status?.text
                == "삽입을 확인하지 못했습니다. 원래 내용을 확인해 주세요", "a fresh event still comes before the store status")
        // An empty pane shows the translation state itself; the footer keeps the failure beside it.
        var input = State.Input()
        input.feedback = permission
        input.feedbackIsStanding = true
        input.status = .translating
        let beside = State(input)
        check(beside.status?.text == permission && beside.pane == Line(text: "번역 중…", showsProgress: true),
              "beside an empty pane both are seen")
    }

    private static func unfinishedStatusTexts() {
        func text(_ change: (inout State.Input) -> Void) -> String? { shown(change).status?.text }
        check(text { $0.status = .waiting } == "입력 중…", "waiting")
        check(text { $0.status = .waiting; $0.hasPartialResult = true } == "추가 내용 입력 중…", "waiting for an appended part")
        check(text { $0.status = .translating } == "번역 중…", "translating")
        check(text { $0.status = .translating; $0.hasPartialResult = true } == "추가 내용 번역 중…", "translating an appended part")
        check(text { $0.status = .idle; $0.hasPartialResult = true } == "추가 내용이 번역되지 않았습니다", "appended part failed")
        check(text { $0.status = .idle; $0.isShowingSupersededText = true } == "번역이 완료되지 않았습니다", "superseded text kept")
        check(text { $0.status = .disconnected } == "번역 제공자 연결 전", "disconnected")
        check(text { $0.status = .disconnected; $0.connecting = true } == "연결 확인 중…", "connecting")
        check(text { $0.status = .error(.timedOut) } == TranslationStoreError.timedOut.localizedDescription, "error text")
        check(text { $0.status = .error(.provider("요청 한도에 도달했습니다")) } == "요청 한도에 도달했습니다", "provider error text")
        // A copyable result is done, whatever the status says.
        check(text { $0.status = .waiting; $0.canCopy = true } == nil, "a current result hides the store status")
    }

    /// The spinner belongs to the capture message and to '번역 중…', not to whatever else is in the slot.
    private static func progressBelongsToItsLine() {
        check(shown { $0.captureMessage = "복사한 텍스트를 확인하는 중…" }.status?.showsProgress == true, "capture spins")
        check(shown { $0.status = .translating }.status?.showsProgress == true, "translating spins")
        check(shown { $0.status = .translating; $0.hasPartialResult = true }.status?.showsProgress == true, "appended part spins")
        check(shown { $0.status = .waiting }.status?.showsProgress == false, "typing does not spin")
        check(shown { $0.status = .disconnected; $0.connecting = true }.status?.showsProgress == false, "connecting does not spin")
        check(shown { $0.status = .translating; $0.feedback = "단축키를 시작하지 못했습니다. 설정에서 다시 시도해 주세요" }
                .status == Line(text: "단축키를 시작하지 못했습니다. 설정에서 다시 시도해 주세요", showsProgress: false),
              "an error shown during a translation does not spin")
    }

    /// With no text yet, the state appears where the text will appear and the footer does not repeat it.
    private static func emptyResultShowsStateInThePane() {
        let translating = empty { $0.status = .translating }
        check(translating.pane == Line(text: "번역 중…", showsProgress: true), "the pane shows the translation state")
        check(translating.status == nil, "the footer does not repeat it")

        let capturing = empty { $0.captureMessage = "복사한 텍스트를 확인하는 중…"; $0.status = .idle }
        check(capturing.pane == Line(text: "복사한 텍스트를 확인하는 중…", showsProgress: true), "the pane shows the capture")
        check(capturing.status == nil, "the footer does not repeat the capture")

        let failed = empty { $0.status = .error(.engineUnavailable) }
        check(failed.pane?.text == TranslationStoreError.engineUnavailable.localizedDescription, "the pane shows the error")
        check(failed.status == nil, "the footer does not repeat the error")
        check(failed.action == .retry, "the footer still offers 다시 시도")

        let retranslation = empty { $0.requiresRetranslation = true }
        check(retranslation.pane?.text == State.retranslationMessage, "the pane shows the retranslation hint")
        check(retranslation.status == nil, "the footer does not repeat it")

        let idle = empty()
        check(idle.pane == Line(text: State.resultPlaceholder), "an idle empty result shows its placeholder")
        check(idle.status == nil, "and the footer stays empty")

        // Feedback is not a pane state, so it stays in the footer next to the pane's own state.
        let rejected = empty { $0.feedback = "복사한 텍스트가 비어 있습니다. 번역할 문장을 선택해 주세요" }
        check(rejected.status?.text == "복사한 텍스트가 비어 있습니다. 번역할 문장을 선택해 주세요", "feedback stays in the footer")
        check(rejected.pane == Line(text: State.resultPlaceholder), "beside the pane placeholder")

        check(shown { $0.status = .translating }.pane == nil, "a result on screen has no pane state")
    }

    private static func detailLine() {
        func detail(_ change: (inout State.Input) -> Void) -> State { shown(change) }
        let timed = detail { $0.status = .success; $0.canCopy = true; $0.elapsedMilliseconds = 5_811 }
        check(timed.detail == "Claude Code · claude-haiku-5-5 · 5.8초", "provider · model · seconds: \(timed.detail)")
        check(timed.detailHasElapsedTime, "the time is reported")
        let cached = detail { $0.status = .success; $0.canCopy = true; $0.elapsedMilliseconds = 31; $0.resultWasCached = true }
        check(cached.detail == "Claude Code · claude-haiku-5-5" && !cached.detailHasElapsedTime, "a cached result has no time")
        let unknown = detail { $0.status = .success; $0.canCopy = true }
        check(unknown.detail == "Claude Code · claude-haiku-5-5", "an unknown time is omitted")
        let running = detail { $0.status = .translating; $0.elapsedMilliseconds = 5_811 }
        check(running.detail == "Claude Code · claude-haiku-5-5", "no time before the translation finishes")
        // The label is what the view passes: the shown result's own model survives a provider change.
        let original = shown { $0.modelLabel = "Codex · luna"; $0.requiresRetranslation = true; $0.status = .success; $0.canCopy = true }
        check(original.detail == "Codex · luna", "the detail names the shown result's model")
        check(original.status?.text == State.retranslationMessage, "and the slot offers the new selection")
    }

    private static func secondsFormat() {
        check(State.seconds(fromMilliseconds: 5_811) == "5.8초", "5,811 ms")
        check(State.seconds(fromMilliseconds: 5_850) == "5.9초", "half up")
        check(State.seconds(fromMilliseconds: 12_049) == "12.0초", "12,049 ms")
        check(State.seconds(fromMilliseconds: 65_432) == "65.4초", "over a minute stays in seconds")
        check(State.seconds(fromMilliseconds: 150) == "0.2초", "150 ms")
        check(State.seconds(fromMilliseconds: 50) == "0.1초", "50 ms")
        check(State.seconds(fromMilliseconds: 49) == "0.1초 미만", "under a tenth")
        check(State.seconds(fromMilliseconds: 0) == "0.1초 미만", "zero")
    }

    private static func actions() {
        check(shown { $0.status = .disconnected; $0.requiresRetranslation = true }.action == .connectProvider,
              "connecting the provider comes first")
        check(shown { $0.status = .success; $0.canCopy = true; $0.requiresRetranslation = true }.action == .retranslate(enabled: true),
              "다시 번역")
        check(shown { $0.status = .translating; $0.requiresRetranslation = true }.action == .retranslate(enabled: false),
              "다시 번역 waits for the running request")
        check(shown { $0.status = .success; $0.requiresRetranslation = true; $0.isComposing = true }.action == .retranslate(enabled: false),
              "다시 번역 waits for the composition")
        check(shown { $0.status = .idle; $0.requiresRetranslation = true; $0.engineReady = false }.action == .retranslate(enabled: false),
              "다시 번역 needs an engine")
        check(shown { $0.status = .error(.timedOut) }.action == .retry, "다시 시도 after an error")
        check(shown { $0.status = .idle; $0.hasPartialResult = true }.action == .retry, "다시 시도 after a failed appended part")
        check(shown { $0.status = .idle; $0.isShowingSupersededText = true }.action == .retry, "다시 시도 for kept text")
        check(shown { $0.status = .success; $0.canCopy = true; $0.newContentBelow = true }.action == .revealNewContent,
              "↓ 새 번역 보기")
        check(shown { $0.status = .error(.timedOut); $0.requiresRetranslation = true }.action == .retranslate(enabled: true),
              "a new selection outranks retrying the old one")
        check(shown { $0.status = .error(.timedOut); $0.newContentBelow = true }.action == .retry, "an error outranks new content")
        check(shown { $0.status = .idle; $0.hasPartialResult = true; $0.newContentBelow = true }.action == .retry,
              "a failed appended part outranks new content")
        // '전체 다시 번역' left the always-visible UI; it stays in the result context menu.
        check(shown { $0.status = .success; $0.canCopy = true }.action == nil, "no action for a finished result")
        check(shown { $0.status = .idle }.action == nil, "no action when idle")
    }
}
