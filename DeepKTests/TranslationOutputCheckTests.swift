import Foundation

/// 요청 단위 출력 검사(TranslationOutputCheck): 조각의 원문 반복 조기 판정, 한자 치환 표시, 완료 검토와 보고 규칙.
@main
private enum TranslationOutputCheckTests {
    static func main() {
        catchesAnEchoWhileStreaming()
        neverAbortsTheSecondAttempt()
        reviewRepairsAndFlags()
        showsRepairedHanWhileStreaming()
        keepsSourceHanAndOtherDirections()
        killSwitches()
        codeRepeatedFromTheSourceIsNotAnEcho()
        reportsCarryNamesAndCountsOnly()
        print("TranslationOutputCheckTests passed")
    }

    private static let source = """
    When a user copies a paragraph twice, the application should show the copied text and start translating without another click. The first copy must still work normally in the original application.

    The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed.
    """

    private static let translation = """
    사용자가 단락을 두 번 복사하면 애플리케이션은 복사한 텍스트를 보여 주고 추가 클릭 없이 번역을 시작해야 합니다. 첫 번째 복사는 원래 애플리케이션에서 계속 정상적으로 동작해야 합니다.

    클립보드는 키보드 이벤트가 도착한 뒤에 바뀔 수 있습니다. 현재 복사를 잠시 기다리되, 복사에 실패했다면 이전 클립보드 내용을 보내지 마세요.
    """

    private static func check(attempt: Int = 1, source: String = source, from: String = "en", to: String = "ko",
                              retriesEcho: Bool = true, repairsHanja: Bool = true) -> TranslationOutputCheck {
        TranslationOutputCheck(source: source, protecting: [source], sourceLanguage: from, targetLanguage: to, attempt: attempt,
                               retriesEcho: retriesEcho, repairsHanja: repairsHanja)
    }

    /// 스트리밍 조각을 글자 단위로 보내며 처음 `.echo`가 나온 조각을 돌려준다.
    private static func firstEcho(_ check: inout TranslationOutputCheck, streaming text: String) -> String? {
        var prefix = ""
        for scalar in text.unicodeScalars {
            prefix.unicodeScalars.append(scalar)
            if check.partial(prefix) == .echo { return prefix }
        }
        return nil
    }

    private static func catchesAnEchoWhileStreaming() {
        var first = check()
        let early = firstEcho(&first, streaming: source)
        require(early != nil, "attempt 1 aborts an echo while it streams")
        require(early!.utf16.count < source.utf16.count, "the abort comes before the stream ends: \(early!.utf16.count)")
        require(first.review(source).echo, "an early echo is an echo at completion too")
        var clean = check()
        require(firstEcho(&clean, streaming: translation) == nil, "a translation is never aborted")
        require(!clean.review(translation).echo, "a translation is not an echo")
    }

    private static func neverAbortsTheSecondAttempt() {
        var second = check(attempt: 2)
        require(firstEcho(&second, streaming: source) == nil, "attempt 2 streams to the end")
        require(second.review(source).echo, "attempt 2 still reports an echo at completion")
    }

    private static func reviewRepairsAndFlags() {
        let review = check().review("보안이 确保된 연결이 필요합니다.")
        require(review.text == "보안이 확보된 연결이 필요합니다." && !review.echo, "review repairs Han: \(review)")
        require(review.hanja == HanjaRepair.Counts(replaced: 2), "review counts the repair: \(review.hanja)")
        let echo = check().review(source)
        require(echo.echo && echo.coverage == 1 && echo.candidates == 4 && echo.text == source, "review flags an echo with its coverage: \(echo)")
        let half = check().review(translation.components(separatedBy: "\n\n")[0] + "\n\n" + source.components(separatedBy: "\n\n")[1])
        require(half.echo && half.coverage > 0.4 && half.coverage < 1, "an echoed second paragraph is an echo: \(half.coverage)")
    }

    /// 조각에는 고친 한자가 보이고, 판정이 남은 끝 묶음은 보류한다. 보이는 글은 완료 결과의 앞부분이다.
    private static func showsRepairedHanWhileStreaming() {
        var current = check()
        require(current.partial("보안이 确") == .show("보안이 "), "an open run is withheld")
        require(current.partial("보안이 确保된") == .show("보안이 확보된"), "a decided run is shown repaired")
        let final = "보안이 确保된 연결이 필요합니다. 궁금한 点이 있으면 언제든지 문의해 주세요."
        let repaired = current.review(final).text
        var stream = check()
        var previous = ""
        var prefix = ""
        for scalar in final.unicodeScalars {
            prefix.unicodeScalars.append(scalar)
            guard case .show(let shown) = stream.partial(prefix) else { return require(false, "a translation is never an echo") }
            require(shown.hasPrefix(previous) && repaired.hasPrefix(shown), "shown text grows into the final text: \(shown)")
            previous = shown
        }
    }

