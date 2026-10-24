import AppKit
import SwiftUI

/// 원문·번역 두 글 창이 함께 쓰는 치수. 이 파일은 단독으로 컴파일되므로 여기에 둔다.
enum TextPaneMetrics {
    /// 글 창 오른쪽에 비워 두는 폭. overlay 스크롤바는 마우스를 올리면 굵어지므로(약 17pt) 그 아래에 글자가 오지 않게 하고,
    /// 스크롤바가 숨어 있을 때도 비워 두어 스크롤바가 나타나고 사라져도 줄바꿈이 바뀌지 않는다.
    static let scrollerGutter: CGFloat = 18

    /// 이 스크롤 뷰의 글이 오른쪽에 남길 폭. legacy 스크롤바(마우스 연결, '스크롤 막대 항상 보기')는 clip view 옆에 자기
    /// 자리를 따로 차지하므로 여백을 더 두지 않는다. 방식이 바뀌면 clip view 폭이 바뀌어 `setFrameSize`가 다시 정한다.
    @MainActor static func gutter(in scrollView: NSScrollView?) -> CGFloat {
        scrollView?.scrollerStyle == .legacy ? 0 : scrollerGutter
    }
}

/// 한글 등 IME 조합 중 번역 요청을 막기 위해 편집 내용과 조합 상태를 함께 전달한다.
struct SourceEditor: NSViewRepresentable {
    var text: String
    var fontSize: CGFloat = 13
    /// 경계로 인정된 `---` 줄의 대시(UTF-16, `text` 기준). 마크다운 가로줄처럼 대시는 숨기고 그 줄에 선 하나만 긋는다.
    /// 글자는 바꾸지 않는다.
    var boundaryLines: [NSRange] = []
    /// 어떤 글에서 경계로 인정될 `---` 줄의 대시. `---`를 다 친 순간 줄을 바꿀지 store 갱신을 기다리지 않고 정한다.
    var findBoundaryLines: (String) -> [NSRange] = { _ in [] }
    /// ⌘↩ '끝에 구분선 넣기'가 이 편집기에 덧붙이도록 연결한다.
    var proxy: SourceEditorProxy?
    var onEdit: (String, Bool) -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = Self.makeScrollView(fontSize: fontSize)
        let editor = scroll.documentView as! Editor
        editor.delegate = context.coordinator
        editor.onEscape = onEscape
        editor.findBoundaryLines = findBoundaryLines
        context.coordinator.show(text, boundaryLines: boundaryLines, in: editor)
        proxy?.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        editor.onEscape = onEscape
        editor.findBoundaryLines = findBoundaryLines
        if editor.font?.pointSize != fontSize { editor.font = .systemFont(ofSize: fontSize) }
        context.coordinator.show(text, boundaryLines: boundaryLines, in: editor)
        proxy?.editor = editor
    }

    /// 창 없이도 만들 수 있는 원문 편집기. TextKit 2를 유지하려고 `layoutManager`는 어디서도 읽지 않는다
    /// (첫 접근에서 TextKit 1로 바뀐다). 텍스트 컨테이너 폭은 `Editor.setFrameSize`가 스크롤바 여백을 빼고 정한다.
    static func makeScrollView(fontSize: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = Editor()
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.font = .systemFont(ofSize: fontSize)
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.setAccessibilityLabel("번역할 원문")
        scroll.documentView = editor
        return scroll
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        private var applyingExternalValue = false
        init(_ parent: SourceEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            reportEdit(editor)
        }
        func reportEdit(_ editor: NSTextView) {
            guard !applyingExternalValue else { return }
            parent.onEdit(editor.string, editor.hasMarkedText())
        }

        /// 바깥 원문을 넣고, 편집기의 글이 그 원문일 때만 경계 구분선을 선으로 바꾼다(범위는 그 원문 기준이다).
        func show(_ text: String, boundaryLines: [NSRange], in editor: Editor) {
            replaceTextIfNeeded(text, in: editor)
            if editor.string == text {
                editor.showListFormatting()
                editor.showBoundaryLines(boundaryLines)
            }
        }

        func replaceTextIfNeeded(_ text: String, in editor: NSTextView) {
            guard editor.string != text else { return }
            applyingExternalValue = true
            defer { applyingExternalValue = false }
            if editor.hasMarkedText() { editor.unmarkText() }
            editor.string = text
        }
    }

    final class Editor: NSTextView {
        var onEscape: (() -> Void)?
        /// `SourceEditor.findBoundaryLines`. 기본값은 아무 줄도 인정하지 않는다(줄을 바꾸지 않는다).
        var findBoundaryLines: (String) -> [NSRange] = { _ in [] }
        /// 숨긴 대시 범위와 그때의 글·판. 글이 바뀌면 rendering attribute가 옮겨지거나(`string =`이면) 사라지므로 다시 숨긴다.
        private var painted: (text: String, lines: [NSRange], revision: Int)?
        /// 저장된 글자가 바뀔 때마다 는다. 커서가 움직일 때마다 그린 선이 지금 글의 것인지 글 전체를 비교하지 않고 안다.
        private var revision = 0
        private var revisionObservation: RevisionObservation?
        /// 마우스로 커서를 놓는 중(`mouseDown` 안의 추적 루프)이면 누른 자리(뷰 좌표).
        private var mouseDownPoint: NSPoint?
        /// 마우스가 마지막 줄의 선 아래를 가리켰지만 그 아래 줄이 없었다.
        private var wantsLineBelowLastRule = false
        private var droppingText = false
        private var listFormatting: (text: String, font: NSFont, lists: TranslationLists)?
        /// AppKit can discard paragraph styles even when replacement/IME text is byte-for-byte equal.
        /// Keep the previous parsed lists so deleting their last marker can still remove stale styles.
        private var listFormattingIsDirty = false
        /// 경계 줄마다 그리는 선(뷰 좌표). 글자가 아니라서 복사·IME와 무관하다.
        private(set) var boundaryRules: [NSRect] = []

        override var font: NSFont? {
            didSet {
                showListFormatting()
                refreshBoundaryRules()
            }
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            listFormattingIsDirty = true
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            // NSTextView는 모든 조합 변경에 textDidChange를 보내지 않는다.
            // 조합 시작 전의 대기 요청을 취소할 수 있도록 직접 알린다.
            (delegate as? Coordinator)?.reportEdit(self)
        }

        override func unmarkText() {
            let wasComposing = hasMarkedText()
            if wasComposing { listFormattingIsDirty = true }
            super.unmarkText()
            showListFormatting()
            if wasComposing { (delegate as? Coordinator)?.reportEdit(self) }
        }

        /// TextKit 2는 같은 글자로 바꾼 범위의 rendering attribute도 지운다. 글이 같으면 store가 갱신을 보내지 않으므로
        /// 숨겼던 범위를 여기서 다시 숨긴다. 글이 바뀌면 다음 갱신이 새 범위로 숨긴다. 새로 친 글자에는 rendering
        /// attribute가 붙지 않으므로 숨긴 대시 사이·뒤에 친 글자와 조합 중인 글은 바로 보인다.
        override func didChangeText() {
            listFormattingIsDirty = true
            super.didChangeText()
            showListFormatting()
            guard let painted, !painted.lines.isEmpty, painted.text == string else { return }
            self.painted = nil
            showBoundaryLines(painted.lines)
        }

        /// Only paragraph layout changes: the literal markers, IME text, undo and plain copy stay intact.
        /// TextKit 2 remains active; reading `layoutManager` here would silently switch it to TextKit 1.
        func showListFormatting() {
            guard !hasMarkedText(), let font, let storage = textStorage else { return }
            let source = string
            if let current = listFormatting, current.text == source, current.font == font, !listFormattingIsDirty { return }
            let lists = listFormatting.flatMap { $0.text == source ? $0.lists : nil } ?? TranslationLists(source)
            let previous = listFormatting?.lists
            listFormatting = (source, font, lists)
            listFormattingIsDirty = false
            guard !lists.items.isEmpty || previous?.items.isEmpty == false else { return }
            let selected = selectedRanges
            let origin = enclosingScrollView?.contentView.bounds.origin
            let text = source as NSString
            let base = defaultParagraphStyle ?? .default
            storage.beginEditing()
            storage.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: storage.length))
            for item in lists.items {
                storage.addAttribute(.paragraphStyle, value: TranslationListLayout.style(item, in: text, font: font, base: base), range: item.range)
            }
            for continuation in lists.continuations {
                let style = TranslationListLayout.continuationStyle(continuation, item: lists.items[continuation.item], in: text, font: font, base: base)
                storage.addAttribute(.paragraphStyle, value: style, range: continuation.range)
            }
            storage.endEditing()
            // A new paragraph must choose its own marker instead of inheriting the preceding item's indent.
            typingAttributes[.paragraphStyle] = base
            if selectedRanges != selected { selectedRanges = selected }
            if let origin, let scroll = enclosingScrollView, scroll.contentView.bounds.origin != origin {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 && !hasMarkedText() {
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }

        // MARK: 선은 글자가 아니라 한 덩어리다
        // 마크다운 편집기의 가로줄처럼 `---`를 다 치면 선이 되고 커서는 그 아래 새 줄로 간다. 커서는 선 줄(숨긴 대시와
        // 그 줄 끝)에 놓이지 않고 건너뛰며, 선 바로 아래 줄 첫머리의 ⌫나 바로 위 줄 끝의 ⌦는 선 줄을 통째로 지운다.
        // 선은 지금 글에 그려진 것(`painted`)만 다룬다. 글이 바뀐 뒤 store 갱신 전에는 보통 글처럼 동작한다.

        override func insertText(_ string: Any, replacementRange: NSRange) {
            super.insertText(string, replacementRange: replacementRange)
            breakAfterTypedBoundary()
        }

        /// 붙여 넣기와 서비스. 끌어다 놓기도 여기를 지나지만, 놓은 글은 NSTextView가 이어서 선택하므로 줄을 바꾸지 않는다.
        override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
            let read = super.readSelection(from: pboard, type: type)
            if read, !droppingText { breakAfterTypedBoundary() }
            return read
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            droppingText = true
            defer { droppingText = false }
            return super.draggingUpdated(sender)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            droppingText = true
            defer { droppingText = false }
            return super.performDragOperation(sender)
        }

        /// 끌어다 놓을 자리(표시와 실제로 넣는 자리)가 선 줄이면, 마우스처럼 높이로 선 위 줄 끝이나 아래 줄 첫머리로 옮긴다
        /// (줄은 만들지 않는다). NSTextView는 이 자리를 셈해 둔 뒤 넣은 글을 선택하므로 놓는 동안에는 커서를 따로 옮기지 않는다.
        override func characterIndexForInsertion(at point: NSPoint) -> Int {
            let index = super.characterIndexForInsertion(at: point)
            guard droppingText, let line = ruleLines.first(where: { $0.contains(index) }), let mid = midY(of: line) else { return index }
            return caretOffRule(index, below: point.y >= mid)?.location ?? index
        }

        /// 누른 동안의 선택은 `setSelectedRanges(_:affinity:stillSelecting:)`로 여러 번 온다. 선 위에서 누르면 그 높이로
        /// 쪽을 정하고, 마지막 줄의 선 아래를 눌렀으면 손을 뗀 뒤 그 아래에 줄을 만든다.
        override func mouseDown(with event: NSEvent) {
            trackMouse(from: convert(event.locationInWindow, from: nil)) { super.mouseDown(with: event) }
        }

        /// `point`에서 누른 마우스의 추적(`track`, NSTextView의 추적 루프) 동안 선 위의 커서를 높이로 정한다.
        func trackMouse(from point: NSPoint, _ track: () -> Void) {
            mouseDownPoint = point
            wantsLineBelowLastRule = false
            track()
            mouseDownPoint = nil
            if wantsLineBelowLastRule {
                wantsLineBelowLastRule = false
                addLineBelowLastRule()
            }
        }

        /// 커서는 선 줄 밖으로 옮긴다. 선 줄 안에만 든 선택(선 위 더블클릭·오른쪽 클릭이 고르는 숨은 대시)은 커서로 보고,
        /// 끝이 선 줄 가운데에 걸친 선택은 선 줄 전체로 넓힌다. 숨은 대시 하나만 바뀌어 선이 `--`로 깨지지 않게 한다.
        override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
            var ranges = ranges, blockedBelow = false
            let lines = ranges.count == 1 && !hasMarkedText() && !droppingText ? ruleLines : []
            if !lines.isEmpty {
                var range = ranges[0].rangeValue
                if range.length > 0, lines.contains(where: { $0.start <= range.location && NSMaxRange(range) <= $0.contentsEnd }) {
                    range.length = 0
                }
                if range.length > 0 {
                    var start = range.location, end = NSMaxRange(range)
                    if let line = lines.first(where: { $0.start < start && start <= $0.contentsEnd }) { start = line.start }
                    if let line = lines.first(where: { $0.start < end && end < $0.contentsEnd }) { end = line.contentsEnd }
                    range = NSRange(location: start, length: end - start)
                } else if let moved = caretOffRule(range.location, below: headsBelow(to: range.location)) {
                    range.location = moved.location
                    blockedBelow = moved.blockedBelow
                }
                ranges = [NSValue(range: range)]
            }
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
            if mouseDownPoint != nil {
                wantsLineBelowLastRule = blockedBelow
            } else if blockedBelow, !stillSelectingFlag {
                addLineBelowLastRule()
            }
        }

        override func deleteBackward(_ sender: Any?) {
            if !deleteRule(backward: true) { super.deleteBackward(sender) }
        }

        override func deleteWordBackward(_ sender: Any?) {
            if !deleteRule(backward: true) { super.deleteWordBackward(sender) }
        }

        override func deleteToBeginningOfLine(_ sender: Any?) {
            if !deleteRule(backward: true) { super.deleteToBeginningOfLine(sender) }
        }

        override func deleteForward(_ sender: Any?) {
            if !deleteRule(backward: false) { super.deleteForward(sender) }
        }

        override func deleteWordForward(_ sender: Any?) {
            if !deleteRule(backward: false) { super.deleteWordForward(sender) }
        }

        /// 경계가 될 줄을 다 친(붙여 넣은) 직후, 커서가 대시 뒤에 있고 그 뒤로 줄 끝까지 공백뿐이면 줄 끝에서 줄을 바꾼다
        /// (↩와 같다). 노션처럼 세 번째 대시에서 바로 바꾸므로 `----`·`---x`를 이어 치면 네 번째 글자부터 다음 줄에 쓰인다.
        /// 대시 사이에서 친 대시, 있던 선의 대시를 다시 친 경우, 조합 중인 글에는 하지 않는다. 문서 전체를 읽는 경계 판정은
        /// 줄이 `---` 모양일 때만 부른다(목록 `- 항목`을 칠 때마다 부르지 않는다).
        private func breakAfterTypedBoundary() {
            guard !hasMarkedText(), selectedRanges.count == 1 else { return }
            let caret = selectedRange(), text = string as NSString
            guard caret.length == 0 else { return }
            var start = 0, contentsEnd = 0
            text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: caret)
            var dashEnd = start
            while dashEnd < contentsEnd, text.character(at: dashEnd) == 0x2D { dashEnd += 1 }
            guard dashEnd - start >= 3, dashEnd <= caret.location,
                  Self.isSpaces(text.substring(with: NSRange(location: dashEnd, length: contentsEnd - dashEnd))),
                  findBoundaryLines(string).contains(where: { $0.location == start })
            else { return }
            if caret.location != contentsEnd { setSelectedRange(NSRange(location: contentsEnd, length: 0)) }
            insertNewline(nil)
        }

        private static func isSpaces(_ text: String) -> Bool {
            text.allSatisfy { $0.isWhitespace && !$0.isNewline }
        }

        /// 그려진 선 하나의 줄. `start…contentsEnd`가 커서가 놓이지 않는 자리이고, `end`는 줄바꿈 뒤다(마지막 줄이면
        /// `contentsEnd`와 같다).
        private struct RuleLine {
            let dashes: NSRange
            let start: Int, contentsEnd: Int, end: Int
            var hasLineBreak: Bool { end > contentsEnd }
            var whole: NSRange { NSRange(location: start, length: end - start) }
            func contains(_ offset: Int) -> Bool { start <= offset && offset <= contentsEnd }
        }

        /// 지금 글에 그려진 선 줄. NSString은 U+000B·U+000C를 줄바꿈으로 보지 않으므로 그런 글에서는 줄이 선보다 넓다.
        /// 줄이 대시로 시작해 공백으로 끝나는 선만 덩어리로 다룬다(나머지는 그려지기만 한다).
        private var ruleLines: [RuleLine] {
            guard let painted, !painted.lines.isEmpty, painted.revision == revision else { return [] }
            let text = string as NSString
            return painted.lines.compactMap { dashes in
                guard NSMaxRange(dashes) <= text.length else { return nil }
                var start = 0, end = 0, contentsEnd = 0
                text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: dashes)
                guard start == dashes.location, contentsEnd >= NSMaxRange(dashes),
                      Self.isSpaces(text.substring(with: NSRange(location: NSMaxRange(dashes), length: contentsEnd - NSMaxRange(dashes))))
                else { return nil }
                return RuleLine(dashes: dashes, start: start, contentsEnd: contentsEnd, end: end)
            }
        }

        /// 선 줄에 놓이려는 커서가 선 아래로 가는 중인지. 마우스는 지금(끌기·떼기 중이면 그 자리, 아니면 누른 자리) 높이가
        /// 선의 가운데 아래인지로, 그 밖(키보드 등)은 이전 선택과 비교한 방향으로 정한다. 선택을 ←로 접으면 그 시작으로
        /// 오므로 위로 간다.
        private func headsBelow(to location: Int) -> Bool {
            if var point = mouseDownPoint, let line = ruleLines.first(where: { $0.contains(location) }), let mid = midY(of: line) {
                if let event = NSApp.currentEvent, event.window === window, [.leftMouseDragged, .leftMouseUp].contains(event.type) {
                    point = convert(event.locationInWindow, from: nil)
                }
                return point.y >= mid
            }
            let previous = selectedRange()
            return previous.length > 0 ? location > previous.location : location >= previous.location
        }

        /// 선 줄에 놓이려는 커서를 옮길 자리. 아래로 가던 커서는 선 아래 줄 첫머리로, 위로 가던 커서는 선 위 줄 끝으로
        /// 간다(연달은 선은 한꺼번에 건넌다). 그쪽에 줄이 없으면 반대쪽으로 가고, 아래가 막혔으면 `blockedBelow`. 선
        /// 줄이 아니면 nil.
        private func caretOffRule(_ location: Int, below: Bool) -> (location: Int, blockedBelow: Bool)? {
            let lines = ruleLines
            guard lines.contains(where: { $0.contains(location) }) else { return nil }
            let text = string as NSString
            var down: Int? = location, up: Int? = location
            while let offset = down, let line = lines.first(where: { $0.contains(offset) }) {
                down = line.hasLineBreak ? line.end : nil
            }
            while let offset = up, let line = lines.first(where: { $0.contains(offset) }) {
                guard line.start > 0 else { up = nil; break }
                var contentsEnd = 0
                text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: line.start - 1, length: 0))
                up = contentsEnd
            }
            if below {
                if let down { return (down, false) }
                return up.map { ($0, true) }
            }
            if let up { return (up, false) }
            return down.map { ($0, false) }
        }

        /// 선 줄의 세로 가운데(뷰 좌표).
        private func midY(of line: RuleLine) -> CGFloat? {
            guard let range = textRange(line.dashes), let frame = lineFrame(range) else { return nil }
            return textContainerOrigin.y + frame.midY
        }

        /// 마지막 줄의 선 아래로 가려 하면(↓·→·선 아래쪽 클릭) 원문 끝에 줄바꿈 하나를 덧붙이고 커서를 그 줄에 둔다.
        private func addLineBelowLastRule() {
            let end = (string as NSString).length
            guard !hasMarkedText(), let last = ruleLines.last, !last.hasLineBreak, last.end == end,
                  shouldChangeText(in: NSRange(location: end, length: 0), replacementString: "\n") else { return }
            textStorage?.replaceCharacters(in: NSRange(location: end, length: 0), with: "\n")
            didChangeText()
            setSelectedRange(NSRange(location: end + 1, length: 0))
            scrollRangeToVisible(selectedRange())
        }

        /// 선 바로 아래 줄 첫머리의 ⌫, 바로 위 줄 끝의 ⌦는 선 줄과 줄바꿈 하나를 지운다. 지웠으면 true.
        private func deleteRule(backward: Bool) -> Bool {
            guard !hasMarkedText(), selectedRanges.count == 1, selectedRange().length == 0 else { return false }
            let caret = selectedRange().location, text = string as NSString
            let target: NSRange? = ruleLines.lazy.compactMap { line -> NSRange? in
                if backward { return line.hasLineBreak && line.end == caret ? line.whole : nil }
                guard line.start > 0 else { return nil }
                var above = 0
                text.getLineStart(nil, end: nil, contentsEnd: &above, for: NSRange(location: line.start - 1, length: 0))
                guard above == caret else { return nil }
                // 마지막 줄의 선은 그 앞 줄바꿈과 함께 지운다.
                return line.hasLineBreak ? line.whole : NSRange(location: caret, length: line.end - caret)
            }.first
            guard let target else { return false }
            guard shouldChangeText(in: target, replacementString: "") else { return true }
            textStorage?.replaceCharacters(in: target, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: backward ? target.location : caret, length: 0))
            return true
        }

        /// 경계 구분선의 대시를 투명하게 그리고(마크다운 가로줄처럼 선만 보인다) 선 위치를 다시 구한다. 커서가 그 줄에
        /// 있으면 줄 밖으로 옮긴다(밖에서 바뀐 글, 늦게 인정된 줄). 경계가 아니게 되면 다음 갱신에서 보통 글로 돌아온다.
        /// TextKit 2 rendering attribute라 저장된 글·속성, 조합 중인 글, 복사는 그대로다. 지금 글 밖의 범위는 다루지 않는다.
        func showBoundaryLines(_ lines: [NSRange]) {
            let text = string
            // 같은 글로 되돌아온 편집 뒤에도 그린 범위는 이 글의 것이다.
            guard painted?.text != text || painted?.lines != lines else { painted?.revision = revision; return }
            let previous = painted?.lines ?? []
            if !lines.isEmpty, revisionObservation == nil, let storage = textStorage {
                revisionObservation = RevisionObservation(storage) { [weak self] in self?.revision += 1 }
            }
            painted = (text, lines, revision)
            // 숨긴 적도 숨길 것도 없으면(구분선 없는 보통 타이핑) rendering attribute를 건드리지 않는다.
            guard !previous.isEmpty || !lines.isEmpty, let layout = textLayoutManager else { return }
            // 숨긴 표시만 지운다. 시스템이 쓰는 다른 rendering attribute는 건드리지 않는다.
            var stale: [NSTextRange] = []
            layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attributes, range in
                if attributes[.deepKBoundaryLine] != nil { stale.append(range) }
                return true
            }
            for range in stale {
                layout.removeRenderingAttribute(.foregroundColor, for: range)
                layout.removeRenderingAttribute(.deepKBoundaryLine, for: range)
            }
            let length = (text as NSString).length
            for line in lines where NSMaxRange(line) <= length {
                guard let range = textRange(line) else { continue }
                layout.addRenderingAttribute(.foregroundColor, value: NSColor.clear, for: range)
                layout.addRenderingAttribute(.deepKBoundaryLine, value: true, for: range)
            }
            refreshBoundaryRules()
            let caret = selectedRange()
            if !hasMarkedText(), selectedRanges.count == 1, caret.length == 0,
               let moved = caretOffRule(caret.location, below: true) {
                // 갱신 중이므로 글을 바꾸지 않는다(아래가 막혀도 줄을 만들지 않고 위로 간다).
                setSelectedRange(NSRange(location: moved.location, length: 0))
            }
        }

        /// ⌘↩ '끝에 구분선 넣기'. 조합 중인 글을 확정한 뒤 끝에 덧붙이기만 한다. 앞 글자를 지우거나 바꾸면 번역 중인
        /// 꼬리의 원문 prefix가 깨져 그 요청이 취소된다. 커서는 끝(구분선 아래 빈 줄)에 둔다.
        func appendBoundary(_ insertion: (String) -> String?) {
            window?.makeFirstResponder(self)
            if hasMarkedText() {
                unmarkText()
                inputContext?.discardMarkedText()
            }
            guard let addition = insertion(string) else { return }
            let end = NSRange(location: (string as NSString).length, length: 0)
            // 타이핑(insertText)과 달리 자동 맞춤법 교정이 앞 단어를 고치지 않는다.
            if !addition.isEmpty, shouldChangeText(in: end, replacementString: addition) {
                textStorage?.replaceCharacters(in: end, with: addition)
                didChangeText()
            }
            let caret = NSRange(location: (string as NSString).length, length: 0)
            setSelectedRange(caret)
            scrollRangeToVisible(caret)
        }

        /// 번역 창(`ResultTextView`)과 같이 오른쪽에 스크롤바 여백을 남기고 줄을 바꾼다. 숨은 스크롤바에도 남겨
        /// 스크롤바가 나타나고 사라져도 줄바꿈이 그대로다. legacy 스크롤바 옆에는 남기지 않는다.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            let gutter = TextPaneMetrics.gutter(in: enclosingScrollView)
            let width = max(0, newSize.width - 2 * textContainerInset.width - gutter)
            guard let container = textContainer, container.size.width != width else { return }
            container.size.width = width
            refreshBoundaryRules()
        }

        override func drawBackground(in rect: NSRect) {
            super.drawBackground(in: rect)
            let rules = boundaryRules.filter { $0.intersects(rect) }
            guard !rules.isEmpty else { return }
            NSColor.separatorColor.setFill()
            for rule in rules { rule.fill(using: .sourceOver) }
        }

        /// 줄 위치는 배치에서 구한다. 바뀐 선의 이전·새 자리만 다시 그린다. 선은 글자 조각 아래(배경)에 그린다.
        private func refreshBoundaryRules() {
            let rules = makeBoundaryRules()
            guard rules != boundaryRules else { return }
            for rule in boundaryRules + rules { setNeedsDisplay(rule) }
            boundaryRules = rules
        }

        /// 마크다운 가로줄: 텍스트 컨테이너 폭 전체(글의 왼쪽 끝부터 스크롤바 여백 앞까지), 그 줄 가운데에 1pt 선.
        /// 번역 창의 단위 사이 선과 같은 색·두께다.
        private func makeBoundaryRules() -> [NSRect] {
            guard let lines = painted?.lines, !lines.isEmpty, let layout = textLayoutManager,
                  let width = textContainer?.size.width, width >= 1 else { return [] }
            let length = (string as NSString).length
            let ranges = lines.filter { NSMaxRange($0) <= length }.compactMap(textRange)
            guard let last = ranges.last,
                  let through = NSTextRange(location: layout.documentRange.location, end: last.endLocation) else { return [] }
            // 앞 글의 배치가 추정값이면 줄 위치가 틀린다. 마지막 선까지 실제로 배치한다.
            layout.ensureLayout(for: through)
            let origin = textContainerOrigin
            return ranges.compactMap { range in
                guard let line = lineFrame(range) else { return nil }
                return backingAlignedRect(NSRect(x: origin.x, y: origin.y + line.midY - 0.5, width: width, height: 1),
                                          options: .alignAllEdgesNearest)
            }
        }

        /// 대시가 차지한 줄 조각(아주 긴 대시가 여러 줄로 감기면 그 묶음). 텍스트 컨테이너 좌표.
        private func lineFrame(_ range: NSTextRange) -> CGRect? {
            var line: CGRect?
            textLayoutManager?.enumerateTextSegments(in: range, type: .standard, options: .rangeNotRequired) { _, frame, _, _ in
                line = line.map { $0.union(frame) } ?? frame
                return true
            }
            return line
        }

        private func textRange(_ range: NSRange) -> NSTextRange? {
            guard let content = textLayoutManager?.textContentManager,
                  let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length) else { return nil }
            return NSTextRange(location: start, end: end)
        }
    }
}

