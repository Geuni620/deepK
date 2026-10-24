import Foundation

/// 저장소에 연결한 출력 검사: 원문 반복의 1회 재요청, 남은 반복의 경고와 캐시 제외, 한자 치환, 보고.
@MainActor
enum OutputCheckStoreTests {
    static func runAll() async {
        await echoWhileStreamingIsRequestedAgain()
        await echoAtCompletionIsRequestedAgain()
        await echoTwiceIsFlaggedAndNeverCached()
        await hanIsRepairedAndCached()
        await echoInATailRetriesOnlyTheTail()
        await editDuringTheRetryCancelsIt()
        await killSwitches()
        await preambleAndRepeatedCodeAreNotRetried()
        await codeAfterAChatFenceIsNotAnEcho()
        await aKeptLogLineIsNotRetried()
        await aCosmeticEditKeepsTheSecondAttempt()
        switchesComeFromUserDefaults()
        print("OutputCheckStoreTests passed")
    }

    private static let source = """
    When a user copies a paragraph twice, the application should show the copied text and start translating without another click. The first copy must still work normally in the original application.

    The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed.
    """

    private static let translation = """
    사용자가 단락을 두 번 복사하면 애플리케이션은 복사한 텍스트를 보여 주고 추가 클릭 없이 번역을 시작해야 합니다. 첫 번째 복사는 원래 애플리케이션에서 계속 정상적으로 동작해야 합니다.

    클립보드는 키보드 이벤트가 도착한 뒤에 바뀔 수 있습니다. 현재 복사를 잠시 기다리되, 복사에 실패했다면 이전 클립보드 내용을 보내지 마세요.
    """

    /// 원문 첫 문단(두 문장): 반복 비율이 0.3을 넘어 원문 반복으로 판정된다.
    private static let firstParagraph = String(source.prefix { $0 != "\n" })

    private static func echoWhileStreamingIsRequestedAgain() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        let identity = store.display.identity
        require(first.attempt == 1, "a copy starts with attempt 1")

        store.receivePartialText(firstParagraph, for: first)
        let second = await probe.nextRequest()
        require(second.attempt == 2 && second.id != first.id && second.input == first.input && second.modelInput == first.modelInput,
                "the echo is requested again for the same unit")
        await waitForCancellation(of: first, in: probe)
        require(store.outputNotice == .retryingAfterEcho && store.isRetryingAfterEcho && store.status == .translating,
                "the retry is shown while it runs")
        require(store.displayedText == nil && store.display.identity != identity, "the echoed draft is cleared and the surface starts over")

        // Late callbacks of the first attempt change nothing.
        store.receivePartialText(source, for: first)
        await probe.complete(first.id, with: source)
        await settleStream()
        require(store.displayedText == nil && store.isRetryingAfterEcho && store.status == .translating, "attempt 1 is ignored once replaced")

        store.receivePartialText("사용자가 단락을", for: second)
        await settleStream()
        require(store.displayedText == "사용자가 단락을", "the second attempt streams")
        await probe.complete(second.id, with: translation)
        await settle()
        require(store.status == .success && store.resultText == translation && store.canCopy && store.canInsert,
                "the second answer is the result")
        require(store.outputNotice == nil && !store.isRetryingAfterEcho, "a successful retry leaves no notice")
        let requests = await probe.requestCount()
        require(requests == 2, "one retry only: \(requests)")

        let log = reports.all
        require(log.map(\.outcome) == [.retryingAfterEcho, .accepted], "reports: \(log)")
        require(log[0].early && log[0].attempt == 1 && log[0].requestID == first.id && log[0].rules == ["sourceEcho"]
                && log[0].coverage >= 0.3 && log[0].candidates == 4, "the retry report: \(log[0])")
        require(!log[1].early && log[1].attempt == 2 && log[1].requestID == second.id && log[1].rules.isEmpty && log[1].coverage == 0,
                "the accepted report: \(log[1])")
        let described = String(describing: log)
        for word in ["clipboard", "paragraph", "사용자", "단락"] {
            require(!described.contains(word), "a report never carries text: \(described)")
        }