    private static func keepsSourceHanAndOtherDirections() {
        let kept = check(source: "Write 漢字 in the title.").review("제목에 漢字를 쓰세요.")
        require(kept.text == "제목에 漢字를 쓰세요." && kept.hanja == HanjaRepair.Counts(), "Han from the model input is kept")
        var english = check(source: "보안이 확보된 연결이 필요합니다.", from: "ko", to: "en")
        require(english.partial("A 确保 connection") == .show("A 确保 connection"), "English results are never repaired")
        require(english.review("A 确保 connection").text == "A 确保 connection", "English results are never repaired at completion")
        // 한글 뒤의 한자는 한국어 결과라면 고칠 묶음이다. 영어 결과에서는 그대로다.
        let mixed = TranslationOutputCheck(source: "회원 가입을 확인합니다.", protecting: ["회원 가입을 확인합니다."], sourceLanguage: "ko",
                                           targetLanguage: "en", attempt: 1).review("Confirm 회원 确保 가입.")
        require(mixed.text == "Confirm 회원 确保 가입." && mixed.hanja == HanjaRepair.Counts(), "Han after Hangul in an English result is kept: \(mixed)")
    }

    private static func killSwitches() {
        var noRetry = check(retriesEcho: false)
        require(firstEcho(&noRetry, streaming: source) == nil, "with the retry off, partials never report an echo")
        require(noRetry.review(source).echo, "the completion still reports the echo")
        var noRepair = check(repairsHanja: false)
        require(noRepair.partial("보안이 确保된") == .show("보안이 确保된"), "with the repair off, partials show raw text")
        require(noRepair.review("보안이 确保된").text == "보안이 确保된", "with the repair off, the review keeps raw text")
    }

    /// en-codeblock-1에 펜스를 씌운 답은 원문 코드를 옮겼을 뿐이다.
    private static func codeRepeatedFromTheSourceIsNotAnEcho() {
        let source = """
        Context handoff works across providers:

        import { getModel, complete } from '@mariozechner/pi-ai';

        // Start with Claude
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);

        The reply keeps the previous messages.
        """
        let output = """
        컨텍스트 전달은 제공자 간에도 동작합니다:

        ```typescript
        import { getModel, complete } from '@mariozechner/pi-ai';

        // Claude로 시작
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);
        ```

        응답은 이전 메시지를 유지합니다.
        """
        var current = check(source: source)
        require(firstEcho(&current, streaming: output) == nil && !current.review(output).echo, "repeated source code is not an echo")
    }

    private static func reportsCarryNamesAndCountsOnly() {
        let current = check()
        let leaked = "보안이 确保된 연결 " + "我们确保安全。"
        let review = current.review(leaked)
        require(current.rules(final: review.text, echo: false) == ["foreignScript", "structure"], "rules are names: \(current.rules(final: review.text, echo: false))")
        require(current.rules(final: source, echo: false).isEmpty, "sourceEcho follows the review, not the lint: \(current.rules(final: source, echo: false))")
        require(current.rules(final: translation, echo: true) == ["sourceEcho"], "the review's echo is reported: \(current.rules(final: translation, echo: true))")
        let report = TranslationOutputReport(
            requestID: UUID(), provider: "claude", attempt: 1, incremental: false, outcome: .accepted, early: false,
            rules: current.rules(final: review.text, echo: review.echo), coverage: review.coverage, candidates: review.candidates,
            hanjaReplaced: review.hanja.replaced, hanjaUnreadable: review.hanja.unreadable, hanjaKept: review.hanja.kept,
            hanjaInCode: review.hanja.inCode, preambleRemoved: false, codeKept: 1, codeRestored: 0, codeRefenced: 0, codeInserted: 0
        )
        let described = String(describing: report)
        for word in ["보안", "确", "clipboard", "paragraph"] {
            require(!described.contains(word), "a report never carries text: \(described)")
        }
        require(report.hanjaReplaced == 2 && report.hanjaKept == 6, "the report keeps the counts: \(report)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("TranslationOutputCheckTests failed: \(message)") }
    }
}