/// Shared hanging indents for source and result. Keeping markers as literal text makes every plain
/// destination retain them; only wrapped visual lines move to the start of the item's body.
@MainActor enum TranslationListLayout {
    static func style(_ item: TranslationLists.Item, in text: NSString, font: NSFont, base: NSParagraphStyle,
                      trailingKern: CGFloat = 0) -> NSParagraphStyle {
        let style = base.mutableCopy() as! NSMutableParagraphStyle
        let width = text.substring(with: item.prefixRange).size(withAttributes: [.font: font, .paragraphStyle: base]).width
        style.headIndent = style.firstLineHeadIndent + width + trailingKern
        return style
    }

    static func continuationStyle(_ continuation: TranslationLists.Continuation, item: TranslationLists.Item,
                                  in text: NSString, font: NSFont, base: NSParagraphStyle) -> NSParagraphStyle {
        let paragraph = style(item, in: text, font: font, base: base).mutableCopy() as! NSMutableParagraphStyle
        let prefix = NSRange(location: continuation.range.location, length: continuation.contentRange.location - continuation.range.location)
        paragraph.firstLineHeadIndent = paragraph.headIndent - text.substring(with: prefix).size(withAttributes: [.font: font, .paragraphStyle: base]).width
        return paragraph
    }
}