        // The checked translation is cached.
        store.editSource("", isComposing: false)
        store.invokeCopiedText(source)
        require(store.lastResultWasCached && store.resultText == translation, "the retried translation is cached")
    }

    /// 조각이 없는 경로(Claude one-shot 등)는 완료 시점에만 다시 요청한다.
    private static func echoAtCompletionIsRequestedAgain() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: source)
        let second = await probe.nextRequest()
        await settle()
        require(second.attempt == 2 && second.input == first.input, "a completed echo is requested again")
        require(!(await probe.wasCancelled(first.id)), "a completed answer needs no cancellation")
        require(store.outputNotice == .retryingAfterEcho && store.result == nil && !store.canCopy, "the echo is never the result")
        await probe.complete(second.id, with: translation)
        await settle()
        require(store.resultText == translation && store.outputNotice == nil, "the second answer is the result")
        let log = reports.all
        require(log.map(\.outcome) == [.retryingAfterEcho, .accepted] && !log[0].early && log[0].coverage == 1, "reports: \(log)")
    }

    private static func echoTwiceIsFlaggedAndNeverCached() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: source)
        let second = await probe.nextRequest()
        let cached = store.testCacheEntryCount

        // The second attempt is never cut short.
        store.receivePartialText(firstParagraph, for: second)
        await settleStream()
        require(store.displayedText == firstParagraph, "attempt 2 shows its stream")
        await probe.complete(second.id, with: source)
        await settle()
        require(!(await probe.wasCancelled(second.id)), "attempt 2 is never aborted")
        let requests = await probe.requestCount()
        require(requests == 2, "no third request: \(requests)")
        require(store.status == .success && store.resultText == source && store.outputNotice == .unresolvedEcho,
                "a remaining echo is shown with the warning")
        require(store.canCopy && store.canInsert, "a flagged result can still be copied and inserted")
        require(store.testCacheEntryCount == cached, "a remaining echo is not cached")
        let last = reports.all.last
        require(last?.outcome == .unresolvedEcho && last?.attempt == 2 && last?.rules.contains("sourceEcho") == true,
                "the unresolved report: \(String(describing: last))")

        // The same copy again keeps today's dedupe.
        store.invokeCopiedText(source)
        let deduped = await probe.requestCount()
        require(deduped == 2 && store.outputNotice == .unresolvedEcho, "the same copy is not requested again")

        // '전체 다시 번역' is a fresh first attempt that may be retried again.
        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        require(whole.attempt == 1 && store.outputNotice == nil && store.display.isStale, "a whole retranslation starts over")
        await probe.complete(whole.id, with: translation)
        await settle()
        require(store.resultText == translation && store.outputNotice == nil, "the whole retranslation replaces the flagged result")

        // Cleared and copied again: the translation comes from the cache, never the echo.
        store.editSource("", isComposing: false)
        store.invokeCopiedText(source)
        require(store.lastResultWasCached && store.resultText == translation, "only the checked translation was cached")
    }

    private static func hanIsRepairedAndCached() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        let english = "A secure connection is required. If you have any questions, contact us at any time."
        let repaired = "보안이 확보된 연결이 필요합니다. 궁금한 점이 있으면 언제든지 문의해 주세요."
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(english)
        let request = await probe.nextRequest()
        store.receivePartialText("보안이 确", for: request)
        await settleStream()
        require(store.displayedText == "보안이", "an undecided Han run is withheld: \(String(describing: store.displayedText))")
        store.receivePartialText("보안이 确保된", for: request)
        await settleStream()
        require(store.displayedText == "보안이 확보된", "the stream shows Hangul: \(String(describing: store.displayedText))")
        await probe.complete(request.id, with: "보안이 确保된 연결이 필요합니다. 궁금한 点이 있으면 언제든지 문의해 주세요.")
        await settle()
        require(store.resultText == repaired, "the result is repaired: \(String(describing: store.resultText))")
        let last = reports.all.last
        require(last?.outcome == .accepted && last?.hanjaReplaced == 3 && last?.rules.contains("foreignScript") == false,
                "the report counts the repair: \(String(describing: last))")
        store.editSource("", isComposing: false)
        store.invokeCopiedText(english)
        require(store.lastResultWasCached && store.resultText == repaired, "the repaired text is cached")

        // Han the source itself wrote is kept.
        store.invokeCopiedText("Write 漢字 in the title.")
        let kept = await probe.nextRequest()
        await probe.complete(kept.id, with: "제목에 漢字를 쓰세요.")
        await settle()
        require(store.resultText == "제목에 漢字를 쓰세요." && reports.all.last?.hanjaReplaced == 0, "source Han is never replaced")
    }

    private static func echoInATailRetriesOnlyTheTail() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        let a = "First paragraph."
        let b = "The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed."
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(a)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: "첫 문단.")
        await settle()
        let cached = store.testCacheEntryCount

        store.invokeCopiedText(a + "\n\n" + b)
        let tail = await probe.nextRequest()
        require(tail.input == b && tail.attempt == 1, "only the new paragraph is requested")
        // 두 문장인 꼬리는 두 문장이 모두 그대로 나와야 반복이다.
        store.receivePartialText("The clipboard may update after the keyboard event arrives. Wait", for: tail)
        await settleStream()
        require(!(await probe.wasCancelled(tail.id)), "one echoed sentence of a two-sentence tail is not an echo yet")
        store.receivePartialText(b, for: tail)
        let retry = await probe.nextRequest()
        require(retry.input == b && retry.attempt == 2, "only the tail is requested again")
        await waitForCancellation(of: tail, in: probe)
        require(store.displayedText == "첫 문단." && store.outputNotice == .retryingAfterEcho, "the completed unit stays while the tail retries")

        await probe.complete(retry.id, with: b)
        await settle()
        let segments = store.displaySegments
        require(store.status == .success && store.outputNotice == .unresolvedEcho && segments.count == 2,
                "the tail that still echoes is flagged")
        require(segments[0].text == "첫 문단." && !segments[0].unresolvedEcho && segments[1].unresolvedEcho, "only the tail carries the flag")
        require(store.testCacheEntryCount == cached, "neither the tail nor a prefix holding it is cached")
        require(reports.all.map(\.incremental) == [false, true, true]
                && reports.all.map(\.outcome) == [.accepted, .retryingAfterEcho, .unresolvedEcho], "reports: \(reports.all)")

        // Dropping the first paragraph keeps the flag on the remaining unit.
        store.invokeCopiedText(b)
        await settle()
        require(store.displaySegments.count == 1 && store.outputNotice == .unresolvedEcho, "the flag survives a retained suffix")
    }

    private static func editDuringTheRetryCancelsIt() async {
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        store.receivePartialText(firstParagraph, for: first)
        let second = await probe.nextRequest()
        store.editSource("Please translate this other sentence instead of the copied text.", isComposing: false)
        await waitForCancellation(of: second, in: probe)
        require(!store.isRetryingAfterEcho && store.outputNotice == nil, "an edit ends the retry")
        let third = await probe.nextRequest()
        require(third.attempt == 1, "the edited source starts with attempt 1")
        await probe.complete(third.id, with: "복사한 텍스트 대신 이 다른 문장을 번역해 주세요.")
        await settle()
        require(store.status == .success, "the edited source completes")
    }

    private static func killSwitches() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.retriesSourceEcho = false
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        store.receivePartialText(firstParagraph, for: first)
        await settleStream()
        let cancelled = await probe.wasCancelled(first.id)
        require(store.displayedText == firstParagraph && !cancelled, "without the retry an echo streams on")
        let cached = store.testCacheEntryCount
        await probe.complete(first.id, with: source)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 1 && store.outputNotice == .unresolvedEcho && store.testCacheEntryCount == cached,
                "without the retry an echo is flagged at once and not cached")
        require(reports.all.map(\.outcome) == [.unresolvedEcho] && reports.all[0].attempt == 1, "reports: \(reports.all)")

        let rawProbe = TranslationProbe(), raw = make(rawProbe)
        raw.repairsHanja = false
        raw.setDirection(.englishToKorean)
        raw.invokeCopiedText("A secure connection is required.")
        let request = await rawProbe.nextRequest()
        raw.receivePartialText("보안이 确保된", for: request)
        await settleStream()
        require(raw.displayedText == "보안이 确保된", "without the repair the stream keeps Han")
        await rawProbe.complete(request.id, with: "보안이 确保된 연결이 필요합니다.")
        await settle()
        require(raw.resultText == "보안이 确保된 연결이 필요합니다.", "without the repair the result keeps Han")
    }

    private static func preambleAndRepeatedCodeAreNotRetried() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Hello there, it is nice to meet you today.")
        let greeting = await probe.nextRequest()
        await probe.complete(greeting.id, with: "번역: 안녕하세요, 오늘 만나서 반갑습니다.")
        await settle()
        require(store.resultText == "안녕하세요, 오늘 만나서 반갑습니다." && reports.all.last?.preambleRemoved == true,
                "a fixable preamble is cut at completion: \(String(describing: store.resultText))")

        let code = """
        Context handoff works across providers:

        import { getModel, complete } from '@mariozechner/pi-ai';

        // Start with Claude
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);

        The reply keeps the previous messages.
        """
        let answer = """
        컨텍스트 전달은 제공자 간에도 동작합니다:

        ```typescript
        import { getModel, complete } from '@mariozechner/pi-ai';

        // Claude로 시작
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);
        ```

        응답은 이전 메시지를 유지합니다.
        """
        store.invokeCopiedText(code)
        let request = await probe.nextRequest()
        store.receivePartialText(answer, for: request)
        await probe.complete(request.id, with: answer)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 2 && store.status == .success && reports.all.last?.outcome == .accepted,
                "code repeated from the source is not an echo: \(requests)")
    }

    /// 한 낱말 채팅식 펜스(```pwd) 뒤의 맨 펜스 로그 블록은 결과 창처럼 코드다. 로그를 그대로 옮긴 올바른 번역은
    /// 스트리밍 중에 끊기지 않고, 경고 없이 캐시된다.
    private static func codeAfterAChatFenceIsNotAnEcho() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        let source = """
        Check where you are first.
        ```pwd
        /home/user/project```
        Then compare your log with the expected output below.
        ```
        The server started successfully and is now listening for new connections on port 8080.
        All background workers have been initialized and are ready to accept new jobs.
        ```
        That is all you need.
        """
        let translation = """
        먼저 현재 위치를 확인하세요.
        ```pwd
        /home/user/project```
        그런 다음 로그를 아래의 예상 출력과 비교하세요.
        ```
        The server started successfully and is now listening for new connections on port 8080.
        All background workers have been initialized and are ready to accept new jobs.
        ```
        이것으로 충분합니다.
        """
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let request = await probe.nextRequest()
        let cached = store.testCacheEntryCount
        var prefix = ""
        for line in translation.split(separator: "\n", omittingEmptySubsequences: false) {
            prefix += prefix.isEmpty ? String(line) : "\n" + line
            store.receivePartialText(prefix, for: request)
        }
        await settleStream()
        let cancelled = await probe.wasCancelled(request.id)
        require(!cancelled && !store.isRetryingAfterEcho, "a correct translation that keeps the log is never cut short")
        await probe.complete(request.id, with: translation)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 1 && store.status == .success && store.resultText == translation && store.outputNotice == nil,
                "the translation is the result without a warning: \(requests) \(String(describing: store.outputNotice))")
        require(store.testCacheEntryCount > cached, "the translation is cached")
        require(reports.all.map(\.outcome) == [.accepted] && reports.all[0].candidates == 2 && reports.all[0].coverage == 0,
                "reports: \(reports.all)")
    }

    /// 두 문장인 원문에서 로그 한 줄을 영어 그대로 둔 번역은 원문 반복이 아니다. 다시 요청하지 않고 캐시한다.
    private static func aKeptLogLineIsNotRetried() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        let source = "Run npm install in the project folder and wait for it to finish.\nadded 245 packages from 120 contributors and audited 300 packages in 5s"
        let answer = "프로젝트 폴더에서 npm install을 실행하고 끝날 때까지 기다리세요.\nadded 245 packages from 120 contributors and audited 300 packages in 5s"
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let request = await probe.nextRequest()
        let cached = store.testCacheEntryCount
        store.receivePartialText(answer, for: request)
        await settleStream()
        let cancelled = await probe.wasCancelled(request.id)
        require(!cancelled && !store.isRetryingAfterEcho, "a kept log line never cuts the stream short")
        await probe.complete(request.id, with: answer)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 1 && store.status == .success && store.resultText == answer && store.outputNotice == nil,
                "the translation is the result without a retry: \(requests) \(String(describing: store.outputNotice))")
        require(store.testCacheEntryCount > cached, "the translation is cached")
        require(reports.all.map(\.outcome) == [.accepted] && reports.all[0].candidates == 2, "reports: \(reports.all)")
    }

    /// 재요청 중 결과가 같은 편집(끝 줄바꿈)은 진행 중인 요청을 그대로 쓴다. 그 요청은 둘째 시도로 남아 다시 반복이어도
    /// 세 번째 요청을 보내지 않는다(`reuseEquivalentActiveRequest`의 `attempt`).
    private static func aCosmeticEditKeepsTheSecondAttempt() async {
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(source)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: source)
        let second = await probe.nextRequest()
        await settle()
        require(second.attempt == 2 && store.isRetryingAfterEcho, "the echo is requested again")
        store.editSource(source + "\n", isComposing: false)
        await settle()
        let cancelled = await probe.wasCancelled(second.id)
        require(!cancelled && store.status == .translating, "a trailing newline keeps the second attempt running")
        await probe.complete(second.id, with: source)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 2 && store.status == .success && store.outputNotice == .unresolvedEcho,
                "the reused request is still attempt 2: \(requests) \(String(describing: store.outputNotice))")
    }

    /// 앱이 읽는 비상 스위치(`outputEchoRetry`, `outputHanjaRepair`). 키가 없으면 켜져 있다.
    private static func switchesComeFromUserDefaults() {
        let suite = "com.deepk.tests.output-switches.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return require(false, "a test defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = make(TranslationProbe())
        store.applyOutputCheckSwitches(from: defaults)
        require(store.retriesSourceEcho && store.repairsHanja, "both checks are on by default")
        defaults.set(false, forKey: "outputEchoRetry")
        store.applyOutputCheckSwitches(from: defaults)
        require(!store.retriesSourceEcho && store.repairsHanja, "outputEchoRetry turns only the echo retry off")
        defaults.removeObject(forKey: "outputEchoRetry")
        defaults.set(false, forKey: "outputHanjaRepair")
        store.applyOutputCheckSwitches(from: defaults)
        require(store.retriesSourceEcho && !store.repairsHanja, "outputHanjaRepair turns only the repair off")
    }

    /// 저장소가 보낸 보고를 모은다.
    @MainActor
    private final class Reports {
        private(set) var all: [TranslationOutputReport] = []

        init(_ store: TranslationStore) {
            store.onOutputReport = { [weak self] in self?.all.append($0) }
        }
    }

    private static func make(_ probe: TranslationProbe) -> TranslationStore {
        TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: nil), engineReady: true,
                         translator: { try await probe.translate($0) })
    }

    private static func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }

    /// 조각은 50ms씩 묶어 보인다.
    private static func settleStream() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    /// 취소는 가짜 번역기의 별도 작업으로 기록되므로 기록될 때까지 기다린다.
    private static func waitForCancellation(of request: TranslationRequest, in probe: TranslationProbe) async {
        for _ in 0..<200 {
            if await probe.wasCancelled(request.id) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        require(false, "the request was not cancelled: attempt \(request.attempt)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "OutputCheckStoreTests: \(message)")
    }
}
