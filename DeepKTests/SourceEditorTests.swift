import AppKit

/// The source pane without a visible window: accepted `---` lines drawn as one Markdown-style rule with the dashes
/// hidden (TextKit 2 rendering attributes) and kept as one piece the caret steps over, the scroller gutter, and ⌘↩
/// '끝에 구분선 넣기'. Windows are created but never ordered front. No test touches the general pasteboard.
@main
@MainActor
private struct SourceEditorTests {
    static func main() {
        _ = NSApplication.shared
        ruleReplacesBoundaryDashes()
        caretSkipsTheRule()
        typingDashesMakesARule()
        mouseClickPicksTheSide()
        droppingOnTheRule()
        deletingRemovesTheWholeRule()
        hiddenFollowsTextChanges()
        compositionStaysVisible()
        ruleFollowsLayout()
        scrollerGutter()
        legacyScrollerTakesItsOwnColumn()
        appendBoundaryAppendsOnly()
        appendBoundaryCommitsComposition()
        menuItemValidation()
        menuKeyEquivalent()
        listParagraphs()
        listFormattingSurvivesEquivalentEdits()
        listRangeExclusions()
        print("SourceEditorTests passed (no windows opened)")
    }

    private static func listParagraphs() {
        let body = String(repeating: "long list item words ", count: 9)
        let text = "3. " + body + "\n  - Child\n7. Last\n\n```text\n- code\n```"
        let f = make(text, width: 240, height: 140)
        let editor = f.editor, layout = editor.textLayoutManager!, content = layout.textContentManager!
        let item = TranslationLists(text).items[0]
        let start = content.location(content.documentRange.location, offsetBy: item.range.location)!
        let end = content.location(start, offsetBy: item.range.length)!
        layout.ensureLayout(for: layout.documentRange)
        var fragments: [NSRect] = []
        layout.enumerateTextSegments(in: NSTextRange(location: start, end: end)!, type: .standard, options: .rangeNotRequired) { _, rect, _, _ in
            fragments.append(rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y))
            return true
        }
        let bodyX = segment(editor, NSRange(location: item.contentRange.location, length: 1)).minX
        require(fragments.count > 2 && abs(fragments[1].minX - bodyX) < 0.6,
                "TextKit 2 wrapped lines align with the item body (body \(bodyX), lines \(fragments.map(\.minX)))")
        require(editor.string == text && editor.textLayoutManager != nil, "source list layout preserves text and TextKit 2")
        let code = (text as NSString).range(of: "- code").location
        require((editor.textStorage!.attribute(.paragraphStyle, at: code, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0 == 0,
                "fenced code does not receive list indentation")
        let board = NSPasteboard(name: NSPasteboard.Name("deepk-source-list-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        editor.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        require(editor.writeSelection(to: board, types: editor.writablePasteboardTypes) && board.string(forType: .string) == text,
                "copying the source retains literal list prefixes")
        f.show("ordinary prose")
        require((editor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0 == 0,
                "removing list markers removes their old hanging indentation")
        let nested = make("- Parent\n  wrapped continuation\n  - Child\n  back to parent", width: 240)
        let lists = TranslationLists(nested.editor.string)
        require(lists.continuations.count == 2, "explicit continuation paragraphs are attached to the parent")
        let first = lists.items[0]
        let firstBody = segment(nested.editor, NSRange(location: first.contentRange.location, length: 1)).minX
        for line in lists.continuations {
            let x = segment(nested.editor, NSRange(location: line.contentRange.location, length: 1)).minX
            require(abs(x - firstBody) < 0.6, "continuation first lines align with the owning body (\(x), \(firstBody))")
        }
    }

    private static func listFormattingSurvivesEquivalentEdits() {
        let sample = "3. " + String(repeating: "long list item words ", count: 24) + "\n- Other item"
        for operation in ["insert", "named paste", "composition commit"] {
            let f = make(sample, width: 240, height: 140), editor = f.editor
            let positions = [0, (sample as NSString).range(of: "\n-").location + 1]
            let original = positions.map {
                (editor.textStorage!.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            }
            require(original.allSatisfy { $0 > 0 }, "\(operation): fixture initially has hanging indents")
            editor.setSelectedRange(NSRange(location: 0, length: sample.utf16.count))
            switch operation {
            case "insert":
                editor.insertText(sample, replacementRange: editor.selectedRange())
            case "named paste":
                let board = NSPasteboard(name: NSPasteboard.Name("deepk-equivalent-list-\(UUID().uuidString)"))
                defer { board.releaseGlobally() }
                board.setString(sample, forType: .string)
                require(editor.readSelection(from: board, type: .string), "named paste is accepted")
            default:
                editor.setMarkedText(sample, selectedRange: NSRange(location: sample.utf16.count, length: 0),
                                     replacementRange: NSRange(location: 0, length: sample.utf16.count))
                f.show(sample)
                require(editor.hasMarkedText() && editor.string == sample, "layout updates leave same-text IME composition active")
                editor.unmarkText()
                require(!editor.hasMarkedText(), "the IME composition commits")
            }
            let restored = positions.map {
                (editor.textStorage!.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            }
            require(editor.string == sample && restored == original,
                    "\(operation): equivalent edits restore native paragraph styles (\(original) -> \(restored))")
            require(editor.textLayoutManager != nil, "\(operation): TextKit 2 stays active")
            let selection = editor.selectedRanges, origin = f.scroll.contentView.bounds.origin
            f.show(sample)
            require(editor.selectedRanges == selection && f.scroll.contentView.bounds.origin == origin,
                    "\(operation): cached showing preserves the user's selection and scroll")
            let layout = editor.textLayoutManager!, content = layout.textContentManager!
            let end = content.location(content.documentRange.location, offsetBy: positions[1] - 1)!
            let range = NSTextRange(location: content.documentRange.location, end: end)!
            layout.ensureLayout(for: range)
            var starts: [CGFloat] = []
            layout.enumerateTextSegments(in: range, type: .standard, options: .rangeNotRequired) { _, rect, _, _ in
                starts.append(rect.minX)
                return true
            }
            let bodyX = segment(editor, NSRange(location: 3, length: 1)).minX - editor.textContainerOrigin.x
            require(starts.count > 2 && abs(starts[1] - bodyX) < 0.6, "\(operation): wrapped text still aligns with the body")
        }
        let removed = make("- Item\nTail")
        removed.editor.insertText("", replacementRange: NSRange(location: 0, length: 2))
        removed.show(removed.editor.string)
        require(removed.editor.string == "Item\nTail"
                && ((removed.editor.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0) == 0,
                "removing the final marker clears its old paragraph style")
    }

    private static func listRangeExclusions() {
        let display = "- literal item\n1. literal item\n- git\n  continuation\n9. Next"
        let text = display as NSString
        let lists = TranslationLists(display, excludingMarkers: [text.range(of: "git"), text.range(of: "1. literal item"),
                                                                text.range(of: "- literal item")])
        require(lists.items.count == 2 && lists.items[0].marker.number == nil && lists.items[1].marker.number == 9
                && lists.continuations.count == 1,
                "inline-code marker lookalikes are excluded while normal list-body code and continuations remain")
        let sample = "- Keep\n- BlockA\n- BlockB\n- Keep2"
        let raw = sample as NSString, blockA = raw.range(of: "- BlockA"), blockB = raw.range(of: "- BlockB")
        let blocked = TranslationLists(sample, excluding: [blockB, blockA, NSRange(location: blockA.location + 2, length: 4),
                                                          NSRange(location: NSNotFound, length: 1), NSRange(location: raw.length + 2, length: 4)])
        require(blocked.items.map { raw.substring(with: $0.contentRange) } == ["Keep", "Keep2"],
                "unsorted, overlapping and out-of-document exclusions preserve unexcluded items")
        let line = "- code\n", count = 8_000
        let many = "- Before\n" + String(repeating: line, count: count) + "- After"
        let ranges = (0..<count).reversed().map { NSRange(location: "- Before\n".utf16.count + $0 * line.utf16.count, length: line.utf16.count) }
        let large = TranslationLists(many, excluding: ranges)
        require(large.items.map { (many as NSString).substring(with: $0.contentRange) } == ["Before", "After"],
                "eight thousand excluded blocks leave only their actual surrounding list items")
    }

    private final class Edits {
        var values: [(text: String, composing: Bool)] = []
    }

    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    /// A drop from another app at a fixed window location.
    private final class Drop: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingDestinationWindow: NSWindow?
        let draggingLocation: NSPoint
        @MainActor init(pasteboard: NSPasteboard, window: NSWindow, location: NSPoint) {
            draggingPasteboard = pasteboard
            draggingDestinationWindow = window
            draggingLocation = location
        }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggedImageLocation: NSPoint { draggingLocation }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 4242 }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func resetSpringLoading() {}
    }

    @MainActor private struct Fixture {
        let scroll: NSScrollView
        let editor: SourceEditor.Editor
        let coordinator: SourceEditor.Coordinator
        let edits: Edits

        /// What SwiftUI does on an update: the store's text and its boundary lines for that text.
        func show(_ text: String) {
            coordinator.show(text, boundaryLines: lines(text), in: editor)
        }

        /// The text container's width: the frame less the scroller gutter.
        var containerWidth: CGFloat { editor.textContainer!.size.width }
    }

    private static func make(_ text: String = "", width: CGFloat = 300, height: CGFloat = 200) -> Fixture {
        let edits = Edits()
        let scroll = SourceEditor.makeScrollView(fontSize: 13)
        scroll.appearance = NSAppearance(named: .aqua)
        scroll.scrollerStyle = .overlay
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let editor = scroll.documentView as! SourceEditor.Editor
        let coordinator = SourceEditor(text: text, onEdit: { edits.values.append(($0, $1)) }, onEscape: {}).makeCoordinator()
        editor.delegate = coordinator
        editor.findBoundaryLines = lines
        let fixture = Fixture(scroll: scroll, editor: editor, coordinator: coordinator, edits: edits)
        fixture.show(text)
        scroll.layoutSubtreeIfNeeded()
        return fixture
    }

    private static func lines(_ text: String) -> [NSRange] {
        IncrementalTranslationPlanner.boundaryLineRanges(in: text)
    }

    private static let insertion: (String) -> String? = IncrementalTranslationPlanner.boundaryInsertion(after:)

    // MARK: rule and hidden dashes

    private static func ruleReplacesBoundaryDashes() {
        let text = "Hello\n\n---\n\nWorld"
        let f = make(text)
        let dash = NSRange(location: 7, length: 3)
        require(f.editor.textLayoutManager != nil, "the editor is TextKit 2")
        require(hidden(f.editor) == [dash], "only the boundary dashes are hidden")
        require(f.editor.string == text, "the text is unchanged")
        require(f.editor.textStorage!.attribute(.foregroundColor, at: dash.location, effectiveRange: nil) as? NSColor == .labelColor,
                "the storage keeps its color; hiding is a rendering attribute")

        // One rule from the text's left edge to the end of the text container, centered on the line.
        let box = segment(f.editor, dash)
        require(f.editor.boundaryRules.count == 1, "one rule")
        let rule = f.editor.boundaryRules[0]
        let origin = f.editor.textContainerOrigin
        require(abs(rule.minX - origin.x) <= 0.5 && abs(rule.maxX - (origin.x + f.containerWidth)) <= 0.5,
                "the rule spans the text container (\(rule.minX)–\(rule.maxX), container \(f.containerWidth))")
        require(abs(rule.midY - box.midY) <= 1 && rule.height <= 1.01, "1pt, centered on the line")

        // Pixels: the dashes leave no ink of their own; the rule runs through where they were.
        let hello = segment(f.editor, NSRange(location: 0, length: 5))
        require(maxInk(f.editor, in: hello) > 0.6, "text is drawn")
        require(maxInk(f.editor, in: box) < 0.3, "the dashes are not drawn (only the faint rule is)")
        require(inkRows(f.editor, x: box.midX, around: rule.midY) > 0, "the rule passes under the hidden dashes")
        require(inkRows(f.editor, x: origin.x + 0.5, around: rule.midY) > 0, "the rule starts at the text's left edge")
        require(inkRows(f.editor, x: origin.x + f.containerWidth - 1, around: rule.midY) > 0, "the rule reaches the container's end")
        require(inkRows(f.editor, x: origin.x + f.containerWidth + 2, around: rule.midY) == 0, "the rule stops before the scroller gutter")
        require(inkRows(f.editor, x: box.midX, around: rule.midY) <= 2, "the rule is one point thick")
        require(inkRows(f.editor, x: origin.x + f.containerWidth - 1, around: hello.midY) == 0
                && f.editor.boundaryRules.allSatisfy { !$0.intersects(hello) }, "no rule on a text line")

        // Copying reads the stored text, dashes included (a private pasteboard, never the general one).
        let board = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        f.editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        require(f.editor.writeSelection(to: board, types: f.editor.writablePasteboardTypes) && board.string(forType: .string) == text,
                "copying the hidden line gives its dashes")
        f.editor.setSelectedRange(NSRange(location: 0, length: 0))

        // UTF-16 ranges: an emoji and Hangul before the line.
        let wide = make("가😀\n\n---\n\nB")
        require(hidden(wide.editor) == [NSRange(location: 5, length: 3)] && wide.editor.boundaryRules.count == 1,
                "UTF-16 offsets after an emoji")

        // Lines the store does not accept stay ordinary text without a rule.
        let fence = make("```\ncode\n\n---\n\nB")
        require(lines(fence.editor.string).isEmpty && hidden(fence.editor).isEmpty && fence.editor.boundaryRules.isEmpty,
                "inside an open fence the line is text")
        require(maxInk(fence.editor, in: segment(fence.editor, NSRange(location: 10, length: 3))) > 0.6, "and its dashes are drawn")
        let typing = make("A\n\n--")
        require(hidden(typing.editor).isEmpty && typing.editor.boundaryRules.isEmpty, "a dash being typed is not a rule")
        require(maxInk(typing.editor, in: segment(typing.editor, NSRange(location: 3, length: 2))) > 0.6, "its dashes are drawn")
        f.coordinator.show(f.editor.string, boundaryLines: [], in: f.editor)
        require(hidden(f.editor).isEmpty && f.editor.boundaryRules.isEmpty, "no ranges, no rule")
        require(maxInk(f.editor, in: box) > 0.6 && inkRows(f.editor, x: origin.x + f.containerWidth - 1, around: rule.midY) == 0,
                "the dashes come back and the rule is gone")
        require(f.editor.textLayoutManager != nil && fence.editor.textLayoutManager != nil, "drawing keeps TextKit 2")
    }

    /// The rule is one piece, not text: the caret never rests on its line (hidden dashes or the line's end) and steps
    /// over it in the direction it was going. A selection across it leaves the dashes hidden.
    private static func caretSkipsTheRule() {
        let text = "Hello\n\n---\n\nWorld"  // the rule's line is 7…10, the blank lines around it start at 6 and 11
        let dash = NSRange(location: 7, length: 3)
        for target in [7, 8, 10] {
            let f = make(text)
            f.editor.setSelectedRange(NSRange(location: 6, length: 0))
            f.editor.setSelectedRange(NSRange(location: target, length: 0))
            require(f.editor.selectedRange() == NSRange(location: 11, length: 0), "coming from above, \(target) lands below the rule")
            f.editor.setSelectedRange(NSRange(location: 12, length: 0))
            f.editor.setSelectedRange(NSRange(location: target, length: 0))
            require(f.editor.selectedRange() == NSRange(location: 6, length: 0), "coming from below, \(target) lands above the rule")
            require(hidden(f.editor) == [dash] && f.edits.values.isEmpty, "nothing is edited")
        }
        let f = make(text)
        f.editor.setSelectedRange(NSRange(location: 6, length: 0))
        f.editor.moveRight(nil)
        require(f.editor.selectedRange() == NSRange(location: 11, length: 0), "→ steps over the rule")
        f.editor.moveLeft(nil)
        require(f.editor.selectedRange() == NSRange(location: 6, length: 0), "← steps back over it")
        f.editor.moveDown(nil)
        require(f.editor.selectedRange() == NSRange(location: 11, length: 0), "↓ steps over the rule")
        f.editor.moveUp(nil)
        require(f.editor.selectedRange() == NSRange(location: 6, length: 0), "↑ steps back over it")
        // Collapsing a selection that starts on the rule: ← goes to its start, so above the rule; → to its end.
        f.editor.setSelectedRange(NSRange(location: 8, length: 6))
        f.editor.moveLeft(nil)
        require(f.editor.selectedRange() == NSRange(location: 6, length: 0), "← collapses a selection from the rule to above it")
        f.editor.setSelectedRange(NSRange(location: 8, length: 6))
        f.editor.moveRight(nil)
        require(f.editor.selectedRange() == NSRange(location: 14, length: 0), "→ collapses it to its end")

        // Two rules in a row are stepped over together; a rule on the last line sends the caret above it.
        let double = make("A\n\n---\n---\n\nB")
        double.editor.setSelectedRange(NSRange(location: 2, length: 0))
        double.editor.setSelectedRange(NSRange(location: 4, length: 0))
        require(double.editor.selectedRange() == NSRange(location: 11, length: 0), "both rules are stepped over")
        // A rule on the last line: going below it opens a line there (the source gains a line break, nothing else).
        let last = make("A\n\n---")
        last.editor.setSelectedRange(NSRange(location: 2, length: 0))
        last.editor.moveDown(nil)
        require(last.editor.string == "A\n\n---\n" && last.editor.selectedRange() == NSRange(location: 7, length: 0),
                "↓ below a last rule opens a line below it")
        require(last.edits.values.last! == ("A\n\n---\n", false), "the line break is reported")
        last.show(last.editor.string)
        require(hidden(last.editor) == [NSRange(location: 3, length: 3)] && last.editor.selectedRange().location == 7, "the caret stays below")
        last.show("A\n\n---")
        last.editor.setSelectedRange(NSRange(location: 2, length: 0))
        last.editor.setSelectedRange(NSRange(location: 6, length: 0), affinity: .downstream, stillSelecting: true)
        require(last.editor.string == "A\n\n---" && last.editor.selectedRange() == NSRange(location: 2, length: 0),
                "while still selecting nothing is added")
        // Text replaced from outside (a copy ending in a rule) never leaves the caret on the rule, and the update adds nothing.
        last.show("B\n\n---")
        require(last.editor.string == "B\n\n---" && last.editor.selectedRange().location <= 2, "an external text puts the caret off the rule")
        // A leading rule: the caret coming from below stays below (there is no line above it).
        let leading = make("---\n\nB")
        leading.editor.setSelectedRange(NSRange(location: 5, length: 0))
        leading.editor.moveUp(nil)
        leading.editor.moveUp(nil)
        require(leading.editor.selectedRange().location >= 4 && leading.editor.string == "---\n\nB", "nothing above a leading rule")

        // Form feed and vertical tab end a line for the planner but not for NSString: such a line is drawn but not one piece.
        let feed = make("A\u{0C}---\u{0C}B\nC")
        feed.editor.setSelectedRange(NSRange(location: 3, length: 0))
        require(feed.editor.selectedRange() == NSRange(location: 3, length: 0), "no snapping on a line NSString reads differently")
        feed.editor.setSelectedRange(NSRange(location: 8, length: 0))
        feed.editor.deleteBackward(nil)
        require(feed.editor.string == "A\u{0C}---\u{0C}BC", "⌫ deletes one character there, never the whole line")

        // A selection across the rule covers its whole line, and the dashes stay hidden under it. One inside the rule's line
        // (a double-click or right-click picks a hidden dash) is a caret: typing never replaces a single hidden dash.
        for (selection, kept) in [(NSRange(location: 0, length: 17), NSRange(location: 0, length: 17)),
                                  (NSRange(location: 3, length: 6), NSRange(location: 3, length: 7)),
                                  (NSRange(location: 8, length: 6), NSRange(location: 7, length: 7)),
                                  (NSRange(location: 6, length: 1), NSRange(location: 6, length: 1)),
                                  (NSRange(location: 10, length: 2), NSRange(location: 7, length: 5))] {
            let g = make(text)
            let (window, _) = keyWindow(g.scroll)
            _ = window.makeFirstResponder(g.editor)
            g.editor.setSelectedRange(selection)
            g.show(g.editor.string)
            require(g.editor.selectedRange() == kept && hidden(g.editor) == [dash], "the selection \(selection) becomes \(kept)")
            require(maxInk(g.editor, in: segment(g.editor, dash)) < 0.4, "the dashes stay invisible under the selection \(selection)")
            window.contentView = nil
        }
        for inside in [dash, NSRange(location: 8, length: 1), NSRange(location: 9, length: 1)] {
            let g = make(text)
            g.editor.setSelectedRange(NSRange(location: 0, length: 0))
            g.editor.setSelectedRange(inside)
            require(g.editor.selectedRange() == NSRange(location: 11, length: 0), "\(inside) inside the rule is a caret below it")
            g.editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(g.editor.string == "Hello\n\n---\nx\nWorld", "typing goes below the rule, not over a dash")
        }
        // ⇧→ from above: the second step reaches into the rule and takes all of it; ⌫ then removes the rule whole.
        let shift = make(text)
        shift.editor.setSelectedRange(NSRange(location: 6, length: 0))
        shift.editor.moveRightAndModifySelection(nil)
        shift.editor.moveRightAndModifySelection(nil)
        require(shift.editor.selectedRange() == NSRange(location: 6, length: 4), "⇧→⇧→ selects the line break and the whole rule")
        shift.editor.deleteBackward(nil)
        require(shift.editor.string == "Hello\n\n\nWorld", "and ⌫ deletes the rule, never one dash")
    }

    /// Typing (or pasting) the last dash of a boundary line breaks the line like ↩: the dashes turn into the rule and the
    /// caret waits on the new line below it.
    private static func typingDashesMakesARule() {
        let f = make("Hello\n\n")
        f.editor.setSelectedRange(NSRange(location: 7, length: 0))
        for _ in 0..<2 { f.editor.insertText("-", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        require(f.editor.string == "Hello\n\n--", "two dashes are text being typed")
        f.editor.insertText("-", replacementRange: NSRange(location: NSNotFound, length: 0))
        require(f.editor.string == "Hello\n\n---\n" && f.editor.selectedRange() == NSRange(location: 11, length: 0),
                "the third dash moves the caret below the line")
        require(f.edits.values.last! == ("Hello\n\n---\n", false), "the line break is reported")
        f.show(f.editor.string)
        require(hidden(f.editor) == [NSRange(location: 7, length: 3)] && f.editor.boundaryRules.count == 1
                && f.editor.selectedRange() == NSRange(location: 11, length: 0), "a rule with the caret below it")
        f.editor.insertText("World", replacementRange: NSRange(location: NSNotFound, length: 0))
        f.show(f.editor.string)
        require(f.editor.string == "Hello\n\n---\nWorld" && hidden(f.editor) == [NSRange(location: 7, length: 3)], "text below keeps the rule")

        // Between two paragraphs the following text moves down a line.
        let middle = make("Hello\n\nWorld")
        middle.editor.setSelectedRange(NSRange(location: 6, length: 0))
        middle.editor.insertText("---", replacementRange: NSRange(location: NSNotFound, length: 0))
        require(middle.editor.string == "Hello\n---\n\nWorld" && middle.editor.selectedRange() == NSRange(location: 10, length: 0),
                "typed between paragraphs")

        // Dashes typed on are cut after the third, as in Notion: the rest goes to the next line.
        let longer = make("Hello\n\n")
        longer.editor.setSelectedRange(NSRange(location: 7, length: 0))
        for character in "----" { longer.editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        require(longer.editor.string == "Hello\n\n---\n-", "a fourth dash starts the next line")

        // A dash typed between the dashes and trailing spaces breaks at the line's end.
        let before = make("Hello\n\n--  ")
        before.editor.setSelectedRange(NSRange(location: 9, length: 0))
        before.editor.insertText("-", replacementRange: NSRange(location: NSNotFound, length: 0))
        require(before.editor.string == "Hello\n\n---  \n" && before.editor.selectedRange() == NSRange(location: 13, length: 0),
                "the line breaks after the trailing spaces")

        // A paste ending in a boundary line (a private pasteboard, never the general one).
        let board = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("World\n\n---", forType: .string)
        let paste = make("Hello\n\n")
        paste.editor.setSelectedRange(NSRange(location: 7, length: 0))
        require(paste.editor.readSelection(from: board, type: .string), "pasted")
        require(paste.editor.string == "Hello\n\nWorld\n\n---\n" && paste.editor.selectedRange() == NSRange(location: 18, length: 0),
                "a paste ending in a rule leaves the caret below it")
        board.clearContents()
        board.setString("---  ", forType: .string)
        let spaces = make("Hello\n\n")
        spaces.editor.setSelectedRange(NSRange(location: 7, length: 0))
        require(spaces.editor.readSelection(from: board, type: .string)
                && spaces.editor.string == "Hello\n\n---  \n" && spaces.editor.selectedRange() == NSRange(location: 13, length: 0),
                "spaces after the pasted dashes still break the line")

        // No line break where the dashes are not a boundary, or more text follows them on the line.
        for (source, caret, typed, expected) in [
            ("", 0, "---", "---"),                                       // nothing above to divide
            ("```\ncode\n\n", 10, "---", "```\ncode\n\n---"),            // inside an open fence
            ("Hello\n\n--x", 9, "-", "Hello\n\n---x"),                  // `---x` is text
            ("Hello\n\n--", 7, "-", "Hello\n\n---"),                    // the first dash typed, not the last
            ("Hello\n\n", 7, "- - -", "Hello\n\n- - -"),
        ] {
            let g = make(source)
            g.editor.setSelectedRange(NSRange(location: caret, length: 0))
            g.editor.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
            require(g.editor.string == expected, "\(typed.debugDescription) into \(source.debugDescription) stays \(expected.debugDescription)")
        }
        let lone = make("")
        lone.editor.insertText("---", replacementRange: NSRange(location: NSNotFound, length: 0))
        lone.show(lone.editor.string)
        require(hidden(lone.editor).isEmpty && lone.editor.boundaryRules.isEmpty, "a lone `---` is text, not a rule")

        // Composition is never broken: a Hangul syllable after the dashes makes the line text.
        let composing = make("Hello\n\n---")
        composing.coordinator.show(composing.editor.string, boundaryLines: [], in: composing.editor)
        composing.editor.setSelectedRange(NSRange(location: 10, length: 0))
        composing.editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        require(composing.editor.hasMarkedText() && composing.editor.string == "Hello\n\n---ㅎ", "marked text after dashes is not broken off")
    }

    /// A click on the rule lands above it from its upper half and below it from its lower half, wherever the caret was and
    /// however many drag callbacks arrive. A click below a rule on the last line opens a line under it once the button is
    /// released. NSTextView's tracking loop is replaced by the callbacks it makes (`stillSelecting` true while held, false
    /// on release, each with the raw click location): synthesized mouse-up events resolve against the real cursor.
    private static func mouseClickPicksTheSide() {
        func click(_ f: Fixture, at point: NSPoint, location: Int, drags: Int) {
            f.editor.trackMouse(from: point) {
                for _ in 0...drags {
                    f.editor.setSelectedRange(NSRange(location: location, length: 0), affinity: .downstream, stillSelecting: true)
                }
                f.editor.setSelectedRange(NSRange(location: location, length: 0), affinity: .downstream, stillSelecting: false)
            }
        }
        let text = "Hello\n\n---\n\nWorld"
        for (from, drags) in [(0, 0), (16, 0), (0, 3), (16, 2)] {
            for (upper, expected) in [(true, 6), (false, 11)] {
                for location in [7, 8, 10] {
                    let f = make(text)
                    let rule = f.editor.boundaryRules[0], line = segment(f.editor, NSRange(location: 7, length: 3))
                    f.editor.setSelectedRange(NSRange(location: from, length: 0))
                    let y = upper ? (line.minY + rule.midY) / 2 : (rule.midY + line.maxY) / 2
                    click(f, at: NSPoint(x: rule.midX, y: y), location: location, drags: drags)
                    require(f.editor.selectedRange() == NSRange(location: expected, length: 0),
                            "\(upper ? "upper" : "lower") half at \(location) from \(from), \(drags) drags → \(expected), got \(f.editor.selectedRange())")
                    require(f.editor.string == text, "a click edits nothing")
                }
            }
        }
        // Below a rule on the last line (NSTextView puts such a click at the end of the text).
        let f = make("A\n\n---")
        f.editor.setSelectedRange(NSRange(location: 0, length: 0))
        var during: [NSRange] = []
        f.editor.trackMouse(from: NSPoint(x: 40, y: f.editor.boundaryRules[0].maxY + 40)) {
            f.editor.setSelectedRange(NSRange(location: 6, length: 0), affinity: .downstream, stillSelecting: true)
            f.editor.setSelectedRange(NSRange(location: 6, length: 0), affinity: .downstream, stillSelecting: false)
            during.append(f.editor.selectedRange())
        }
        require(during == [NSRange(location: 2, length: 0)] && f.editor.string == "A\n\n---\n"
                && f.editor.selectedRange() == NSRange(location: 7, length: 0),
                "a click below a last rule opens a line there after release, got \(f.editor.string.debugDescription) \(f.editor.selectedRange())")
        // A drag that ends with a range keeps it.
        let g = make(text)
        g.editor.trackMouse(from: NSPoint(x: 5, y: 1)) {
            g.editor.setSelectedRange(NSRange(location: 0, length: 0), affinity: .downstream, stillSelecting: true)
            g.editor.setSelectedRange(NSRange(location: 0, length: 9), affinity: .downstream, stillSelecting: false)
        }
        require(g.editor.selectedRange() == NSRange(location: 0, length: 10) && g.editor.string == text, "a range dragged into the rule takes all of it")
    }

    /// Text dropped on the rule's line goes above it from the upper half and below it from the lower half, is selected as
    /// dropped, and gets no line break. NSTextView's drag destination methods run with a stand-in `NSDraggingInfo` and a
    /// private pasteboard.
    private static func droppingOnTheRule() {
        let board = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let text = "Hello\n\n---\n\nWorld"
        for (dropped, upper, expected, selection) in [
            ("abc", true, "Hello\nabc\n---\n\nWorld", NSRange(location: 6, length: 3)),
            ("abc", false, "Hello\n\n---\nabc\nWorld", NSRange(location: 11, length: 3)),
            ("---", false, "Hello\n\n---\n---\nWorld", NSRange(location: 11, length: 3)),
        ] {
            board.clearContents()
            board.setString(dropped, forType: .string)
            let f = make(text)
            let (window, _) = keyWindow(f.scroll)
            _ = window.makeFirstResponder(f.editor)
            let rule = f.editor.boundaryRules[0], line = segment(f.editor, NSRange(location: 7, length: 3))
            let y = upper ? (line.minY + rule.midY) / 2 : (rule.midY + line.maxY) / 2
            let drag = Drop(pasteboard: board, window: window, location: f.editor.convert(NSPoint(x: rule.midX, y: y), to: nil))
            _ = f.editor.draggingEntered(drag)
            _ = f.editor.draggingUpdated(drag)
            _ = f.editor.prepareForDragOperation(drag)
            require(f.editor.performDragOperation(drag), "dropped")
            f.editor.concludeDragOperation(drag)
            require(f.editor.string == expected && f.editor.selectedRange() == selection,
                    "\(dropped) dropped on the \(upper ? "upper" : "lower") half → \(f.editor.string.debugDescription) \(f.editor.selectedRange())")
            window.contentView = nil
        }
    }

    /// ⌫ at the start of the line below a rule, or ⌦ at the end of the line above it, deletes the rule's line whole.
    private static func deletingRemovesTheWholeRule() {
        let text = "Hello\n\n---\n\nWorld"
        let backward: [(String, (NSTextView) -> Void)] = [
            ("⌫", { $0.deleteBackward(nil) }), ("⌥⌫", { $0.deleteWordBackward(nil) }), ("⌘⌫", { $0.deleteToBeginningOfLine(nil) }),
        ]
        for (name, delete) in backward {
            let f = make(text)
            f.editor.setSelectedRange(NSRange(location: 11, length: 0))
            delete(f.editor)
            require(f.editor.string == "Hello\n\n\nWorld" && f.editor.selectedRange() == NSRange(location: 7, length: 0),
                    "\(name) below the rule deletes its line")
            require(f.edits.values.last! == ("Hello\n\n\nWorld", false), "\(name): the deletion is reported")
            f.show(f.editor.string)
            require(hidden(f.editor).isEmpty && f.editor.boundaryRules.isEmpty, "\(name): no rule is left")
        }
        let forward: [(String, (NSTextView) -> Void)] = [("⌦", { $0.deleteForward(nil) }), ("⌥⌦", { $0.deleteWordForward(nil) })]
        for (name, delete) in forward {
            let f = make(text)
            f.editor.setSelectedRange(NSRange(location: 6, length: 0))
            delete(f.editor)
            require(f.editor.string == "Hello\n\n\nWorld" && f.editor.selectedRange() == NSRange(location: 6, length: 0),
                    "\(name) above the rule deletes its line")
        }
        // A rule on the last line goes with the line break before it.
        let last = make("Hello\n\n---")
        last.editor.setSelectedRange(NSRange(location: 6, length: 0))
        last.editor.deleteForward(nil)
        require(last.editor.string == "Hello\n" && last.editor.selectedRange() == NSRange(location: 6, length: 0), "⌦ above a last rule")
        // Elsewhere the keys delete one character.
        let f = make(text)
        f.editor.setSelectedRange(NSRange(location: 12, length: 0))
        f.editor.deleteBackward(nil)
        require(f.editor.string == "Hello\n\n---\nWorld", "⌫ further below deletes a line break")
        f.show(f.editor.string)
        require(hidden(f.editor) == [NSRange(location: 7, length: 3)], "and the rule stays")
        // Before the store has seen an edit, the old rule is not used.
        let stale = make(text)
        stale.editor.insertText("!", replacementRange: NSRange(location: 17, length: 0))
        stale.editor.setSelectedRange(NSRange(location: 11, length: 0))
        stale.editor.deleteBackward(nil)
        require(stale.editor.string == "Hello\n\n---\nWorld!", "a stale rule is ordinary text until the next update")
    }

    private static func hiddenFollowsTextChanges() {
        let f = make("A\n\n---")
        require(hidden(f.editor) == [NSRange(location: 3, length: 3)], "first line")
        // An external replacement (`string =`) drops rendering attributes; the same ranges are hidden again.
        f.show("X\n\n---")
        require(f.editor.string == "X\n\n---" && hidden(f.editor) == [NSRange(location: 3, length: 3)], "hidden again after replacement")
        f.show("Intro\n\nX\n\n---\n\nB\n\n---\n\nC")
        require(hidden(f.editor) == [NSRange(location: 10, length: 3), NSRange(location: 18, length: 3)], "two lines move with the text")
        require(f.editor.boundaryRules.count == 2, "two rules")
        // A user edit (not an external replacement) moves the text; the next update applies the store's ranges.
        f.editor.setSelectedRange(NSRange(location: 0, length: 0))
        f.editor.insertText("New ", replacementRange: NSRange(location: 0, length: 0))
        f.show(f.editor.string)
        require(hidden(f.editor) == [NSRange(location: 14, length: 3), NSRange(location: 22, length: 3)], "hidden after typing above")
        f.coordinator.show(f.editor.string, boundaryLines: [], in: f.editor)
        require(hidden(f.editor).isEmpty && f.editor.boundaryRules.isEmpty, "no ranges show the dashes")
        // Ranges for another text are never applied.
        f.coordinator.show("Other", boundaryLines: [NSRange(location: 0, length: 3)], in: f.editor)
        require(f.editor.string == "Other" && hidden(f.editor) == [NSRange(location: 0, length: 3)], "ranges apply to the text they came with")
        f.editor.showBoundaryLines([NSRange(location: 4, length: 9)])
        require(hidden(f.editor).isEmpty && f.editor.boundaryRules.isEmpty, "a range past the end is ignored")
        require(f.edits.values.count == 1, "replacements and hiding report no edits; typing reported one")

        // Only the hiding is removed; other rendering attributes (the system's) stay.
        let g = make("Hello\n\n---\n\nWorld")
        let layout = g.editor.textLayoutManager!, content = layout.textContentManager!
        let hello = NSTextRange(location: content.documentRange.location, end: content.location(content.documentRange.location, offsetBy: 5)!)!
        layout.addRenderingAttribute(.foregroundColor, value: NSColor.systemRed, for: hello)
        g.coordinator.show(g.editor.string, boundaryLines: [], in: g.editor)
        require(hidden(g.editor).isEmpty && colored(g.editor, .systemRed) == [NSRange(location: 0, length: 5)], "only the hiding is removed")
        g.editor.insertText("!", replacementRange: NSRange(location: 17, length: 0))
        g.show(g.editor.string)
        require(hidden(g.editor) == [NSRange(location: 7, length: 3)] && colored(g.editor, .systemRed) == [NSRange(location: 0, length: 5)],
                "a foreign rendering color survives")

        // Typing the same characters over the line drops TextKit 2's rendering attributes there, and the store, seeing the
        // same text, sends no update. The editor hides them again itself; the rule never runs through drawn dashes.
        let line = NSRange(location: 7, length: 3)
        for (replaced, with) in [(NSRange(location: 8, length: 1), "-"), (NSRange(location: 5, length: 6), "\n\n---\n"),
                                 (NSRange(location: 0, length: 17), "Hello\n\n---\n\nWorld")] {
            let h = make("Hello\n\n---\n\nWorld")
            h.editor.insertText(with, replacementRange: replaced)
            require(h.editor.string == "Hello\n\n---\n\nWorld" && hidden(h.editor) == [line] && h.editor.boundaryRules.count == 1,
                    "the same text typed over \(replaced) is hidden again without an update")
            require(maxInk(h.editor, in: segment(h.editor, line)) < 0.3, "and not drawn")
            h.show(h.editor.string)
            require(hidden(h.editor) == [line] && h.edits.values.count == 1, "and after the update")
        }
    }

    private static func compositionStaysVisible() {
        // Composing on the empty line below a rule.
        let f = make("A\n\n---\n\n")
        f.editor.setSelectedRange(NSRange(location: 8, length: 0))
        f.editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let reported = f.edits.values.count
        require(f.edits.values.last?.composing == true, "composition is reported")
        f.show(f.editor.string)
        require(f.editor.hasMarkedText() && f.editor.markedRange() == NSRange(location: 8, length: 1), "the update keeps the marked text")
        require(hidden(f.editor) == [NSRange(location: 3, length: 3)] && f.editor.boundaryRules.count == 1, "the rule stays while composing below it")
        require(maxInk(f.editor, in: segment(f.editor, NSRange(location: 8, length: 1))) > 0.6, "the marked text is drawn")
        f.editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        f.show(f.editor.string)
        require(f.editor.markedRange() == NSRange(location: 8, length: 1), "composition continues")
        f.editor.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        f.show(f.editor.string)
        require(!f.editor.hasMarkedText() && f.editor.string == "A\n\n---\n\n한", "composition commits")
        require(f.edits.values.count > reported && f.edits.values.last! == ("A\n\n---\n\n한", false), "the commit is reported")
        require(hidden(f.editor) == [NSRange(location: 3, length: 3)] && f.editor.textLayoutManager != nil, "hidden dashes and TextKit 2 remain")

        // The caret cannot reach the rule's line, so a composition never starts among or after the hidden dashes.
        let g = make("A\n\n---\n\nB")
        g.editor.setSelectedRange(NSRange(location: 2, length: 0))
        g.editor.setSelectedRange(NSRange(location: 6, length: 0))
        g.editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        require(g.editor.string == "A\n\n---\nㅎ\nB" && g.editor.markedRange() == NSRange(location: 7, length: 1),
                "the composition starts below the rule")
        require(maxInk(g.editor, in: segment(g.editor, NSRange(location: 7, length: 1))) > 0.6, "and is drawn")
    }

    private static func ruleFollowsLayout() {
        let paragraph = Array(repeating: "word", count: 40).joined(separator: " ")
        let text = paragraph + "\n\n---\n\nB"
        let line = NSRange(location: (paragraph + "\n\n").utf16.count, length: 3)
        let f = make(text, width: 320, height: 400)
        let wide = segment(f.editor, line)
        require(abs(f.editor.boundaryRules[0].midY - wide.midY) <= 1, "placed on the line")
        // A narrower pane wraps the paragraph into more lines; the rule follows the line down and keeps the full width.
        f.scroll.frame.size.width = 160
        f.scroll.layoutSubtreeIfNeeded()
        let narrow = segment(f.editor, line)
        require(narrow.midY > wide.midY + 10, "the narrow pane moves the line down")
        require(f.editor.boundaryRules.count == 1 && abs(f.editor.boundaryRules[0].midY - narrow.midY) <= 1
                && abs(f.editor.boundaryRules[0].maxX - f.containerWidth) <= 0.5
                && abs(f.containerWidth - (f.editor.bounds.width - TextPaneMetrics.scrollerGutter)) <= 0.5, "the rule follows the width")
        require(inkRows(f.editor, x: f.containerWidth - 1, around: narrow.midY) > 0, "drawn at the new place")
        require(maxInk(f.editor, in: narrow) < 0.3, "the dashes stay hidden after re-wrapping")
        // A larger font (the expanded window) moves it too.
        f.editor.font = .systemFont(ofSize: 20)
        let large = segment(f.editor, line)
        require(large.midY > narrow.midY + 10 && abs(f.editor.boundaryRules[0].midY - large.midY) <= 1, "the rule follows the font")
        require(maxInk(f.editor, in: large) < 0.3, "the dashes stay hidden in the larger font")
        // Text added above moves it.
        f.show("Intro\n\n" + text)
        let moved = segment(f.editor, NSRange(location: line.location + 7, length: 3))
        require(moved.midY > large.midY && abs(f.editor.boundaryRules[0].midY - moved.midY) <= 1, "the rule follows the text")
        require(f.editor.textLayoutManager != nil, "TextKit 2 remains")
    }

    // MARK: scroller gutter

    /// Overlay scrollers grow on hover; text and rules end before them, also while the scroller is hidden.
    private static func scrollerGutter() {
        let gutter = TextPaneMetrics.scrollerGutter
        require(gutter == 18 && NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) <= gutter,
                "the gutter holds a grown overlay scroller")
        // Words of varying width, so some lines end close to the container's edge.
        let paragraph = (1...600).map(String.init).joined(separator: " ")
        let f = make(paragraph + "\n\n---\n\nEnd", width: 300, height: 120)
        require(f.editor.bounds.width == f.scroll.contentSize.width && f.editor.bounds.width == 300, "the editor fills the pane")
        require(f.containerWidth == f.editor.bounds.width - gutter, "the text container leaves the gutter")
        // Pixels: the paragraph wraps close to the gutter but never into it, and the rule ends where the text does.
        let (rep, scale) = render(f.editor)
        let edge = Int((f.containerWidth + 0.5) * scale)
        let inGutter = (edge..<rep.pixelsWide).contains { x in
            (0..<rep.pixelsHigh).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0 }
        }
        let nearEdge = (Int((f.containerWidth - 25) * scale)..<edge).contains { x in
            (0..<rep.pixelsHigh).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.5 }
        }
        require(nearEdge && !inGutter, "lines end at the container, nothing is drawn in the gutter")
        let rule = f.editor.boundaryRules[0]
        require(abs(rule.maxX - f.containerWidth) <= 0.5 && rule.maxX <= f.editor.bounds.width - gutter + 0.5, "the rule ends before the gutter")

        // Showing or hiding the scroller never re-wraps the text.
        let end = NSRange(location: (paragraph as NSString).length + 7, length: 3)
        let before = segment(f.editor, end)
        f.scroll.hasVerticalScroller = false
        f.scroll.tile()
        f.scroll.layoutSubtreeIfNeeded()
        require(f.containerWidth == f.editor.bounds.width - gutter && segment(f.editor, end) == before, "hidden scroller: same wrapping")
        f.scroll.hasVerticalScroller = true
        f.scroll.flashScrollers()
        f.scroll.tile()
        f.scroll.layoutSubtreeIfNeeded()
        require(f.containerWidth == f.editor.bounds.width - gutter && segment(f.editor, end) == before, "shown scroller: same wrapping")

        // A new width keeps the gutter.
        f.scroll.frame.size.width = 220
        f.scroll.layoutSubtreeIfNeeded()
        require(f.editor.bounds.width == 220 && f.containerWidth == 220 - gutter
                && abs(f.editor.boundaryRules[0].maxX - f.containerWidth) <= 0.5, "the gutter follows the width")
        require(f.editor.textLayoutManager != nil, "TextKit 2 remains")
    }

    /// A legacy scroller (a mouse, or "always show scroll bars") has its own column beside the clip view, so the text
    /// and the rule run up to it without a second band. Switching back to overlay scrollers restores the gutter.
    private static func legacyScrollerTakesItsOwnColumn() {
        let gutter = TextPaneMetrics.scrollerGutter
        let f = make((1...300).map(String.init).joined(separator: " ") + "\n\n---\n\nEnd", width: 300, height: 120)
        f.scroll.scrollerStyle = .legacy
        f.scroll.tile()
        f.scroll.layoutSubtreeIfNeeded()
        require(f.editor.bounds.width < 300, "the legacy scroller narrows the clip view")
        require(f.containerWidth == f.editor.bounds.width, "no gutter next to a legacy scroller")
        require(abs(f.editor.boundaryRules[0].maxX - f.containerWidth) <= 0.5, "the rule runs up to the scroller's column")
        f.scroll.scrollerStyle = .overlay
        f.scroll.tile()
        f.scroll.layoutSubtreeIfNeeded()
        require(f.editor.bounds.width == 300 && f.containerWidth == 300 - gutter
                && abs(f.editor.boundaryRules[0].maxX - f.containerWidth) <= 0.5, "overlay scrollers get the gutter back")
        require(f.editor.textLayoutManager != nil, "TextKit 2 remains")
    }

    // MARK: ⌘↩

    private static func appendBoundaryAppendsOnly() {
        let table: [(String, String)] = [
            ("A", "A\n\n---\n\n"),
            ("A\n", "A\n\n---\n\n"),
            ("A\n\n", "A\n\n---\n\n"),
            ("A  ", "A  \n\n---\n\n"),
            ("A\n\n  ", "A\n\n  \n---\n\n"),
            ("A\n\n-", "A\n\n---\n\n"),
            ("A\n\n--", "A\n\n---\n\n"),
            ("A\n-", "A\n---\n\n"),
            ("A\n\n---", "A\n\n---\n\n"),
            ("A\n\n--- ", "A\n\n--- \n\n"),
            ("A\n\n---\n", "A\n\n---\n\n"),
            ("A\n\n---\n\n", "A\n\n---\n\n"),
            ("x = 1 | y\n\n---\n\nB", "x = 1 | y\n\n---\n\nB\n\n---\n\n"),
        ]
        for (source, expected) in table {
            let f = make(source)
            let (window, other) = keyWindow(f.scroll)
            let proxy = SourceEditorProxy(insertion: insertion)
            proxy.editor = f.editor
            _ = window.makeFirstResponder(other)
            f.editor.setSelectedRange(NSRange(location: 0, length: min(1, source.utf16.count)))
            require(proxy.validateMenuItem(proxy.makeMenuItem()), "enabled for \(source.debugDescription)")
            proxy.appendBoundary(nil)
            let end = NSRange(location: expected.utf16.count, length: 0)
            require(f.editor.string == expected && expected.hasPrefix(source), "\(source.debugDescription) → \(f.editor.string.debugDescription)")
            require(f.edits.values.count == (expected == source ? 0 : 1), "one edit, or none when nothing is appended")
            require(expected == source || f.edits.values.last! == (expected, false), "the edit carries the whole text")
            require(f.editor.selectedRange() == end && window.firstResponder === f.editor, "the cursor ends below the line in the source pane")
            f.show(f.editor.string)
            let last = (expected as NSString).range(of: "---", options: .backwards)
            require(hidden(f.editor).last == last, "the appended line is a rule once the store accepts it")
            // Pressing again changes nothing.
            proxy.appendBoundary(nil)
            require(f.editor.string == expected && f.edits.values.count == (expected == source ? 0 : 1)
                    && f.editor.selectedRange() == end, "repeated presses are idempotent")
            window.contentView = nil
        }

        // A long source scrolls to the new empty line.
        let long = (1...60).map { "문단 \($0)" }.joined(separator: "\n")
        let f = make(long, height: 120)
        let (window, _) = keyWindow(f.scroll)
        let proxy = SourceEditorProxy(insertion: insertion)
        proxy.editor = f.editor
        f.editor.scroll(.zero)
        proxy.appendBoundary(nil)
        require(f.editor.visibleRect.maxY >= f.editor.bounds.maxY - 1, "the end is scrolled into view")
        require(f.editor.textLayoutManager != nil, "appending keeps TextKit 2")
        window.contentView = nil
    }

    private static func appendBoundaryCommitsComposition() {
        let f = make("A")
        let (window, _) = keyWindow(f.scroll)
        let proxy = SourceEditorProxy(insertion: insertion)
        proxy.editor = f.editor
        _ = window.makeFirstResponder(f.editor)
        f.editor.setSelectedRange(NSRange(location: 1, length: 0))
        f.editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        require(f.edits.values.last! == ("A한", true), "composing")
        let before = f.edits.values.count
        proxy.appendBoundary(nil)
        let after = f.edits.values[before...]
        require(!f.editor.hasMarkedText() && f.editor.string == "A한\n\n---\n\n", "the composition is committed, then the line appended")
        require(after.allSatisfy { !$0.composing } && after.contains { $0 == ("A한", false) } && after.last! == ("A한\n\n---\n\n", false),
                "the commit and the append are reported, never as composing")
        require(f.editor.selectedRange() == NSRange(location: 9, length: 0), "the cursor ends below the line")
        window.contentView = nil
    }

    private static func menuItemValidation() {
        let proxy = SourceEditorProxy(insertion: insertion)
        let item = proxy.makeMenuItem()
        require(item.title == "끝에 구분선 넣기" && item.keyEquivalent == "\r" && item.keyEquivalentModifierMask == .command
                && item.target === proxy && item.action == #selector(SourceEditorProxy.appendBoundary(_:)), "⌘↩ menu item")
        require(!proxy.validateMenuItem(item), "no editor")

        let f = make("A")
        proxy.editor = f.editor
        require(!proxy.validateMenuItem(item), "an editor without a window")
        let plain = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                             styleMask: [.borderless], backing: .buffered, defer: true)
        plain.contentView = f.scroll
        require(!plain.isKeyWindow && !proxy.validateMenuItem(item), "another window is key (settings)")
        proxy.appendBoundary(nil)
        require(f.editor.string == "A" && f.edits.values.isEmpty, "a disabled action does nothing")
        plain.contentView = nil

        let (window, _) = keyWindow(f.scroll)
        require(proxy.validateMenuItem(item), "the translation window is key")
        for source in ["", "  \n", "---", "-", "\n\n---\n\n", "```\ncode", "Run:\n```bash\nls\n\n---"] {
            f.show(source)
            require(!proxy.validateMenuItem(item), "disabled for \(source.debugDescription): no content or inside an open fence")
            proxy.appendBoundary(nil)
            require(f.editor.string == source, "nothing appended to \(source.debugDescription)")
        }
        f.show("```\ncode\n```")
        require(proxy.validateMenuItem(item), "enabled after a closed fence")
        window.contentView = nil
    }

    private static func menuKeyEquivalent() {
        let f = make("A")
        let proxy = SourceEditorProxy(insertion: insertion)
        proxy.editor = f.editor
        let menu = NSMenu(title: "편집")
        menu.addItem(proxy.makeMenuItem())
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        let plain = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                             styleMask: [.borderless], backing: .buffered, defer: true)
        plain.contentView = f.scroll
        _ = menu.performKeyEquivalent(with: event)
        require(f.editor.string == "A", "⌘↩ does nothing while another window is key")
        plain.contentView = nil
        let (window, other) = keyWindow(f.scroll)
        _ = window.makeFirstResponder(other)
        require(menu.performKeyEquivalent(with: event), "⌘↩ is handled by the menu")
        require(f.editor.string == "A\n\n---\n\n" && window.firstResponder === f.editor, "⌘↩ appends from the result pane")
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        require(!menu.performKeyEquivalent(with: returnKey), "a plain return stays with the text view")
        window.contentView = nil
    }

    // MARK: helpers

    /// A key window that is never ordered front, holding the source pane and a stand-in for the result pane.
    private static func keyWindow(_ scroll: NSScrollView) -> (NSWindow, NSView) {
        let window = KeyWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 400),
                               styleMask: [.borderless], backing: .buffered, defer: true)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let other = NSTextView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        container.addSubview(scroll)
        container.addSubview(other)
        window.contentView = container
        return (window, other)
    }

    /// UTF-16 ranges whose glyphs are hidden (a clear rendering color), merged.
    private static func hidden(_ editor: NSTextView) -> [NSRange] { colored(editor, .clear) }

    private static func colored(_ editor: NSTextView, _ color: NSColor) -> [NSRange] {
        let layout = editor.textLayoutManager!, content = layout.textContentManager!
        let start = content.documentRange.location
        var ranges: [NSRange] = []
        layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            guard attributes[.foregroundColor] as? NSColor == color else { return true }
            let next = NSRange(location: content.offset(from: start, to: range.location), length: content.offset(from: range.location, to: range.endLocation))
            if let last = ranges.last, NSMaxRange(last) == next.location {
                ranges[ranges.count - 1].length += next.length
            } else {
                ranges.append(next)
            }
            return true
        }
        return ranges
    }

