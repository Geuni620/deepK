import AppKit

/// Replays provider events through the real store and applies every display
/// snapshot to the real result surface, as the app does.
private actor IntegrationProbe {
    private var requests: [TranslationRequest] = []
    private var waiters: [CheckedContinuation<TranslationRequest, Never>] = []
    private var completions: [UUID: CheckedContinuation<String, Error>] = [:]

    func translate(_ request: TranslationRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            completions[request.id] = continuation
            if waiters.isEmpty { requests.append(request) } else { waiters.removeFirst().resume(returning: request) }
        }
    }

    func nextRequest() async -> TranslationRequest {
        if !requests.isEmpty { return requests.removeFirst() }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { fatalError("Expected translation request did not arrive within five seconds") }
        }
        defer { watchdog.cancel() }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func complete(_ id: UUID, with text: String) { completions.removeValue(forKey: id)?.resume(returning: text) }
    func fail(_ id: UUID, with error: Error) { completions.removeValue(forKey: id)?.resume(throwing: error) }
}

@main
@MainActor
private enum StableAppendIntegrationTests {
    static func main() async {
        _ = NSApplication.shared
        let probe = IntegrationProbe()
        let store = TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: nil), engineReady: true,
                                     translator: { try await probe.translate($0) })
        let scroll = TranslationResultTextView.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        scroll.layoutSubtreeIfNeeded()
        let view = scroll.documentView as! NSTextView
        var settings = ResultDisplaySettings.standard
        func apply() {
            let display = store.display
            TranslationResultTextView.update(scroll, content: TranslationResultContent(
                identity: display.identity, text: display.text ?? "", tailStart: display.tailStart,
                isStreaming: store.status == .translating, isStale: display.isStale, inline: display.inline,
                unitBreaks: display.unitBreaks
            ), lineSpacing: 3, display: settings)
        }
        func settle() async {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            apply()
        }

        let a = (1...12).map { "Paragraph \($0) of the original article, which the reader is reading." }.joined(separator: " ")
        let translatedA = (1...30).map { "원래 글의 \($0)번째 문단을 읽고 있습니다." }.joined(separator: "\n\n")
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(a)
        let first = await probe.nextRequest()
        store.receivePartialText("원래 글의", for: first)
        await settle()
        await probe.complete(first.id, with: translatedA)
        await settle()
        require(view.string == translatedA && scroll.contentView.bounds.origin.y == 0, "first translation starts at the top")

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        let selection = NSRange(location: 40, length: 12)
        view.setSelectedRange(selection)
        func requireReaderUnmoved(_ step: String) {
            require(abs(scroll.contentView.bounds.origin.y - 200) < 1, "\(step): reading position must not move")
            require(view.selectedRange() == selection, "\(step): selection must not move")
            require(view.string.hasPrefix(translatedA), "\(step): text being read must not change")
        }

        let b = "I've also built agents (various kinds) over the years."
        store.invokeCopiedText(a + "\n\n" + b)
        let tail = await probe.nextRequest()
        require(tail.input == b, "only the appended paragraph is requested")
        await settle()
        requireReaderUnmoved("pending tail")
        for partial in ["에이전트", "에이전트도 여러 해", "에이전트도 여러 해 동안 만들었다.\n"] {
            store.receivePartialText(partial, for: tail)
            await settle()
            requireReaderUnmoved("streaming tail")
        }
        await probe.complete(tail.id, with: "에이전트도 여러 해 동안 만들었다.")
        await settle()
        requireReaderUnmoved("completed tail")
        require(store.canCopy && view.string == store.resultText, "the surface shows the completed result")

        let c = "Speaking of surfacing things, I want to inspect every aspect."
        store.invokeCopiedText(a + "\n\n" + b + "\n\n" + c)
        let failing = await probe.nextRequest()
        store.receivePartialText("표면화에 대해 말하자면", for: failing)
        await settle()
        await probe.fail(failing.id, with: TranslationStoreError.timedOut)
        await settle()
        requireReaderUnmoved("failed tail")
        store.invokeCopiedText(store.sourceText)
        let retry = await probe.nextRequest()
        require(retry.input == c, "retry requests only the failed paragraph")
        await probe.complete(retry.id, with: "표면화에 대해 말하자면, 모든 측면을 보고 싶다.")
        await settle()
        requireReaderUnmoved("retried tail")

        // Dropping the unit being read continues with the text that followed it.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, view.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        require(topLine(of: scroll).hasPrefix("원래 글의"), "the reader is still in the first unit")
        store.invokeCopiedText(b + "\n\n" + c)
        await settle()
        require(store.canCopy && topLine(of: scroll).hasPrefix("에이전트도"), "removing the unit being read shows what followed it")
        require(scroll.documentVisibleRect.minY <= 1, "no blank space is kept above the remaining text")

        // A whole retranslation keeps the old text readable, then replaces it in place.
        let identity = store.display.identity
        let origin = scroll.contentView.bounds.origin.y
        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        await settle()
        require(store.display.isStale && abs(scroll.contentView.bounds.origin.y - origin) < 1, "stale text stays in place")
        await probe.complete(whole.id, with: "문맥을 포함한 전체 번역.")
        await settle()
        require(store.display.identity == identity && view.string == "문맥을 포함한 전체 번역.", "replacement uses the same surface")

        // A finished block closed by its own last line stays while it is superseded or the next unit has no text yet.
        let named = "실행:\n```deploy\n```"
        store.invokeCopiedText("Run the command.")
        let run = await probe.nextRequest()
        await probe.complete(run.id, with: named)
        await settle()
        store.retranslateWholeDocument()
        let again = await probe.nextRequest()
        await settle()
        require(store.display.isStale && view.string == "실행:\ndeploy", "superseded text keeps its last block")
        await probe.complete(again.id, with: named)
        await settle()
        let deploy = (view.string as NSString).range(of: "deploy")
        view.setSelectedRange(deploy)
        store.invokeCopiedText("Run the command.\n\nThen check the logs.")
        let next = await probe.nextRequest()
        await settle()
        require(next.input == "Then check the logs." && view.string == "실행:\ndeploy" && view.selectedRange() == deploy,
                "the finished block and its selection stay while the next unit is pending")
        store.receivePartialText("그다음 로그를", for: next)
        await settle()
        require(view.string == "실행:\ndeploy\n\n그다음 로그를" && view.selectedRange() == deploy, "the next unit only appends")

        // A copied page with a link and inline code streams its words at once; markers never show.
        let harness = SourceLink(url: URL(string: "https://blog.example.com/harness")!, text: "the best harness")
        let page = CapturedSource(plain: "Use read. Check it out: the best harness.", markup: SourceMarkup(
            text: "Use `read`. Check it out: <a1>the best harness</a1>.", links: [harness], code: ["read"]))
        store.invokeCopiedSource(page)
        let structured = await probe.nextRequest()
        require(structured.modelInput == page.markup?.text && structured.input == page.plain, "the model gets the markup")
        var streamed = ""
        var shown = ""
        for chunk in ["`re", "ad`를 쓰세요. 확인: <", "a1", ">최고의 하네스", "</a", "1>."] {
            streamed += chunk
            store.receivePartialText(streamed, for: structured)
            await settle()
            require(view.string.utf16.starts(with: shown.utf16) && !view.string.contains("<") && !view.string.contains("`"),
                    "structured stream appends display text only: \(chunk)")
            shown = view.string
        }
        await probe.complete(structured.id, with: streamed)
        await settle()
        let words = view.string as NSString
        require(view.string == "read를 쓰세요. 확인: 최고의 하네스.", "final display")
        require(view.textStorage!.attribute(.link, at: words.range(of: "하네스").location, effectiveRange: nil) as? URL == harness.url, "the link resolves")
        require(view.textStorage!.attribute(.deepKInlineCode, at: 0, effectiveRange: nil) != nil, "the chip is styled")

        // U1: after code symbols and an explicit `---` boundary, only the unit below is requested. It appends below
        // a drawn line; the reader, the selection and T(A) never move, and no `---` reaches the surface.
        let codeA = "Set x = 1 | y before the build. " + (1...10).map { "Step \($0) follows." }.joined(separator: " ")
        let codeT = (1...30).map { "빌드 전에 x = 1 | y로 설정하는 \($0)번째 단계입니다." }.joined(separator: "\n\n")
        let surface = scroll as! ResultScrollView
        store.invokeCopiedText(codeA)
        let unitA = await probe.nextRequest()
        await probe.complete(unitA.id, with: codeT)
        await settle()
        require(view.string == codeT && surface.unitLineRects.isEmpty, "one unit, no line")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        view.setSelectedRange(selection)
        func requireUnitAUnmoved(_ step: String) {
            require(abs(scroll.contentView.bounds.origin.y - 200) < 1 && view.selectedRange() == selection, "\(step): the reader must not move")
            require(view.string.hasPrefix(codeT) && !view.string.contains("-"), "\(step): T(A) stays and no `---` is shown")
        }
        let below = "Keep the earlier answer readable above the line."
        store.invokeCopiedText(codeA + "\n\n---\n\n" + below)
        let unitB = await probe.nextRequest()
        require(unitB.input == below && unitB.markup == nil, "only the unit after the boundary is requested")
        await settle()
        requireUnitAUnmoved("pending unit")
        require(store.display.unitBreaks.isEmpty && surface.unitLineRects.isEmpty, "no line before B has text")
        let breaks = [codeT.utf16.count]
        for partial in ["앞 답변을", "앞 답변을 선 위에", "앞 답변을 선 위에서 읽을 수 있게 둡니다.\n"] {
            store.receivePartialText(partial, for: unitB)
            await settle()
            requireUnitAUnmoved("streaming unit")
            require(store.display.unitBreaks == breaks && surface.unitLineRects.count == 1, "the line is drawn while B streams")
        }
        let translatedB = "앞 답변을 선 위에서 읽을 수 있게 둡니다."
        await probe.complete(unitB.id, with: translatedB)
        await settle()
        requireUnitAUnmoved("completed unit")
        require(view.string == codeT + "\n\n" + translatedB && store.display.unitBreaks == breaks, "T(A), a line and T(B)")
        let layout = view.layoutManager!, top = view.textContainerOrigin.y
        let aBottom = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: codeT.utf16.count - 1), effectiveRange: nil).maxY
        let bTop = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: codeT.utf16.count + 2), effectiveRange: nil).minY
        let unitLines = surface.unitLineRects
        require(unitLines.count == 1 && unitLines[0].minY >= aBottom + top && unitLines[0].maxY <= bTop + top, "the line sits between T(A) and T(B)")
        require(store.resultCopy?.plain == codeT + "\n\n" + translatedB && store.resultInsertionText?.contains("---") == false,
                "copy and insert join the units with one blank line")
        // A fenced block streamed in another style with the source pill only appends, its opener's title heads it once the
        // opener is complete, and its copy control copies the code.
        settings.style = .github
        settings.showsLinkSource = true
        let guide = SourceLink(url: URL(string: "https://docs.example.com/install")!, text: "the guide")
        store.invokeCopiedSource(CapturedSource(plain: "Install it with the guide:\nnpm\nnpm install deepk\nnpm test", markup: SourceMarkup(
            text: "Install it with <a1>the guide</a1>:\n```sh title=\"npm\"\nnpm install deepk\nnpm test\n```", links: [guide], code: [])))
        let fenced = await probe.nextRequest()
        streamed = ""
        shown = ""
        for chunk in ["<a1>안내서</a1>로 설치합니다:\n``", "`sh title=\"n", "pm\"\nnpm inst", "all deepk\nnpm", " test\n``", "`"] {
            streamed += chunk
            store.receivePartialText(streamed, for: fenced)
            await settle()
            require(view.string.utf16.starts(with: shown.utf16) && !view.string.contains("`") && !view.string.contains("<"),
                    "a styled fenced stream appends display text only: \(chunk)")
            let result = view as! ResultTextView
            require(result.codeBoxes().allSatisfy { result.headerLabel(of: $0) == "npm · sh" }, "the header has the whole title: \(chunk)")
            shown = view.string
        }
        await probe.complete(fenced.id, with: streamed)
        await settle()
        require(view.string == "안내서로 설치합니다:\nnpm install deepk\nnpm test", "fenced final display")
        let result = view as! ResultTextView
        require(result.codeBoxes().compactMap(result.headerLabel(of:)) == ["npm · sh"], "the completed block keeps its title")
        let title = (view.string as NSString).range(of: "안내서")
        require((view.textStorage!.attribute(.kern, at: NSMaxRange(title) - 1, effectiveRange: nil) as? CGFloat ?? 0) > 0, "the link has its pill")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            pasteboard.releaseGlobally()
        }
        let box = result.codeBoxes()
        require(box.count == 1, "one box")
        let hit = box[0].geometry.copyHit
        let control = result.chromeControl(at: NSPoint(x: hit.midX, y: hit.midY))
        require(control.map { result.perform($0) } == true && pasteboard.string(forType: .string) == "npm install deepk\nnpm test",
                "the block's copy control copies its code")

        // With the default display (Native, 문법 색, 긴 코드 접기 at 5 lines) a block longer than the limit streams colored and
        // folds as it grows: the text only appends, and every copy keeps the folded lines.
        settings = .standard
        store.invokeCopiedText("Read the setup code.")
        let setup = await probe.nextRequest()
        streamed = ""
        shown = ""
        let lines = (1...8).map { "const value\($0) = getValue(\($0));" }
        let chunks = ["설정 코드를 읽으세요.\n``", "`ts\n"] + lines.map { $0 + "\n" } + ["```"]
        for chunk in chunks {
            streamed += chunk
            store.receivePartialText(streamed, for: setup)
            await settle()
            require(view.string.utf16.starts(with: shown.utf16) && !view.string.contains("`"), "a colored, folding stream appends only: \(chunk)")
            for box in result.codeBoxes() {
                require(box.fold.isFolded == (box.fold.lineCount > 5), "the block folds as it grows: \(chunk)")
            }
            shown = view.string
        }
        await probe.complete(setup.id, with: streamed)
        await settle()
        let folded = result.codeBoxes()
        require(folded.count == 1 && folded[0].fold.isFolded && folded[0].fold.lineCount == 8, "the completed block is folded to five lines")
        let keyword = (view.string as NSString).range(of: "const value8").location
        require(view.textStorage!.attribute(.foregroundColor, at: keyword, effectiveRange: nil) as? NSColor
                == ResultStyle.native.syntax!.keyword.nsColor, "the code is colored")
        require(result.perform(.copy(folded[0].key)) && pasteboard.string(forType: .string) == lines.joined(separator: "\n"),
                "the block's copy control copies the folded lines")
        require(store.resultText?.contains("const value8") == true, "the store's copy holds every line")

        // Han leaked into Korean prose streams as Hangul next to a code block; a run still open is held back, never rewritten.
        store.invokeCopiedText("A secure connection is required.\n\n```swift\nlet label = \"value\"\n```\n\nCheck that point.")
        let leaked = await probe.nextRequest()
        await settle()
        var answer = ""
        var seen = view.string
        for chunk in ["보안이 确", "保된 연결이 필요합니다.\n\n", "```swift\nlet label = \"确保\"\n", "```\n\n그 点", "을 확인하세요."] {
            answer += chunk
            store.receivePartialText(answer, for: leaked)
            await settle()
            require(view.string.utf16.starts(with: seen.utf16), "a repaired stream only appends: \(view.string)")
            seen = view.string
        }
        await probe.complete(leaked.id, with: answer)
        await settle()
        require(view.string.hasPrefix(seen) && view.string.hasPrefix("보안이 확보된 연결이 필요합니다.") && view.string.hasSuffix("그 점을 확인하세요."),
                "Hangul in prose: \(view.string)")
        require(view.string.contains("let label = \"确保\""), "Han in code is never touched: \(view.string)")
        print("StableAppendIntegrationTests passed (no windows opened)")
    }

    private static func topLine(of scroll: NSScrollView) -> String {
        let view = scroll.documentView as! NSTextView
        let point = NSPoint(x: 1, y: scroll.contentView.bounds.minY - view.textContainerOrigin.y)
        let glyph = view.layoutManager!.glyphIndex(for: point, in: view.textContainer!)
        var range = NSRange()
        view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        return (view.string as NSString).substring(with: view.layoutManager!.characterRange(forGlyphRange: range, actualGlyphRange: nil))
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "StableAppendIntegrationTests: \(message)")
    }
}