/// 글자 편집마다 알린다. 편집기와 함께 사라지며 등록을 지운다.
private final class RevisionObservation {
    private let token: NSObjectProtocol

    init(_ storage: NSTextStorage, onEdit: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage,
                                                       queue: nil) { note in
            guard (note.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) == true else { return }
            MainActor.assumeIsolated { onEdit() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}

private extension NSAttributedString.Key {
    /// 원문 창이 경계 대시를 숨겼다는 표시(rendering attribute). 되돌릴 때 이것만 찾는다.
    static let deepKBoundaryLine = NSAttributedString.Key("deepKBoundaryLine")
}

/// ⌘↩ '끝에 구분선 넣기'의 메뉴 target(편집 메뉴). 번역 창이 key이면 포커스가 결과 창에 있어도 원문 끝에
/// 덧붙인다. 무엇을 덧붙일지는 경계 규칙을 아는 쪽이 정한다. 이 파일은 IME 픽스처와 단독으로 컴파일된다.
@MainActor final class SourceEditorProxy: NSObject, NSMenuItemValidation {
    weak var editor: SourceEditor.Editor?
    /// 원문 끝에 덧붙일 글. nil이면 넣을 수 없다(내용 없음, 열린 펜스 안).
    private let insertion: (String) -> String?

    init(insertion: @escaping (String) -> String?) {
        self.insertion = insertion
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "끝에 구분선 넣기", action: #selector(appendBoundary(_:)), keyEquivalent: "\r")
        item.keyEquivalentModifierMask = .command
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { target != nil }

    @objc func appendBoundary(_ sender: Any?) {
        target?.appendBoundary(insertion)
    }

    /// 편집기가 없거나, 번역 창이 key가 아니거나(설정 창 등), 덧붙일 수 없으면 nil이다.
    private var target: SourceEditor.Editor? {
        guard let editor, editor.window?.isKeyWindow == true, insertion(editor.string) != nil else { return nil }
        return editor
    }
}