    /// The glyph box of a UTF-16 range, in editor coordinates.
    private static func segment(_ editor: NSTextView, _ range: NSRange) -> NSRect {
        let layout = editor.textLayoutManager!, content = layout.textContentManager!
        let start = content.location(content.documentRange.location, offsetBy: range.location)!
        let textRange = NSTextRange(location: start, end: content.location(start, offsetBy: range.length)!)!
        layout.ensureLayout(for: layout.documentRange)
        var frame: NSRect?
        layout.enumerateTextSegments(in: textRange, type: .standard, options: .rangeNotRequired) { _, rect, _, _ in
            frame = frame.map { $0.union(rect) } ?? rect
            return true
        }
        return frame!.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    }

    private static func render(_ view: NSTextView) -> (NSBitmapImageRep, CGFloat) {
        view.textLayoutManager!.ensureLayout(for: view.textLayoutManager!.documentRange)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    /// The darkest pixel in `rect`: alpha × (1 − brightness). Text is about 0.85, the separator-colored rule about 0.1,
    /// an inactive selection's light grey about 0.15.
    private static func maxInk(_ view: NSTextView, in rect: NSRect) -> CGFloat {
        let (rep, scale) = render(view)
        var best: CGFloat = 0
        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                best = max(best, color.alphaComponent * (1 - brightness))
            }
        }
        return best
    }

    /// Device rows with ink in one column within 3pt of `y` (flipped view coordinates).
    private static func inkRows(_ view: NSTextView, x: CGFloat, around y: CGFloat) -> Int {
        let (rep, scale) = render(view)
        return (Int((y - 3) * scale)..<Int((y + 3) * scale)).filter { (rep.colorAt(x: Int(x * scale), y: $0)?.alphaComponent ?? 0) > 0 }.count
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "SourceEditorTests: \(message)")
    }
}
