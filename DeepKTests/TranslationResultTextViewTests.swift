import AppKit
import Observation

@main
@MainActor
private struct TranslationResultTextViewTests {
    static func main() {
        _ = NSApplication.shared
        readingPositionIsNeverMovedByUpdates()
        shortResultDoesNotFollowAppendedText()
        completionDifferencesEditOnlyTheTail()
        removedTextKeepsTheReader()
        identityControlsResets()
        pureHelpers()
        newContentHint()
        firstResponderKeepsPosition()
        draftsAndStaleTextCannotBeCopied()
        hintFollowsEditsAndReader()
        announcementsOnlyForCompletedText()
        lostLinesAreFoundOrClamped()
        repeatedLinesAndProxyAttach()
        codeBlocks()
        codeLinePitch()
        codeBlocksWhileStreaming()
        clipboard()
        inlineChipsAndLinks()
        inlineWhileStreaming()
        inlineClipboard()
        inlineReview()
        secondReview()
        fourthReview()
        singleWordChatCommandsDisplayAndCopy()
        singleWordChatCommandsRespectCopyLimits()
        unknownTagsKeepTheirLabelAndCopies()
        unitBreakLines()
        unitBreakPositions()
        unitBreakCopyAndStreaming()
        contextMenuActions()
        legacyScrollerTakesItsOwnColumn()
        styleApplication()
        perBlockCopy()
        linkSource()
        displayChangeKeepsReader()
        streamingWithStyle()
        titledBlocks()
        titleWhileStreaming()
        foldSpike()
        folding()
        foldingKeepsWhatTheReaderSees()
        foldingAndHighlightWhileStreaming()
        tokenColors()
        chromeRegionsFollowChanges()
        hoverLooksNearThePointer()
        completionRedrawsCopyControl()
        cursorFollowsControls()
        clickRunsOnRelease()
        foldFootersNearThePointer()
        foldedLinesAreNotDrawn()
        foldToggleRestylesOnlyTheBlock()
        expansionFollowsEditsBeforeTheBlock()
        foldingTurnedOnWithAChunkKeepsTheReader()
        trailingBlankLinesDoNotFold()
        sameIdentityEditRecolorsTheEditedLine()
        listsWrapAndKeepState()
        listClipboard()
        inlineCodeListLookalikes()
        print("TranslationResultTextViewTests passed (no windows opened)")
    }

