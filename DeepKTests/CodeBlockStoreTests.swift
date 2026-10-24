import Foundation

/// 저장소에 연결한 코드 블록 가드(PR A–B 약속): 검사는 모델 입력으로 하고, 다시 요청도 같은 펜스를 싣고, 가드가 고친 글이
/// 화면·캐시·복사·삽입에 쓰인다. 빈 결과는 가드 전에 끝난다.
@MainActor
enum CodeBlockStoreTests {
    static func runAll() async {
        await mangledCodeIsRestoredShownAndCached()
        await droppedBlockIsInserted()
        await echoRetryKeepsTheFencesAndIsGuarded()
        await checksReadTheModelInput()
        await emptyOrFenceOnlyRepliesAreEmpty()
        await editAndRevertKeepTheGuardedText()
        await appendedSentenceKeepsGuardedBlocks()
        await fencesInsideCodeAreTheCode()
        await fenceOnlyAndPlainCopiesAreCachedApart()
        print("CodeBlockStoreTests passed")
    }

    /// impeccable 위젯: 선택된 탭 `Most Agents`는 정리본에서 코드 바로 위 줄이고, 모델 입력에서는 여는 펜스의 제목이다.
    private static let plain = "Run this to document your project:\nMost Agents\n/impeccable document\nIt scans the codebase and writes a context file for later sessions."
    private static let block = SourceCodeBlock(language: "text", code: "/impeccable document", title: "Most Agents")
    private static let markup = SourceMarkup(
        text: "Run this to document your project:\n```text title=\"Most Agents\"\n/impeccable document\n```\nIt scans the codebase and writes a context file for later sessions.",
        links: [], code: [], blocks: [block])
    private static let copied = CapturedSource(plain: plain, markup: markup)

    private static let before = "프로젝트를 문서화하려면 다음을 실행하세요:"
    private static let after = "코드베이스를 살펴보고 나중 세션을 위한 컨텍스트 파일을 작성합니다."
    /// 모델이 제목과 명령을 번역한 답.
    private static let mangled = "\(before)\n```text title=\"대부분의 에이전트\"\n/impeccable 문서\n```\n\(after)"
    private static let restored = "\(before)\n```text title=\"Most Agents\"\n/impeccable document\n```\n\(after)"

    private static func mangledCodeIsRestoredShownAndCached() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(copied)
        let request = await probe.nextRequest()
        require(request.input == plain && request.modelInput == markup.text && !request.usesInlineMarkup,
                "the model gets the fences, the identity stays plain, and the prompt is a plain copy's")
        let cached = store.testCacheEntryCount
        await probe.complete(request.id, with: mangled)
        await settle()
        require(store.status == .success && store.resultText == restored, "the restored text is the result: \(String(describing: store.resultText))")
        require(store.displayedText == restored, "the restored text is shown")
        require(store.resultFenceStyle == .none, "the page had no fences, so view copies drop them")
        require(store.resultCopy?.markdown == restored, "markdown copy keeps the opener and its title")
        require(store.resultInsertionText == "\(before)\n/impeccable document\n\(after)" && store.resultCopy?.plain == store.resultInsertionText,
                "plain copy and insert take the code without fences or title: \(String(describing: store.resultInsertionText))")
        require(store.testCacheEntryCount > cached, "the restored text is cached")
        let report = reports.all.last
        require(report?.outcome == .accepted && report?.codeKept == 0 && report?.codeRestored == 1
                && report?.codeRefenced == 0 && report?.codeInserted == 0, "the report counts the repair: \(String(describing: report))")
        let described = String(describing: reports.all)
        for word in ["impeccable", "Most Agents", "에이전트", "코드베이스"] {
            require(!described.contains(word), "a report never carries text: \(described)")
        }

        // Cleared and copied again: the cache returns the restored text, never the model's.
        store.editSource("", isComposing: false)
        store.invokeCopiedSource(copied)
        await settle()
        require(store.lastResultWasCached && store.resultText == restored && store.result?.markup == markup,
                "the cache hit is the restored text with its structure")
        // Re-invoking with the plain words reattaches the captured structure and stays a cache hit.
        store.invokeCopiedText(plain)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 1 && store.resultText == restored && store.result?.markup == markup, "the same copy is not requested again")
    }

    private static func droppedBlockIsInserted() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(copied)
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: "\(before)\n\(after)")
        await settle()
        require(store.resultText == restored, "a dropped block goes back where the source had it: \(String(describing: store.resultText))")
        let report = reports.all.last
        require(report?.codeInserted == 1 && report?.codeKept == 0, "the report counts the insert: \(String(describing: report))")
    }

    /// 다시 요청은 같은 모델 입력(펜스와 제목)을 싣고, 가드는 둘째 답에도 돈다.
    private static func echoRetryKeepsTheFencesAndIsGuarded() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(copied)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: first.modelInput)
        let second = await probe.nextRequest()
        require(second.attempt == 2 && second.input == first.input && second.markup == markup && second.modelInput == markup.text,
                "the retry resends the same markup")
        await probe.complete(second.id, with: mangled)
        await settle()
        require(store.resultText == restored && store.outputNotice == nil, "the second answer is guarded: \(String(describing: store.resultText))")
        require(reports.all.map(\.outcome) == [.retryingAfterEcho, .accepted] && reports.all.last?.codeRestored == 1, "reports: \(reports.all)")
    }

    /// 검사의 원문은 모델 입력이다. 펜스 안 로그 줄은 원문 반복 후보가 아니어서, 모델이 펜스를 빼고 그대로 옮겨도 다시 요청하지
    /// 않는다. 가드가 그 줄을 다시 펜스에 넣는다.
    private static func checksReadTheModelInput() async {
        let line = "The server started successfully and is now listening for new connections on port 8080."
        let plain = "Compare your log with this line:\n\(line)\nIf it differs, restart the server and check the configuration file again."
        let markup = SourceMarkup(
            text: "Compare your log with this line:\n```\n\(line)\n```\nIf it differs, restart the server and check the configuration file again.",
            links: [], code: [], blocks: [SourceCodeBlock(language: nil, code: line)])
        let answer = "로그를 이 줄과 비교하세요:\n\(line)\n다르면 서버를 다시 시작하고 설정 파일을 다시 확인하세요."
        // Control: read against the plain copy, the same answer would be an echo.
        let plainCheck = TranslationOutputCheck(source: plain, protecting: [plain], sourceLanguage: "en", targetLanguage: "ko",
                                                attempt: 1, retriesEcho: true, repairsHanja: true)
        require(plainCheck.review(answer).echo, "the control reads the unfenced log line as an echo")

        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup))
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: answer)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 1 && store.outputNotice == nil, "the kept log line is no echo: \(requests)")
        require(store.resultText == "로그를 이 줄과 비교하세요:\n```\n\(line)\n```\n다르면 서버를 다시 시작하고 설정 파일을 다시 확인하세요.",
                "the guard fences the line again: \(String(describing: store.resultText))")
        let report = reports.all.last
        require(report?.outcome == .accepted && report?.coverage == 0 && report?.codeRefenced == 1 && report?.rules.contains("sourceEcho") == false,
                "the report: \(String(describing: report))")
    }

    /// 빈 답과 펜스만 온 답은 가드가 블록을 넣기 전에 빈 결과로 끝나고, 아무것도 캐시하지 않는다.
    private static func emptyOrFenceOnlyRepliesAreEmpty() async {
        for reply in ["  \n", "```text title=\"Most Agents\"\n```", "```\n```\n"] {
            let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(copied)
            let request = await probe.nextRequest()
            let cached = store.testCacheEntryCount
            await probe.complete(request.id, with: reply)
            await settle()
            require(store.status == .error(.emptyResult) && store.result == nil, "\(reply.debugDescription) is an empty result: \(store.status)")
            require(store.testCacheEntryCount == cached && reports.all.isEmpty, "\(reply.debugDescription) is neither cached nor reported")
        }
    }

    /// 복사 영역 안을 고치면 구조 없이 번역하고, 정확히 되돌리면 가드가 고친 글이 캐시에서 돌아온다.
    private static func editAndRevertKeepTheGuardedText() async {
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(copied)
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: mangled)
        await settle()

        let changed = plain.replacingOccurrences(of: "document your project", with: "describe your project")
        store.editSource(changed, isComposing: false)
        let edited = await probe.nextRequest()
        require(edited.markup == nil && edited.modelInput == changed, "an edited captured prefix is plain")
        await probe.complete(edited.id, with: "고친 번역")
        await settle()
        require(store.resultText == "고친 번역", "the edited source's answer is not guarded")

        store.editSource(plain, isComposing: false)
        await settle()
        try? await Task.sleep(for: .milliseconds(5))
        require(store.lastResultWasCached && store.resultText == restored && store.result?.markup == markup,
                "undo brings back the guarded translation: \(String(describing: store.resultText))")
    }

    private static func appendedSentenceKeepsGuardedBlocks() async {
        let probe = TranslationProbe(), store = make(probe), reports = Reports(store)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(copied)
        await probe.complete((await probe.nextRequest()).id, with: mangled)
        await settle()

        let suffix = " Then commit it.", translatedSuffix = " 그런 다음 커밋하세요."
        let combined = plain + suffix
        store.editSource(combined, isComposing: false)
        let appended = await probe.nextRequest()
        require(appended.input == combined && appended.modelInput == markup.text + suffix
                    && appended.markup?.blocks == [block], "an unchanged copied prefix keeps its guarded block when extended")
        await probe.complete(appended.id, with: mangled + translatedSuffix)
        await settle()
        require(store.resultText == restored + translatedSuffix && reports.all.last?.codeRestored == 1,
                "the appended source's answer still restores mangled code")

        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        require(whole.modelInput == markup.text + suffix && whole.markup?.blocks == [block],
                "whole retranslation keeps the original block guard")
        await probe.complete(whole.id, with: mangled + translatedSuffix)
        await settle()
        let count = await probe.requestCount()
        store.editSource("", isComposing: false)
        store.invokeCopiedText(combined)
        await settle()
        require(await probe.requestCount() == count && store.lastResultWasCached
                    && store.resultText == restored + translatedSuffix && store.result?.markup?.blocks == [block],
                "the cache restores the guarded extension and its block metadata")
    }

    /// 코드에 ``` 줄이 있는 블록은 백틱 4개 앱 펜스로 실린다(RichSourceImporterTests의 README 복사와 같은 마크업). 페이지에는 펜스가
    /// 없었으므로 일반 복사·삽입은 앱 펜스와 언어를 빼고 코드의 ``` 줄은 그대로 둔다.
    private static func fencesInsideCodeAreTheCode() async {
        let code = "```js\nconsole.log(1)\n```"
        let plain = "Add this to your README:\n\(code)\nThen commit the file to your repository today."
        let markup = SourceMarkup(text: "Add this to your README:\n````markdown\n\(code)\n````\nThen commit the file to your repository today.",
                                  links: [], code: [], blocks: [SourceCodeBlock(language: "markdown", code: code)])
        let translated = "README에 다음을 추가하세요:\n````markdown\n\(code)\n````\n그런 다음 오늘 저장소에 파일을 커밋하세요."
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup))
        let request = await probe.nextRequest()
        require(request.modelInput == markup.text, "the model gets the four-backtick fence")
        await probe.complete(request.id, with: translated)
        await settle()
        require(store.resultText == translated && store.resultCopy?.markdown == translated, "markdown copy keeps the app fence: \(String(describing: store.resultText))")
        require(store.resultFenceStyle == .none, "the page had no fences: its code's own ``` lines are no fences of the source")
        let inserted = "README에 다음을 추가하세요:\n\(code)\n그런 다음 오늘 저장소에 파일을 커밋하세요."
        require(store.resultInsertionText == inserted && store.resultCopy?.plain == inserted,
                "plain copy and insert drop the app fence and keep the code's: \(String(describing: store.resultInsertionText))")

        // Fences the source writes outside the app's blocks still count.
        let fencedProse = "Run:\n```sh\nls\n```\nThen:\n\(code)"
        require(TranslationMarkup.FenceStyle(source: TranslationStore.fenceSource(fencedProse, markup: markup)) == .fenced
                && TranslationStore.fenceSource(plain, markup: nil) == plain, "prose fences keep a fenced source")
    }

    /// 같은 글이라도 펜스만 있는 복사와 일반 복사는 캐시를 나눠 쓴다. 펜스 없는 번역이 코드 블록 복사에 쓰이면 안 된다.
    private static func fenceOnlyAndPlainCopiesAreCachedApart() async {
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        require(markup.hasInlineStructure == false, "the copy has fences only")
        store.invokeCopiedSource(CapturedSource(plain: plain))
        let first = await probe.nextRequest()
        require(first.markup == nil && first.modelInput == plain, "a plain copy has no fences")
        let unfenced = "\(before)\nMost Agents\n/impeccable document\n\(after)"
        await probe.complete(first.id, with: unfenced)
        await settle()
        require(store.resultText == unfenced, "the plain copy's answer")

        store.invokeCopiedSource(copied)
        await settle()
        let requests = await probe.requestCount()
        require(requests == 2 && !store.lastResultWasCached, "the fenced copy is requested, not served the plain answer: \(requests)")
        let second = await probe.nextRequest()
        require(second.modelInput == markup.text, "with its fences")
        await probe.complete(second.id, with: restored)
        await settle()
        require(store.resultText == restored, "the fenced answer")

        // Each copy finds its own answer again.
        store.invokeCopiedSource(CapturedSource(plain: plain))
        await settle()
        require(store.lastResultWasCached && store.resultText == unfenced, "the plain copy hits its own entry: \(String(describing: store.resultText))")
        store.invokeCopiedSource(copied)
        await settle()
        let total = await probe.requestCount()
        require(total == 2 && store.lastResultWasCached && store.resultText == restored, "the fenced copy hits its own entry")

        // The same words with other fences (the page names another language) are another request too.
        let shell = SourceMarkup(text: markup.text.replacingOccurrences(of: "```text title=", with: "```sh title="), links: [], code: [],
                                 blocks: [SourceCodeBlock(language: "sh", code: "/impeccable document", title: "Most Agents")])
        store.invokeCopiedSource(CapturedSource(plain: plain, markup: shell))
        await settle()
        let third = await probe.requestCount()
        require(third == 3 && !store.lastResultWasCached, "other fences are not served the first fenced answer: \(third)")
        let last = await probe.nextRequest()
        require(last.modelInput == shell.text, "with the other fences")
        await probe.complete(last.id, with: restored.replacingOccurrences(of: "```text title=", with: "```sh title="))
        await settle()
    }

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

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "CodeBlockStoreTests: \(message)")
    }
}