    private static func listsWrapAndKeepState() {
        let (scroll, view) = makeScroll(width: 250, height: 150)
        let body = String(repeating: "long list item words ", count: 9)
        let source = "3. " + body + "\n  - Child item\n7. Last item\n\n```text\n- literal code\n```"
        apply(scroll, source)
        let text = view.string as NSString, storage = view.textStorage!, layout = view.layoutManager!
        let item = TranslationMarkup(source).lists.items[0]
        let bodyGlyph = layout.glyphIndexForCharacter(at: item.contentRange.location)
        let first = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: nil)
        let bodyX = first.minX + layout.location(forGlyphAt: bodyGlyph).x
        var lines: [NSRect] = []
        let glyphs = layout.glyphRange(forCharacterRange: item.range, actualCharacterRange: nil)
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in lines.append(used) }
        require(lines.count > 2 && abs(lines[1].minX - bodyX) < 0.6,
                "wrapped item body aligns after its marker (body \(bodyX), wrapped \(lines.map(\.minX)))")
        let child = text.range(of: "Child item").location
        let paragraph = storage.attribute(.paragraphStyle, at: child, effectiveRange: nil) as! NSParagraphStyle
        require(paragraph.headIndent > 0 && paragraph.textLists.isEmpty, "nested visual layout keeps literal markers without native duplicates")
        let code = text.range(of: "- literal code").location
        require(storage.attribute(.deepKCodeBlock, at: code, effectiveRange: nil) != nil,
                "a code line resembling a marker retains code styling")
        view.setSelectedRange(NSRange(location: child, length: 5))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 45))
        let top = scroll.contentView.bounds.origin
        apply(scroll, source + "\n\n- New streamed item", streaming: true)
        require(view.selectedRange() == NSRange(location: child, length: 5) && abs(scroll.contentView.bounds.minY - top.y) < 0.5,
                "appending lists preserves selection and the reading position")
        let (changed, changedView) = makeScroll(width: 250, height: 100)
        apply(changed, "- Before")
        require((changedView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).headIndent > 0,
                "a list initially hangs")
        apply(changed, "ordinary prose")
        require((changedView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).headIndent == 0,
                "removing a marker removes its old paragraph indent")
    }

    private static func listClipboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-list-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard, previousFormat = TranslationResultTextView.copyFormat
        TranslationResultTextView.copyPasteboard = { pasteboard }
        TranslationResultTextView.copyFormat = { .rich }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            TranslationResultTextView.copyFormat = previousFormat
            pasteboard.releaseGlobally()
        }
        let source = "3. First\n  - Child\n7. Last"
        require(ResultClipboard.write(markdown: source, plain: source, format: .rich, to: pasteboard), "copy button writes list structure")
        require(pasteboard.string(forType: .string) == source && pasteboard.string(forType: .html)?.contains("<li value=\"7\">Last</li>") == true,
                "plain copy retains literals while HTML carries actual numbering")
        guard let data = pasteboard.data(forType: .rtf), let rich = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return require(false, "list RTF roundtrips")
        }
        let copied = rich.string as NSString
        let serialized = String(data: data, encoding: .ascii) ?? ""
        // macOS 26 represents list markers in NSTextList rather than in attributedString.string.
        require(serialized.contains("{\\listtext\t3.\t}First") && serialized.contains("{\\listtext\t7.\t}Last")
                && !serialized.contains("}3. First") && !serialized.contains("}7. Last"),
                "RTF has one native marker per item with the actual numbers")
        let style = { (word: String) in rich.attribute(.paragraphStyle, at: copied.range(of: word).location, effectiveRange: nil) as! NSParagraphStyle }
        require(style("First").textLists.map(\.startingItemNumber) == [3]
                && style("Child").textLists.map(\.startingItemNumber) == [3, 1]
                && style("Last").textLists.map(\.startingItemNumber) == [7],
                "RTF has native semantic nesting and an explicit restart at seven")
        let (scroll, view) = makeScroll(width: 250, height: 150)
        apply(scroll, source)
        let selected = (view.string as NSString).range(of: "First")
        view.setSelectedRange(selected)
        view.copy(nil)
        let fragment = pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        require(pasteboard.string(forType: .string) == "First" && pasteboard.string(forType: .html) == "<meta charset=\"utf-8\"><p>First</p>"
                && fragment?.string == "First" && (fragment?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.isEmpty != false,
                "a body-only selection invents no marker in HTML, RTF or plain text")
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "7.").location, length: 7))
        view.copy(nil)
        require(pasteboard.string(forType: .html)?.contains("<ol start=\"7\">") == true,
                "copying a later item retains its own starting number")
        TranslationResultTextView.copyFormat = { .markdown }
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.copy(nil)
        require(pasteboard.pasteboardItems?.first?.types == [.string] && pasteboard.string(forType: .string) == source,
                "Markdown-only copy keeps all literal markers and indentation")
    }

    private static func inlineCodeListLookalikes() {
        let board = NSPasteboard(name: NSPasteboard.Name("deepk-code-list-lookalike-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        for literal in ["- literal item", "1. literal item"] {
            let options = InlineOptions(code: .only([literal]))
            let markdown = "`" + literal + "`"
            require(ResultClipboard.write(markdown: markdown, plain: literal, inline: options, format: .rich, to: board),
                    "an inline-code lookalike is copied")
            let html = board.string(forType: .html) ?? ""
            let rich = board.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
            require(rich?.string == literal
                    && (rich?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.isFixedPitch == true
                    && (rich?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.isEmpty != false,
                    "RTF keeps the complete inline-code literal without semantic list conversion: \(literal)")
            require(board.string(forType: .string) == literal && html.contains("<p><code>" + literal + "</code></p>")
                    && !html.contains("<ul") && !html.contains("<ol"),
                    "inline code keeps its apparent marker as literal code in HTML and plain text: \(literal)")
        }
        let options = InlineOptions(code: .only(["git"]))
        require(ResultClipboard.write(markdown: "- `git`", plain: "- git", inline: options, format: .rich, to: board),
                "a real list with an inline-code body is copied")
        require(board.string(forType: .html)?.contains("<ul><li><code>git</code></li></ul>") == true,
                "code in the item's body does not suppress its genuine marker")
        let rich = board.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        let body = rich.map { ($0.string as NSString).range(of: "git").location }
        require(body != nil && body != NSNotFound
                && (rich?.attribute(.paragraphStyle, at: body ?? 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.count == 1
                && (rich?.attribute(.font, at: body ?? 0, effectiveRange: nil) as? NSFont)?.isFixedPitch == true,
                "RTF keeps genuine list semantics and its inline-code body font together")
    }

    private static func makeScroll(width: CGFloat, height: CGFloat) -> (ResultScrollView, NSTextView) {
        let scroll = TranslationResultTextView.makeScrollView() as! ResultScrollView
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
        scroll.layoutSubtreeIfNeeded()
        return (scroll, scroll.documentView as! NSTextView)
    }

    private static func codeBlocks() {
        let (scroll, view) = makeScroll(width: 320, height: 600)
        let storage = view.textStorage!, layout = view.layoutManager!
        let text = "설명 문단입니다.\n\n```swift\nlet a = 1\nlet b = 2\n```\n\n다음 문단"
        apply(scroll, text)
        require(view.string == TranslationMarkup(text).displayText && !view.string.contains("`"), "storage holds display text without fences")
        let code = (view.string as NSString).range(of: "let a = 1")
        let codeFont = storage.attribute(.font, at: code.location, effectiveRange: nil) as! NSFont
        require(codeFont.isFixedPitch && codeFont.pointSize == 13, "code uses a 13pt fixed-pitch font")
        require(storage.attribute(.deepKCodeLanguage, at: code.location, effectiveRange: nil) as? String == "swift", "language attribute")
        let prose = storage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        require(!prose.isFixedPitch && prose.pointSize == 16, "prose keeps the 16pt system font")
        let used = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: code.location), effectiveRange: nil)
        let native = ResultStyle.native
        require(used.minX >= native.box.insets.left && used.maxX <= view.textContainer!.size.width - native.box.insets.right + 0.5,
                "code is padded inside the box")
        let blank = view.textContainer!.size.width - 6
        require(pixelAlpha(view, at: NSPoint(x: blank, y: view.textContainerOrigin.y + used.midY)) > 0, "box is drawn behind code")
        require(pixelAlpha(view, at: NSPoint(x: blank, y: 4)) == 0, "no box behind prose")
        let band = view.textContainerOrigin.y + used.minY - native.topPortion
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        require(minBrightness(view, in: NSRect(x: 12, y: band + 6, width: 30, height: 20))
                < minBrightness(view, in: NSRect(x: view.textContainer!.size.width / 2, y: band + 6, width: 30, height: 20)) - 0.1,
                "the header label stays visible over a selection")
        view.setSelectedRange(NSRange(location: 0, length: 0))

        apply(scroll, "```swift\nx\n```\n```python\ny\n```", identity: UUID())
        let ids = [0, 2].map { storage.attribute(.deepKCodeBlock, at: $0, effectiveRange: nil) as? Int }
        require(view.string == "x\ny" && ids[0] != nil && ids[1] != nil && ids[0] != ids[1], "adjacent blocks stay separate")

        apply(scroll, "```py\nprint(1)\n```\n뒤", identity: UUID())
        require(view.textContainerOrigin.y >= ResultStyle.native.topPortion && view.textContainerInset == .zero,
                "a leading box gets room above only")
        require(pixelAlpha(view, at: NSPoint(x: view.textContainer!.size.width - 6, y: 3)) > 0, "the leading box band is drawn above the text")

        // A short viewport so the frame is sized by the text, not the clip view.
        let (short, shortView) = makeScroll(width: 320, height: 60)
        apply(short, "끝에 오는 코드\n```sh\nnpm install express\nnpm run build\nnpm test")
        let shortLayout = shortView.layoutManager!
        let tail = shortLayout.lineFragmentUsedRect(forGlyphAt: shortLayout.glyphIndexForCharacter(at: shortView.string.utf16.count - 1), effectiveRange: nil)
        require(shortView.frame.height >= shortView.textContainerOrigin.y + tail.maxY + ResultStyle.native.bottomPortion,
                "frame includes the bottom padding of a trailing box")
        // AppKit resizes the view itself when the width changes; the bands must survive that.
        apply(short, "```py\nprint(1)\n```\n" + String(repeating: "줄바꿈되는 긴 산문입니다. ", count: 10), identity: UUID())
        for width in [220.0, 320.0] {
            short.setFrameSize(NSSize(width: width, height: 60))
            short.layoutSubtreeIfNeeded()
            shortLayout.ensureLayout(for: shortView.textContainer!)
            require(shortView.frame.height >= shortView.textContainerOrigin.y + shortLayout.usedRect(for: shortView.textContainer!).maxY,
                    "the last line stays inside the frame after a width change: \(width)")
        }
    }

    /// Every code line is the style's line height apart, a wrapped last line too. The box ends as far below its last
    /// line, and text after it starts as far below the box, as without wrapping.
    private static func codeLinePitch() {
        let long = String(repeating: "abcdefgh ", count: 12)
        for style in ResultStyle.builtIns {
            let glyphHeight = NSLayoutManager().defaultLineHeight(for: style.code.font.nsFont)
            var bottoms: [CGFloat] = []
            for tail in ["", "\n\n뒤"] {
                let name = "\(style.name)\(tail.isEmpty ? "" : ", text after")"
                let (scroll, view) = makeScroll(width: 320, height: 400)
                apply(scroll, "앞\n\n```ts\n\(long)\n\(long)\n```" + tail, display: display(style))
                let layout = view.layoutManager!, text = view.string as NSString
                var tops: [CGFloat] = []
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: text.range(of: long).location,
                                                                                                          length: 2 * long.utf16.count + 1),
                                                                               actualCharacterRange: nil)) { _, used, _, _, _ in tops.append(used.minY) }
                let pitches = zip(tops.dropFirst(), tops).map { $0 - $1 }
                require(tops.count > 4 && pitches.allSatisfy { abs($0 - style.code.lineHeight) < 0.01 },
                        "\(name): every code line is \(style.code.lineHeight) apart: \(pitches)")
                let box = (view as! ResultTextView).codeBoxes()[0].geometry.box
                bottoms.append(box.maxY - view.textContainerOrigin.y - tops.last!)
                if !tail.isEmpty {
                    let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: text.range(of: "뒤").location), effectiveRange: nil)
                    require(abs(view.textContainerOrigin.y + after.minY - (box.maxY + style.box.margin + ResultStyle.blankLineGap)) < 0.01,
                            "\(name): text after the box starts a margin and a blank line below it")
                }
            }
            require(abs(bottoms[0] - bottoms[1]) < 0.01 && abs(bottoms[0] - glyphHeight - style.bottomPortion) < 0.01,
                    "\(style.name): the box ends as far below its last line with or without text after it: \(bottoms)")
        }
    }

    private static func codeBlocksWhileStreaming() {
        let (scroll, view) = makeScroll()
        var raw = (1...20).map { "번역 문단 \($0): 선택 범위를 유지합니다." }.joined(separator: "\n\n")
        apply(scroll, raw, streaming: true)
        let selection = NSRange(location: 8, length: 30)
        view.setSelectedRange(selection)
        Self.scroll(scroll, to: 120)
        let origin = scroll.contentView.bounds.origin
        var previous = view.string
        for chunk in ["\n\n``", "`py", "\nprint(", "1)", "\nprint(2)", "\n``", "`\n\n끝"] {
            raw += chunk
            apply(scroll, raw, streaming: true)
            require(view.string.utf16.starts(with: previous.utf16) && !view.string.contains("`"), "stream appends display only: \(chunk)")
            require(view.selectedRange() == selection, "stream keeps selection: \(chunk)")
            require(abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "stream keeps scroll: \(chunk)")
            previous = view.string
        }
        let storage = view.textStorage!
        require(!(storage.attribute(.font, at: (view.string as NSString).range(of: "끝").location, effectiveRange: nil) as! NSFont).isFixedPitch,
                "prose after the closer")
        require(storage.attribute(.deepKCodeLanguage, at: (view.string as NSString).range(of: "print").location, effectiveRange: nil) as? String == "py",
                "streamed block is styled")
        let spacing = { (word: String) in
            (storage.attribute(.paragraphStyle, at: (view.string as NSString).range(of: word).location, effectiveRange: nil) as! NSParagraphStyle).paragraphSpacing
        }
        require(spacing("print(1)") == 0 && spacing("print(2)") > 0, "only the block's current last line keeps the bottom padding")

        // With code above, an append restyles only the end of the text.
        let (partial, partialView) = makeScroll()
        let spy = EditSpy()
        partialView.textStorage!.delegate = spy
        let codeHead = "```py\nprint(0)\n```\n\n" + (1...10).map { "문단 \($0)입니다." }.joined(separator: "\n\n")
        apply(partial, codeHead, streaming: true)
        spy.ranges = []
        apply(partial, codeHead + " 이어서 붙는 글", streaming: true)
        let first = spy.ranges.map(\.location).min() ?? 0
        require(first > (partialView.string as NSString).range(of: "문단 10").location - 2, "an append after code restyles only the last paragraph")
        require(partialView.textStorage!.attribute(.deepKCodeBlock, at: 0, effectiveRange: nil) != nil, "earlier code keeps its style")

        // A stray fence removed at completion does not reset the reader.
        let stray = raw + "\n```"
        apply(scroll, stray, streaming: true)
        let before = view.string
        apply(scroll, TranslationMarkup.normalized(stray))
        require(view.string == before && view.selectedRange() == selection, "final without the stray fence keeps selection")
        require(abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "final without the stray fence keeps scroll")

        let across = NSRange(location: (view.string as NSString).range(of: "print").location - 3, length: 8)
        view.setSelectedRange(across)
        apply(scroll, TranslationMarkup.normalized(stray), lineSpacing: 6)
        require(view.selectedRange() == across, "lineSpacing change keeps a selection across the box edge")
        require((storage.attribute(.font, at: across.location + 4, effectiveRange: nil) as! NSFont).isFixedPitch, "lineSpacing change keeps code style")

        // The new unit's start is given in markdown offsets and shown in display offsets.
        let (units, _) = makeScroll()
        let head = "설명\n\n```py\nprint(1)\n```"
        apply(units, head)
        apply(units, head + "\n\n추가 문단", tailStart: head.utf16.count, streaming: true)
        // The completed side keeps the code line's own break, so selecting that line can still be copied.
        require(units.pendingTail == ("설명\n\nprint(1)\n" as NSString).length, "the tail offset maps into the display text")
    }

    private static func clipboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let markdown = "설명\n\n```swift\nlet a = 1\n```"
        require(ResultClipboard.write(markdown: markdown, plain: "설명\n\nlet a = 1", format: .rich, to: pasteboard), "rich write")
        let types = pasteboard.pasteboardItems?.first?.types ?? []
        require(types.contains(.html) && types.contains(.rtf) && pasteboard.string(forType: .string) == "설명\n\nlet a = 1",
                "rich copy has html, rtf and the plain text")
        let rtf = NSAttributedString(rtf: pasteboard.data(forType: .rtf)!, documentAttributes: nil)!
        let font = rtf.attribute(.font, at: (rtf.string as NSString).range(of: "let").location, effectiveRange: nil) as? NSFont
        require(font?.isFixedPitch == true, "rtf code is fixed pitch")
        require(pasteboard.string(forType: .html)?.contains("<code class=\"language-swift\">") == true, "html code block")
        require(ResultClipboard.write(markdown: markdown, plain: "설명\n\nlet a = 1", format: .markdown, to: pasteboard), "markdown write")
        require(pasteboard.pasteboardItems?.first?.types == [.string] && pasteboard.string(forType: .string) == markdown, "markdown copy is a plain string")
        require(ResultClipboard.write(markdown: "산문만 있는 결과", plain: "산문만 있는 결과", format: .rich, to: pasteboard), "prose write")
        require(pasteboard.pasteboardItems?.first?.types == [.string] && pasteboard.string(forType: .string) == "산문만 있는 결과",
                "prose copy stays a plain string")
        let defaults = UserDefaults(suiteName: "deepk-test-\(UUID().uuidString)")!
        require(ResultCopyFormat.load(from: defaults) == .rich, "rich is the default copy format")
        defaults.set(ResultCopyFormat.markdown.rawValue, forKey: ResultCopyFormat.defaultsKey)
        require(ResultCopyFormat.load(from: defaults) == .markdown, "copy format round-trips")
    }

    private static let harness = SourceLink(url: URL(string: "https://blog.example.com/harness?x=1&y=2")!, text: "Finding the best harness")
    private static let linked = InlineOptions(code: .only(["read", "write"]), links: [harness, SourceLink(url: URL(string: "javascript:alert(1)")!, text: "bad")])

    private static func inlineChipsAndLinks() {
        let (scroll, view) = makeScroll(width: 320, height: 300)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        let text = "도구는 `read`, `write` 두 개입니다. 확인: <a1>최고의 하네스 찾기</a1>. 나쁜 <a2>링크</a2>와 `other`."
        apply(scroll, text, inline: linked)
        require(view.string == "도구는 read, write 두 개입니다. 확인: 최고의 하네스 찾기. 나쁜 링크와 other.", "markers are not in the storage")
        let storage = view.textStorage!, string = view.string as NSString
        let read = string.range(of: "read")
        require(storage.attribute(.deepKInlineCode, at: read.location, effectiveRange: nil) != nil
                && (storage.attribute(.font, at: read.location, effectiveRange: nil) as! NSFont).isFixedPitch, "a chip is monospaced")
        require(storage.attribute(.deepKInlineCode, at: string.range(of: "other").location, effectiveRange: nil) == nil,
                "backticks the page did not mark as code get no chip")
        let title = string.range(of: "하네스")
        require(storage.attribute(.link, at: title.location, effectiveRange: nil) as? URL == harness.url, "link target")
        require((storage.attribute(.toolTip, at: title.location, effectiveRange: nil) as? String)?.hasSuffix("원문: Finding the best harness") == true,
                "tooltip names the original words")
        require(storage.attribute(.foregroundColor, at: title.location, effectiveRange: nil) as? NSColor == ResultStyle.native.link.color!.nsColor,
                "link color in storage")
        let bad = string.range(of: "링크")
        require(storage.attribute(.link, at: bad.location, effectiveRange: nil) == nil, "a disallowed scheme is never a link")

        // Chips are painted behind the glyphs, inside the padding before the first one.
        let layout = view.layoutManager!
        let glyphs = layout.glyphRange(forCharacterRange: read, actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer!).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        let pad = ResultStyle.native.chip.padding
        require(pixelAlpha(view, at: NSPoint(x: bounds.minX - 1.5, y: bounds.midY)) > 0, "chip fill in the leading padding")
        require(pixelAlpha(view, at: NSPoint(x: bounds.minX - pad - 1, y: bounds.midY)) == 0, "no fill outside the chip")

        // Clicks: only allowed URLs reach the opener, and only links take the first click.
        var opened: [URL] = []
        let previous = TranslationResultTextView.openLink
        TranslationResultTextView.openLink = { opened.append($0) }
        defer { TranslationResultTextView.openLink = previous }
        view.clicked(onLink: URL(string: "javascript:alert(1)")!, at: bad.location)
        view.clicked(onLink: "file:///etc/passwd", at: bad.location)
        view.clicked(onLink: harness.url, at: title.location)
        require(opened == [harness.url], "only the allowed link opens")
        let titleRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: title, actualCharacterRange: nil), in: view.textContainer!)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        func event(at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        require(view.acceptsFirstMouse(for: event(at: NSPoint(x: titleRect.midX, y: titleRect.midY))), "a link takes the first click")
        require(!view.acceptsFirstMouse(for: event(at: NSPoint(x: bounds.midX, y: bounds.midY))), "other text does not")

        // Stale text keeps the words but cannot be followed; the dimmed color applies to links too.
        apply(scroll, text, stale: true, inline: linked)
        require(storage.attribute(.link, at: title.location, effectiveRange: nil) == nil
                && storage.attribute(.foregroundColor, at: title.location, effectiveRange: nil) as? NSColor == .secondaryLabelColor, "stale links are inert")

        // Same display text: a new table moves the target, a smaller code set drops a chip.
        apply(scroll, text, inline: linked)
        let moved = SourceLink(url: URL(string: "https://moved.example.com/")!, text: harness.text)
        apply(scroll, text, inline: InlineOptions(code: .only(["write"]), links: [moved]))
        require(view.string == string as String, "only styles changed")
        require(storage.attribute(.link, at: title.location, effectiveRange: nil) as? URL == moved.url, "a new table updates the target")
        require(storage.attribute(.deepKInlineCode, at: read.location, effectiveRange: nil) == nil
                && !(storage.attribute(.font, at: read.location, effectiveRange: nil) as! NSFont).isFixedPitch, "a dropped chip is cleared")
        apply(scroll, text, inline: InlineOptions(code: .only(["read", "write"])))
        require(view.string.contains("<a1>") && storage.attribute(.link, at: (view.string as NSString).range(of: "하네스").location, effectiveRange: nil) == nil,
                "tags without a table stay literal")
    }

    private static func inlineWhileStreaming() {
        let (scroll, view) = makeScroll()
        var raw = (1...20).map { "번역 문단 \($0): 선택 범위를 유지합니다." }.joined(separator: "\n\n") + "\n\n"
        let inline = InlineOptions(code: .only(["read"]), links: [harness])
        apply(scroll, raw, streaming: true, inline: inline)
        let selection = NSRange(location: 8, length: 30)
        view.setSelectedRange(selection)
        Self.scroll(scroll, to: 120)
        let origin = scroll.contentView.bounds.origin
        let spy = EditSpy()
        view.textStorage!.delegate = spy
        var previous = view.string
        for chunk in ["확인: <", "a1", ">하네스 ", "찾기</a", "1>. `re", "ad` 끝"] {
            raw += chunk
            spy.ranges = []
            apply(scroll, raw, streaming: true, inline: inline)
            require(view.string.utf16.starts(with: previous.utf16), "stream appends display only: \(chunk)")
            require(!view.string.contains("<") && !view.string.contains("`"), "no marker reaches the view: \(chunk)")
            require(view.selectedRange() == selection && abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "stream keeps the reader: \(chunk)")
            require((spy.ranges.map(\.location).min() ?? Int.max) >= (previous as NSString).range(of: "번역 문단 20").location,
                    "only the last paragraph is restyled: \(chunk)")
            previous = view.string
        }
        let storage = view.textStorage!, string = view.string as NSString
        require(storage.attribute(.link, at: string.range(of: "하네스 찾기").location, effectiveRange: nil) as? URL == harness.url, "link after its closing tag")
        require(storage.attribute(.deepKInlineCode, at: string.range(of: "read").location, effectiveRange: nil) != nil, "chip after its closing run")
        require(storage.attribute(.deepKInlineCode, at: string.range(of: "끝").location, effectiveRange: nil) == nil, "prose after the chip")

        // The unit start maps through the same options.
        let (units, _) = makeScroll()
        let head = "확인: <a1>하네스</a1> `read`"
        apply(units, head, inline: inline)
        apply(units, head + "\n\n추가", tailStart: head.utf16.count, streaming: true, inline: inline)
        require(units.pendingTail == "확인: 하네스 read".utf16.count, "the tail offset maps through inline markers")
    }

    private static func inlineClipboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let raw = "도구 `read`. 확인: <a1>하네스 (찾기)</a1>."
        let inline = InlineOptions(code: .only(["read"]), links: [harness])
        let plain = TranslationMarkup.insertionText(result: raw, source: "Tool read. See it.", inline: inline)
        require(plain == "도구 read. 확인: 하네스 (찾기).", "insert text drops tags, URLs and page-only backticks")
        require(TranslationMarkup.insertionText(result: "`x` 와 <a1>y</a1>", source: "`x` and y", inline: InlineOptions(code: .any, links: [harness]))
                == "`x` 와 y", "backticks the source wrote stay")
        require(ResultClipboard.write(markdown: raw, plain: plain, inline: inline, format: .rich, to: pasteboard), "rich write")
        let html = pasteboard.string(forType: .html) ?? ""
        require(html.contains("<code>read</code>") && html.contains("<a href=\"https://blog.example.com/harness?x=1&amp;y=2\">하네스 (찾기)</a>"), "html: \(html)")
        require(pasteboard.string(forType: .string) == plain, "rich string is the plain text")
        let rtf = NSAttributedString(rtf: pasteboard.data(forType: .rtf)!, documentAttributes: nil)!
        let linkValue = rtf.attribute(.link, at: (rtf.string as NSString).range(of: "하네스").location, effectiveRange: nil)
        require((linkValue as? URL ?? (linkValue as? String).flatMap(URL.init(string:))) == harness.url, "rtf link")
        require(ResultClipboard.write(markdown: raw, plain: plain, inline: inline, format: .markdown, to: pasteboard), "markdown write")
        require(pasteboard.string(forType: .string) == "도구 `read`. 확인: [하네스 (찾기)](https://blog.example.com/harness?x=1&y=2).",
                "markdown resolves the tag: \(pasteboard.string(forType: .string) ?? "")")

        // A partial selection of a link keeps the link.
        let markup = TranslationMarkup(raw, inline: inline)
        let everything = NSRange(location: 0, length: (markup.displayText as NSString).length)
        require(markup.plainText(in: everything, fences: .none) == plain, "a selection's plain text matches the copy button")
        let typed = TranslationMarkup("`x` 와 <a1>y</a1>", inline: InlineOptions(code: .any, links: [harness]))
        require(typed.plainText(in: NSRange(location: 0, length: (typed.displayText as NSString).length), fences: .none) == "`x` 와 y",
                "typed backticks stay in plain text")
        let part = (markup.displayText as NSString).range(of: "하네스")
        require(markup.needsMarkdown(for: part), "a link selection copies with structure")
        ResultClipboard.write(selection: part, of: markup, fences: .none, format: .markdown, to: pasteboard)
        require(pasteboard.string(forType: .string) == "[하네스](https://blog.example.com/harness?x=1&y=2)", "partial link")
        require(TranslationMarkup("``a`b``", inline: InlineOptions(code: .any)).markdown(in: NSRange(location: 0, length: 3)) == "``a`b``",
                "code containing a backtick gets a longer delimiter")
    }

    /// Second review of PR #49.
    private static func secondReview() {
        // A result that starts with a labeled box shows its label in the band above the text.
        let (leading, leadingView) = makeScroll(width: 320, height: 200)
        let window = NSWindow(contentRect: leading.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = leading
        apply(leading, "```python\nprint(1)\n```\n\n뒤 문단")
        require(minBrightness(leadingView, in: NSRect(x: 12, y: 4, width: 40, height: 24))
                < minBrightness(leadingView, in: NSRect(x: 160, y: 4, width: 40, height: 24)) - 0.1, "a leading box's label is drawn")
        window.contentView = nil

        // A tail edit that starts right after a box keeps the small gap below it.
        let (tail, tailView) = makeScroll(width: 320, height: 200)
        let retried = UUID()
        apply(tail, "```py\nprint(1)\n```\n\nHello world", identity: retried, streaming: true)
        apply(tail, "```py\nprint(1)\n```\n\nGoodbye world", identity: retried)
        let gap = (tailView.string as NSString).range(of: "\n\n").location + 1
        let style = tailView.textStorage!.attribute(.paragraphStyle, at: gap, effectiveRange: nil) as! NSParagraphStyle
        require(style.maximumLineHeight == 6, "the gap below a box survives a partial restyle")

        // ⌘C, drag and Services write the same structured selection; plain text follows the source's fences.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let dragboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previous = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previous
            pasteboard.releaseGlobally()
            dragboard.releaseGlobally()
        }
        let result = "설명\n\n```py\nprint(1)\n```"
        for fenced in [true, false] {
            let (copying, copyView) = makeScroll(width: 320, height: 200)
            apply(copying, result, sourceFences: fenced ? .fenced : .none)
            copyView.setSelectedRange(NSRange(location: 0, length: (copyView.string as NSString).length))
            copyView.copy(nil)
            let plain = pasteboard.string(forType: .string)
            require(plain == (fenced ? result : "설명\n\nprint(1)"), "copied plain text follows the source: \(fenced)")
            require(pasteboard.string(forType: .html)?.contains("<code class=\"language-py\">print(1)</code>") == true, "copied html keeps the box")
            _ = copyView.writeSelection(to: dragboard, types: copyView.writablePasteboardTypes)
            require(dragboard.string(forType: .string) == plain, "drag writes what copy writes: \(fenced)")
        }

        // While a unit streams after a box, only the completed text can leave the app.
        let (draft, draftView) = makeScroll(width: 320, height: 200)
        let head = "설명\n\n```py\nprint(1)\n```"
        apply(draft, head)
        apply(draft, head + "\n\n초안 문단", tailStart: head.utf16.count, streaming: true)
        draftView.setSelectedRange((draftView.string as NSString).range(of: "초안"))
        require(!canCopy(draftView), "the draft after a box cannot be copied")
        draftView.setSelectedRange((draftView.string as NSString).range(of: "print(1)"))
        require(canCopy(draftView), "the completed box can be copied")

        // The completed unit after a box is announced once.
        let (announced, _) = makeScroll(width: 320, height: 200)
        apply(announced, head)
        apply(announced, head + "\n\n끝", tailStart: head.utf16.count, streaming: true)
        apply(announced, head + "\n\n끝.", tailStart: head.utf16.count)
        require(announced.announcementCount == 1, "a completed unit after a box is announced")

        // Superseded code is dimmed like superseded prose.
        let (stale, staleView) = makeScroll(width: 320, height: 200)
        apply(stale, head, stale: true)
        let code = (staleView.string as NSString).range(of: "print").location
        require(staleView.textStorage!.attribute(.foregroundColor, at: code, effectiveRange: nil) as? NSColor == .secondaryLabelColor, "stale code is dimmed")

        // Streaming inside a long block restyles only its end, not the whole block.
        let (long, longView) = makeScroll(width: 320, height: 200)
        let spy = EditSpy()
        longView.textStorage!.delegate = spy
        let lines = "```swift\n" + (1...80).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        apply(long, lines, streaming: true)
        spy.ranges = []
        apply(long, lines + " + 1", streaming: true)
        let first = spy.ranges.map(\.location).min() ?? 0
        require(first >= (longView.string as NSString).range(of: "let value79").location, "a growing block restyles only its last lines")
        require(longView.textStorage!.attribute(.deepKCodeBlock, at: 0, effectiveRange: nil) != nil
                && (longView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).paragraphSpacingBefore > 0,
                "the block's first line keeps its style")
    }

    /// Fourth review of PR #49.
    private static func fourthReview() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard, previousFormat = TranslationResultTextView.copyFormat
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            TranslationResultTextView.copyFormat = previousFormat
            pasteboard.releaseGlobally()
        }
        // A partial structured selection writes only what is selected, in every flavor; the draft after it stays out.
        let (draft, draftView) = makeScroll(width: 320, height: 300)
        let head = "설명\n\n```py\nprint(1)\n```"
        apply(draft, head)
        apply(draft, head + "\n\nSECRET 초안 문단", tailStart: head.utf16.count, streaming: true)
        draftView.setSelectedRange(NSRange(location: 0, length: NSMaxRange((draftView.string as NSString).range(of: "print(1)"))))
        draftView.copy(nil)
        let rtf = pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }?.string ?? ""
        require(pasteboard.string(forType: .html)?.contains("SECRET") == false && !rtf.contains("SECRET") && rtf.contains("print(1)")
                && pasteboard.string(forType: .string)?.contains("SECRET") == false, "a partial selection writes only itself")

        // The markdown format setting holds for ⌘C too.
        TranslationResultTextView.copyFormat = { .markdown }
        let (markdown, markdownView) = makeScroll(width: 320, height: 200)
        apply(markdown, head)
        markdownView.setSelectedRange(NSRange(location: 0, length: (markdownView.string as NSString).length))
        markdownView.copy(nil)
        require(pasteboard.pasteboardItems?.first?.types == [.string] && pasteboard.string(forType: .string) == head, "markdown-only ⌘C writes fenced markdown")
        TranslationResultTextView.copyFormat = previousFormat

        // Same display text, new code layout: a retranslation that fences the same words gets its box and label.
        let (retranslated, retranslatedView) = makeScroll(width: 320, height: 200)
        apply(retranslated, "설명\n\nnpm i")
        apply(retranslated, "설명\n\n```bash\nnpm i\n```", identity: UUID())
        let storage = retranslatedView.textStorage!, npm = (retranslatedView.string as NSString).range(of: "npm i").location
        require(storage.attribute(.deepKCodeLanguage, at: npm, effectiveRange: nil) as? String == "bash"
                && (storage.attribute(.font, at: npm, effectiveRange: nil) as! NSFont).isFixedPitch, "the same words become a box")
        apply(retranslated, "설명\n\n```sh\nnpm i\n```", identity: UUID())
        require(storage.attribute(.deepKCodeLanguage, at: npm, effectiveRange: nil) as? String == "sh", "a new tag updates the label")

        // Padding sits only on a box's first and last lines; the blank line above a box is a small gap.
        let (padded, paddedView) = makeScroll(width: 320, height: 300)
        apply(padded, "설명 문단입니다.\n\n```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```\n\n다음 문단")
        let text = paddedView.string as NSString
        let style = { (word: String) in paddedView.textStorage!.attribute(.paragraphStyle, at: text.range(of: word).location, effectiveRange: nil) as! NSParagraphStyle }
        require(style("let a").paragraphSpacingBefore > 0 && style("let b").paragraphSpacingBefore == 0 && style("let b").paragraphSpacing == 0,
                "middle lines have no padding")
        let above = paddedView.textStorage!.attribute(.paragraphStyle, at: text.range(of: "\n\n").location + 1, effectiveRange: nil) as! NSParagraphStyle
        require(above.maximumLineHeight == 6, "the blank line above a box is a small gap")
    }

    private static func singleWordChatCommandsDisplayAndCopy() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard, previousFormat = TranslationResultTextView.copyFormat
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            TranslationResultTextView.copyFormat = previousFormat
            pasteboard.releaseGlobally()
        }
        for command in ["pwd", "ls", "deepk-check"] {
            let result = "명령어:\n```\(command)\n```\n완료"
            let display = "명령어:\n\(command)\n완료"
            let rebuilt = "명령어:\n```\n\(command)\n```\n완료"
            let (scroll, view) = makeScroll(width: 320, height: 200)
            apply(scroll, result, sourceFences: .untagged)
            require(view.string == display, "the result view displays the opener's command: \(command)")
            let location = (view.string as NSString).range(of: command).location
            require(view.textStorage!.attribute(.deepKCodeBlock, at: location, effectiveRange: nil) != nil
                    && view.textStorage!.attribute(.deepKCodeLanguage, at: location, effectiveRange: nil) == nil,
                    "the command has code styling without a false language label: \(command)")

            view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
            TranslationResultTextView.copyFormat = { .rich }
            view.copy(nil)
            require(pasteboard.string(forType: .string) == rebuilt, "rich selection's plain text keeps an untagged command: \(command)")
            require(pasteboard.string(forType: .html)?.contains("<code>\(command)</code>") == true,
                    "rich selection's HTML keeps the command: \(command)")
            require(pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }?.string == display,
                    "rich selection's RTF keeps the command: \(command)")
            TranslationResultTextView.copyFormat = { .markdown }
            view.copy(nil)
            require(pasteboard.pasteboardItems?.first?.types == [.string] && pasteboard.string(forType: .string) == rebuilt,
                    "markdown selection keeps the command in the body: \(command)")

            apply(scroll, result, sourceFences: .none)
            TranslationResultTextView.copyFormat = { .rich }
            view.copy(nil)
            require(pasteboard.string(forType: .string) == display, "unfenced-source selection drops only delimiters: \(command)")
            for format in ResultCopyFormat.allCases {
                require(ResultClipboard.write(markdown: result, plain: display, format: format, to: pasteboard), "copy button writes a command: \(command)")
                require(pasteboard.string(forType: .string) == (format == .rich ? display : result),
                        "copy button keeps the command in either format: \(command)")
                if format == .rich {
                    require(pasteboard.string(forType: .html)?.contains("<code>\(command)</code>") == true,
                            "copy button HTML keeps the command: \(command)")
                    require(pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }?.string == display,
                            "copy button RTF keeps the command: \(command)")
                }
            }
        }

        let (inline, inlineView) = makeScroll(width: 320, height: 200)
        apply(inline, "명령어:\n```pwd\nls```\n완료", sourceFences: .none)
        require(inlineView.string == "명령어:\npwd\nls\n완료", "an inline closer displays both commands without backticks")
        inlineView.setSelectedRange(NSRange(location: 0, length: inlineView.string.utf16.count))
        TranslationResultTextView.copyFormat = { .rich }
        inlineView.copy(nil)
        require(pasteboard.string(forType: .string) == inlineView.string
                && pasteboard.string(forType: .html)?.contains("<code>pwd\nls</code>") == true,
                "selection copy keeps both commands from an inline closing fence")
    }

    private static func singleWordChatCommandsRespectCopyLimits() {
        let head = "명령어:\n```pwd\n```"
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, head, sourceFences: .untagged)
        apply(scroll, head + "\n\nSECRET", tailStart: head.utf16.count, streaming: true, sourceFences: .untagged)
        view.setSelectedRange((view.string as NSString).range(of: "pwd"))
        require(canCopy(view), "a completed single-word command remains copyable before a draft")
        view.setSelectedRange((view.string as NSString).range(of: "SECRET"))
        require(!canCopy(view), "the draft after a single-word command cannot leave the view")
        apply(scroll, head, stale: true, sourceFences: .untagged)
        view.setSelectedRange((view.string as NSString).range(of: "pwd"))
        require(!canCopy(view), "a stale single-word command cannot leave the view")

        let (draft, draftView) = makeScroll(width: 320, height: 200)
        apply(draft, "```pwd\n", streaming: true)
        require(draftView.string == "pwd", "a streamed command appears after its opener line completes")
        draftView.setSelectedRange(NSRange(location: 0, length: draftView.string.utf16.count))
        require(!canCopy(draftView), "a command in an unfinished first result cannot be copied")
    }

    /// A shell transcript tag (```console) is a label, and every copy agrees on it.
    private static func unknownTagsKeepTheirLabelAndCopies() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard, previousFormat = TranslationResultTextView.copyFormat
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            TranslationResultTextView.copyFormat = previousFormat
            pasteboard.releaseGlobally()
        }
        let source = "Create a project:\n```console\n$ cargo new hello\n```\nDone."
        let result = "프로젝트를 만듭니다:\n```console\n$ cargo new hello\n```\n완료."
        let fences = TranslationMarkup.FenceStyle(source: source)
        require(fences == .fenced, "a source fenced with console keeps tags")
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, result, sourceFences: fences)
        require(view.string == "프로젝트를 만듭니다:\n$ cargo new hello\n완료.", "the tag is not shown as code")
        let code = (view.string as NSString).range(of: "$ cargo").location
        require(view.textStorage!.attribute(.deepKCodeLanguage, at: code, effectiveRange: nil) as? String == "console", "the tag is the label")
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        TranslationResultTextView.copyFormat = { .rich }
        view.copy(nil)
        let button = TranslationMarkup.insertionText(result: result, source: source)
        require(pasteboard.string(forType: .string) == button && button == result, "selection copy matches the copy button")
        require(pasteboard.string(forType: .html)?.contains("<code class=\"language-console\">$ cargo new hello</code>") == true, "HTML keeps the class")
        TranslationResultTextView.copyFormat = { .markdown }
        view.copy(nil)
        require(pasteboard.string(forType: .string) == result, "markdown selection keeps the tag on its fence")

        // An unknown name streams in once its first code line is complete, and only appends.
        let (stream, streamView) = makeScroll(width: 320, height: 200)
        let id = UUID()
        apply(stream, "설명:\n```nginx\nserver", identity: id, streaming: true)
        require(streamView.string == "설명:", "the name waits for its first code line")
        apply(stream, "설명:\n```nginx\nserver {}\n", identity: id, streaming: true)
        require(streamView.string == "설명:\nserver {}", "then the code appears without the name")
        apply(stream, "설명:\n```nginx\nserver {}\n```", identity: id)
        require(streamView.string == "설명:\nserver {}"
                && streamView.textStorage!.attribute(.deepKCodeLanguage, at: 4, effectiveRange: nil) as? String == "nginx", "the label stays")
    }

    /// Independent review of PR #53.
    private static func inlineReview() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        // Tags the model left unpaired and backticks the page did not mark never reach the clipboard.
        let guide = SourceLink(url: URL(string: "https://example.com/guide")!, text: "guide")
        for raw in ["자세한 내용은 <a1>가이드를 참고하세요.", "<a1>문서</a2>를 보세요.", "`쓰기` 도구를 <a2>쓰세요</a2>."] {
            let inline = InlineOptions(code: .only(["read"]), links: [guide])
            let plain = TranslationMarkup.insertionText(result: raw, source: "See the guide.", inline: inline)
            for format in [ResultCopyFormat.rich, .markdown] {
                ResultClipboard.write(markdown: raw, plain: plain, inline: inline, format: format, to: pasteboard)
                let copied = pasteboard.string(forType: .string) ?? ""
                require(!copied.contains("<a") && !copied.contains("</a") && !copied.contains("`"), "no raw markup is copied: \(copied)")
                require(copied == TranslationMarkup(raw, inline: inline).displayText, "the copy matches what is shown: \(copied)")
            }
        }

        // A new link table alone, same words and spans, moves the target.
        let (scroll, view) = makeScroll(width: 320, height: 200)
        let text = "도구 `read`. 확인: <a1>하네스</a1>."
        apply(scroll, text, inline: InlineOptions(code: .only(["read"]), links: [harness]))
        let moved = SourceLink(url: URL(string: "https://moved.example.com/")!, text: harness.text)
        apply(scroll, text, inline: InlineOptions(code: .only(["read"]), links: [moved]))
        let title = (view.string as NSString).range(of: "하네스").location
        require(view.textStorage!.attribute(.link, at: title, effectiveRange: nil) as? URL == moved.url, "a new link table alone updates the target")
    }

    /// U1: units across an explicit `---` boundary are told apart by a drawn line, never by characters.
    private static func unitBreakLines() {
        let above = "윗 단위의 번역입니다.", below = "아랫 단위의 번역입니다."
        let text = above + "\n\n" + below
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, text)
        let right = view.textContainer!.size.width - 6
        var gap = Self.gap(view, after: above, before: below)
        require(scroll.unitLineRects.isEmpty && inkRows(view, x: right, from: gap.top, to: gap.bottom) == 0, "no line without breaks")
        apply(scroll, text, breaks: [above.utf16.count])
        require(view.string == text && !view.string.contains("-") && !view.string.contains("\u{FFFC}") && !hasAttachment(view),
                "the line is neither a character nor an attachment")
        let rows = inkRows(view, x: right, from: gap.top, to: gap.bottom)
        require(rows >= 1 && rows <= 2, "a hairline is drawn between the units: \(rows) device rows")
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], gap)
                && abs(scroll.unitLineRects[0].width - view.textContainer!.size.width) < 0.5, "the line spans the text between the units")
        apply(scroll, text)
        require(scroll.unitLineRects.isEmpty && inkRows(view, x: right, from: gap.top, to: gap.bottom) == 0, "the line goes with its break")

        // A breaks-only update edits nothing, so the reader and the selection stay.
        let (long, longView) = makeScroll()
        let tail = "아래 단위입니다."
        apply(long, first + "\n\n" + tail)
        Self.scroll(long, to: 150)
        let selection = NSRange(location: 8, length: 40)
        longView.setSelectedRange(selection)
        let spy = EditSpy()
        longView.textStorage!.delegate = spy
        for breaks in [[first.utf16.count], []] {
            apply(long, first + "\n\n" + tail, breaks: breaks)
            require(spy.ranges.isEmpty && longView.selectedRange() == selection && abs(long.contentView.bounds.origin.y - 150) < 1,
                    "breaks alone keep the storage, the selection and the reading position: \(breaks)")
            require(long.unitLineRects.count == breaks.count, "lines follow the breaks: \(breaks)")
        }

        // Every boundary gets its line; removing the unit above moves the line with the text.
        let c = "셋째 단위입니다.", units = UUID()
        apply(scroll, text + "\n\n" + c, identity: units, breaks: [above.utf16.count, text.utf16.count])
        let lines = scroll.unitLineRects
        require(lines.count == 2 && isBetween(lines[0], Self.gap(view, after: above, before: below))
                && isBetween(lines[1], Self.gap(view, after: below, before: c)), "two boundaries, two lines in order")
        apply(scroll, below + "\n\n" + c, identity: units, breaks: [below.utf16.count])
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], Self.gap(view, after: below, before: c)),
                "removing the unit above moves the line with the text")

        // Wrapped units, a wider line spacing and a width change keep the line between them.
        let wrappedAbove = Array(repeating: "줄바꿈되는 윗 단위 문장입니다.", count: 4).joined(separator: " ")
        let wrappedBelow = Array(repeating: "줄바꿈되는 아랫 단위 문장입니다.", count: 4).joined(separator: " ")
        let (wrapped, wrappedView) = makeScroll(width: 320, height: 400)
        apply(wrapped, wrappedAbove + "\n\n" + wrappedBelow, lineSpacing: 6, breaks: [wrappedAbove.utf16.count])
        for width in [320.0, 220.0, 320.0] {
            wrapped.setFrameSize(NSSize(width: width, height: 400))
            wrapped.layoutSubtreeIfNeeded()
            gap = Self.gap(wrappedView, after: wrappedAbove, before: wrappedBelow)
            let rows = inkRows(wrappedView, x: wrappedView.textContainer!.size.width - 6, from: gap.top, to: gap.bottom)
            require(wrapped.unitLineRects.count == 1 && isBetween(wrapped.unitLineRects[0], gap) && rows >= 1 && rows <= 2,
                    "the line stays between wrapped units at width \(width)")
        }
    }

    /// The break is a markdown offset; boxes, chips and links before it move the line to the right place.
    private static func unitBreakPositions() {
        let (scroll, view) = makeScroll(width: 320, height: 300)
        let right = view.textContainer!.size.width - 6
        let boxed = "설명\n\n```py\nprint(1)\n```", next = "다음 단위 문단"
        apply(scroll, boxed + "\n\n" + next, breaks: [boxed.utf16.count])
        var text = view.string as NSString
        let boxBottom = codeBox(view, at: text.range(of: "print(1)").location).bottom
        let nextTop = usedLine(view, at: text.range(of: next).location).minY
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], (boxBottom, nextTop)),
                "below a code box: \(scroll.unitLineRects) \(boxBottom) \(nextTop)")
        let rows = inkRows(view, x: right, from: boxBottom, to: nextTop)
        require(rows >= 1 && rows <= 2, "the line is drawn below the box: \(rows)")

        let prose = "윗 단위 문단"
        apply(scroll, prose + "\n\n```sh\nls -la\n```", identity: UUID(), breaks: [prose.utf16.count])
        text = view.string as NSString
        let boxTop = codeBox(view, at: text.range(of: "ls -la").location).top
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], (usedLine(view, at: prose.utf16.count - 1).maxY, boxTop)),
                "above a labeled code box: \(scroll.unitLineRects) \(boxTop)")

        let marked = "도구 `read`. 확인: <a1>하네스</a1>.", after = "아래 단위 문단입니다."
        apply(scroll, marked + "\n\n" + after, identity: UUID(), inline: InlineOptions(code: .only(["read"]), links: [harness]),
              breaks: [marked.utf16.count])
        require(view.string == "도구 read. 확인: 하네스.\n\n" + after, "markers are not shown")
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], Self.gap(view, after: "하네스.", before: after)),
                "a break after a chip and a link maps through their markers: \(scroll.unitLineRects)")
        require(view.textStorage!.attribute(.link, at: (view.string as NSString).range(of: "하네스").location, effectiveRange: nil) as? URL == harness.url
                && view.textStorage!.attribute(.deepKInlineCode, at: 3, effectiveRange: nil) != nil, "the link and the chip keep their style")

        // Blank code lines at a box's end or start are inside the box; the line stays outside it.
        let trailingBlank = "설명\n\n```py\nprint(1)\n\n\n```"
        apply(scroll, trailingBlank + "\n\n" + next, identity: UUID(), breaks: [trailingBlank.utf16.count])
        text = view.string as NSString
        let lower = codeBox(view, at: text.range(of: "print(1)").location)
        require(lower.bottom > usedLine(view, at: NSMaxRange(text.range(of: "print(1)")) - 1).maxY + 10, "the box holds the blank lines")
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], (lower.bottom, usedLine(view, at: text.range(of: next).location).minY)),
                "below a box ending in blank lines: \(scroll.unitLineRects) \(lower)")
        let leadingBlank = "```\n\n\nls\n```"
        apply(scroll, prose + "\n\n" + leadingBlank, identity: UUID(), breaks: [prose.utf16.count])
        text = view.string as NSString
        let upper = codeBox(view, at: text.range(of: "ls").location)
        require(upper.top < usedLine(view, at: text.range(of: "ls").location).minY - 10, "the box holds the blank lines")
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], (usedLine(view, at: prose.utf16.count - 1).maxY, upper.top)),
                "above a box starting with blank lines: \(scroll.unitLineRects) \(upper)")
    }

    private final class Counter {
        var fired = 0
        var enabled = true
    }

    /// '전체 다시 번역' lives in the text view's own right-click menu. A SwiftUI `.contextMenu` on the representable
    /// never opens there: AppKit hands the right click to the NSTextView under the pointer, which answers with its own
    /// menu (Look Up, Copy, Services…). Nothing here touches a pasteboard; the menu is built, not shown.
    private static func contextMenuActions() {
        let (scroll, view) = makeScroll(width: 320, height: 200)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        apply(scroll, "번역 문단입니다. 오른쪽 클릭 메뉴를 확인합니다.")
        let point = view.convert(NSPoint(x: 20, y: 8), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let standard = view.menu(for: event)
        require(standard?.items.contains { $0.title == "전체 다시 번역" } != true, "nothing is added without actions")

        let counter = Counter()
        TranslationResultTextView.setMenuActions([ResultMenuAction(title: "전체 다시 번역", isEnabled: { counter.enabled },
                                                                   perform: { counter.fired += 1 })], in: scroll)
        for _ in 0..<2 {
            let menu = view.menu(for: event)
            let items = menu?.items.filter { $0.title == "전체 다시 번역" } ?? []
            require(items.count == 1, "the action is in the text view's menu once, also on the next right click")
            require(menu?.items.first === items.first && menu?.items.dropFirst().first?.isSeparatorItem == true,
                    "it comes first, above the text view's own items")
            require(menu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true, "the text view's own items stay")
        }
        require(NSTextView.defaultMenu?.items.contains { $0.title == "전체 다시 번역" } != true,
                "the shared default menu is not changed")
        let other = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        require(other.menu(for: event)?.items.contains { $0.title == "전체 다시 번역" } != true, "other text views are untouched")

        let item = view.menu(for: event)!.items.first { $0.title == "전체 다시 번역" }!
        let validator = item.target as? NSMenuItemValidation
        require(validator?.validateMenuItem(item) == true, "enabled while a whole-document retranslation can start")
        counter.enabled = false
        require(validator?.validateMenuItem(item) == false, "disabled otherwise, evaluated when the menu opens")
        counter.enabled = true
        require(NSApp.sendAction(item.action!, to: item.target, from: item) && counter.fired == 1, "choosing it runs the action")

        TranslationResultTextView.setMenuActions([], in: scroll)
        require(view.menu(for: event)?.items.contains { $0.title == "전체 다시 번역" } != true, "actions can be removed")
    }

    /// Overlay scrollers draw over the text, so the text leaves a gutter for them. A legacy scroller (a mouse, or
    /// "always show scroll bars") already has its own column beside the clip view; no second band is added.
    private static func legacyScrollerTakesItsOwnColumn() {
        let gutter = TextPaneMetrics.scrollerGutter
        let (scroll, view) = makeScroll(width: 320, height: 140)
        apply(scroll, first)
        scroll.scrollerStyle = .legacy
        scroll.tile()
        scroll.layoutSubtreeIfNeeded()
        require(view.frame.width < 320, "the legacy scroller narrows the clip view")
        require(view.textContainer!.size.width == view.frame.width, "no gutter next to a legacy scroller")
        scroll.scrollerStyle = .overlay
        scroll.tile()
        scroll.layoutSubtreeIfNeeded()
        require(view.frame.width == 320 && view.textContainer!.size.width == 320 - gutter, "an overlay scroller gets the gutter")
    }

    /// The box drawn behind the code block holding `character`, its header and bottom padding included.
    private static func codeBox(_ view: NSTextView, at character: Int) -> (top: CGFloat, bottom: CGFloat) {
        let box = (view as! ResultTextView).codeBoxes().first { NSLocationInRange(character, $0.block.range) }!.geometry.box
        return (box.minY, box.maxY)
    }

    /// Copying never writes a line or `---`; drafts and superseded text keep their lines but their copy limits.
    private static func unitBreakCopyAndStreaming() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let dragboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard, previousFormat = TranslationResultTextView.copyFormat
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            TranslationResultTextView.copyFormat = previousFormat
            pasteboard.releaseGlobally()
            dragboard.releaseGlobally()
        }
        let (scroll, view) = makeScroll(width: 320, height: 200)
        let all = { NSRange(location: 0, length: (view.string as NSString).length) }
        let plainText = "윗 단위 번역.\n\n아랫 단위 번역."
        apply(scroll, plainText, breaks: ["윗 단위 번역.".utf16.count])
        view.setSelectedRange(all())
        // A plain selection's ⌘C is NSTextView's own and writes the general pasteboard; it writes what this writes.
        _ = view.writeSelection(to: dragboard, types: view.writablePasteboardTypes)
        require(dragboard.string(forType: .string) == plainText, "⌘C and drag write the units joined by one blank line")

        let above = "윗 단위 `read` 번역.", below = "아랫 단위 번역."
        let raw = above + "\n\n" + below
        let inline = InlineOptions(code: .only(["read"]))
        apply(scroll, raw, identity: UUID(), inline: inline, breaks: [above.utf16.count])
        view.setSelectedRange(all())
        TranslationResultTextView.copyFormat = { .rich }
        view.copy(nil)
        let html = pasteboard.string(forType: .html) ?? ""
        require(pasteboard.string(forType: .string) == "윗 단위 read 번역.\n\n" + below && !html.contains("<hr") && !html.contains("---")
                && html.components(separatedBy: "<p>").count == 3, "rich copy has two paragraphs and no rule: \(html)")
        TranslationResultTextView.copyFormat = { .markdown }
        view.copy(nil)
        _ = view.writeSelection(to: dragboard, types: view.writablePasteboardTypes)
        require(pasteboard.string(forType: .string) == raw && dragboard.string(forType: .string) == raw, "markdown copy has no `---`")

        // While the unit below streams, the line is drawn; only the completed unit can leave the view.
        let head = "완료된 윗 단위."
        let (stream, streamView) = makeScroll(width: 320, height: 200)
        apply(stream, head)
        apply(stream, head + "\n\n```py", tailStart: head.utf16.count, streaming: true, breaks: [head.utf16.count])
        require(stream.unitLineRects.isEmpty, "no line until the unit below shows text")
        apply(stream, head + "\n\n초안 문단", tailStart: head.utf16.count, streaming: true, breaks: [head.utf16.count])
        let gap = Self.gap(streamView, after: head, before: "초안")
        let rows = inkRows(streamView, x: streamView.textContainer!.size.width - 6, from: gap.top, to: gap.bottom)
        require(stream.unitLineRects.count == 1 && isBetween(stream.unitLineRects[0], gap) && rows >= 1 && rows <= 2,
                "the line is drawn while the unit below streams")
        streamView.setSelectedRange((streamView.string as NSString).range(of: head))
        require(canCopy(streamView), "the completed unit above the line can be copied")
        streamView.setSelectedRange((streamView.string as NSString).range(of: "초안"))
        require(!canCopy(streamView), "the draft below the line cannot")
        apply(stream, head, breaks: [head.utf16.count])
        require(stream.unitLineRects.isEmpty, "nothing below, no line")
        apply(stream, "   \n\n" + head, identity: UUID(), breaks: [3])
        require(streamView.string.hasSuffix(head) && stream.unitLineRects.isEmpty, "nothing shown above, no line")

        // Superseded text keeps its lines and stays inside the app.
        apply(scroll, raw, stale: true, inline: inline, breaks: [above.utf16.count])
        require(scroll.unitLineRects.count == 1 && isBetween(scroll.unitLineRects[0], Self.gap(view, after: "read 번역.", before: below)),
                "superseded text keeps its line")
        view.setSelectedRange(all())
        require(!canCopy(view), "superseded text with a line cannot be copied")

        // Offsets before the newest unit are converted once, not on every streamed chunk.
        let (cached, cachedView) = makeScroll(width: 320, height: 300)
        let one = "첫 `read` 단위.", two = "둘째 <a1>하네스</a1> 단위."
        let options = InlineOptions(code: .only(["read"]), links: [harness])
        let done = one + "\n\n" + two
        apply(cached, done, inline: options, breaks: [one.utf16.count])
        let converted = cached.offsetConversions
        var streamed = done + "\n\n초"
        apply(cached, streamed, tailStart: done.utf16.count, streaming: true, inline: options, breaks: [one.utf16.count, done.utf16.count])
        require(cached.offsetConversions == converted + 1, "only the new unit's start is converted: \(cached.offsetConversions - converted)")
        for chunk in ["안", " 문단", "입니다."] {
            streamed += chunk
            apply(cached, streamed, tailStart: done.utf16.count, streaming: true, inline: options, breaks: [one.utf16.count, done.utf16.count])
        }
        require(cached.offsetConversions == converted + 1, "streamed chunks reuse converted offsets")
        require(cached.unitLineRects.count == 2 && isBetween(cached.unitLineRects[1], Self.gap(cachedView, after: "하네스 단위.", before: "초안")),
                "both lines are drawn")
        // An edit above a break, even one that keeps its markdown offset, or new inline options convert it again.
        let edited = "첫 'read' 단위."
        apply(cached, edited + "\n\n" + two, inline: options, breaks: [one.utf16.count])
        require(cached.unitLineRects.count == 1 && isBetween(cached.unitLineRects[0], Self.gap(cachedView, after: "'read' 단위.", before: "둘째")),
                "an edit above the break moves the line")
        apply(cached, done, inline: options, breaks: [one.utf16.count])
        apply(cached, done, inline: InlineOptions(), breaks: [one.utf16.count])
        require(cachedView.string.hasPrefix(one) && cached.unitLineRects.count == 1
                && isBetween(cached.unitLineRects[0], Self.gap(cachedView, after: "`read` 단위.", before: "둘째")),
                "new inline options convert the break again")
    }

    /// Rows between the last line of `above` and the first line of `below`, in view coordinates.
    private static func gap(_ view: NSTextView, after above: String, before below: String) -> (top: CGFloat, bottom: CGFloat) {
        let text = view.string as NSString
        return (usedLine(view, at: NSMaxRange(text.range(of: above)) - 1).maxY,
                usedLine(view, at: text.range(of: below, options: .backwards).location).minY)
    }

    private static func isBetween(_ rect: NSRect, _ gap: (top: CGFloat, bottom: CGFloat)) -> Bool {
        rect.height > 0 && rect.minY >= gap.top - 0.01 && rect.maxY <= gap.bottom + 0.01
    }

    private static func usedLine(_ view: NSTextView, at character: Int) -> NSRect {
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        return layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }

    /// Device rows with any ink in one column, strictly between `top` and `bottom` (flipped view coordinates).
    private static func inkRows(_ view: NSView, x: CGFloat, from top: CGFloat, to bottom: CGFloat) -> Int {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let rows = Int((top * scale).rounded(.up))..<max(Int((top * scale).rounded(.up)), Int((bottom * scale).rounded(.down)))
        return rows.filter { (rep.colorAt(x: Int(x * scale), y: $0)?.alphaComponent ?? 0) > 0 }.count
    }

    private static func hasAttachment(_ view: NSTextView) -> Bool {
        var found = false
        let storage = view.textStorage!
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        return found
    }

    private static func display(_ style: ResultStyle, pill: Bool = false) -> ResultDisplaySettings {
        var display = ResultDisplaySettings.standard
        display.style = style
        display.showsLinkSource = pill
        return display
    }

    /// Every style, shipped or fixture, light and dark: the box, header, copy control, chips and links follow its values.
    private static func styleApplication() {
        let text = "도구는 `read`입니다. 확인: <a1>docs</a1>.\n\n```swift\nlet a = 1\nlet b = 2\n```\n\n끝"
        let inline = InlineOptions(code: .only(["read"]), links: [harness])
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            for dark in [false, true] {
                let name = "\(style.name) \(dark ? "dark" : "light")"
                let (scroll, view) = makeScroll(width: 320, height: 400)
                if dark { scroll.appearance = NSAppearance(named: .darkAqua) }
                apply(scroll, text, inline: inline, display: display(style))
                let result = view as! ResultTextView, storage = view.textStorage!, string = view.string as NSString
                let boxes = result.codeBoxes()
                require(boxes.count == 1, "\(name): one box")
                let box = boxes[0].geometry
                require(box.header.height == style.header.height && box.box.minY + style.topPortion
                        <= view.textContainerOrigin.y + view.layoutManager!.lineFragmentUsedRect(
                            forGlyphAt: view.layoutManager!.glyphIndexForCharacter(at: string.range(of: "let a").location), effectiveRange: nil).minY + 0.5,
                        "\(name): the code starts below the header")
                let body = NSPoint(x: box.box.maxX - 6, y: box.header.maxY + 1.5)
                require(shows(view, style.box.fill, at: body, dark: dark), "\(name): box fill")
                if let border = style.box.border {
                    require(shows(view, [style.box.fill, border.color], at: NSPoint(x: box.box.minX + 0.5, y: box.box.midY), dark: dark),
                            "\(name): border")
                }
                if let rule = style.box.rule {
                    require(shows(view, rule.color, at: NSPoint(x: box.box.minX + 1, y: box.box.midY), dark: dark), "\(name): rule")
                }
                if let separator = style.header.separator {
                    require(shows(view, [style.box.fill, separator], at: NSPoint(x: box.box.midX, y: box.header.maxY - 0.5), dark: dark),
                            "\(name): header separator")
                }
                let empty = NSRect(x: box.box.midX - 10, y: box.header.minY + 4, width: 20, height: box.header.height - 8)
                require(differs(view, in: box.label.intersection(NSRect(x: box.label.minX, y: box.header.minY, width: 60, height: box.header.height)),
                                from: NSPoint(x: empty.midX, y: empty.midY)), "\(name): the header label is drawn")
                let copyHit = NSPoint(x: box.copyHit.midX, y: box.copyHit.midY)
                require(result.chromeControl(at: copyHit) == .copy(boxes[0].key), "\(name): the copy control is hit")
                let reference = NSPoint(x: empty.midX, y: empty.midY)
                if style.header.copyVisibility == .hover {
                    require(!differs(view, in: box.copy, from: reference), "\(name): copy waits for the pointer")
                    result.updateHover(at: NSPoint(x: box.box.midX, y: box.box.midY))
                    require(result.hoveredBox == boxes[0].key && differs(view, in: box.copy, from: reference), "\(name): copy shows on hover")
                    result.updateHover(at: nil)
                } else {
                    require(differs(view, in: box.copy, from: reference), "\(name): copy is always drawn")
                }

                // With 문법 색 on by default, `let` takes the palette's keyword color; the space after it is plain code.
                let code = string.range(of: "let a").location
                require(storage.attribute(.foregroundColor, at: code + 3, effectiveRange: nil) as? NSColor
                        == style.code.color.nsColor, "\(name): code color")
                require(storage.attribute(.foregroundColor, at: code, effectiveRange: nil) as? NSColor
                        == (style.syntax?.keyword ?? style.code.color).nsColor, "\(name): keyword color")
                let read = string.range(of: "read")
                let chipFont = storage.attribute(.font, at: read.location, effectiveRange: nil) as! NSFont
                require(chipFont.isFixedPitch && chipFont.pointSize == style.chip.font.size, "\(name): chip font")
                require(storage.attribute(.foregroundColor, at: read.location, effectiveRange: nil) as? NSColor
                        == style.chip.text?.nsColor ?? .labelColor, "\(name): chip text color")
                require(storage.attribute(.deepKChipKern, at: NSMaxRange(read) - 1, effectiveRange: nil) as? CGFloat == style.chip.kern,
                        "\(name): chip kern")
                let layout = view.layoutManager!, container = view.textContainer!, origin = view.textContainerOrigin
                let readBounds = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: read, actualCharacterRange: nil), in: container)
                    .offsetBy(dx: origin.x, dy: origin.y)
                let padding = NSPoint(x: readBounds.minX - style.chip.padding / 2, y: readBounds.midY)
                if let fill = style.chip.fill {
                    if let border = style.chip.border {
                        let chip = result.chips(in: view.bounds)[0]
                        require(shows(view, [fill, border.color], at: NSPoint(x: chip.minX + 0.5, y: chip.midY), dark: dark), "\(name): chip border")
                    }
                    // A chip as light as the window is seen by its border alone.
                    if style.chip.border == nil || standsOut([fill], dark: dark) {
                        require(shows(view, fill, at: padding, dark: dark), "\(name): chip fill")
                    }
                } else {
                    require(pixelAlpha(view, at: padding) == 0 && style.chip.kern == 0, "\(name): a chipless style draws and pads nothing")
                }

                let docs = string.range(of: "docs")
                require(storage.attribute(.foregroundColor, at: docs.location, effectiveRange: nil) as? NSColor
                        == style.link.color?.nsColor ?? .labelColor, "\(name): link color")
                require(view.linkTextAttributes?[.underlineStyle] == nil, "\(name): the text system never underlines links")
                require(storage.attribute(.kern, at: NSMaxRange(docs) - 1, effectiveRange: nil) as? CGFloat
                        == (style.link.trailingArrow ? CodeBlockChrome.arrowWidth : nil), "\(name): room for the arrow")
                let glyph = layout.glyphIndexForCharacter(at: docs.location + 1)
                let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let font = storage.attribute(.font, at: docs.location, effectiveRange: nil) as! NSFont
                let underline = NSPoint(x: origin.x + layout.location(forGlyphAt: glyph).x + 2,
                                        y: origin.y + line.minY + layout.location(forGlyphAt: glyph).y - font.underlinePosition)
                switch style.link.underline {
                case .always: require(pixelAlpha(view, at: underline) > 0, "\(name): underlined")
                case .never: require(pixelAlpha(view, at: underline) == 0, "\(name): never underlined")
                case .hover:
                    require(pixelAlpha(view, at: underline) == 0, "\(name): not underlined before hover")
                    result.updateHover(at: NSPoint(x: underline.x, y: underline.y - 6))
                    require(result.hoveredLink == docs && pixelAlpha(view, at: underline) > 0, "\(name): underlined on hover")
                    result.updateHover(at: nil)
                    require(pixelAlpha(view, at: underline) == 0, "\(name): the hover underline goes away")
                }
            }
        }
    }

    /// The copy control copies one block's code as shown, without touching the selection.
    private static func perBlockCopy() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previous = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previous
            pasteboard.releaseGlobally()
        }
        let (scroll, view) = makeScroll(width: 320, height: 400)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        let text = "설명\n\n```py\nprint(1)\n```\n\n- 목록\n  ```sh\n  npm i\n    npm test\n  ```\n\n끝"
        for style in [ResultStyle.native, .github] {
            apply(scroll, text, identity: UUID(), display: display(style))
            let result = view as! ResultTextView
            let boxes = result.codeBoxes()
            require(boxes.count == 2, "two boxes")
            let selection = NSRange(location: 0, length: 2)
            view.setSelectedRange(selection)
            let center = NSPoint(x: boxes[1].geometry.copyHit.midX, y: boxes[1].geometry.copyHit.midY)
            guard let control = result.chromeControl(at: center) else { return require(false, "\(style.name): copy control") }
            require(control == .copy(boxes[1].key) && result.perform(control), "\(style.name): the second block's control copies")
            require(pasteboard.string(forType: .string) == "npm i\n  npm test" && pasteboard.pasteboardItems?.first?.types == [.string],
                    "\(style.name): only that block's code, without the list's indent: \(pasteboard.string(forType: .string) ?? "")")
            require(view.selectedRange() == selection && result.copiedBlock == boxes[1].key, "\(style.name): the selection stays")
            if style == .native {
                // Native's words are shorter than the 24pt the pointer gets; the rest of that height still copies.
                let geometry = boxes[0].geometry, edge = NSPoint(x: geometry.copy.midX, y: geometry.copyHit.minY + 1)
                require(!geometry.copy.contains(edge) && result.chromeControl(at: edge) == .copy(boxes[0].key),
                        "a point in the 24pt hit area outside the drawn control copies")
            }
            let press = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(center, to: nil), modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            require(view.acceptsFirstMouse(for: press) && view.shouldDelayWindowOrdering(for: press), "\(style.name): the control takes the first click")
            let actions = view.accessibilityCustomActions() ?? []
            require(actions.map(\.name) == ["Python 코드 복사", "Shell 코드 복사"], "VoiceOver names each copy: \(actions.map(\.name))")
            require(actions[0].handler?() == true && pasteboard.string(forType: .string) == "print(1)", "a VoiceOver action copies its block")
        }
        apply(scroll, text, identity: UUID())
        require((view as! ResultTextView).copiedBlock == nil, "a new identity forgets the copied mark")

        // Code a model nests in a numbered step pastes as code that runs; the copy button keeps the list's indent.
        let step = "1. 실행합니다:\n   ```python\n   import os\n   print(os.getcwd())\n   ```\n2. 끝"
        apply(scroll, step, identity: UUID())
        let stepBox = (view as! ResultTextView).codeBoxes()
        require(stepBox.count == 1 && (view as! ResultTextView).perform(.copy(stepBox[0].key))
                && pasteboard.string(forType: .string) == "import os\nprint(os.getcwd())",
                "a block in a list copies without the list's indent: \(pasteboard.string(forType: .string) ?? "")")
        let code = (view.string as NSString).range(of: "import os\nprint(os.getcwd())")
        require(TranslationMarkup(step).plainText(in: code, fences: .none) == "   import os\n   print(os.getcwd())",
                "a selection copied with the copy button keeps it")

        // A block in the draft after the completed text cannot leave the app, nor can superseded code.
        let head = "설명\n\n```py\nprint(1)\n```"
        apply(scroll, head)
        apply(scroll, head + "\n\n```sh\nSECRET\n```", tailStart: head.utf16.count, streaming: true)
        let result = view as! ResultTextView
        let boxes = result.codeBoxes()
        require(boxes.count == 2, "draft box")
        let draft = boxes[1].geometry.copyHit
        require(result.chromeControl(at: NSPoint(x: draft.midX, y: draft.midY)) == nil && !result.perform(.copy(boxes[1].key)),
                "a draft block's copy is disabled")
        require(result.chromeControl(at: NSPoint(x: boxes[0].geometry.copyHit.midX, y: boxes[0].geometry.copyHit.midY)) == .copy(boxes[0].key),
                "the completed block before the draft copies")
        require(view.accessibilityCustomActions()?.map(\.name) == ["Python 코드 복사"], "VoiceOver offers only the completed block")
        require(result.copyState(of: boxes[1]) == .disabled && result.copyState(of: boxes[0]) == .normal, "the draft block's control is drawn disabled")
        require(result.chromeToolTips.map(\.rect) == [boxes[0].geometry.copyHit], "only the completed block's control has a tooltip")
        apply(scroll, head, stale: true)
        let stale = result.codeBoxes()[0]
        require(result.chromeControl(at: NSPoint(x: stale.geometry.copyHit.midX, y: stale.geometry.copyHit.midY)) == nil
                && !result.perform(.copy(stale.key)) && view.accessibilityCustomActions() == nil, "superseded code cannot be copied")
        require(result.copyState(of: stale) == .disabled && result.chromeToolTips.isEmpty, "superseded code is drawn disabled, without a tooltip")

        // A block that runs past the copy limit holds draft lines, so it cannot leave the app either.
        let crossing = "설명\n\n```py\nprint(1)\nSECRET_DRAFT_LINE"
        pasteboard.clearContents()
        apply(scroll, crossing, identity: UUID(), tailStart: (crossing as NSString).range(of: "SECRET_DRAFT_LINE").location, streaming: true)
        let crossed = result.codeBoxes()
        require(crossed.count == 1, "the crossing block has a box")
        require(result.chromeControl(at: NSPoint(x: crossed[0].geometry.copyHit.midX, y: crossed[0].geometry.copyHit.midY)) == nil
                && !result.perform(.copy(crossed[0].key)) && view.accessibilityCustomActions() == nil
                && pasteboard.string(forType: .string) == nil, "a block crossing the copy limit cannot be copied")

        // Blocks with no title or language are told apart by their place.
        apply(scroll, "```\na\n```\n\n```\nb\n```", identity: UUID())
        require(view.accessibilityCustomActions()?.map(\.name) == ["코드 블록 1 복사", "코드 블록 2 복사"],
                "untitled, untagged blocks are numbered: \(view.accessibilityCustomActions()?.map(\.name) ?? [])")

        // "복사됨" reads for a while, then the control is back.
        let copied = result.codeBoxes()[0]
        require(result.perform(.copy(copied.key)) && result.copyState(of: copied) == .copied, "the control reads 복사됨")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        require(result.copiedBlock == copied.key, "복사됨 stays for a moment")
        let deadline = Date().addingTimeInterval(4)
        while result.copiedBlock != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        require(result.copiedBlock == nil && result.copyState(of: copied) == .normal, "복사됨 clears after the copied duration")
    }

    /// 링크 출처 표시 adds a pill as kern after a link: the words, copies and chips stay as they are.
    private static func linkSource() {
        require(ResultStyle.SourcePill.host(for: URL(string: "https://www.blog.example.com/x")!) == "blog.example.com", "www. is dropped")
        let long = ResultStyle.SourcePill.host(for: URL(string: "https://a-very-long-subdomain.of-an-example-site.example.com/")!)
        require(long?.count == 28 && long?.contains("…") == true, "a long host is cut in the middle: \(long ?? "")")
        require(ResultStyle.SourcePill.host(for: URL(string: "mailto:a@example.com")!) == nil, "mail links have no pill")
        require(ResultStyle.SourcePill.host(for: URL(string: "https://xn--bcher-kva.example/")!) == "xn--bcher-kva.example", "IDN stays punycode")

        let links = [SourceLink(url: URL(string: "https://www.blog.example.com/harness")!, text: "harness"),
                     SourceLink(url: URL(string: "mailto:a@example.com")!, text: "mail"),
                     SourceLink(url: URL(string: "https://docs.example.com/read")!, text: "read")]
        let inline = InlineOptions(code: .only(["read"]), links: links)
        let text = "확인: <a1>하네스 찾기</a1>. 메일: <a2>문의</a2>. 칩 링크: <a3>`read`</a3> 끝."
        let (off, offView) = makeScroll(width: 320, height: 300)
        apply(off, text, inline: inline)
        let (on, onView) = makeScroll(width: 320, height: 300)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = on
        defer { window.contentView = nil }
        apply(on, text, inline: inline, display: display(.native, pill: true))
        require(onView.string == offView.string, "the pill is not in the text")
        let string = onView.string as NSString, storage = onView.textStorage!
        let title = string.range(of: "찾기"), mail = string.range(of: "문의"), read = string.range(of: "read")
        let pill = ResultStyle.native.pill
        let width = CodeBlockChrome.adornmentWidth(host: "blog.example.com", arrow: false, style: .native)
        require(width == pill.leading + CodeBlockChrome.pillWidth(host: "blog.example.com", pill: pill) + pill.trailing, "pill width")
        require(storage.attribute(.kern, at: NSMaxRange(title) - 1, effectiveRange: nil) as? CGFloat == width, "room for the pill")
        require(offView.textStorage!.attribute(.kern, at: NSMaxRange(title) - 1, effectiveRange: nil) == nil, "no room without the setting")
        require(storage.attribute(.kern, at: NSMaxRange(mail) - 1, effectiveRange: nil) == nil, "a mail link gets no pill")
        let chipKern = ResultStyle.native.chip.kern
        require(storage.attribute(.kern, at: NSMaxRange(read) - 1, effectiveRange: nil) as? CGFloat
                == chipKern + CodeBlockChrome.adornmentWidth(host: "docs.example.com", arrow: false, style: .native)
                && storage.attribute(.deepKChipKern, at: NSMaxRange(read) - 1, effectiveRange: nil) as? CGFloat == chipKern,
                "a link ending in a chip adds the pill to the chip's kern")
        let onChip = (onView as! ResultTextView).chips(in: onView.bounds).first!
        let offChip = (offView as! ResultTextView).chips(in: offView.bounds).first!
        require(abs(onChip.width - offChip.width) < 0.5, "the pill never stretches a chip")

        // The pill is drawn after the link's words and opens the link.
        let layout = onView.layoutManager!, origin = onView.textContainerOrigin
        let last = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(title) - 1, length: 1),
                                                                         actualCharacterRange: nil), in: onView.textContainer!)
        let inside = NSPoint(x: origin.x + last.maxX - width + pill.leading + 8, y: origin.y + last.midY)
        require(pixelAlpha(onView, at: inside) > 0, "the pill is drawn")
        let result = onView as! ResultTextView
        let control = result.chromeControl(at: inside)
        require(control == .pill(string.range(of: "하네스 찾기")), "the pill is a control")
        var opened: [URL] = []
        let previous = TranslationResultTextView.openLink
        TranslationResultTextView.openLink = { opened.append($0) }
        defer { TranslationResultTextView.openLink = previous }
        if let control { result.perform(control) }
        require(opened == [links[0].url], "the pill opens its link")

        // A chip right after a link keeps its padding after the pill, which starts right after the link's words.
        let (chipAfter, chipAfterView) = makeScroll(width: 320, height: 300)
        apply(chipAfter, "보기: <a1>설정</a1>`config` 끝.", inline: InlineOptions(code: .only(["config"]), links: [links[2]]),
              display: display(.native, pill: true))
        let word = (chipAfterView.string as NSString).range(of: "설정")
        let wordLayout = chipAfterView.layoutManager!, wordOrigin = chipAfterView.textContainerOrigin
        let wordEnd = wordLayout.boundingRect(forGlyphRange: wordLayout.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(word) - 1, length: 1),
                                                                                    actualCharacterRange: nil), in: chipAfterView.textContainer!)
        let wordKern = chipAfterView.textStorage!.attribute(.kern, at: NSMaxRange(word) - 1, effectiveRange: nil) as? CGFloat ?? 0
        let chipAfterResult = chipAfterView as! ResultTextView
        let followingChip = chipAfterResult.chips(in: chipAfterView.bounds)[0]
        let y = wordOrigin.y + wordEnd.midY
        require(chipAfterResult.chromeControl(at: NSPoint(x: wordOrigin.x + wordEnd.maxX - wordKern + pill.leading + 1, y: y)) == .pill(word),
                "the pill starts after the link's words")
        require(chipAfterResult.chromeControl(at: NSPoint(x: followingChip.minX + 0.5, y: y)) == nil, "the pill ends before the chip")

        // Copies are the same with or without the pill.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previousBoard
            pasteboard.releaseGlobally()
        }
        var copies: [String] = []
        for copyView in [offView, onView] {
            copyView.setSelectedRange(NSRange(location: 0, length: string.length))
            copyView.copy(nil)
            copies.append(pasteboard.string(forType: .string) ?? "")
        }
        require(copies[0] == copies[1] && !copies[0].isEmpty, "copies do not change")

        // Superseded text keeps the pill, dimmed, so nothing re-wraps; it no longer opens.
        apply(on, text, stale: true, inline: inline, display: display(.native, pill: true))
        require(storage.attribute(.kern, at: NSMaxRange(title) - 1, effectiveRange: nil) as? CGFloat == width
                && result.chromeControl(at: inside) == nil, "a stale pill stays in place, inert")
    }

    /// Changing the style or the pill restyles in place: the text, the selection and the line being read stay.
    private static func displayChangeKeepsReader() {
        let (scroll, view) = makeScroll()
        let text = (1...12).map { "문단 \($0): 확인할 <a1>링크</a1>와 `read` 칩이 있는 번역 문장입니다." }.joined(separator: "\n\n")
            + "\n\n```ts\n" + (1...12).map { "const value\($0) = \($0);" }.joined(separator: "\n") + "\n```\n\n"
            + (13...24).map { "문단 \($0): 이어지는 번역 문장입니다." }.joined(separator: "\n\n")
        let inline = InlineOptions(code: .only(["read"]), links: [harness])
        apply(scroll, text, inline: inline)
        Self.scroll(scroll, to: 420)
        let selection = NSRange(location: 30, length: 40)
        view.setSelectedRange(selection)
        let line = topLineText(of: scroll), string = view.string
        func requireReader(_ step: String) {
            require(view.string == string && view.selectedRange() == selection, "\(step): the text and selection stay")
            require(topLineText(of: scroll) == line, "\(step): the line being read stays: \(topLineText(of: scroll))")
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        apply(scroll, text, inline: inline, display: display(.github))
        requireReader("GitHub")
        require(scroll.appliedDisplay.style == .github && (view as! ResultTextView).codeBoxes().first?.geometry.header.height == 35,
                "the new style applies at once")
        // `const` takes the palette's keyword color with 문법 색 on; the space after it is plain code.
        let const1 = (view.string as NSString).range(of: "const value1 ").location
        require(view.textStorage!.attribute(.foregroundColor, at: const1 + 5, effectiveRange: nil) as? NSColor == ResultStyle.github.code.color.nsColor
                && view.textStorage!.attribute(.foregroundColor, at: const1, effectiveRange: nil) as? NSColor
                    == ResultStyle.github.syntax?.keyword.nsColor,
                "the code takes the new style's colors")
        settle()
        apply(scroll, text, inline: inline, display: display(.github, pill: true))
        requireReader("pill")
        settle()
        apply(scroll, text, lineSpacing: 6, inline: inline, display: display(.native, pill: true))
        requireReader("Native and line spacing")

        // Stepping through styles restyles at most once per interval, and the last one wins.
        settle()
        let spy = EditSpy()
        view.textStorage!.delegate = spy
        let steps = [ResultStyle.github] + ResultStyle.fixtures + [.github, .native]
        for style in steps { apply(scroll, text, lineSpacing: 6, inline: inline, display: display(style)) }
        let immediate = spy.ranges.count
        settle()
        settle()
        requireReader("after stepping")
        require(scroll.appliedDisplay == display(.native), "the last style wins")
        require(immediate >= 1 && spy.ranges.count < steps.count, "rapid changes are coalesced: \(spy.ranges.count) restyles for \(steps.count)")
        view.textStorage!.delegate = nil

        // Back to the shown style within the interval: the style held back is dropped, so the last one, the shown one, wins.
        settle()
        for style in [ResultStyle.github, .native, .github] { apply(scroll, text, lineSpacing: 6, inline: inline, display: display(style)) }
        settle()
        settle()
        require(scroll.appliedDisplay == display(.github), "A → B → A within the interval keeps A: \(scroll.appliedDisplay.style.name)")
        requireReader("A → B → A")
    }

    /// A styled stream with a fenced block and a pill link only appends, and keeps the reader.
    private static func streamingWithStyle() {
        for style in [ResultStyle.github, .railFixture] {
            let (scroll, view) = makeScroll()
            let inline = InlineOptions(code: .only(["read"]), links: [harness])
            let style = display(style, pill: true)
            var raw = (1...20).map { "번역 문단 \($0): 선택 범위를 유지합니다." }.joined(separator: "\n\n")
            apply(scroll, raw, streaming: true, inline: inline, display: style)
            let selection = NSRange(location: 8, length: 30)
            view.setSelectedRange(selection)
            Self.scroll(scroll, to: 120)
            let origin = scroll.contentView.bounds.origin
            var previous = view.string
            for chunk in ["\n\n확인: <a1>하네", "스</a1> `re", "ad`.\n\n``", "`ts\nconst a", " = 1;\nconst b", " = 2;\n``", "`\n\n끝"] {
                raw += chunk
                apply(scroll, raw, streaming: true, inline: inline, display: style)
                require(view.string.utf16.starts(with: previous.utf16) && !view.string.contains("`") && !view.string.contains("<"),
                        "\(style.style.name) stream appends display only: \(chunk)")
                require(view.selectedRange() == selection && abs(scroll.contentView.bounds.origin.y - origin.y) < 1,
                        "\(style.style.name) stream keeps the reader: \(chunk)")
                previous = view.string
            }
            let boxes = (view as! ResultTextView).codeBoxes()
            require(boxes.count == 1 && CodeBlockChrome.lineCount(of: boxes[0].block.range, in: view.string as NSString) == 2,
                    "\(style.style.name): the streamed block has two lines")
        }
    }

    /// A fence's title heads its block, as the selected tab did on the page the code was copied from. It is not code:
    /// the text, the line count and the block's copy hold only the code.
    private static func titledBlocks() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previous = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previous
            pasteboard.releaseGlobally()
        }
        // The last is a language tab's block: its title names the language, so the header and VoiceOver say it once.
        let text = "에이전트에 맞는 명령을 고르세요.\n\n```text title=\"Most Agents\"\n/impeccable document\n```\n\n"
            + "npm으로 설치합니다.\n\n```bash title=\"npm\"\nnpm install deepk\n```\n\n"
            + "클라이언트를 만듭니다.\n\n```python title=\"Python\"\nimport anthropic\n```\n\n끝"
        for (style, labels) in [(ResultStyle.native, ["Most Agents · 1줄", "npm · Bash · 1줄", "Python · 1줄"]),
                                (.github, ["Most Agents", "npm · bash", "Python"])] {
            let (scroll, view) = makeScroll(width: 320, height: 400)
            apply(scroll, text, display: display(style))
            let result = view as! ResultTextView
            let boxes = result.codeBoxes()
            require(view.string == TranslationMarkup(text).displayText && !view.string.contains("Most") && !view.string.contains("title"),
                    "\(style.name): the title is not in the text")
            require(boxes.map(\.title) == ["Most Agents", "npm", "Python"] && boxes.compactMap(result.headerLabel(of:)) == labels,
                    "\(style.name): the header shows the title: \(boxes.map(result.headerLabel(of:)))")
            require(boxes.allSatisfy { CodeBlockChrome.lineCount(of: $0.block.range, in: view.string as NSString) == 1 },
                    "\(style.name): the title is not a line")
            require(result.perform(.copy(boxes[0].key)) && pasteboard.string(forType: .string) == "/impeccable document",
                    "\(style.name): the block's copy holds only the code: \(pasteboard.string(forType: .string) ?? "")")
            require(view.accessibilityCustomActions()?.map(\.name) == ["Most Agents 코드 복사", "npm, Bash 코드 복사", "Python 코드 복사"],
                    "\(style.name): VoiceOver names the title")
            require(boxes.allSatisfy { result.headerToolTip(of: $0) == nil } && result.chromeToolTips.map(\.rect) == boxes.map(\.geometry.copyHit),
                    "\(style.name): a label that fits needs no tooltip")
            // Past where a line count alone would end, so only the title draws here.
            let geometry = boxes[0].geometry
            let words = NSRect(x: geometry.label.minX + 40, y: geometry.header.minY + 4, width: 30, height: geometry.header.height - 8)
            require(differs(view, in: words, from: NSPoint(x: geometry.label.maxX - 4, y: geometry.header.midY)), "\(style.name): the title is drawn")
        }

        // A label longer than its room ends in "…" before the copy control, which does not move; the tooltip has it whole.
        let long = "src/components/settings/CodeStylePickerPreview.tsx"
        for style in [ResultStyle.native, .github, .railFixture] {
            let (scroll, view) = makeScroll(width: 320, height: 300)
            let result = view as! ResultTextView
            apply(scroll, "```ts title=\"a.ts\"\nlet a = 1\n```", display: display(style))
            let short = result.codeBoxes()[0]
            require(result.chromeToolTips.map(\.rect) == [short.geometry.copyHit], "\(style.name): only the copy control has a tooltip")
            apply(scroll, "```ts title=\"\(long)\"\nlet a = 1\n```", display: display(style))
            let cut = result.codeBoxes()[0], geometry = cut.geometry
            require(geometry == short.geometry && cut.key == short.key, "\(style.name): a long title moves nothing")
            require(result.headerToolTip(of: short) == nil && result.headerToolTip(of: cut) == result.headerLabel(of: cut)
                    && result.headerLabel(of: cut)?.hasPrefix(long) == true, "\(style.name): the tooltip has the whole label")
            // The view owns its tooltip rects and answers for each by its tag.
            let tips = result.chromeToolTips
            let words = tips.map { result.view(result, stringForToolTip: $0.tag, point: NSPoint(x: $0.rect.midX, y: $0.rect.midY), userData: nil) }
            require(tips.map(\.rect) == [geometry.copyHit, geometry.label] && Set(tips.map(\.tag)).count == 2
                    && words == ["코드 복사", result.headerLabel(of: cut)], "\(style.name): the cut label's room has the whole label: \(words)")
            require(result.chromeControl(at: NSPoint(x: geometry.copyHit.midX, y: geometry.copyHit.midY)) == .copy(cut.key),
                    "\(style.name): the copy control is still hit")
            let reference = NSPoint(x: geometry.label.maxX + 1, y: geometry.header.minY + 3)
            let gap = NSRect(x: geometry.label.maxX, y: geometry.header.minY + 2, width: geometry.copyHit.minX - geometry.label.maxX,
                             height: geometry.header.height - 4)
            require(!differs(view, in: gap, from: reference), "\(style.name): nothing is drawn between the cut label and the copy control")
            // "복사됨" is wider than "복사"; it still keeps the gap to the label's room.
            require(result.perform(.copy(cut.key)) && result.copyState(of: cut) == .copied, "\(style.name): copied")
            require(!differs(view, in: gap, from: reference), "\(style.name): 복사됨 stays out of the label's room and its gap")
            let end = NSRect(x: geometry.label.maxX - 24, y: geometry.header.minY + 2, width: 24, height: geometry.header.height - 4)
            require(differs(view, in: end, from: reference), "\(style.name): the cut label runs to the end of its room")
        }

        // Only the title changed in place, as when B's guard restores a reworded one: the block keeps its key and state.
        let (scroll, view) = makeScroll(width: 320, height: 300)
        let result = view as! ResultTextView
        let code = "\n/impeccable document\n```\n\n끝"
        apply(scroll, "```text title=\"대부분의 에이전트\"" + code)
        let before = result.codeBoxes()[0]
        require(result.perform(.copy(before.key)) && result.copiedBlock == before.key, "the block is copied")
        apply(scroll, "```text title=\"Most Agents\"" + code)
        let after = result.codeBoxes()[0]
        require(after.key == before.key && result.copiedBlock == before.key && result.headerLabel(of: after) == "Most Agents · 1줄",
                "a new title keeps the block's state and shows at once")
        apply(scroll, "```bash title=\"Most Agents\"" + code)
        require(result.codeBoxes()[0].key != before.key, "a new language is a new block")
    }

    /// An opener streamed in pieces shows no box until its line is complete, so a cut title (`title="Most Ag`) is never
    /// drawn, and the text only appends.
    private static func titleWhileStreaming() {
        for (style, label) in [(ResultStyle.native, "Most Agents · 1줄"), (.github, "Most Agents")] {
            let (scroll, view) = makeScroll(width: 320, height: 400)
            let result = view as! ResultTextView
            var raw = "에이전트에 맞는 명령을 고르세요."
            apply(scroll, raw, streaming: true, display: display(style))
            var previous = view.string
            for chunk in ["\n\n``", "`text ti", "tle=\"Most Ag", "ents\"", "\n/impeccable", " document", "\n``", "`\n\n이어서 설치합니다."] {
                raw += chunk
                apply(scroll, raw, streaming: true, display: display(style))
                require(view.string.utf16.starts(with: previous.utf16) && !view.string.contains("`") && !view.string.contains("Most"),
                        "\(style.name): the stream appends display text only: \(chunk)")
                let boxes = result.codeBoxes()
                require(boxes.count == (view.string.contains("/impeccable") ? 1 : 0)
                        && boxes.allSatisfy { result.headerLabel(of: $0) == label },
                        "\(style.name): a box, with the whole title, only once code arrives: \(chunk) \(boxes.map(result.headerLabel(of:)))")
                previous = view.string
            }
            apply(scroll, raw, display: display(style))
            require(result.codeBoxes().compactMap(result.headerLabel(of:)) == [label], "\(style.name): the completed block")
        }
    }

    /// Tooltip rects are registered again only when a box, its copy state or its words change; a chunk that moves
    /// nothing leaves them, and every change still shows.
    private static func chromeRegionsFollowChanges() {
        let (scroll, view) = makeScroll(width: 320, height: 400)
        let result = view as! ResultTextView
        func requireCurrent(_ step: String) {
            let text = view.string as NSString
            let boxes = result.codeBoxes()
            let tips = boxes.map { (rect: $0.geometry.copyHit, text: "코드 복사") } + boxes.compactMap { box in
                CodeBlockChrome.headerLabel(title: box.title, tag: box.block.fence?.language,
                                            lineCount: CodeBlockChrome.lineCount(of: box.block.range, in: text), style: .native)
                    .flatMap { CodeBlockChrome.fittedLabel($0, in: box.geometry, style: .native) == $0 ? nil : (rect: box.geometry.label, text: $0) }
            }
            require(result.chromeToolTips.map(\.rect) == tips.map(\.rect) && result.chromeToolTips.map(\.text) == tips.map(\.text),
                    "\(step): the tooltips are the boxes' own: \(result.chromeToolTips.map(\.text))")
        }
        var text = "첫 문단\n\n```ts title=\"src/components/settings/Preview.tsx\"\nlet a = 1\n```\n\n둘째 문단\n\n```py\nprint(1)\n```\n\n셋째 문단"
        apply(scroll, text)
        requireCurrent("first")
        require(result.chromeToolTips.count == 3, "two copy controls and the cut label have tooltips")
        let registered = result.chromeRegistrations
        for chunk in [" 이어서", " 더 이어서", "\n\n넷째 문단"] {
            text += chunk
            apply(scroll, text)
            requireCurrent("after \(chunk)")
        }
        require(result.chromeRegistrations == registered, "text after the boxes leaves the tooltips: \(result.chromeRegistrations - registered)")
        text = text.replacingOccurrences(of: "첫 문단", with: "첫 문단\n새로 들어온 줄")
        apply(scroll, text)
        requireCurrent("a line before the boxes")
        require(result.chromeRegistrations == registered + 1, "moved boxes move their tooltips")
        scroll.setFrameSize(NSSize(width: 640, height: 400))
        requireCurrent("wider")
        require(result.chromeToolTips.count == 2, "a label that fits the wider room needs no tooltip")
        scroll.setFrameSize(NSSize(width: 320, height: 400))
        requireCurrent("narrow again")
        require(result.chromeToolTips.count == 3, "the cut label has its tooltip again")

        // An edit inside a block that keeps its length and fence still renames its header.
        apply(scroll, "```\na b\n```\n\n끝", identity: UUID())
        require(result.codeBoxes().compactMap(result.headerLabel(of:)) == ["1줄"], "one line")
        apply(scroll, "```\na\nb\n```\n\n끝", identity: UUID())
        require(result.codeBoxes().compactMap(result.headerLabel(of:)) == ["2줄"], "a new identity counts again")
        apply(scroll, "```\na b\n```\n\n끝")
        apply(scroll, "```\na\nb\n```\n\n끝")
        require(result.codeBoxes().compactMap(result.headerLabel(of:)) == ["2줄"],
                "an edit in place counts again: \(result.codeBoxes().compactMap(result.headerLabel(of:)))")
    }

    /// The pointer and drawing lay out only the boxes and link adornments near them, and still find them far down the text.
    private static func hoverLooksNearThePointer() {
        let links = (1...30).map { SourceLink(url: URL(string: "https://site\($0).example.com/page")!, text: "문서 \($0)") }
        let text = (1...30).map { n in "문단 \(n): <a\(n)>안내 \(n)</a\(n)> 참고.\n\n```ts\nconst v\(n) = \(n);\n```\n\n" }.joined() + "끝"
        let (scroll, view) = makeScroll(width: 320, height: 300)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        apply(scroll, text, inline: InlineOptions(links: links), display: display(.github, pill: true))
        let result = view as! ResultTextView
        let boxes = result.codeBoxes()
        require(boxes.count == 30, "thirty boxes")
        let box = boxes[17]
        Self.scroll(scroll, to: box.geometry.box.minY - 60)
        let before = result.chromeLayouts
        result.updateHover(at: NSPoint(x: box.geometry.copyHit.midX, y: box.geometry.copyHit.midY))
        require(result.hoveredControl == .copy(box.key) && result.hoveredBox == box.key, "the control far down the text is found")
        let hover = result.chromeLayouts - before
        require(hover <= 6, "hovering lays out only what is near the pointer: \(hover)")

        // The pill of the link just above that box.
        let string = view.string as NSString, storage = view.textStorage!
        let words = string.range(of: "안내 18")
        let layout = view.layoutManager!, origin = view.textContainerOrigin
        let last = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(words) - 1, length: 1),
                                                                        actualCharacterRange: nil), in: view.textContainer!)
        let kern = storage.attribute(.kern, at: NSMaxRange(words) - 1, effectiveRange: nil) as? CGFloat ?? 0
        let pill = NSPoint(x: origin.x + last.maxX - kern + ResultStyle.github.pill.leading + 8, y: origin.y + last.midY)
        require(result.chromeControl(at: pill) == .pill(words), "the pill far down the text is a control")

        let visible = scroll.documentVisibleRect
        let rep = view.bitmapImageRepForCachingDisplay(in: visible)!
        let drawn = result.chromeLayouts
        view.cacheDisplay(in: visible, to: rep)
        let drawing = result.chromeLayouts - drawn
        require(drawing > 0 && drawing < 20, "drawing lays out only what it shows: \(drawing)")
        let local = NSPoint(x: pill.x - visible.minX, y: pill.y - visible.minY)
        let color = rep.colorAt(x: Int(local.x * CGFloat(rep.pixelsWide) / visible.width), y: Int(local.y * CGFloat(rep.pixelsHigh) / visible.height))
        require((color?.alphaComponent ?? 0) > 0, "the pill is drawn")
    }

    /// A stream that completes with the text it last showed restyles nothing, yet the draft block's control now works,
    /// so it asks to be drawn again. A window that is never shown does not draw, so the requests are counted.
    private static func completionRedrawsCopyControl() {
        let (scroll, view) = makeScroll(width: 320, height: 400)
        let result = view as! ResultTextView
        let head = "설명\n\n```py\nprint(1)\n```"
        let full = head + "\n\n```sh\nx\n```"
        apply(scroll, head)
        apply(scroll, full, tailStart: head.utf16.count, streaming: true)
        require(result.copyState(of: result.codeBoxes()[1]) == .disabled, "the draft block is disabled")
        let spy = EditSpy()
        view.textStorage!.delegate = spy
        defer { view.textStorage!.delegate = nil }
        var requests = result.copyControlRedraws
        apply(scroll, full, tailStart: head.utf16.count)
        require(spy.ranges.isEmpty, "the same text completes without a restyle")
        require(result.copyState(of: result.codeBoxes()[1]) == .normal, "the completed block copies")
        require(result.copyControlRedraws == requests + 1, "the control is drawn again when it starts to work")
        requests = result.copyControlRedraws
        apply(scroll, full, tailStart: head.utf16.count)
        require(result.copyControlRedraws == requests, "nothing changed, nothing is drawn")
        apply(scroll, full, tailStart: head.utf16.count, stale: true)
        require(result.copyControlRedraws > requests && result.copyState(of: result.codeBoxes()[0]) == .disabled,
                "superseded code is drawn again, disabled")
    }

    /// The pointing hand over a drawn control is put back when the pointer leaves it or the view, even in a panel that is not key.
    private static func cursorFollowsControls() {
        let (scroll, view) = makeScroll(width: 320, height: 400)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        apply(scroll, "설명 문단입니다.\n\n```py\nprint(1)\n```\n\n끝 문단입니다.", identity: UUID())
        let result = view as! ResultTextView
        let box = result.codeBoxes()[0]
        let control = NSPoint(x: box.geometry.copyHit.midX, y: box.geometry.copyHit.midY)
        let prose = NSPoint(x: 20, y: view.textContainerOrigin.y + 8)
        func moved(to point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }
        NSCursor.arrow.set()
        view.mouseMoved(with: moved(to: control))
        require(result.hoveredControl == .copy(box.key) && NSCursor.current == NSCursor.pointingHand, "a pointing hand over the control")
        view.mouseMoved(with: moved(to: prose))
        require(result.hoveredControl == nil && NSCursor.current == NSCursor.iBeam, "back to the I-beam over the text")
        view.mouseMoved(with: moved(to: control))
        require(NSCursor.current == NSCursor.pointingHand, "the hand again")
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: view.convert(NSPoint(x: -5, y: -5), to: nil), modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseExited(with: exit)
        require(result.hoveredControl == nil && NSCursor.current == NSCursor.arrow, "the arrow once the pointer leaves the view")
        NSCursor.arrow.set()
    }

    /// The real click path: mouseDown follows the press with the window's events and copies only when released over
    /// the control. The window is never ordered in; the release is queued before the press.
    private static func clickRunsOnRelease() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previous = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previous
            pasteboard.releaseGlobally()
        }
        let (scroll, view) = makeScroll(width: 320, height: 400)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        // A tracking loop that never sees its release would wait forever.
        let watchdog = DispatchWorkItem {
            FileHandle.standardError.write(Data("TranslationResultTextViewTests: the click's tracking loop did not end\n".utf8))
            exit(1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        defer { watchdog.cancel() }
        let result = view as! ResultTextView
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func click(at point: NSPoint, path: [(NSEvent.EventType, NSPoint)]) {
            for (type, at) in path { NSApp.postEvent(event(type, at: at), atStart: false) }
            view.mouseDown(with: event(.leftMouseDown, at: point))
        }
        let text = "설명\n\n```py\nprint(1)\n```\n\n끝"
        for (step, release, copies) in [("released over it", true, true), ("released outside", false, false), ("dragged out and back", true, true)] {
            pasteboard.clearContents()
            apply(scroll, text, identity: UUID())
            let box = result.codeBoxes()[0]
            let control = NSPoint(x: box.geometry.copyHit.midX, y: box.geometry.copyHit.midY)
            let outside = NSPoint(x: box.geometry.box.midX, y: box.geometry.box.maxY - 4)
            let selection = NSRange(location: 0, length: 2)
            view.setSelectedRange(selection)
            var path: [(NSEvent.EventType, NSPoint)] = []
            if step == "dragged out and back" { path += [(.leftMouseDragged, outside), (.leftMouseDragged, control)] }
            if !release { path.append((.leftMouseDragged, outside)) }
            path.append((.leftMouseUp, release ? control : outside))
            click(at: control, path: path)
            require((pasteboard.string(forType: .string) == "print(1)") == copies && (result.copiedBlock == box.key) == copies,
                    "\(step): copies \(copies)")
            require(view.selectedRange() == selection, "\(step): the selection stays")
            require(NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) == nil, "\(step): the release was taken")
        }
    }

    /// A fold footer far down the text is found by the pointer looking only near itself, and a footer click or a fold setting
    /// change, which move every box below, registers the tooltips again where the boxes now are.
    private static func foldFootersNearThePointer() {
        let text = (1...30).map { n in "문단 \(n)\n\n```ts\n\(codeLines(8, from: n * 10))\n```\n\n" }.joined() + "끝"
        let (scroll, view) = makeScroll(width: 320, height: 300)
        let result = view as! ResultTextView
        func requireCurrent(_ step: String) {
            let boxes = result.codeBoxes()
            let tips = boxes.map { (rect: $0.geometry.copyHit, text: "코드 복사") }
                + boxes.compactMap { box in result.headerToolTip(of: box).map { (rect: box.geometry.label, text: $0) } }
            require(result.chromeToolTips.map(\.rect) == tips.map(\.rect) && result.chromeToolTips.map(\.text) == tips.map(\.text),
                    "\(step): the tooltips are where the boxes are")
        }
        apply(scroll, text, identity: UUID(), display: folds(5))
        var boxes = result.codeBoxes()
        require(boxes.count == 30 && boxes.allSatisfy(\.fold.isFolded), "thirty folded boxes")
        requireCurrent("folded")
        let box = boxes[17]
        Self.scroll(scroll, to: box.geometry.box.minY - 60)
        func hoverFooter(_ step: String) {
            let footer = result.codeBoxes()[17].geometry.footer!
            let before = result.chromeLayouts
            result.updateHover(at: NSPoint(x: footer.midX, y: footer.midY))
            let layouts = result.chromeLayouts - before
            require(result.hoveredControl == .fold(box.key) && result.hoveredBox == box.key && layouts <= 6,
                    "\(step): the footer far down the text is found near the pointer: \(layouts)")
        }
        hoverFooter("folded")
        let below = boxes[18].geometry.copyHit
        var registered = result.chromeRegistrations
        require(result.perform(.fold(box.key)) && !result.codeBoxes()[17].fold.isFolded, "expand")
        boxes = result.codeBoxes()
        require(boxes[18].geometry.copyHit.minY > below.minY && result.chromeRegistrations == registered + 1,
                "expanding moves the boxes below and their tooltips")
        requireCurrent("expanded")
        hoverFooter("expanded")
        registered = result.chromeRegistrations
        require(result.perform(.fold(box.key)) && result.codeBoxes()[18].geometry.copyHit == below
                && result.chromeRegistrations == registered + 1, "folding again puts them back")
        requireCurrent("folded again")
        apply(scroll, text, display: folds(nil))
        require(result.codeBoxes().allSatisfy { !$0.fold.hasFooter }, "folding off")
        requireCurrent("folding off")
        apply(scroll, text, display: folds(8))
        requireCurrent("eight lines")
    }

    /// A long folded block draws only its shown lines: hidden glyphs, which all sit at the footer's height, are skipped.
    private static func foldedLinesAreNotDrawn() {
        let (scroll, view) = makeScroll(width: 320, height: 300)
        apply(scroll, "앞\n\n```ts\n\(codeLines(400))\n```\n\n뒤", identity: UUID(), display: folds())
        let result = view as! ResultTextView, layout = view.layoutManager as! CodeFoldLayoutManager
        let string = view.string as NSString
        guard let box = result.codeBoxes().first, let hidden = box.fold.hidden else { return require(false, "a folded box") }
        let before = layout.drawnGlyphs
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let drawn = layout.drawnGlyphs - before
        let shown = string.length - hidden.length
        // TextKit may draw a run more than once in a pass; the hidden lines are forty times the shown text.
        require(drawn > 0 && drawn <= 2 * shown && hidden.length > 40 * shown, "only shown glyphs are drawn: \(drawn) of \(string.length)")
        // The footer around the hidden lines is still drawn.
        let footer = box.geometry.footer!
        require(differs(view, in: footer.insetBy(dx: 4, dy: 4), from: NSPoint(x: box.geometry.box.maxX - 6, y: box.geometry.header.maxY + 1.5)),
                "the footer is drawn")
        // Expanded, every line is drawn.
        require(result.perform(.fold(box.key)), "expand")
        let expandedBefore = layout.drawnGlyphs
        let all = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: all)
        require(layout.drawnGlyphs - expandedBefore >= string.length - 2, "an expanded block draws every line")
    }

    /// A footer click restyles its block and the paragraph after it, not the text to its end, and the result is what a full
    /// restyle gives.
    private static func foldToggleRestylesOnlyTheBlock() {
        let id = UUID()
        let text = (1...4).map { n in "문단 \(n)에 `chip`과 [링크](https://example.com/\(n))가 있습니다.\n\n```ts\n\(codeLines(8, from: n * 10))\n```\n\n" }.joined()
            + (1...5).map { "꼬리 문단 \($0)" }.joined(separator: "\n\n")
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, text, identity: id, display: folds())
        let result = view as! ResultTextView, storage = view.textStorage!
        let string = view.string as NSString
        let spy = EditSpy()
        storage.delegate = spy
        defer { storage.delegate = nil }
        let box = result.codeBoxes()[1]
        let end = NSMaxRange(string.paragraphRange(for: NSRange(location: NSMaxRange(box.block.range), length: 0)))
        require(result.perform(.fold(box.key)), "expand the second block")
        require(!spy.ranges.isEmpty && spy.ranges.allSatisfy { $0.location >= box.block.range.location && NSMaxRange($0) <= end },
                "only the block and the paragraph after it are restyled: \(spy.ranges) in \(box.block.range.location)..<\(end)")
        @MainActor func tops(_ view: NSTextView) -> [CGFloat] {
            var tops: [CGFloat] = []
            view.layoutManager!.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: view.layoutManager!.numberOfGlyphs)) { rect, used, _, _, _ in
                tops.append(rect.minY + used.height)
            }
            return tops
        }
        // The same expansion restyled whole: a line spacing change restyles everything and keeps what is expanded.
        let (fresh, freshView) = makeScroll(width: 320, height: 200)
        apply(fresh, text, identity: id, display: folds())
        require(Self.result(of: freshView).perform(.fold(box.key)), "expand the reference")
        apply(fresh, text, identity: id, lineSpacing: 4, display: folds())
        apply(fresh, text, identity: id, display: folds())
        require(!Self.result(of: freshView).codeBoxes()[1].fold.isFolded, "the reference stays expanded")
        require(storage.isEqual(to: freshView.textStorage!), "the attributes are a full restyle's")
        require(tops(view) == tops(freshView) && result.codeBoxes().map(\.geometry) == Self.result(of: freshView).codeBoxes().map(\.geometry)
                && view.frame.height == freshView.frame.height, "the layout is a full restyle's")
        spy.ranges = []
        require(result.perform(.fold(box.key)), "fold it again")
        let (folded, foldedView) = makeScroll(width: 320, height: 200)
        apply(folded, text, identity: UUID(), display: folds())
        require(spy.ranges.allSatisfy { $0.location >= box.block.range.location && NSMaxRange($0) <= end }
                && storage.isEqual(to: foldedView.textStorage!) && tops(view) == tops(foldedView), "folding again is a fresh render")
    }

    /// An expanded block stays expanded when text before it changes under the same identity, and the reader stays in it.
    private static func expansionFollowsEditsBeforeTheBlock() {
        let id = UUID()
        let body = (1...3).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n") + "\n\n```ts\n\(codeLines(20))\n```\n\n"
            + (1...10).map { "뒤 문단 \($0)입니다." }.joined(separator: "\n\n")
        for lead in ["머리말 문단입니다.\n\n", "", "const value0 = 0; 로 시작하는 머리말\n\n"] {
            let (scroll, view) = makeScroll(width: 320, height: 200)
            apply(scroll, "머리말 문단입니다. 앞에 더 있습니다.\n\n" + body, identity: id, display: folds())
            let result = view as! ResultTextView
            require(result.perform(.fold(result.codeBoxes()[0].key)), "expand")
            let layout = view.layoutManager!
            let line15 = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: (view.string as NSString).range(of: "const value15").location),
                                                 effectiveRange: nil)
            Self.scroll(scroll, to: view.textContainerOrigin.y + line15.minY)
            let reading = topLineText(of: scroll)
            require(reading.contains("const value15"), "reading line 15: \(reading)")
            apply(scroll, lead + body, identity: id, display: folds())
            require(result.codeBoxes()[0].fold.expanded && !result.codeBoxes()[0].fold.isFolded && result.expandedBlocks.count == 1,
                    "\"\(lead)\": the block stays expanded")
            require(topLineText(of: scroll) == reading, "\"\(lead)\": the reader stays in the code: \(topLineText(of: scroll))")
            apply(scroll, lead + "앞 문단만 남았습니다.", identity: id, display: folds())
            require(result.expandedBlocks.isEmpty, "\"\(lead)\": a block that is gone is forgotten")
        }
    }

    /// Folding turned on in the same update as a streamed chunk still leaves the block the reader is in expanded.
    private static func foldingTurnedOnWithAChunkKeepsTheReader() {
        let id = UUID()
        var raw = (1...3).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n") + "\n\n```ts\n\(codeLines(40))"
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, raw, identity: id, streaming: true, display: folds(nil))
        let layout = view.layoutManager!
        let line15 = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: (view.string as NSString).range(of: "const value15").location),
                                             effectiveRange: nil)
        Self.scroll(scroll, to: view.textContainerOrigin.y + line15.minY)
        let reading = topLineText(of: scroll)
        raw += "\nconst value41 = 41;"
        apply(scroll, raw, identity: id, streaming: true, display: folds(5))
        let box = (view as! ResultTextView).codeBoxes()[0]
        require(box.fold.expanded && !box.fold.isFolded && topLineText(of: scroll) == reading,
                "the block being read stays expanded: \(topLineText(of: scroll))")
        // Not read, it folds.
        let (other, otherView) = makeScroll(width: 320, height: 200)
        var otherRaw = (1...3).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n") + "\n\n```ts\n\(codeLines(40))"
        apply(other, otherRaw, identity: id, streaming: true, display: folds(nil))
        otherRaw += "\nconst value41 = 41;"
        apply(other, otherRaw, identity: id, streaming: true, display: folds(5))
        require((otherView as! ResultTextView).codeBoxes()[0].fold.isFolded, "a block the reader is not in folds")
    }

    /// Blank lines at the end of a fence do not count toward the limit; they are hidden with the lines before them.
    private static func trailingBlankLinesDoNotFold() {
        let blanks = "1\n2\n3\n4\n5\n \t\n\r\n\n" as NSString
        let plan = CodeFold.plan(block: NSRange(location: 0, length: blanks.length), in: blanks, limit: 5, expanded: false)
        require(plan.lineCount == 8 && plan.contentLineCount == 5 && !plan.hasFooter && !plan.isFolded, "blank lines do not fold: \(plan)")
        let (scroll, view) = makeScroll(width: 320, height: 300)
        apply(scroll, "앞\n\n```ts\n\(codeLines(5))\n\n\n\n```\n\n뒤", identity: UUID(), display: folds())
        let box = (view as! ResultTextView).codeBoxes()[0]
        require(!box.fold.hasFooter && !box.fold.isFolded && box.geometry.footer == nil, "five lines and three blank ones show whole")
        apply(scroll, "앞\n\n```ts\n\(codeLines(6))\n\n\n```\n\n뒤", identity: UUID(), display: folds())
        let string = view.string as NSString
        let folded = (view as! ResultTextView).codeBoxes()[0]
        require(folded.fold.isFolded && folded.fold.hidden?.location == string.range(of: "const value6").location
                && NSMaxRange(folded.fold.hidden!) == NSMaxRange(folded.block.range) && CodeFold.footerLabel(folded.fold, style: .native) == "8줄 모두 보기",
                "six lines fold, and the blank lines after them hide with them")
    }

    /// An edit in the middle of a colored block under the same identity colors the edited line as a fresh render does.
    private static func sameIdentityEditRecolorsTheEditedLine() {
        let id = UUID()
        let text = "앞\n\n```ts\nconst a = 1;\nconst b = 2;\nconst c = 3;\n```\n\n뒤"
        let edited = text.replacingOccurrences(of: "const b", with: "cost b")
        let (scroll, view) = makeScroll(width: 320, height: 300)
        apply(scroll, text, identity: id, display: display(.native))
        apply(scroll, edited, identity: id, display: display(.native))
        let (fresh, freshView) = makeScroll(width: 320, height: 300)
        apply(fresh, edited, identity: UUID(), display: display(.native))
        let cost = (view.string as NSString).range(of: "cost b")
        require(view.textStorage!.attribute(.foregroundColor, at: cost.location, effectiveRange: nil) as? NSColor == ResultStyle.native.code.color.nsColor
                && view.textStorage!.isEqual(to: freshView.textStorage!), "the edited line is colored again")
    }

    // MARK: - Folding and syntax colors

    private static func folds(_ limit: Int? = 5, style: ResultStyle = .native, colors: Bool = true) -> ResultDisplaySettings {
        var settings = display(style)
        settings.foldsLongCode = limit != nil
        if let limit { settings.foldLineCount = limit }
        settings.colorsSyntax = colors
        return settings
    }

    private static func codeLines(_ count: Int, from first: Int = 1) -> String {
        (first..<(first + count)).map { "const value\($0) = \($0);" }.joined(separator: "\n")
    }

    /// What ⌘C, drag and Services write for the selection, written to a private pasteboard. `copy(_:)` itself would write a
    /// plain selection to the general pasteboard.
    private static func writeSelection(of view: NSTextView, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        _ = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)
    }

    /// Swaps in a private pasteboard for the copy controls.
    private static func withPasteboard(_ body: @MainActor (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previous = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.copyPasteboard = previous
            pasteboard.releaseGlobally()
        }
        body(pasteboard)
    }

    /// The fold rule: lines after the limit are hidden with their breaks to the block's end, and line 5's break stays. The box
    /// is the header, five lines and the footer; the text after it starts where it would after any box; nothing is lost.
    private static func foldSpike() {
        let wrapped = "const hidden = '" + String(repeating: "아주 긴 줄 ", count: 40) + "';"
        let cases: [(name: String, text: String)] = [
            ("middle", "앞 문단\n\n```ts\n\(codeLines(8))\n```\n\n뒤 문단"),
            ("trailing", "앞 문단\n\n```ts\n\(codeLines(8))\n```"),
            ("empty last line", "앞 문단\n\n```ts\n\(codeLines(7))\n\n```\n\n뒤 문단"),
            ("CRLF", "앞 문단\r\n\r\n```ts\r\n" + codeLines(8).replacingOccurrences(of: "\n", with: "\r\n") + "\r\n```\r\n\r\n뒤 문단"),
            ("wrapped hidden line", "앞 문단\n\n```ts\n\(codeLines(6))\n\(wrapped)\n\(codeLines(1, from: 8))\n```\n\n뒤 문단")
        ]
        let style = ResultStyle.native
        let lineHeight = NSLayoutManager().defaultLineHeight(for: style.code.font.nsFont)
        withPasteboard { pasteboard in
            for (name, text) in cases {
                let (scroll, view) = makeScroll(width: 320, height: 60)
                apply(scroll, text, identity: UUID(), display: folds())
                let result = view as! ResultTextView, layout = view.layoutManager!, storage = view.textStorage!
                let string = view.string as NSString
                guard let box = result.codeBoxes().first, let hidden = box.fold.hidden else { return require(false, "\(name): a folded box") }
                require(box.fold.lineCount == 8 && box.fold.hiddenLineCount == 3, "\(name): eight lines show five")
                require(hidden.location == string.range(of: "const value6").location && NSMaxRange(hidden) == NSMaxRange(box.block.range)
                        && string.character(at: hidden.location - 1) == 0x0A, "\(name): lines 6 to 8 and their breaks, to the block's end")
                var folded = NSRange()
                require(storage.attribute(.deepKCodeFolded, at: hidden.location, longestEffectiveRange: &folded,
                                          in: NSRange(location: 0, length: string.length)) != nil && folded == hidden
                        && storage.attribute(.deepKCodeFolded, at: hidden.location - 1, effectiveRange: nil) == nil,
                        "\(name): exactly the hidden lines are folded; line 5's break is not")
                let glyphs = layout.glyphRange(forCharacterRange: hidden, actualCharacterRange: nil)
                require((glyphs.location..<NSMaxRange(glyphs)).allSatisfy { glyph in
                    let character = string.character(at: layout.characterIndexForGlyph(at: glyph))
                    return character == 0x0A || character == 0x0D || layout.notShownAttribute(forGlyphAt: glyph)
                }, "\(name): hidden glyphs are not shown")
                var heights: [CGFloat] = []
                layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in heights.append(rect.height + used.height) }
                let spacer = storage.attribute(.deepKFoldSpacer, at: NSMaxRange(hidden) - 1, effectiveRange: nil) as? CGFloat
                require(heights.count == 3 && heights.dropLast().allSatisfy { $0 == 0 } && heights.last == spacer,
                        "\(name): hidden lines take no height, a wrapped one neither, and the last takes the spacer: \(heights)")

                // 1. The header, five lines and the footer.
                let geometry = box.geometry
                let firstUsed = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: box.block.range.location), effectiveRange: nil)
                require(abs(geometry.box.minY + style.topPortion - (view.textContainerOrigin.y + firstUsed.minY)) < 0.01
                        && abs(geometry.box.height - (style.topPortion + 4 * style.code.lineHeight + lineHeight + style.bottomPortion(footer: true))) < 0.01,
                        "\(name): the box is the header, five lines and the footer: \(geometry.box.height)")
                require(geometry.footer?.maxY == geometry.box.maxY, "\(name): the footer ends the box")
                // 2. What follows starts where it would after any box.
                if NSMaxRange(box.block.range) < string.length {
                    let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: string.range(of: "뒤 문단").location), effectiveRange: nil)
                    require(abs(view.textContainerOrigin.y + after.minY - (geometry.box.maxY + style.box.margin + ResultStyle.blankLineGap)) < 0.01,
                            "\(name): the next paragraph follows the footer")
                } else {
                    require(abs(view.frame.height - (geometry.box.maxY + style.box.margin)) < 0.5,
                            "\(name): a trailing folded box keeps its margin and nothing more: \(view.frame.height) \(geometry.box.maxY)")
                }
                // 3. Points over the footer find a glyph and the footer's control.
                let footer = geometry.footer!
                for point in [NSPoint(x: footer.midX, y: footer.midY), NSPoint(x: footer.minX + 1, y: footer.maxY - 1)] {
                    _ = layout.glyphIndex(for: NSPoint(x: point.x - view.textContainerOrigin.x, y: point.y - view.textContainerOrigin.y),
                                          in: view.textContainer!)
                    require(result.chromeControl(at: point) == .fold(box.key), "\(name): the footer is a control")
                }
                // 4. Everything selected copies the hidden lines.
                view.setSelectedRange(NSRange(location: 0, length: string.length))
                writeSelection(of: view, to: pasteboard)
                let copied = pasteboard.string(forType: .string) ?? ""
                require(copied.contains("const value6 = 6;") && (name != "wrapped hidden line" || copied.contains("아주 긴 줄")),
                        "\(name): ⌘C copies the hidden lines")
                view.setSelectedRange(NSRange(location: 0, length: 0))
                // 5. Expanded, the lines sit where they do without folding, and the box only adds the footer.
                let (plain, plainView) = makeScroll(width: 320, height: 60)
                apply(plain, text, identity: UUID(), display: folds(nil))
                require(result.perform(.fold(box.key)), "\(name): the footer expands the block")
                let expanded = result.codeBoxes()[0]
                @MainActor func tops(_ view: NSTextView) -> [CGFloat] {
                    let layout = view.layoutManager!
                    var tops: [CGFloat] = []
                    layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(forCharacterRange: box.block.range, actualCharacterRange: nil)) { rect, _, _, _, _ in
                        tops.append(rect.minY)
                    }
                    return tops
                }
                let plainBox = (plainView as! ResultTextView).codeBoxes()[0].geometry.box
                require(!expanded.fold.isFolded && expanded.fold.hasFooter && tops(view) == tops(plainView)
                        && abs(expanded.geometry.box.height - plainBox.height - (style.bottomPortion(footer: true) - style.bottomPortion)) < 0.01,
                        "\(name): expanded lines are laid out as unfolded ones, above the footer")
                if NSMaxRange(box.block.range) < string.length {
                    let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: string.range(of: "뒤 문단").location), effectiveRange: nil)
                    require(abs(view.textContainerOrigin.y + after.minY - (expanded.geometry.box.maxY + style.box.margin + ResultStyle.blankLineGap)) < 0.01,
                            "\(name): expanded, the next paragraph follows the 접기 footer")
                } else {
                    require(abs(view.frame.height - (expanded.geometry.box.maxY + style.box.margin)) < 0.5,
                            "\(name): a trailing expanded box keeps its footer and margin: \(view.frame.height) \(expanded.geometry.box.maxY)")
                }
                require(storage.attribute(.deepKCodeFolded, at: hidden.location, effectiveRange: nil) == nil
                        && (glyphs.location..<NSMaxRange(glyphs)).allSatisfy { !layout.notShownAttribute(forGlyphAt: $0)
                            || [0x0A, 0x0D].contains(string.character(at: layout.characterIndexForGlyph(at: $0))) },
                        "\(name): expanded glyphs are shown again")
            }
        }
    }

    /// A 7-line block folds to 5 under its footer in both styles; the footer toggles it and keeps the reader in place, and
    /// every copy still has all seven lines.
    private static func folding() {
        let code = codeLines(7)
        let text = (1...8).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n") + "\n\n```ts\n\(code)\n```\n\n"
            + (1...12).map { "뒤 문단 \($0)입니다." }.joined(separator: "\n\n")
        withPasteboard { pasteboard in
            for style in [ResultStyle.native, .github] {
                let (scroll, view) = makeScroll(width: 320, height: 200)
                apply(scroll, text, identity: UUID(), display: folds(style: style))
                let result = view as! ResultTextView
                let string = view.string as NSString
                var box = result.codeBoxes()[0]
                require(box.fold.isFolded && CodeFold.footerLabel(box.fold, style: style) == (style == .native ? "7줄 모두 보기" : "2줄 더 보기"),
                        "\(style.name): the footer's words")
                let footer = box.geometry.footer!
                require(differs(view, in: footer.insetBy(dx: 4, dy: 4), from: NSPoint(x: box.geometry.box.maxX - 6, y: box.geometry.header.maxY + 1.5)),
                        "\(style.name): the footer is drawn")
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 200),
                                      styleMask: [.borderless], backing: .buffered, defer: true)
                window.contentView = scroll
                defer { window.contentView = nil }
                let center = NSPoint(x: footer.midX, y: footer.midY)
                Self.scroll(scroll, to: max(0, footer.midY - 100))
                let press = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(center, to: nil), modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                require(result.chromeControl(at: center) == .fold(box.key) && view.acceptsFirstMouse(for: press),
                        "\(style.name): the footer is a control and takes the first click")
                require(view.accessibilityCustomActions()?.map(\.name) == ["TypeScript 코드 복사", "TypeScript 코드 7줄 모두 보기"],
                        "\(style.name): VoiceOver can expand: \(view.accessibilityCustomActions()?.map(\.name) ?? [])")
                require(view.accessibilityValue()?.contains("const value7 = 7;") == true, "\(style.name): VoiceOver reads every line")
                // The actions run: one expands, and the block's next action folds it again.
                let expand = view.accessibilityCustomActions()?.first { $0.name == "TypeScript 코드 7줄 모두 보기" }
                require(expand?.handler?() == true && result.expandedBlocks.contains(box.key) && !result.codeBoxes()[0].fold.isFolded,
                        "\(style.name): VoiceOver's action expands the block")
                let fold = view.accessibilityCustomActions()?.first { $0.name == "TypeScript 코드 접기" }
                require(fold?.handler?() == true && !result.expandedBlocks.contains(box.key) && result.codeBoxes()[0].fold.isFolded,
                        "\(style.name): VoiceOver's action folds it again")

                // Shorter than unfolded by two lines, less the footer.
                let (plain, plainView) = makeScroll(width: 320, height: 200)
                apply(plain, text, identity: UUID(), display: folds(nil, style: style))
                let plainBox = (plainView as! ResultTextView).codeBoxes()[0]
                require(!plainBox.fold.hasFooter && abs(plainBox.geometry.box.height - box.geometry.box.height
                    - (2 * style.code.lineHeight + style.bottomPortion - style.bottomPortion(footer: true))) < 0.01,
                        "\(style.name): the folded box is two lines shorter, with a footer")

                // Copies hold every line: ⌘C of everything, of the shown lines into the hidden ones, the block's copy control,
                // and what the store copies and inserts, which never read the view.
                view.setSelectedRange(NSRange(location: 0, length: string.length))
                writeSelection(of: view, to: pasteboard)
                require(pasteboard.string(forType: .string)?.contains("const value7 = 7;") == true, "\(style.name): ⌘C of everything")
                let shownAndHidden = NSRange(location: string.range(of: "const value4").location,
                                             length: NSMaxRange(string.range(of: "const value7 = 7;")) - string.range(of: "const value4").location)
                view.setSelectedRange(shownAndHidden)
                writeSelection(of: view, to: pasteboard)
                require(pasteboard.string(forType: .string) == string.substring(with: shownAndHidden), "\(style.name): ⌘C into the hidden lines")
                view.setSelectedRange(NSRange(location: 0, length: 0))
                require(result.perform(.copy(box.key)) && pasteboard.string(forType: .string) == code, "\(style.name): the block's copy control")
                require(TranslationMarkup.insertionText(result: text, source: "plain").contains("const value7 = 7;")
                        && ResultClipboard.write(markdown: text, plain: TranslationMarkup(text).plainText(in: NSRange(location: 0, length: string.length), fences: .none),
                                                 format: .rich, to: pasteboard)
                        && pasteboard.string(forType: .string)?.contains("const value7 = 7;") == true, "\(style.name): the store's copy and insertion")

                // Expanding keeps the header where it is on screen; it then reads "접기".
                Self.scroll(scroll, to: box.geometry.box.minY - 30)
                require(result.perform(.fold(box.key)), "\(style.name): expand")
                box = result.codeBoxes()[0]
                require(abs(box.geometry.box.minY - scroll.documentVisibleRect.minY - 30) < 0.5, "\(style.name): the header holds on expand")
                require(!box.fold.isFolded && box.fold.hasFooter && CodeFold.footerLabel(box.fold, style: style) == "접기"
                        && result.expandedBlocks.contains(box.key), "\(style.name): an expanded block offers 접기")
                require(view.accessibilityCustomActions()?.map(\.name).last == "TypeScript 코드 접기", "\(style.name): VoiceOver can fold")
                // Folding from below the header keeps the footer under the pointer instead.
                Self.scroll(scroll, to: box.geometry.footer!.minY - 120)
                require(box.geometry.box.minY < scroll.documentVisibleRect.minY, "\(style.name): the header is above the screen")
                require(result.perform(.fold(box.key)), "\(style.name): fold")
                box = result.codeBoxes()[0]
                require(box.fold.isFolded && abs(box.geometry.footer!.minY - scroll.documentVisibleRect.minY - 120) < 0.5,
                        "\(style.name): the footer holds on fold, so the reader is never left in empty space")
                require(view.string == string as String, "\(style.name): folding never changes the text")

                // The settings restyle in place: off, a higher limit, a lower one.
                settle()
                apply(scroll, text, identity: identity(of: scroll), display: folds(nil, style: style))
                require(!result.codeBoxes()[0].fold.hasFooter && view.textStorage!.attribute(.deepKCodeFolded, at: string.range(of: "const value7").location,
                                                                                               effectiveRange: nil) == nil, "\(style.name): folding off")
                settle()
                apply(scroll, text, identity: identity(of: scroll), display: folds(8, style: style))
                require(!result.codeBoxes()[0].fold.hasFooter, "\(style.name): seven lines fit a limit of eight")
                settle()
                apply(scroll, text, identity: identity(of: scroll), display: folds(3, style: style))
                require(result.codeBoxes()[0].fold.hiddenLineCount == 4, "\(style.name): a limit of three hides four lines")
                settle()
            }
        }
        // A folded block at the start of the text keeps the band above it.
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, "```ts\n\(codeLines(7))\n```\n\n뒤", identity: UUID())
        let box = (view as! ResultTextView).codeBoxes()[0]
        require(box.fold.isFolded && view.textContainerOrigin.y >= ResultStyle.native.topPortion && abs(box.geometry.box.minY) < 0.5,
                "a leading folded box keeps its band")
    }

    private static func identity(of scroll: ResultScrollView) -> UUID { scroll.applied!.identity }

    private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    /// A setting that would fold away what the reader is looking at, the selection or the top line, leaves that block
    /// expanded. Lines already folded away do not expand a block when another setting changes.
    private static func foldingKeepsWhatTheReaderSees() {
        let text = (1...10).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n") + "\n\n```ts\n\(codeLines(10))\n```\n\n"
            + (1...10).map { "뒤 문단 \($0)입니다." }.joined(separator: "\n\n")
        // The selection.
        let (scroll, view) = makeScroll(width: 320, height: 200)
        apply(scroll, text, display: folds(nil))
        let line7 = (view.string as NSString).range(of: "const value7 = 7;")
        view.setSelectedRange(line7)
        apply(scroll, text, display: folds(5))
        let result = view as! ResultTextView
        require(result.codeBoxes()[0].fold.expanded && !result.codeBoxes()[0].fold.isFolded && view.selectedRange() == line7,
                "turning folding on keeps a selected hidden line in view")
        // The top line, when the limit is lowered.
        let (top, topView) = makeScroll(width: 320, height: 200)
        apply(top, text, display: folds(15))
        let layout = topView.layoutManager!
        let line8 = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: (topView.string as NSString).range(of: "const value8").location),
                                            effectiveRange: nil)
        Self.scroll(top, to: topView.textContainerOrigin.y + line8.minY)
        let reading = topLineText(of: top)
        apply(top, text, display: folds(5))
        let topResult = topView as! ResultTextView
        require(topResult.codeBoxes()[0].fold.expanded && topLineText(of: top) == reading, "lowering the limit keeps the top line: \(topLineText(of: top))")
        // A selection elsewhere lets the block fold.
        let (other, otherView) = makeScroll(width: 320, height: 200)
        apply(other, text, display: folds(nil))
        otherView.setSelectedRange(NSRange(location: 0, length: 4))
        apply(other, text, display: folds(5))
        require((otherView as! ResultTextView).codeBoxes()[0].fold.isFolded, "a selection outside the block lets it fold")
        // Everything selected while folded: another setting changes nothing it newly hides.
        otherView.setSelectedRange(NSRange(location: 0, length: (otherView.string as NSString).length))
        settle()
        apply(other, text, display: folds(5, style: .github))
        require((otherView as! ResultTextView).codeBoxes()[0].fold.isFolded, "lines already folded away do not expand the block")
        settle()
        apply(other, text, display: folds(8, style: .github))
        require((otherView as! ResultTextView).codeBoxes()[0].fold.isFolded, "a higher limit shows more and hides nothing new")
        // A new identity forgets what was expanded.
        apply(scroll, text, identity: UUID(), display: folds(5))
        require(result.expandedBlocks.isEmpty && result.codeBoxes()[0].fold.isFolded, "a new identity folds again")
    }

    /// A streamed block is colored and folds as it grows: the text only appends, the reader stays, each chunk restyles and
    /// rescans only the block's last lines, and the box grows by the footer once instead of a line per chunk.
    private static func foldingAndHighlightWhileStreaming() {
        let (scroll, view) = makeScroll()
        let result = view as! ResultTextView
        let spy = EditSpy()
        view.textStorage!.delegate = spy
        defer { view.textStorage!.delegate = nil }
        var raw = (1...20).map { "번역 문단 \($0): 선택 범위를 유지합니다." }.joined(separator: "\n\n")
        apply(scroll, raw, streaming: true)
        let selection = NSRange(location: 8, length: 30)
        view.setSelectedRange(selection)
        Self.scroll(scroll, to: 120)
        let origin = scroll.contentView.bounds.origin
        var previous = view.string
        let palette = ResultStyle.native.syntax!
        func color(of word: String) -> NSColor? {
            let string = view.string as NSString
            let range = string.range(of: word, options: .backwards)
            return range.location == NSNotFound ? nil : view.textStorage!.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        }
        var foldedHeight: CGFloat?
        let chunks = ["\n\n```ts\n// 시작", "\nimport { getModel } from 'ai';", "\nconst claude = getMod", "el('anthropic');",
                      "\nconst a = 1;", "\nconst b = 2;", "\nconst c = 3;", "\nconst d = 4;", "\nconst e = 5;\n", "```\n\n끝"]
        for chunk in chunks {
            let text = view.string as NSString
            // The renderer restyles from the line before the old last one; the highlighter rescans from the edit's line.
            let lastLine = text.paragraphRange(for: NSRange(location: max(0, text.length - 1), length: 0)).location
            let restyledFrom = text.paragraphRange(for: NSRange(location: max(0, lastLine - 1), length: 0)).location
            let scanned = result.highlightLinesScanned
            spy.ranges = []
            raw += chunk
            apply(scroll, raw, streaming: true)
            require(view.string.utf16.starts(with: previous.utf16) && !view.string.contains("`"), "the stream only appends: \(chunk)")
            require(view.selectedRange() == selection && abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "the reader stays: \(chunk)")
            require((spy.ranges.map(\.location).min() ?? .max) >= restyledFrom, "only the end of the text is restyled: \(chunk)")
            require(result.highlightLinesScanned - scanned <= 2, "at most two lines are rescanned: \(chunk) \(result.highlightLinesScanned - scanned)")
            if let box = result.codeBoxes().first {
                require(box.fold.isFolded == (box.fold.lineCount > 5) && box.fold.hasFooter == box.fold.isFolded,
                        "the block folds once it has a sixth line: \(chunk)")
                if box.fold.isFolded {
                    if let foldedHeight {
                        require(abs(box.geometry.box.height - foldedHeight) < 0.01, "a folded box no longer grows: \(chunk)")
                    }
                    foldedHeight = box.geometry.box.height
                }
            }
            if chunk == "\nconst claude = getMod" {
                require(color(of: "getMod") == ResultStyle.native.code.color.nsColor, "an unfinished name is plain")
            }
            previous = view.string
        }
        require(color(of: "getModel(") == palette.function.nsColor, "the name is a function once its parenthesis arrives")
        require(color(of: "import") == palette.keyword.nsColor && color(of: "'ai'") == palette.string.nsColor
                && color(of: "// 시작") == palette.comment.nsColor, "completed lines keep their colors")
        require(foldedHeight != nil && result.codeBoxes().first.map(result.headerLabel(of:)) == "TypeScript · 8줄",
                "the header counts every line while folded")
        apply(scroll, raw)
        require(view.string == previous && result.codeBoxes()[0].fold.isFolded, "the completed block stays folded")
    }

    /// Token colors come from the style's palette; 문법 색 off, a style without a palette and superseded text keep one color.
    private static func tokenColors() {
        let text = "앞\n\n```ts\n// 주석\nconst a = 'x';\n```\n\n뒤"
        func color(_ view: NSTextView, _ word: String) -> NSColor? {
            view.textStorage!.attribute(.foregroundColor, at: (view.string as NSString).range(of: word).location, effectiveRange: nil) as? NSColor
        }
        for style in [ResultStyle.native, .github, .darkFixture] {
            let palette = style.syntax!
            let (scroll, view) = makeScroll(width: 320, height: 300)
            apply(scroll, text, display: display(style))
            require(color(view, "const") == palette.keyword.nsColor && color(view, "'x'") == palette.string.nsColor
                    && color(view, "// 주석") == palette.comment.nsColor && color(view, "a =") == style.code.color.nsColor,
                    "\(style.name): keyword, string, comment and plain code")
            let comment = view.textStorage!.attribute(.font, at: (view.string as NSString).range(of: "// 주석").location, effectiveRange: nil) as! NSFont
            let plain = view.textStorage!.attribute(.font, at: (view.string as NSString).range(of: "const").location, effectiveRange: nil) as! NSFont
            require(comment.fontDescriptor.symbolicTraits.contains(.italic) == palette.commentItalic && comment.isFixedPitch
                    && comment.pointSize == plain.pointSize && abs(comment.maximumAdvancement.width - plain.maximumAdvancement.width) < 0.01,
                    "\(style.name): an italic comment keeps the code's advance")

            let (off, offView) = makeScroll(width: 320, height: 300)
            apply(off, text, display: folds(style: style, colors: false))
            let code = (offView.string as NSString).range(of: "// 주석\nconst a = 'x';")
            var uniform = true
            offView.textStorage!.enumerateAttribute(.foregroundColor, in: code) { value, _, _ in
                if value as? NSColor != style.code.color.nsColor { uniform = false }
            }
            require(uniform, "\(style.name): 문법 색 off keeps one color")

            let (stale, staleView) = makeScroll(width: 320, height: 300)
            apply(stale, text, stale: true, display: display(style))
            require(color(staleView, "const") == .secondaryLabelColor && color(staleView, "'x'") == .secondaryLabelColor,
                    "\(style.name): superseded code is dimmed, not colored")
        }
        let (rail, railView) = makeScroll(width: 320, height: 300)
        apply(rail, text, display: display(.railFixture))
        require(color(railView, "const") == ResultStyle.railFixture.code.color.nsColor, "a style without a palette keeps one color")
        let (untagged, untaggedView) = makeScroll(width: 320, height: 300)
        apply(untagged, "앞\n\n```\nconst a = 'x';\n```", display: display(.native))
        require(color(untaggedView, "const") == ResultStyle.native.code.color.nsColor, "a block without a tag keeps one color")

        // Native fades a folded block's last shown line; GitHub does not.
        let long = "앞\n\n```ts\n\(codeLines(7))\n```\n\n뒤"
        for style in [ResultStyle.native, .github] {
            let (scroll, view) = makeScroll(width: 320, height: 300)
            apply(scroll, long, display: display(style))
            let fifth = (view.string as NSString).range(of: "const value5")
            let keyword = view.textStorage!.attribute(.foregroundColor, at: fifth.location, effectiveRange: nil) as? NSColor
            let plain = view.textStorage!.attribute(.foregroundColor, at: fifth.location + 6, effectiveRange: nil) as? NSColor
            let fourth = view.textStorage!.attribute(.foregroundColor, at: (view.string as NSString).range(of: "const value4").location, effectiveRange: nil) as? NSColor
            if let fade = style.fold.fade {
                require(keyword == style.syntax!.keyword.faded(fade).nsColor && plain == style.code.color.faded(fade).nsColor
                        && fourth == style.syntax!.keyword.nsColor, "\(style.name): the last shown line fades")
            } else {
                require(keyword == style.syntax!.keyword.nsColor && plain == style.code.color.nsColor, "\(style.name): no fade")
            }
            require(result(of: view).perform(.fold(result(of: view).codeBoxes()[0].key))
                    && view.textStorage!.attribute(.foregroundColor, at: fifth.location, effectiveRange: nil) as? NSColor == style.syntax!.keyword.nsColor,
                    "\(style.name): an expanded block does not fade")
            // Superseded text fades its own dimmed color.
            let (stale, staleView) = makeScroll(width: 320, height: 300)
            apply(stale, long, stale: true, display: display(style))
            let staleFifth = staleView.textStorage!.attribute(.foregroundColor, at: fifth.location, effectiveRange: nil) as? NSColor
            let staleFourth = staleView.textStorage!.attribute(.foregroundColor, at: (staleView.string as NSString).range(of: "const value4").location,
                                                                effectiveRange: nil) as? NSColor
            require(result(of: staleView).codeBoxes()[0].fold.isFolded && staleFourth == .secondaryLabelColor
                    && staleFifth == style.fold.fade.map { NSColor.secondaryLabelColor.withAlphaComponent($0) } ?? .secondaryLabelColor,
                    "\(style.name): a superseded folded block fades its last shown line from the dimmed color")
        }
    }

    private static func result(of view: NSTextView) -> ResultTextView { view as! ResultTextView }

    /// Whether a pixel shows `color`, both composited over the window background so translucent fills compare as seen.
    private static func shows(_ view: NSView, _ color: StyleColor?, at point: NSPoint, dark: Bool) -> Bool {
        guard let color else { return sRGBPixel(view, at: point)?.alphaComponent == 0 }
        return shows(view, [color], at: point, dark: dark)
    }

    /// Whether a pixel shows these colors painted bottom first, both composited over the window background the system
    /// resolves for the appearance. The top layer must stand out, so a pixel nothing was drawn on never passes.
    private static func shows(_ view: NSView, _ layers: [StyleColor?], at point: NSPoint, dark: Bool) -> Bool {
        guard standsOut(layers, dark: dark), let pixel = sRGBPixel(view, at: point) else { return false }
        let seen = zip([pixel.redComponent, pixel.greenComponent, pixel.blueComponent], windowBackground(dark: dark))
            .map { $0 * pixel.alphaComponent + $1 * (1 - pixel.alphaComponent) }
        return matches(seen, painted(layers.compactMap { $0?.variant(dark: dark) }, dark: dark))
    }

    /// Whether the top layer changes what the window shows under it.
    private static func standsOut(_ layers: [StyleColor?], dark: Bool) -> Bool {
        let variants = layers.compactMap { $0?.variant(dark: dark) }
        return !variants.isEmpty && !matches(painted(variants, dark: dark), painted(variants.dropLast(), dark: dark))
    }

    private static func painted(_ layers: some Sequence<StyleColor.Variant>, dark: Bool) -> [CGFloat] {
        layers.reduce(windowBackground(dark: dark)) { under, layer in
            zip([layer.red, layer.green, layer.blue], under).map { top, under in top * layer.alpha + under * (1 - layer.alpha) }
        }
    }

    private static func matches(_ a: [CGFloat], _ b: [CGFloat]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.02 } }

    private static func windowBackground(dark: Bool) -> [CGFloat] {
        var color = NSColor.white
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
        }
        return [color.redComponent, color.greenComponent, color.blueComponent]
    }

    /// Whether any pixel in `rect` differs from the one at `reference`.
    private static func differs(_ view: NSView, in rect: NSRect, from reference: NSPoint) -> Bool {
        guard let base = sRGBPixel(view, at: reference) else { return false }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        for x in stride(from: rect.minX, to: rect.maxX, by: 0.5) {
            for y in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
                guard let color = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { continue }
                let channels = [(color.redComponent, base.redComponent), (color.greenComponent, base.greenComponent),
                                (color.blueComponent, base.blueComponent), (color.alphaComponent, base.alphaComponent)]
                if channels.contains(where: { abs($0.0 - $0.1) > 0.1 }) { return true }
            }
        }
        return false
    }

    private static func sRGBPixel(_ view: NSView, at point: NSPoint) -> NSColor? {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
    }

    private final class EditSpy: NSObject, NSTextStorageDelegate {
        var ranges: [NSRange] = []
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            ranges.append(editedRange)
        }
    }

    private static func minBrightness(_ view: NSView, in rect: NSRect) -> CGFloat {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return stride(from: rect.minX, to: rect.maxX, by: 1).flatMap { x in
            stride(from: rect.minY, to: rect.maxY, by: 1).map { y in
                guard let color = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB) else { return 1 }
                return 1 - color.alphaComponent * (1 - color.brightnessComponent)
            }
        }.min() ?? 1
    }

    private static func pixelAlpha(_ view: NSView, at point: NSPoint) -> CGFloat {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        return rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))?.alphaComponent ?? 0
    }

    private static let identity = UUID()
    private static let first = (1...35).map { "번역 문단 \($0): 읽고 있던 내용과 선택 범위를 유지합니다." }.joined(separator: "\n\n")

    private static func makeScroll() -> (ResultScrollView, NSTextView) {
        let scroll = TranslationResultTextView.makeScrollView() as! ResultScrollView
        scroll.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        scroll.layoutSubtreeIfNeeded()
        return (scroll, scroll.documentView as! NSTextView)
    }

    private static func apply(_ scroll: NSScrollView, _ text: String, identity: UUID = identity, tailStart: Int? = nil,
                              streaming: Bool = false, stale: Bool = false, lineSpacing: CGFloat = 3, inline: InlineOptions = .init(),
                              sourceFences: TranslationMarkup.FenceStyle = .none, breaks: [Int] = [], display: ResultDisplaySettings = .standard) {
        TranslationResultTextView.update(scroll, content: TranslationResultContent(
            identity: identity, text: text, tailStart: tailStart, isStreaming: streaming, isStale: stale, inline: inline,
            sourceFences: sourceFences, unitBreaks: breaks
        ), lineSpacing: lineSpacing, display: display)
    }

    private static func scroll(_ scroll: NSScrollView, to y: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private static func readingPositionIsNeverMovedByUpdates() {
        let (scroll, view) = makeScroll()
        apply(scroll, first)
        require(view.string == first && view.frame.height > scroll.contentSize.height, "long output must scroll")
        require(scroll.contentView.bounds.origin.y == 0, "initial result starts at top")

        let selection = NSRange(location: 8, length: 40)
        view.setSelectedRange(selection)
        Self.scroll(scroll, to: 150)
        let origin = scroll.contentView.bounds.origin
        let second = first + "\n\n새 번역 문단입니다."
        apply(scroll, second)
        require(view.string == second && view.selectedRange() == selection, "append must preserve selected characters")
        require(abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "append must preserve reading position")

        var streamed = second
        let viewport = scroll.frame
        for chunk in [" 한", " 글자씩", " 나타나는", " 스트리밍", " 결과입니다."] {
            streamed += chunk
            apply(scroll, streamed, streaming: true)
            require(view.selectedRange() == selection, "token-sized appends preserve selection")
            require(abs(scroll.contentView.bounds.origin.y - origin.y) < 1, "token-sized appends preserve scroll")
            require(scroll.frame == viewport, "stream does not resize the viewport")
        }

        // A selection may span old and new paragraphs on the same native surface.
        let crossParagraph = NSRange(location: first.utf16.count - 5, length: 10)
        view.setSelectedRange(crossParagraph)
        apply(scroll, streamed, lineSpacing: 6)
        require(view.selectedRange() == crossParagraph, "layout/style update preserves cross-paragraph selection")

        // A reader at the bottom is not dragged along by new text.
        Self.scroll(scroll, to: view.frame.height - scroll.contentView.bounds.height)
        let bottom = scroll.contentView.bounds.origin.y
        let flashes = scroll.flashCount
        apply(scroll, streamed + "\n\n" + String(repeating: "새 내용이 추가됩니다.\n", count: 10), lineSpacing: 6)
        require(abs(scroll.contentView.bounds.origin.y - bottom) < 1, "reader at the bottom stays where they were")
        require(scroll.documentVisibleRect.maxY < view.bounds.maxY - 5, "appended text extends the scroll range below")
        require(scroll.flashCount == flashes + 1, "growth past the viewport flashes the scrollers")
        apply(scroll, streamed + "\n\n" + String(repeating: "새 내용이 추가됩니다.\n", count: 10), lineSpacing: 6)
        require(scroll.flashCount == flashes + 1, "reapplying the same content is a no-op")
    }

    private static func shortResultDoesNotFollowAppendedText() {
        let (scroll, view) = makeScroll()
        let short = "짧은 번역."
        apply(scroll, short)
        var text = short + "\n\n"
        for index in 1...5 {
            text += String(repeating: "추가 번역 \(index)이 들어옵니다. ", count: 6)
            apply(scroll, text, tailStart: short.utf16.count, streaming: true)
            require(scroll.contentView.bounds.origin.y == 0, "a fully visible result stays in place while text is appended")
        }
        require(view.frame.height > scroll.contentView.bounds.height, "the appended text overflowed the viewport")
    }

    private static func completionDifferencesEditOnlyTheTail() {
        let (scroll, view) = makeScroll()
        let head = first
        apply(scroll, head + "\n\n둘째 문단.\n", tailStart: head.utf16.count, streaming: true)
        Self.scroll(scroll, to: 40)
        let selection = NSRange(location: 3, length: 12)
        view.setSelectedRange(selection)
        apply(scroll, head + "\n\n둘째 문단.", tailStart: head.utf16.count)
        require(view.string == head + "\n\n둘째 문단." && view.selectedRange() == selection, "trimmed completion keeps selection")
        require(abs(scroll.contentView.bounds.origin.y - 40) < 1, "trimmed completion keeps the reading position")

        apply(scroll, head + "\n\n완전히 다른 재시도 결과.", tailStart: head.utf16.count)
        require(view.string.hasSuffix("완전히 다른 재시도 결과.") && view.selectedRange() == selection, "a retried tail edits only the tail")
        require(abs(scroll.contentView.bounds.origin.y - 40) < 1, "a retried tail keeps the reading position")
    }

    private static func removedTextKeepsTheReader() {
        let (scroll, view) = makeScroll()
        let draft = first + "\n\n" + String(repeating: "곧 사라질 초안입니다. ", count: 40)
        apply(scroll, draft, tailStart: first.utf16.count, streaming: true)
        let bottom = view.frame.height - scroll.contentView.bounds.height
        Self.scroll(scroll, to: bottom)
        apply(scroll, first)
        require(abs(scroll.contentView.bounds.origin.y - bottom) < 1, "a removed draft does not pull the reader up")

        let (shifted, shiftedView) = makeScroll()
        let leading = (1...10).map { "앞 문단 \($0)입니다." }.joined(separator: "\n\n")
        apply(shifted, leading + "\n\n" + first)
        Self.scroll(shifted, to: 800)
        let topCharacter = topCharacter(of: shifted)
        require(topCharacter > leading.utf16.count, "the reader is past the leading text")
        shiftedView.setSelectedRange(NSRange(location: leading.utf16.count + 20, length: 5))
        apply(shifted, first)
        require(abs(Self.topCharacter(of: shifted) - (topCharacter - leading.utf16.count - 2)) <= 40,
                "removing leading text keeps the same line at the top")
        require(shiftedView.selectedRange() == NSRange(location: 18, length: 5), "selection moves with its characters")
    }

    private static func identityControlsResets() {
        let (scroll, view) = makeScroll()
        apply(scroll, first)
        Self.scroll(scroll, to: 120)
        apply(scroll, first, identity: UUID())
        require(abs(scroll.contentView.bounds.origin.y - 120) < 1, "a new identity with the same text keeps the position")
        view.setSelectedRange(NSRange(location: 2, length: 3))
        apply(scroll, "다른 원문의 번역", identity: UUID())
        require(view.string == "다른 원문의 번역" && view.selectedRange().length == 0, "replacement clears obsolete selection")
        require(scroll.contentView.bounds.origin.y == 0, "replacement resets scroll")
        apply(scroll, "다른 원문의 번역", identity: UUID(), stale: true)
        require(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor,
                "stale text is dimmed")
    }

    private static func pureHelpers() {
        let edit = TranslationResultTextView.TextEdit(location: 20, removed: 10, inserted: 4)
        require(TranslationResultTextView.shifted(NSRange(location: 5, length: 10), by: edit) == NSRange(location: 5, length: 10), "before edit")
        require(TranslationResultTextView.shifted(NSRange(location: 15, length: 10), by: edit) == NSRange(location: 15, length: 5), "overlap clips")
        require(TranslationResultTextView.shifted(NSRange(location: 35, length: 3), by: edit) == NSRange(location: 29, length: 3), "after edit moves")
        let affixes = TranslationResultTextView.commonAffixes("a😀" as NSString, "a😃" as NSString)
        require(affixes.prefix == 1 && affixes.suffix == 0, "affixes never split a surrogate pair")
        let same = TranslationResultTextView.commonAffixes("앞 뒤" as NSString, "앞 중간 뒤" as NSString)
        require(same.prefix == 2 && same.suffix == 1, "middle edits keep both sides")
    }

    private static func newContentHint() {
        let visible = NSRect(x: 0, y: 0, width: 320, height: 140)
        typealias View = TranslationResultTextView
        require(View.newContentHint(tailStartY: nil, contentHeight: 900, visible: visible, isStreaming: true) == .hidden, "no tail")
        require(View.newContentHint(tailStartY: 500, contentHeight: 900, visible: visible, isStreaming: true) == .arriving, "below, streaming")
        require(View.newContentHint(tailStartY: 500, contentHeight: 900, visible: visible, isStreaming: false) == .arrived, "below, done")
        require(View.newContentHint(tailStartY: 140, contentHeight: 900, visible: visible, isStreaming: true) == .arriving, "at edge")
        require(View.newContentHint(tailStartY: 100, contentHeight: 400, visible: visible, isStreaming: true) == .arriving, "overflowing")
        require(View.newContentHint(tailStartY: 100, contentHeight: 400, visible: visible, isStreaming: false) == .hidden, "visible start")
        require(View.newContentHint(tailStartY: 100, contentHeight: 130, visible: visible, isStreaming: true) == .hidden, "fits")

        let (scroll, view) = makeScroll()
        apply(scroll, first)
        let tail = first.utf16.count
        apply(scroll, first + "\n\n새로 붙은 번역", tailStart: tail, streaming: true)
        require(scroll.hint == .arriving && scroll.pendingTail == tail, "an appended unit below the screen is announced")
        apply(scroll, first + "\n\n새로 붙은 번역입니다.", tailStart: tail)
        require(scroll.hint == .arrived, "the completed unit stays announced until seen")
        TranslationResultTextView.revealNewContent(in: scroll)
        require(scroll.hint == .hidden && scroll.pendingTail == nil, "revealing marks the unit seen")
        let revealed = scroll.contentView.bounds.origin.y
        require(revealed > 0 && revealed <= view.frame.height - scroll.contentView.bounds.height + 1, "reveal scrolls to the new unit")
        Self.scroll(scroll, to: 0)
        require(scroll.hint == .hidden, "a seen unit is not announced again")

        let cached = makeScroll().0
        apply(cached, first + "\n\n캐시된 번역", tailStart: first.utf16.count)
        require(cached.hint == .hidden && cached.pendingTail == nil, "text restored on a fresh surface is not announced")
    }

    /// A focused text view must not scroll its selection into view on updates.
    /// The window is never ordered front.
    private static func firstResponderKeepsPosition() {
        let (scroll, view) = makeScroll()
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 140),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        apply(scroll, first)
        _ = window.makeFirstResponder(view)
        Self.scroll(scroll, to: 150)
        let selection = NSRange(location: 8, length: 40)
        view.setSelectedRange(selection)
        var text = first + "\n\n"
        for chunk in ["추가", " 번역이", " 들어옵니다."] {
            text += chunk
            apply(scroll, text, tailStart: first.utf16.count, streaming: true)
            require(abs(scroll.contentView.bounds.origin.y - 150) < 1 && view.selectedRange() == selection,
                    "a focused surface keeps the reading position and selection")
        }
        require(!window.isVisible, "the test window is never shown")
        window.contentView = nil
    }

    private static func canCopy(_ view: NSTextView) -> Bool {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-result-view-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let menu = NSMenuItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        pasteboard.clearContents()
        let written = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)
        return written && view.validateUserInterfaceItem(menu)
    }

    private static func draftsAndStaleTextCannotBeCopied() {
        let (scroll, view) = makeScroll()
        apply(scroll, first)
        view.setSelectedRange(NSRange(location: 0, length: 10))
        require(canCopy(view), "completed text can be copied")
        apply(scroll, first, stale: true)
        require(view.selectedRange().length == 0, "becoming stale clears the selection")
        view.setSelectedRange(NSRange(location: 0, length: 10))
        require(!canCopy(view), "stale text cannot leave the app")

        let (streaming, streamingView) = makeScroll()
        apply(streaming, first)
        apply(streaming, first + "\n\n초안", tailStart: first.utf16.count, streaming: true)
        streamingView.setSelectedRange(NSRange(location: 0, length: 10))
        require(canCopy(streamingView), "completed text before a draft can be copied")
        streamingView.setSelectedRange(NSRange(location: first.utf16.count - 2, length: 5))
        require(!canCopy(streamingView), "a selection reaching into the draft cannot be copied")
        // A finished unit that ends with its own line break, selected with it (a triple click), can be copied.
        let (ending, endingView) = makeScroll()
        apply(ending, first + "\n")
        apply(ending, first + "\n\n초안", tailStart: (first + "\n").utf16.count, streaming: true)
        endingView.setSelectedRange(NSRange(location: first.utf16.count - 10, length: 11))
        require(canCopy(endingView), "the completed unit's line break can be copied")
        apply(streaming, first + "\n\n초안 완료.", tailStart: first.utf16.count)
        require(canCopy(streamingView), "the completed tail can be copied")
    }

    private static func hintFollowsEditsAndReader() {
        // Leading text removed after a tail arrived: the remembered tail moves with its text.
        let (scroll, _) = makeScroll()
        let leading = "앞 문단입니다.\n\n"
        apply(scroll, leading + first)
        let tail = (leading + first).utf16.count
        apply(scroll, leading + first + "\n\n새 번역", tailStart: tail)
        require(scroll.pendingTail == tail && scroll.hint == .arrived, "the appended unit is pending")
        apply(scroll, first + "\n\n새 번역", tailStart: first.utf16.count)
        require(scroll.pendingTail == first.utf16.count, "the pending tail moves with the removed leading text")
        TranslationResultTextView.revealNewContent(in: scroll)
        let tailY = TranslationResultTextView.lineTop(ofFirstTextFrom: first.utf16.count, in: scroll.documentView as! NSTextView)!
        require(scroll.documentVisibleRect.minY <= tailY && tailY < scroll.documentVisibleRect.maxY,
                "reveal brings the appended unit into view")

        // A stale surface forgets unseen tails.
        let (stale, _) = makeScroll()
        apply(stale, first)
        apply(stale, first + "\n\n새 번역", tailStart: first.utf16.count)
        apply(stale, first + "\n\n새 번역", tailStart: first.utf16.count, stale: true)
        require(stale.pendingTail == nil && stale.hint == .hidden, "stale text has no new-content hint")

        // Seen while streaming stays seen.
        let (seen, seenView) = makeScroll()
        apply(seen, first)
        apply(seen, first + "\n\n스트리밍 중", tailStart: first.utf16.count, streaming: true)
        Self.scroll(seen, to: seenView.frame.height - seen.contentView.bounds.height)
        Self.scroll(seen, to: 0)
        apply(seen, first + "\n\n스트리밍 완료.", tailStart: first.utf16.count)
        require(seen.hint == .hidden, "a tail the reader saw while streaming is not announced again")

        // Restoring onto an empty surface of the same identity is not news.
        let (empty, _) = makeScroll()
        apply(empty, "")
        apply(empty, first + "\n\n캐시된 번역", tailStart: first.utf16.count)
        require(empty.hint == .hidden && empty.pendingTail == nil, "text restored on an empty surface is not announced")

        // Widening the window can bring the tail into view.
        let (resized, _) = makeScroll()
        resized.frame = NSRect(x: 0, y: 0, width: 200, height: 140)
        let short = String(repeating: "좁은 창에서는 여러 줄로 나뉘어 표시됩니다. ", count: 4)
        apply(resized, short)
        apply(resized, short + "\n\n새 번역", tailStart: short.utf16.count)
        require(resized.hint == .arrived, "the tail starts below a narrow viewport")
        resized.setFrameSize(NSSize(width: 900, height: 140))
        require(resized.hint == .hidden, "resizing refreshes the hint")
    }

    private static func announcementsOnlyForCompletedText() {
        let (scroll, _) = makeScroll()
        apply(scroll, first)
        apply(scroll, first + "\n\n추가", tailStart: first.utf16.count, streaming: true)
        apply(scroll, first + "\n\n추가 번역.", tailStart: first.utf16.count)
        require(scroll.announcementCount == 1, "a completed tail is announced once")
        apply(scroll, first + "\n\n추가 번역.\n\n또", tailStart: (first + "\n\n추가 번역.").utf16.count, streaming: true)
        apply(scroll, first + "\n\n추가 번역.", tailStart: first.utf16.count)
        require(scroll.announcementCount == 1, "a failed or edited tail is not announced")
    }

    private static func lostLinesAreFoundOrClamped() {
        // A leading deletion and a streamed snapshot rendered together.
        let (scroll, view) = makeScroll()
        let second = (1...20).map { "둘째 묶음 \($0)번 줄을 읽고 있습니다." }.joined(separator: "\n")
        apply(scroll, first + "\n\n" + second + "\n\n초안", tailStart: (first + "\n\n" + second).utf16.count, streaming: true)
        let target = (first + "\n\n").utf16.count + ("둘째 묶음 1번 줄을 읽고 있습니다.\n".utf16.count * 5)
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: target)
        let y = view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        Self.scroll(scroll, to: y)
        let line = topLineText(of: scroll)
        apply(scroll, second + "\n\n초안이 더 길어졌습니다", tailStart: second.utf16.count, streaming: true)
        require(topLineText(of: scroll) == line, "the line being read is found again after a combined edit")

        // A shorter replacement does not leave an empty screen.
        let (replaced, replacedView) = makeScroll()
        apply(replaced, first, stale: true)
        Self.scroll(replaced, to: replacedView.frame.height - replaced.contentView.bounds.height)
        apply(replaced, "짧은 새 번역입니다.")
        let used = replacedView.layoutManager!.usedRect(for: replacedView.textContainer!).maxY
        require(replaced.documentVisibleRect.minY < used, "a shorter replacement stays visible")

        let flag = TranslationResultTextView.commonAffixes(" 🇰🇷" as NSString, " 🇰🇷\u{301}x" as NSString)
        let old = " 🇰🇷" as NSString, new = " 🇰🇷\u{301}x" as NSString
        require(flag.prefix == old.length || old.rangeOfComposedCharacterSequence(at: flag.prefix).location == flag.prefix,
                "the prefix ends on a cluster boundary in the old text")
        require(new.rangeOfComposedCharacterSequence(at: flag.prefix).location == flag.prefix,
                "the prefix ends on a cluster boundary in the new text")
    }

    private static func repeatedLinesAndProxyAttach() {
        // The same words repeat; the reader's own line is found, not the first copy.
        let (scroll, view) = makeScroll()
        let leading = (1...10).map { "앞 단위 \($0)" }.joined(separator: "\n\n")
        let repeated = (1...30).map { "같은 문장으로 시작하는 줄입니다만 끝은 다릅니다 \($0)" }.joined(separator: "\n")
        apply(scroll, leading + "\n\n" + repeated + "\n\n초안", tailStart: (leading + "\n\n" + repeated).utf16.count, streaming: true)
        let line = "같은 문장으로 시작하는 줄입니다만 끝은 다릅니다 20"
        let index = (view.string as NSString).range(of: line).location
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: index)
        Self.scroll(scroll, to: view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY)
        require(topParagraph(of: scroll) == line, "the reader starts on line 20")
        apply(scroll, repeated + "\n\n초안이 더 길어졌습니다", tailStart: repeated.utf16.count, streaming: true)
        require(topParagraph(of: scroll) == line, "the reader stays on line 20 among repeated lines")

        // A proxy attached later starts from the current hint.
        let (hinted, _) = makeScroll()
        apply(hinted, first)
        apply(hinted, first + "\n\n새 번역", tailStart: first.utf16.count)
        require(hinted.hint == .arrived, "the surface has an unseen unit")
        let proxy = ResultScrollProxy()
        let received = waitForHintDelivery(.arrived, from: proxy) { hinted.attach(proxy) }
        require(received && proxy.hint == .arrived, "a newly attached proxy receives the current hint")

        // A hidden hint must also be delivered. Starting from the received .arrived value prevents
        // an omitted callback from passing merely because a fresh proxy already defaults to .hidden.
        let (empty, _) = makeScroll()
        require(empty.hint == .hidden, "the empty surface has no new-content hint")
        hinted.attach(nil)
        let receivedHidden = waitForHintDelivery(.hidden, from: proxy) { empty.attach(proxy) }
        require(receivedHidden && proxy.hint == .hidden, "reattaching the proxy receives the hidden hint")
    }

    @MainActor private final class HintDeliveryReceipt {
        var observed = false
    }

    /// Wait for an actual observable publication, not an elapsed scheduling allowance. Observation's
    /// callback runs before the setter finishes; its MainActor task records completion after that
    /// synchronous publisher has returned. RunLoop pumping lets that delivery run without changing
    /// the suite's synchronous AppKit lifecycle. The deadline bounds a missing or wrong publication.
    private static func waitForHintDelivery(_ expected: NewContentHint, from proxy: ResultScrollProxy,
                                            action: () -> Void) -> Bool {
        require(proxy.hint != expected, "the hint fixture must require a real value transition")
        let receipt = HintDeliveryReceipt()
        withObservationTracking {
            _ = proxy.hint
        } onChange: {
            Task { @MainActor in receipt.observed = true }
        }
        action()
        let deadline = ContinuousClock.now + .seconds(5)
        while !(receipt.observed && proxy.hint == expected), ContinuousClock.now < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return receipt.observed && proxy.hint == expected
    }

    private static func topParagraph(of scroll: NSScrollView) -> String {
        let text = (scroll.documentView as! NSTextView).string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: topCharacter(of: scroll), length: 0))
        return text.substring(with: paragraph).trimmingCharacters(in: .newlines)
    }

    private static func topLineText(of scroll: NSScrollView) -> String {
        let view = scroll.documentView as! NSTextView
        let glyph = view.layoutManager!.glyphIndex(for: NSPoint(x: 1, y: scroll.contentView.bounds.minY + 1), in: view.textContainer!)
        var range = NSRange()
        view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        return (view.string as NSString).substring(with: view.layoutManager!.characterRange(forGlyphRange: range, actualGlyphRange: nil))
    }

    private static func topCharacter(of scroll: NSScrollView) -> Int {
        let view = scroll.documentView as! NSTextView
        let point = NSPoint(x: 1, y: scroll.contentView.bounds.minY - view.textContainerOrigin.y)
        let glyph = view.layoutManager!.glyphIndex(for: point, in: view.textContainer!)
        return view.layoutManager!.characterIndexForGlyph(at: glyph)
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "TranslationResultTextViewTests: \(message)")
    }
}
