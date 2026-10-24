import AppKit
import Observation
import SwiftUI

/// What the result surface shows. Only an identity change with different text may
/// reset the reading position; everything else is edited in place.
struct TranslationResultContent: Equatable {
    var identity: UUID
    var text: String
    /// UTF-16 offset where the newest unit's translation begins.
    var tailStart: Int?
    var isStreaming: Bool
    var isStale: Bool
    /// How inline code and `<aN>` link tags in `text` are read.
    var inline = InlineOptions()
    /// How the source fences its code; copied plain text follows it, as the copy button does.
    var sourceFences = TranslationMarkup.FenceStyle.none
    /// UTF-16 offsets in `text` where a unit above an explicit `---` boundary ends, as for `tailStart`.
    /// A line is drawn there; nothing is added to the text, so copies and insertion never hold it.
    var unitBreaks: [Int] = []

    /// Only text after `tailStart` is a provider's draft. A finished or superseded translation shown while
    /// a request runs is read as final, so a block closed by its own last line does not disappear.
    var endsInDraft: Bool { isStreaming && !isStale && (tailStart ?? 0) < text.utf16.count }
}

enum NewContentHint: Equatable, Sendable {
    case hidden
    case arriving
    case arrived
}

/// Lets SwiftUI observe whether appended text is below the visible area and
/// scroll to it, without the scroll view writing SwiftUI state during an update.
@MainActor
@Observable
final class ResultScrollProxy {
    private(set) var hint: NewContentHint = .hidden
    @ObservationIgnored fileprivate weak var scrollView: ResultScrollView?

    func revealNewContent() {
        guard let scrollView else { return }
        TranslationResultTextView.revealNewContent(in: scrollView)
    }

    fileprivate func publish(_ hint: NewContentHint) {
        if self.hint != hint { self.hint = hint }
    }
}

/// An item the result text adds to its own right-click menu, above Look Up, Copy and Services. A SwiftUI
/// `.contextMenu` on the representable never opens over the text: AppKit hands the right click to the NSTextView,
/// which answers with its own menu. Whether the item is enabled is asked when the menu opens.
struct ResultMenuAction {
    var title: String
    var isEnabled: @MainActor () -> Bool
    var perform: @MainActor () -> Void
}

/// A single selectable text surface keeps selection across paragraph boundaries.
/// The reader's position never moves by itself: appended text only extends the
/// scroll range. Code blocks, inline code and links are styled in place: the storage holds the
/// display text without fences, backticks or link tags, so `content.text` (markdown) and the storage can differ.
struct TranslationResultTextView: NSViewRepresentable {
    var content: TranslationResultContent
    var lineSpacing: CGFloat
    var display = ResultDisplaySettings.standard
    var proxy: ResultScrollProxy?
    var menuActions: [ResultMenuAction] = []

    /// Opens a clicked link. Replaced in tests.
    @MainActor static var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Where ⌘C writes. Replaced in tests so they never touch the user's clipboard.
    @MainActor static var copyPasteboard: () -> NSPasteboard = { .general }
    /// The copy format setting ⌘C, drag and Services follow. Replaced in tests.
    @MainActor static var copyFormat: () -> ResultCopyFormat = { .load(from: .standard) }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let scroll = scroll as? ResultScrollView {
            proxy?.scrollView = scroll
            scroll.attach(proxy)
        }
        Self.setMenuActions(menuActions, in: scroll)
        Self.update(scroll, content: content, lineSpacing: lineSpacing, display: display)
    }

    @MainActor static func setMenuActions(_ actions: [ResultMenuAction], in scrollView: NSScrollView) {
        (scrollView.documentView as? ResultTextView)?.menuActions = actions
    }

    /// A `preview` (the code style picker's) shows display changes at once instead of coalescing them, and is not
    /// selectable, so it never takes the keyboard from the picker's ↑↓. Its sample links go nowhere, the source pill
    /// included; the fold footer and block copy still respond.
    @MainActor static func makeScrollView(preview: Bool = false) -> NSScrollView {
        let scroll = ResultScrollView()
        scroll.coalescesDisplay = !preview
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.setAccessibilityIdentifier(preview ? "code-style-preview-scroll" : "translation-result-scroll")
        let view = ResultTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = !preview
        view.followsLinks = !preview
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.drawsBackground = false
        // The color stays in the storage so superseded text can dim its links. The view draws underlines itself,
        // so they stop before a link's ↗ and source pill.
        view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        view.isAutomaticLinkDetectionEnabled = false
        // Folded code is laid out as nothing while its characters stay in the storage, and is not drawn.
        view.textContainer?.replaceLayoutManager(CodeFoldLayoutManager())
        view.layoutManager?.delegate = view.foldLayout
        view.setAccessibilityLabel(preview ? "코드 스타일 미리보기" : "번역 결과")
        view.setAccessibilityIdentifier(preview ? "code-style-preview-text" : "translation-result-text")
        scroll.documentView = view
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            scroll, selector: #selector(ResultScrollView.contentBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
        return scroll
    }

    /// Display settings restyle the text in place; the characters, selection and reading position stay.
    @MainActor static func update(_ scrollView: NSScrollView, content: TranslationResultContent, lineSpacing: CGFloat,
                                  display settings: ResultDisplaySettings = .standard) {
        guard let scroll = scrollView as? ResultScrollView, let view = scroll.documentView as? NSTextView,
              let storage = view.textStorage else { return }
        if scroll.applied == content, scroll.appliedLineSpacing == lineSpacing, scroll.holdsDisplay(settings) { return }
        scroll.isApplying = true
        defer { scroll.isApplying = false }

        let previous = scroll.applied
        let attributes = Self.attributes(lineSpacing: lineSpacing, stale: content.isStale)
        let resultView = view as? ResultTextView
        // Copied, hover and expanded marks belong to the text they were made on; dropped expansions fold again.
        let unfolds = previous?.identity != content.identity && resultView?.resetBlockState() == true
        let displayChanged = scroll.appliedDisplay != settings
        resultView?.display = settings
        let markup = resultView?.markup(for: content.text, streaming: content.endsInDraft, inline: content.inline)
            ?? TranslationMarkup(content.text, streaming: content.endsInDraft, inline: content.inline)
        let display = markup.displayText
        scroll.keepOffsets(for: content.text, inline: content.inline)
        let tailStart = content.tailStart.map {
            scroll.displayOffset(of: $0, in: content.text, limit: (display as NSString).length, inline: content.inline)
        }
        // NSTextStorage exposes its mutable backing string; keep a copy of the old text.
        let old = NSString(string: storage.string)
        let heightBefore = view.frame.height

        if let previous, previous.identity == content.identity || old.isEqual(to: display) {
            let anchor = topAnchor(in: scroll)
            let selection = view.selectedRanges.map(\.rangeValue)
            let new = display as NSString
            var edit: TextEdit?
            if !old.isEqual(to: display) {
                let affixes = commonAffixes(old, new)
                edit = TextEdit(location: affixes.prefix, removed: old.length - affixes.prefix - affixes.suffix,
                                inserted: new.length - affixes.prefix - affixes.suffix)
            }
            // Expanded blocks are known by where they start; text edited before one moves it, not folds it again.
            if let edit { resultView?.moveBlockState(by: edit, in: markup) }
            // A setting that would fold away the line being read or the selection leaves that block expanded, also when a
            // streamed chunk arrives with it: both are taken past the edit first.
            if displayChanged {
                let reading = selection.map { range in edit.map { shifted(range, by: $0) } ?? range }
                    + (anchor.flatMap { anchor in edit.map { shiftedOffset(anchor.character, by: $0) } ?? anchor.character }
                        .map { [NSRange(location: $0, length: 1)] } ?? [])
                resultView?.expandBlocks(newlyHiding: reading, in: markup, before: scroll.appliedDisplay)
            }
            storage.beginEditing()
            if let edit {
                let inserted = new.substring(with: NSRange(location: edit.location, length: edit.inserted))
                storage.replaceCharacters(in: NSRange(location: edit.location, length: edit.removed),
                                          with: NSAttributedString(string: inserted, attributes: attributes))
            }
            // Prose-only text keeps attributes from the insertion; code, chips and links need their ranges
            // restyled, but only from the first changed paragraph so a stream does not re-lay out everything.
            let restyleAll = previous.isStale != content.isStale || scroll.appliedLineSpacing != lineSpacing || displayChanged || unfolds
            let restyled = restyleAll || resultView?.styleChanged(markup) == true
                || (edit != nil && (markup.containsCode || markup.hasInlineStructure || markup.containsLists))
            if restyled {
                if let resultView {
                    resultView.restyle(markup, prose: attributes, stale: content.isStale,
                                       from: restyleAll ? 0 : resultView.restyleStart(for: markup, editedAt: edit?.location),
                                       changedFrom: restyleAll ? 0 : edit?.location)
                } else { storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length)) }
            }
            storage.endEditing()
            if content.isStale, !previous.isStale {
                // Superseded text can still be read, but not selected for use.
                view.setSelectedRange(NSRange(location: 0, length: 0))
            } else if let edit {
                view.selectedRanges = selection.map { NSValue(range: shifted($0, by: edit)) }
            }
            if let edit {
                scroll.pendingTail = scroll.pendingTail.flatMap { shiftedOffset($0, by: edit) }
                scroll.knownTail = scroll.knownTail.flatMap { shiftedOffset($0, by: edit) }
            }

            // A shrinking draft must not pull the reader up: keep at least the
            // visible height until the reader scrolls back into the text.
            if view.minSize.height < scroll.contentView.bounds.maxY { view.minSize.height = scroll.contentView.bounds.maxY }
            layout(view)
            var holdsPosition = true
            if let anchor {
                switch anchorTarget(anchor, after: edit, restyled: restyled, old: old, new: new) {
                case let .restore(target): restore(target, in: scroll)
                case .keep: break
                case .lost: holdsPosition = false
                }
            }
            // Keep only the height the current position still needs. Text that was
            // replaced by a different translation does not keep an empty screen.
            if let layoutManager = view.layoutManager, let container = view.textContainer {
                let used = layoutManager.usedRect(for: container).maxY + view.textContainerOrigin.y
                let bottom = scroll.contentView.bounds.maxY
                view.minSize.height = holdsPosition && bottom > used + 1 ? bottom : 0
                view.sizeToFit()
                if !holdsPosition {
                    let maxY = max(0, view.frame.height - scroll.contentView.bounds.height)
                    if scroll.contentView.bounds.minY > maxY {
                        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: maxY))
                    }
                }
            }
            if content.isStale {
                scroll.pendingTail = nil
            } else if let tail = tailStart, tail > 0, old.length > 0, !previous.isStale,
                      old.length <= tail, tail != scroll.knownTail {
                // A newly appended unit; remember the earliest one the reader has not seen.
                scroll.pendingTail = min(scroll.pendingTail ?? tail, tail)
            }
        } else {
            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: display, attributes: attributes))
            resultView?.restyle(markup, prose: attributes, stale: content.isStale)
            storage.endEditing()
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.minSize.height = 0
            layout(view)
            scroll.contentView.scroll(to: .zero)
            scroll.pendingTail = nil
        }
        // A draft or a superseded translation must not leave the app through the
        // pasteboard, drag or Services; completed text before the draft may.
        resultView?.fences = content.sourceFences
        resultView?.copyableLength = content.isStale ? 0
            : content.isStreaming ? (tailStart ?? 0) : nil
        if let resultView {
            resultView.unitBreaks = content.unitBreaks.map {
                scroll.displayOffset(of: $0, in: content.text, limit: (display as NSString).length, inline: content.inline)
            }
            resultView.refreshUnitLines()
        }
        scroll.knownTail = tailStart
        scroll.reflectScrolledClipView(scroll.contentView)
        if view.frame.height > heightBefore, view.frame.height > scroll.contentView.bounds.height {
            scroll.flashScrollers()
        }
        // Announce only the unit that was streaming, and only if it completed with text.
        if let previous, previous.isStreaming, !content.isStreaming, !content.isStale,
           let rawTail = content.tailStart, rawTail > 0, rawTail == previous.tailStart,
           let tail = tailStart, lineTop(ofFirstTextFrom: tail, in: view) != nil {
            scroll.announcementCount += 1
            NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
                .announcement: "추가 번역이 완료되었습니다", .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])
        }
        if displayChanged, previous != nil { scroll.displayChangedAt = .now }
        scroll.applied = content
        scroll.appliedLineSpacing = lineSpacing
        scroll.appliedDisplay = settings
        scroll.requestedDisplay = nil
        resultView?.refreshChromeRegions()
        scroll.refreshHint()
    }

    /// Scrolls to the start of the earliest unseen appended unit, or one page down.
    @MainActor static func revealNewContent(in scroll: ResultScrollView) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let visible = scroll.documentVisibleRect
        let maxY = max(0, view.frame.height - scroll.contentView.bounds.height)
        var target = visible.maxY - 20
        if let tail = scroll.pendingTail, let y = lineTop(ofFirstTextFrom: tail, in: view), y >= visible.maxY {
            target = y
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, target), maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    static func newContentHint(tailStartY: CGFloat?, contentHeight: CGFloat, visible: NSRect,
                               isStreaming: Bool) -> NewContentHint {
        guard let y = tailStartY else { return .hidden }
        if y >= visible.maxY { return isStreaming ? .arriving : .arrived }
        return isStreaming && contentHeight > visible.maxY + 1 ? .arriving : .hidden
    }

    /// Common prefix and suffix lengths that never split a composed character.
    static func commonAffixes(_ old: NSString, _ new: NSString) -> (prefix: Int, suffix: Int) {
        let limit = min(old.length, new.length)
        var prefix = 0
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        while true {
            var snapped = prefix
            if snapped < old.length { snapped = min(snapped, old.rangeOfComposedCharacterSequence(at: snapped).location) }
            if snapped < new.length { snapped = min(snapped, new.rangeOfComposedCharacterSequence(at: snapped).location) }
            if snapped == prefix { break }
            prefix = snapped
        }
        var suffix = 0
        while suffix < limit - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        while suffix > 0 {
            let oldStart = old.length - suffix, newStart = new.length - suffix
            if old.rangeOfComposedCharacterSequence(at: oldStart).location == oldStart,
               new.rangeOfComposedCharacterSequence(at: newStart).location == newStart { break }
            suffix -= 1
        }
        return (prefix, suffix)
    }

    struct TextEdit: Equatable {
        let location: Int
        let removed: Int
        let inserted: Int
    }

    /// Moves a range after the edit by its length change and clips a range that
    /// overlapped replaced characters to the unchanged text before them.
    static func shifted(_ range: NSRange, by edit: TextEdit) -> NSRange {
        if NSMaxRange(range) <= edit.location { return range }
        if range.location >= edit.location + edit.removed {
            return NSRange(location: range.location + edit.inserted - edit.removed, length: range.length)
        }
        let location = min(range.location, edit.location)
        return NSRange(location: location, length: edit.location - location)
    }

    /// An offset into the old text, moved past an edit, or nil when the edit replaced it.
    static func shiftedOffset(_ offset: Int, by edit: TextEdit) -> Int? {
        if offset <= edit.location { return offset }
        if offset >= edit.location + edit.removed { return offset + edit.inserted - edit.removed }
        return nil
    }

    fileprivate struct TextAnchor {
        let character: Int
        let offset: CGFloat
    }

    private enum AnchorTarget {
        case restore(TextAnchor)
        case keep
        /// The line being read was replaced by different text.
        case lost
    }

    /// Where the reader's top line should be after an edit.
    private static func anchorTarget(_ anchor: TextAnchor, after edit: TextEdit?, restyled: Bool,
                                     old: NSString, new: NSString) -> AnchorTarget {
        guard let edit else { return restyled ? .restore(anchor) : .keep }
        if anchor.character < edit.location { return restyled ? .restore(anchor) : .keep }
        if anchor.character >= edit.location + edit.removed {
            return .restore(TextAnchor(character: anchor.character + edit.inserted - edit.removed, offset: anchor.offset))
        }
        // The edit covered the line being read. If that line still exists, for
        // example because a deletion and a streamed snapshot arrived together,
        // find it again.
        let length = min(24, old.length - anchor.character)
        if length >= 8 {
            let snippet = old.substring(with: old.rangeOfComposedCharacterSequences(
                for: NSRange(location: anchor.character, length: length)))
            // The same words may repeat; prefer the match closest to where the line
            // should be, measured from the nearer end of the edit.
            let nearerEnd = edit.location + edit.removed - anchor.character < anchor.character - edit.location
            let expected = nearerEnd ? anchor.character + edit.inserted - edit.removed : anchor.character
            var best: Int?
            var search = NSRange(location: 0, length: new.length)
            while true {
                let found = new.range(of: snippet, options: [], range: search)
                guard found.location != NSNotFound else { break }
                if best.map({ abs(found.location - expected) < abs($0 - expected) }) ?? true { best = found.location }
                search = NSRange(location: found.location + 1, length: new.length - found.location - 1)
            }
            if let best { return .restore(TextAnchor(character: best, offset: anchor.offset)) }
        }
        // A deleted line continues with the text that followed it.
        if edit.inserted == 0 { return .restore(TextAnchor(character: edit.location, offset: 0)) }
        return .lost
    }

    @MainActor fileprivate static func topAnchor(in scroll: NSScrollView) -> TextAnchor? {
        guard let view = scroll.documentView as? NSTextView, let layout = view.layoutManager,
              let container = view.textContainer, (view.string as NSString).length > 0 else { return nil }
        let top = scroll.contentView.bounds.minY
        let origin = view.textContainerOrigin
        let glyph = layout.glyphIndex(for: NSPoint(x: 1, y: max(0, top - origin.y)), in: container)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return TextAnchor(character: layout.characterIndexForGlyph(at: glyph), offset: top - (line.minY + origin.y))
    }

    @MainActor fileprivate static func restore(_ anchor: TextAnchor, in scroll: NSScrollView) {
        guard let view = scroll.documentView as? NSTextView, let layout = view.layoutManager,
              anchor.character < (view.string as NSString).length else { return }
        let glyph = layout.glyphIndexForCharacter(at: anchor.character)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let maxY = max(0, view.frame.height - scroll.contentView.bounds.height)
        let y = min(max(0, line.minY + view.textContainerOrigin.y + anchor.offset), maxY)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: y))
    }

    @MainActor static func lineTop(ofFirstTextFrom offset: Int, in view: NSTextView) -> CGFloat? {
        let text = view.string as NSString
        guard offset < text.length, let layout = view.layoutManager else { return nil }
        let found = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted,
                                          range: NSRange(location: offset, length: text.length - offset))
        guard found.location != NSNotFound else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: found.location)
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + view.textContainerOrigin.y
    }

    @MainActor fileprivate static func layout(_ view: NSTextView) {
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()
    }

    private static func attributes(lineSpacing: CGFloat, stale: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: stale ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }
}

final class ResultScrollView: NSScrollView {
    /// Rapid display changes, such as stepping through styles, restyle shown text at most once per interval.
    static let displayCoalescing = Duration.milliseconds(100)

    /// Off for the style picker's preview, which follows every ↑↓ at once.
    var coalescesDisplay = true
    fileprivate(set) var applied: TranslationResultContent?
    fileprivate var appliedLineSpacing: CGFloat = 0
    fileprivate(set) var appliedDisplay = ResultDisplaySettings.standard
    /// When shown text last took new display settings.
    fileprivate var displayChangedAt: ContinuousClock.Instant?
    /// Settings held back by `holdsDisplay` until the interval ends.
    fileprivate var requestedDisplay: ResultDisplaySettings?
    private var trailingDisplay: Task<Void, Never>?
    fileprivate var isApplying = false
    /// The earliest appended unit the reader has not scrolled to yet.
    fileprivate(set) var pendingTail: Int?
    fileprivate var knownTail: Int?
    fileprivate weak var proxy: ResultScrollProxy?
    private(set) var hint: NewContentHint = .hidden
    private(set) var flashCount = 0
    fileprivate(set) var announcementCount = 0
    /// Markdown offsets converted to display offsets. Each depends only on the markdown before it and the
    /// inline options, so a streamed unit does not re-parse the units above it on every chunk.
    private var offsets: (text: String, inline: InlineOptions, display: [Int: Int]) = ("", .init(), [:])
    private(set) var offsetConversions = 0

    /// Where the lines between units are drawn, in the text view's coordinates.
    var unitLineRects: [NSRect] { (documentView as? ResultTextView)?.unitLineRects() ?? [] }

    /// Drops converted offsets whose markdown prefix or inline options changed.
    fileprivate func keepOffsets(for text: String, inline: InlineOptions) {
        guard offsets.inline == inline else { offsets = (text, inline, [:]); return }
        if !offsets.display.isEmpty, offsets.text != text {
            var common = 0
            var old = offsets.text.utf16.makeIterator(), new = text.utf16.makeIterator()
            while let a = old.next(), let b = new.next(), a == b { common += 1 }
            offsets.display = offsets.display.filter { $0.key <= common }
        }
        offsets.text = text
    }

    fileprivate func displayOffset(of rawOffset: Int, in text: String, limit: Int, inline: InlineOptions) -> Int {
        if let known = offsets.display[rawOffset] { return min(known, limit) }
        offsetConversions += 1
        let offset = TranslationMarkup.displayOffset(of: rawOffset, in: text, limit: .max, inline: inline)
        offsets.display[rawOffset] = offset
        return min(offset, limit)
    }

    override func flashScrollers() {
        flashCount += 1
        super.flashScrollers()
    }

    override func setFrameSize(_ newSize: NSSize) {
        // Re-wrapping after a size change keeps the line the reader was on.
        let anchor = newSize.width != frame.width ? TranslationResultTextView.topAnchor(in: self) : nil
        super.setFrameSize(newSize)
        guard let anchor, let view = documentView as? NSTextView else { return }
        let wasApplying = isApplying
        isApplying = true
        TranslationResultTextView.layout(view)
        TranslationResultTextView.restore(anchor, in: self)
        reflectScrolledClipView(contentView)
        isApplying = wasApplying
        (view as? ResultTextView)?.refreshChromeRegions()
        refreshHint()
    }

    /// Whether unchanged text can skip `display` for now: it is already shown, or it follows the last change within
    /// the interval and waits for the interval's end, where the newest settings win.
    fileprivate func holdsDisplay(_ display: ResultDisplaySettings) -> Bool {
        if display == appliedDisplay {
            requestedDisplay = nil
            return true
        }
        guard coalescesDisplay, let changed = displayChangedAt, ContinuousClock.now < changed + Self.displayCoalescing else { return false }
        requestedDisplay = display
        if trailingDisplay == nil {
            trailingDisplay = Task { @MainActor [weak self] in
                try? await Task.sleep(until: changed + Self.displayCoalescing, clock: .continuous)
                guard let self else { return }
                trailingDisplay = nil
                guard let content = applied, let display = requestedDisplay else { return }
                requestedDisplay = nil
                TranslationResultTextView.update(self, content: content, lineSpacing: appliedLineSpacing, display: display)
            }
        }
        return true
    }

    @objc func contentBoundsDidChange(_ notification: Notification) {
        guard !isApplying, let view = documentView as? NSTextView else { return }
        // Release the height kept for a shrunk draft once the reader is back in the text.
        if view.minSize.height > 0, let layout = view.layoutManager, let container = view.textContainer,
           documentVisibleRect.maxY <= layout.usedRect(for: container).maxY + view.textContainerOrigin.y + 1 {
            isApplying = true
            view.minSize.height = 0
            view.sizeToFit()
            isApplying = false
        }
        // The reader scrolled the start of the appended unit into view.
        if let tail = pendingTail, let y = TranslationResultTextView.lineTop(ofFirstTextFrom: tail, in: view),
           y < documentVisibleRect.maxY {
            pendingTail = nil
        }
        refreshHint()
    }

    /// A newly attached proxy starts from the current hint instead of a stale default.
    func attach(_ proxy: ResultScrollProxy?) {
        guard proxy !== self.proxy else { return }
        self.proxy = proxy
        let current = hint
        Task { @MainActor [weak proxy] in proxy?.publish(current) }
    }

    fileprivate func refreshHint() {
        guard let view = documentView as? NSTextView else { return }
        var next = NewContentHint.hidden
        if let tail = pendingTail {
            let streaming = applied?.isStreaming ?? false
            next = TranslationResultTextView.newContentHint(
                tailStartY: TranslationResultTextView.lineTop(ofFirstTextFrom: tail, in: view),
                contentHeight: view.frame.height, visible: documentVisibleRect, isStreaming: streaming
            )
            // A completed unit whose start is on screen has been seen.
            if next == .hidden, !streaming { pendingTail = nil }
        }
        guard next != hint else { return }
        hint = next
        // SwiftUI may be updating views right now; publish on the next turn.
        Task { @MainActor [weak proxy] in proxy?.publish(next) }
    }
}

final class ResultTextView: NSTextView, NSViewToolTipOwner {
    /// How long a block's copy control reads "복사됨".
    private static let copiedDuration = Duration.milliseconds(1500)

    /// Text after this UTF-16 offset may be read but not copied, dragged or sent to Services.
    /// A block's copy control is drawn by it, so a change redraws even when the text and its styles stay, as when a
    /// stream completes with the text it last showed.
    var copyableLength: Int? {
        didSet { if copyableLength != oldValue { redrawCopyControls() } }
    }
    /// The app's items in this view's right-click menu ('전체 다시 번역').
    var menuActions: [ResultMenuAction] = []
    var fences = TranslationMarkup.FenceStyle.none
    /// Display offsets where a unit above an explicit boundary ends. The line between the units is only
    /// drawn, so ⌘C, drag, Services, accessibility and find read the text as it is.
    var unitBreaks: [Int] = []
    private var unitLines: [NSRect] = []
    /// The style and behaviors the text is drawn with; `update` restyles after setting it.
    var display = ResultDisplaySettings.standard {
        didSet {
            if display.style != oldValue.style { headerWords.removeAll() }
            if display.style.pill != oldValue.style.pill { pillWidths.removeAll() }
        }
    }
    private var style: ResultStyle { display.style }
    private var parsed: (text: String, streaming: Bool, inline: InlineOptions, markup: TranslationMarkup)?
    private var styledCode: [TranslationMarkup.Block] = []
    private var styledSpans: [InlineSpan] = []
    private var styledLinks: [SourceLink] = []
    private var styledLists = TranslationLists("")
    private var adornments: [LinkAdornment] = []
    private var isStale = false {
        didSet { if isStale != oldValue { redrawCopyControls() } }
    }
    /// Each block's header words and whether they fit their room, so a stream does not measure every header on every
    /// chunk. A restyle drops the blocks from where it starts, whose characters may have changed.
    private var headerWords: [HeaderWordsKey: HeaderWords] = [:]
    /// Source pill widths by host for the current style's pill.
    private var pillWidths: [String: CGFloat] = [:]
    /// Whether the pointer was set to a pointing hand over a drawn control, to be put back when it leaves.
    private var setsPointingHand = false
    /// Off for the style picker's sample: its links open nothing, and its source pills are drawn but are not controls.
    var followsLinks = true
    /// Room for a box's padding where TextKit adds no paragraph spacing: before the first
    /// paragraph and after the last one.
    private var leadingBand: CGFloat = 0
    private var trailingBand: CGFloat = 0

    // Chrome state, keyed by block, never by position.
    private(set) var hoveredBox: CodeBlockKey?
    private(set) var hoveredControl: ResultChromeControl?
    private(set) var copiedBlock: CodeBlockKey?
    /// The link under the pointer; styles that underline on hover underline it.
    private(set) var hoveredLink: NSRange?
    private var pressedControl: ResultChromeControl?
    private var copiedReset: Task<Void, Never>?
    /// The tooltip rects over drawn controls as registered, by the tag AppKit gave each. The view owns them.
    private(set) var chromeToolTips: [(tag: NSView.ToolTipTag, rect: NSRect, text: String)] = []
    /// How many times the tooltip rects were registered again; tests check a chunk that moves nothing leaves them.
    private(set) var chromeRegistrations = 0
    /// How many boxes and link adornments were laid out; tests check the pointer and drawing look only near themselves.
    private(set) var chromeLayouts = 0
    /// How many times a change in what may be copied asked to draw the copy controls again. A window that is never
    /// shown does not draw, so tests count the requests.
    private(set) var copyControlRedraws = 0
    private var hoverArea: NSTrackingArea?

    /// Blocks the reader expanded past the fold limit, or that a setting change would have folded under them.
    private(set) var expandedBlocks: Set<CodeBlockKey> = []
    /// How each block in `styledCode` was folded by the last restyle.
    private var styledFolds: [CodeFoldPlan] = []
    private var highlights = SyntaxHighlightCache()
    /// Lines the highlighter has scanned; a streamed block rescans only its last lines.
    var highlightLinesScanned: Int { highlights.linesScanned }
    /// The prose attributes of the last restyle, so a footer click restyles without an update.
    private var lastProse: [NSAttributedString.Key: Any] = [:]
    /// Held here: the layout manager keeps its delegate weakly.
    let foldLayout = CodeFoldLayoutDelegate()

    /// What follows a link: the style's ↗ and, with 링크 출처 표시, the site pill.
    private struct LinkAdornment {
        let range: NSRange
        let host: String?
        let arrow: Bool
        let pillWidth: CGFloat
        let width: CGFloat
    }

    private struct HeaderWordsKey: Hashable {
        let range: NSRange
        let info: String
    }

    private struct HeaderWords {
        let label: String?
        /// The room's width the label was last fitted to, and whether it fit whole.
        var fitted: (width: CGFloat, whole: Bool)?
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y + leadingBand)
    }

    /// TextKit sizes the view here after every layout pass, including width changes.
    override func setConstrainedFrameSize(_ desiredSize: NSSize) {
        super.setConstrainedFrameSize(NSSize(width: desiredSize.width, height: desiredSize.height + leadingBand + trailingBand))
    }

    func markup(for text: String, streaming: Bool, inline: InlineOptions) -> TranslationMarkup {
        if let parsed, parsed.streaming == streaming, parsed.inline == inline, parsed.text == text { return parsed.markup }
        let markup = TranslationMarkup(text, streaming: streaming, inline: inline)
        parsed = (text, streaming, inline, markup)
        return markup
    }

    func styleChanged(_ markup: TranslationMarkup) -> Bool {
        markup.blocks.filter { $0.fence != nil } != styledCode || markup.spans != styledSpans || markup.links != styledLinks
            || markup.lists != styledLists
    }

    /// Forgets the copied, hover, pressed and expanded marks and the highlighter's lines, for text with a new identity.
    /// True when blocks were expanded, so the text needs restyling to fold them again.
    @discardableResult
    func resetBlockState() -> Bool {
        defer { expandedBlocks = [] }
        copiedReset?.cancel()
        copiedBlock = nil
        hoveredBox = nil
        hoveredControl = nil
        pressedControl = nil
        hoveredLink = nil
        highlights.removeAll()
        return !expandedBlocks.isEmpty
    }

    /// Moves the expanded marks past an edit of text with the same identity, so a block keeps its state when text before
    /// it changes. A block's start is matched where the edit puts it, or where it was; marks of blocks that are gone or
    /// whose first line changed are dropped.
    func moveBlockState(by edit: TranslationResultTextView.TextEdit, in markup: TranslationMarkup) {
        guard !expandedBlocks.isEmpty else { return }
        let text = markup.displayText as NSString
        let current = Set(markup.blocks.filter { $0.fence != nil && NSMaxRange($0.range) <= text.length }
            .map { CodeBlockKey(block: $0, in: text) })
        let delta = edit.inserted - edit.removed
        expandedBlocks = Set(expandedBlocks.compactMap { key in
            // The common prefix may end inside the block's first characters, so its start is tried both ways.
            let starts = key.start < edit.location ? [key.start, key.start + delta] : [key.start + delta, key.start]
            return starts.lazy.map(key.moved(to:)).first(where: current.contains)
        })
    }

    /// Expands each block whose fold under the current settings would newly hide part of `ranges`, which the settings
    /// in `before` showed: the reader's top line or the selection stays in view when 긴 코드 접기 is turned on or its
    /// limit lowered.
    func expandBlocks(newlyHiding ranges: [NSRange], in markup: TranslationMarkup, before: ResultDisplaySettings) {
        guard display.foldsLongCode else { return }
        let text = markup.displayText as NSString
        let oldLimit = before.foldsLongCode ? before.foldLineCount : nil
        for block in markup.blocks where block.fence != nil && NSMaxRange(block.range) <= text.length {
            let key = CodeBlockKey(block: block, in: text)
            guard !expandedBlocks.contains(key),
                  let hidden = CodeFold.plan(block: block.range, in: text, limit: display.foldLineCount, expanded: false).hidden else { continue }
            let shown = CodeFold.plan(block: block.range, in: text, limit: oldLimit, expanded: false).hidden?.location ?? NSMaxRange(hidden)
            let newlyHidden = NSRange(location: hidden.location, length: max(0, shown - hidden.location))
            if ranges.contains(where: { NSIntersectionRange($0, newlyHidden).length > 0 }) { expandedBlocks.insert(key) }
        }
    }

    /// Start of the paragraph before the first edited or re-laid-out code block or span. Styles before it are current.
    /// A block that only grew or shrank at its end changes style from its old last line on, so a block
    /// being streamed is not restyled from its start on every chunk.
    func restyleStart(for markup: TranslationMarkup, editedAt location: Int?) -> Int {
        let text = (textStorage?.string ?? "") as NSString
        var start = location ?? Int.max
        let code = markup.blocks.filter { $0.fence != nil }
        for index in 0..<max(code.count, styledCode.count) {
            guard index < code.count, index < styledCode.count, code[index] == styledCode[index] else {
                if index < code.count, index < styledCode.count, code[index].fence == styledCode[index].fence,
                   code[index].range.location == styledCode[index].range.location, text.length > 0 {
                    let end = min(NSMaxRange(code[index].range), NSMaxRange(styledCode[index].range), text.length)
                    start = min(start, text.paragraphRange(for: NSRange(location: max(code[index].range.location, end - 1), length: 0)).location)
                    break
                }
                if index < code.count { start = min(start, code[index].range.location) }
                if index < styledCode.count { start = min(start, styledCode[index].range.location) }
                break
            }
        }
        for index in 0..<max(markup.spans.count, styledSpans.count) {
            guard index < markup.spans.count, index < styledSpans.count, markup.spans[index] == styledSpans[index] else {
                if index < markup.spans.count { start = min(start, markup.spans[index].range.location) }
                if index < styledSpans.count { start = min(start, styledSpans[index].range.location) }
                break
            }
        }
        // A new link table changes every link's target and tooltip.
        if markup.links != styledLinks, let first = markup.spans.first(where: { $0.kind != .code }) {
            start = min(start, first.range.location)
        }
        if markup.lists != styledLists {
            for index in 0..<max(markup.lists.items.count, styledLists.items.count) {
                if index < markup.lists.items.count, index < styledLists.items.count,
                   markup.lists.items[index] == styledLists.items[index] { continue }
                if index < markup.lists.items.count { start = min(start, markup.lists.items[index].range.location) }
                if index < styledLists.items.count { start = min(start, styledLists.items[index].range.location) }
                break
            }
            for index in 0..<max(markup.lists.continuations.count, styledLists.continuations.count) {
                if index < markup.lists.continuations.count, index < styledLists.continuations.count,
                   markup.lists.continuations[index] == styledLists.continuations[index] { continue }
                if index < markup.lists.continuations.count { start = min(start, markup.lists.continuations[index].range.location) }
                if index < styledLists.continuations.count { start = min(start, styledLists.continuations[index].range.location) }
                break
            }
        }
        guard start != Int.max, text.length > 0 else { return 0 }
        return text.paragraphRange(for: NSRange(location: min(max(0, start - 1), text.length - 1), length: 0)).location
    }

    /// Re-applies prose and code attributes from `start` to `end` (by default the text's end); `end` must end a paragraph.
    /// Characters never change here, so selection holds. Text before `changedFrom` (by default `start`) is as it was at the
    /// last restyle, so its code keeps the runs it was scanned into.
    func restyle(_ markup: TranslationMarkup, prose: [NSAttributedString.Key: Any], stale: Bool, from start: Int = 0,
                 through end: Int? = nil, changedFrom: Int? = nil) {
        guard let storage = textStorage, let layoutManager else { return }
        let text = storage.string as NSString
        let start = min(start, storage.length)
        let end = max(start, min(end ?? storage.length, storage.length))
        let restyled = NSRange(location: start, length: end - start)
        func touches(_ range: NSRange) -> Bool { NSMaxRange(range) > start && range.location < end }
        let style = self.style
        let codeFont = style.code.font.nsFont
        let paragraphs = CodeParagraphs(style: style, font: codeFont, naturalLineHeight: layoutManager.defaultLineHeight(for: codeFont))
        var code: [NSAttributedString.Key: Any] = [.font: codeFont, .foregroundColor: stale ? NSColor.secondaryLabelColor : style.code.color.nsColor]
        // Superseded code keeps today's uniform dimming; a style without a palette keeps one color.
        let palette = display.colorsSyntax && !stale ? style.syntax : nil
        let limit = display.foldsLongCode ? display.foldLineCount : nil
        if let link = hoveredLink, touches(link) { hoveredLink = nil }
        lastProse = prose
        headerWords = headerWords.filter { !touches($0.key.range) }
        storage.beginEditing()
        storage.setAttributes(prose, range: restyled)
        var index = 0
        var folds: [CodeFoldPlan] = []
        for block in markup.blocks {
            guard let fence = block.fence else { continue }
            guard NSMaxRange(block.range) <= storage.length else {
                folds.append(.unfolded)
                continue
            }
            defer { index += 1 }
            let fold = CodeFold.plan(block: block.range, in: text, limit: limit, expanded: expandedBlocks.contains(CodeBlockKey(block: block, in: text)))
            folds.append(fold)
            if touches(block.range) {
                // Only the part from `start` on, a paragraph start, needs its style again. Hidden lines before it are still
                // hidden: they only fold or unfold when the start is at or before them.
                let part = NSIntersectionRange(block.range, restyled)
                code[.deepKCodeBlock] = index
                code[.deepKCodeLanguage] = fence.language
                storage.setAttributes(code, range: part)
                // Padding comes from indents and spacing on the block's first and last paragraphs.
                var location = part.location
                while location < NSMaxRange(part) {
                    let paragraph = NSIntersectionRange(text.paragraphRange(for: NSRange(location: location, length: 0)), block.range)
                    storage.addAttribute(.paragraphStyle, value: paragraphs.style(first: location == block.range.location,
                                                                                  last: NSMaxRange(paragraph) == NSMaxRange(block.range),
                                                                                  footer: fold.hasFooter),
                                         range: paragraph)
                    location = NSMaxRange(paragraph)
                }
                color(block, part: part, fold: fold, palette: palette, stale: stale, font: codeFont, changedFrom: changedFrom)
                if let hidden = fold.hidden {
                    let folded = NSIntersectionRange(hidden, part)
                    if folded.length > 0 { storage.addAttribute(.deepKCodeFolded, value: true, range: folded) }
                    if NSLocationInRange(NSMaxRange(hidden) - 1, part) {
                        storage.addAttribute(.deepKFoldSpacer, value: paragraphs.foldSpacer, range: NSRange(location: NSMaxRange(hidden) - 1, length: 1))
                    }
                }
            }
            // A blank line next to a box only needs a small gap; the full line wastes the small window.
            // It is checked even when the box itself is before `start`.
            for location in [block.range.location - 1, NSMaxRange(block.range)] where location >= 0 && location < text.length {
                let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
                if touches(paragraph), storage.attribute(.deepKCodeBlock, at: paragraph.location, effectiveRange: nil) == nil,
                   text.substring(with: paragraph).allSatisfy(\.isWhitespace) {
                    storage.addAttribute(.paragraphStyle, value: CodeParagraphs.spacer, range: paragraph)
                }
            }
        }
        // Spans never cross a line, so every span touching the restyled part starts in it.
        let chip = style.chip, chipFont = chip.font.nsFont
        let proseColor = prose[.foregroundColor] as? NSColor ?? .labelColor
        for span in markup.spans where touches(span.range) && NSMaxRange(span.range) <= storage.length {
            switch span.kind {
            case .code:
                storage.addAttributes([.font: chipFont, .deepKInlineCode: true], range: span.range)
                if !stale, let color = chip.text { storage.addAttribute(.foregroundColor, value: color.nsColor, range: span.range) }
                // Room for the chip's padding: after its last character and after the character before it.
                var neighbors = [text.rangeOfComposedCharacterSequence(at: NSMaxRange(span.range) - 1)]
                if span.range.location > 0, text.character(at: span.range.location - 1) != 0x0A {
                    neighbors.append(text.rangeOfComposedCharacterSequence(at: span.range.location - 1))
                }
                for range in neighbors { storage.addAttributes([.kern: chip.kern, .deepKChipKern: chip.kern], range: range) }
            case .link(let index):
                guard markup.links.indices.contains(index) else { continue }
                let link = markup.links[index]
                let color = stale ? NSColor.secondaryLabelColor : style.link.color?.nsColor ?? proseColor
                storage.addAttributes([.toolTip: "\(link.url.absoluteString)\n원문: \(link.text)", .foregroundColor: color], range: span.range)
                // Superseded text can be read, not used.
                if !stale, let url = markup.url(of: span) { storage.addAttribute(.link, value: url, range: span.range) }
            }
        }
        // A link's ↗ and pill are kern on its last character, on top of a chip's own kern so the chip never stretches.
        adornments = markup.spans.compactMap { adornment(for: $0, in: markup) }
        for adornment in adornments where touches(adornment.range) && NSMaxRange(adornment.range) <= storage.length {
            let last = text.rangeOfComposedCharacterSequence(at: NSMaxRange(adornment.range) - 1)
            let chipKern = storage.attribute(.deepKChipKern, at: last.location, effectiveRange: nil) as? CGFloat ?? 0
            storage.addAttribute(.kern, value: chipKern + adornment.width, range: last)
        }
        let proseFont = prose[.font] as? NSFont ?? .systemFont(ofSize: 16)
        let proseParagraph = prose[.paragraphStyle] as? NSParagraphStyle ?? .default
        for item in markup.lists.items where touches(item.range) {
            let kern = item.prefixRange.length > 0
                ? storage.attribute(.kern, at: NSMaxRange(item.prefixRange) - 1, effectiveRange: nil) as? CGFloat ?? 0 : 0
            storage.addAttribute(.paragraphStyle,
                                 value: TranslationListLayout.style(item, in: text, font: proseFont, base: proseParagraph, trailingKern: kern),
                                 range: NSIntersectionRange(item.range, restyled))
        }
        for continuation in markup.lists.continuations where touches(continuation.range) {
            let item = markup.lists.items[continuation.item]
            storage.addAttribute(.paragraphStyle,
                                 value: TranslationListLayout.continuationStyle(continuation, item: item, in: text, font: proseFont, base: proseParagraph),
                                 range: NSIntersectionRange(continuation.range, restyled))
        }
        storage.endEditing()
        if palette == nil {
            highlights.removeAll()
        } else {
            highlights.keep(blockStarts: Set(markup.blocks.filter { $0.fence != nil }.map(\.range.location)))
        }
        let spansChanged = markup.spans != styledSpans
        styledCode = markup.blocks.filter { $0.fence != nil }
        styledFolds = folds
        styledSpans = markup.spans
        styledLinks = markup.links
        styledLists = markup.lists
        isStale = stale
        let leading = markup.blocks.first?.fence == nil ? 0 : style.topPortion
        if leadingBand != leading { leadingBand = leading; invalidateTextContainerOrigin() }
        // A folded block's hidden last line holds no used height, so the band takes its spacer.
        if markup.blocks.last?.fence != nil, let fold = folds.last {
            trailingBand = fold.isFolded ? paragraphs.foldSpacer : style.bottomPortion(footer: fold.hasFooter) + style.box.margin
        } else {
            trailingBand = 0
        }
        if index > 0 || spansChanged || !markup.spans.isEmpty { needsDisplay = true }
    }

    /// Syntax colors for the lines of `part`, scanned from the block's first changed line (`SyntaxHighlightCache`), and the
    /// fade on a folded block's last shown line. Only attributes inside `part` change.
    private func color(_ block: TranslationMarkup.Block, part: NSRange, fold: CodeFoldPlan, palette: ResultStyle.SyntaxPalette?,
                       stale: Bool, font: NSFont, changedFrom: Int?) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        var faded: NSRange?
        if let opacity = style.fold.fade, let shown = fold.lastShown {
            var start = shown
            while start > block.range.location, text.character(at: start - 1) != 0x0A { start -= 1 }
            let line = NSRange(location: start, length: shown + 1 - start)
            faded = line
            let range = NSIntersectionRange(line, part)
            if range.length > 0 {
                storage.addAttribute(.foregroundColor, value: stale ? NSColor.secondaryLabelColor.withAlphaComponent(opacity)
                                     : style.code.color.faded(opacity).nsColor, range: range)
            }
        }
        guard let palette, let tag = block.fence?.language?.lowercased(), let highlighter = SyntaxHighlighter(tag: tag) else { return }
        let italic = palette.commentItalic
            ? NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize) : nil
        for token in highlights.tokens(in: text, block: block.range, tag: tag, highlighter: highlighter, from: part.location,
                                       changedFrom: changedFrom) {
            let range = NSIntersectionRange(token.range, part)
            guard range.length > 0 else { continue }
            var color = palette.color(for: token.kind)
            if let faded, let opacity = style.fold.fade, NSLocationInRange(range.location, faded) { color = color.faded(opacity) }
            storage.addAttribute(.foregroundColor, value: color.nsColor, range: range)
            if token.kind == .comment, let italic { storage.addAttribute(.font, value: italic, range: range) }
        }
    }

    /// Superseded links keep their pill, dimmed, so the text does not re-wrap when it goes stale.
    private func adornment(for span: InlineSpan, in markup: TranslationMarkup) -> LinkAdornment? {
        guard case .link = span.kind, let url = markup.url(of: span) else { return nil }
        let host = display.showsLinkSource ? ResultStyle.SourcePill.host(for: url) : nil
        let arrow = style.link.trailingArrow
        guard host != nil || arrow else { return nil }
        let pill = style.pill
        let pillWidth = host.map { host in
            if let width = pillWidths[host] { return width }
            let width = CodeBlockChrome.pillWidth(host: host, pill: pill)
            pillWidths[host] = width
            return width
        } ?? 0
        return LinkAdornment(range: span.range, host: host, arrow: arrow, pillWidth: pillWidth,
                             width: CodeBlockChrome.adornmentWidth(pillWidth: host == nil ? nil : pillWidth, arrow: arrow, style: style))
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// Boxes and chips go under the text and the selection highlight; headers and link adornments go over it.
    /// Drawn in view coordinates because layout manager drawing is clipped to the container,
    /// which excludes a leading box's band.
    override func draw(_ dirtyRect: NSRect) {
        let style = self.style, dark = isDark
        let boxes = codeBoxes(in: dirtyRect).filter { $0.geometry.box.intersects(dirtyRect) }
        for box in boxes { CodeBlockChrome.drawBox(box.geometry, style: style, dark: dark) }
        if style.chip.fill != nil || style.chip.border != nil {
            for chip in chips(in: dirtyRect) { CodeBlockChrome.drawChip(chip, chip: style.chip, dark: dark) }
        }
        // The same color and width as the line between the window's panes.
        NSColor.separatorColor.setFill()
        unitLines = unitLineRects()
        for line in unitLines where line.intersects(dirtyRect) { line.fill(using: .sourceOver) }
        // NSTextView leaves the clip narrowed to its text container, which excludes a leading box's header.
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        for box in boxes {
            CodeBlockChrome.drawHeader(box.geometry, label: headerLabel(of: box), style: style, dark: dark, copy: copyState(of: box))
            if box.fold.hasFooter {
                CodeBlockChrome.drawFooter(box.geometry, label: CodeFold.footerLabel(box.fold, style: style), folded: box.fold.isFolded,
                                           style: style, dark: dark, pressed: pressedControl == .fold(box.key))
            }
        }
        drawLinkUnderlines(in: dirtyRect, dark: dark)
        let linkColor = isStale ? NSColor.secondaryLabelColor : style.link.color?.resolved(dark: dark) ?? NSColor.labelColor
        for frame in adornmentFrames(in: dirtyRect) {
            if let arrow = frame.arrow, arrow.intersects(dirtyRect) { CodeBlockChrome.drawSymbol("arrow.up.right", in: arrow, color: linkColor) }
            if let pill = frame.pill, let host = frame.adornment.host, pill.intersects(dirtyRect) {
                CodeBlockChrome.drawPill(host: host, in: pill, pill: style.pill, dark: dark, dimmed: isStale)
            }
        }
    }

    /// Under every followable link for `.always`, under the hovered one for `.hover`. A link's last character carries its
    /// ↗ and pill as kern, which the underline leaves out.
    private func drawLinkUnderlines(in rect: NSRect, dark: Bool) {
        let underline = style.link.underline
        guard underline != .never, let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let all = NSRange(location: 0, length: storage.length)
        let visible = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        var links: [NSRange] = []
        storage.enumerateAttribute(.link, in: layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)) { value, range, _ in
            guard value != nil else { return }
            var link = NSRange()
            storage.attribute(.link, at: range.location, longestEffectiveRange: &link, in: all)
            if underline == .always || link == hoveredLink, links.last != link { links.append(link) }
        }
        ((style.link.underlineColor ?? style.link.color)?.resolved(dark: dark) ?? NSColor.labelColor).setFill()
        for link in links {
            let glyphs = layoutManager.glyphRange(forCharacterRange: link, actualCharacterRange: nil)
            let trailing = storage.attribute(.kern, at: NSMaxRange(link) - 1, effectiveRange: nil) as? CGFloat ?? 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let bounds = layoutManager.boundingRect(forGlyphRange: part, in: container)
                let width = bounds.width - (NSMaxRange(part) == NSMaxRange(glyphs) ? trailing : 0)
                let font = storage.attribute(.font, at: layoutManager.characterIndexForGlyph(at: part.location), effectiveRange: nil) as? NSFont
                    ?? .systemFont(ofSize: 16)
                let thickness = max(1, font.underlineThickness)
                let baseline = origin.y + line.minY + layoutManager.location(forGlyphAt: part.location).y
                NSBezierPath(rect: NSRect(x: origin.x + bounds.minX, y: baseline - font.underlinePosition - thickness / 2,
                                          width: max(0, width), height: thickness)).fill()
            }
        }
    }

    private func redrawCopyControls() {
        guard !styledCode.isEmpty else { return }
        needsDisplay = true
        copyControlRedraws += 1
    }

    func copyState(of box: CodeBoxLayout) -> CodeBlockChrome.CopyState {
        if style.header.copyVisibility == .hover, hoveredBox != box.key { return .hidden }
        if !isCopyable(box.block) { return .disabled }
        if copiedBlock == box.key { return .copied }
        if pressedControl == .copy(box.key) { return .pressed }
        return hoveredControl == .copy(box.key) ? .hover : .normal
    }

    /// The words in a block's header: its title, language and line count as the style shows them.
    func headerLabel(of box: CodeBoxLayout) -> String? {
        let key = HeaderWordsKey(range: box.block.range, info: box.block.fence?.info ?? "")
        if let words = headerWords[key] { return words.label }
        let text = (textStorage?.string ?? "") as NSString
        let label = CodeBlockChrome.headerLabel(title: box.title, tag: box.block.fence?.language,
                                                lineCount: CodeBlockChrome.lineCount(of: box.block.range, in: text), style: style)
        headerWords[key] = HeaderWords(label: label)
        return label
    }

    /// The whole header label when it is cut short before the copy control, as a long title is.
    func headerToolTip(of box: CodeBoxLayout) -> String? {
        guard let label = headerLabel(of: box) else { return nil }
        let key = HeaderWordsKey(range: box.block.range, info: box.block.fence?.info ?? "")
        let width = box.geometry.label.width
        if let fitted = headerWords[key]?.fitted, fitted.width == width { return fitted.whole ? nil : label }
        let whole = CodeBlockChrome.fittedLabel(label, in: box.geometry, style: style) == label
        headerWords[key]?.fitted = (width, whole)
        return whole ? nil : label
    }

    /// Every code block as laid out now, with its header geometry; with `rect`, only the boxes that may meet it.
    func codeBoxes(in rect: NSRect? = nil) -> [CodeBoxLayout] {
        guard !styledCode.isEmpty, let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return [] }
        let text = storage.string as NSString
        let origin = textContainerOrigin
        let style = self.style
        let copySize = CodeBlockChrome.copySize(for: style)
        // A box reaches past its lines by its header and bottom padding, a fold footer included, so the lines looked at
        // reach as far.
        let bottom = max(style.bottomPortion, style.bottomPortion(footer: true))
        let near = rect.map { characters(near: $0, reach: style.topPortion + bottom + style.box.margin) }
        return styledCode.enumerated().compactMap { offset, block in
            guard block.range.length > 0, NSMaxRange(block.range) <= storage.length else { return nil }
            if let near, block.range.location > NSMaxRange(near) || NSMaxRange(block.range) < near.location { return nil }
            chromeLayouts += 1
            let fold = offset < styledFolds.count ? styledFolds[offset] : .unfolded
            // A folded block ends below its last shown line; its hidden lines take no room.
            let end = fold.lastShown ?? NSMaxRange(block.range) - 1
            let first = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: block.range.location), effectiveRange: nil)
            let last = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: end), effectiveRange: nil)
            // TextKit puts the line spacing under every line but the text's last; the box ends below the glyphs either way.
            let spacing = end + 1 < storage.length
                ? (storage.attribute(.paragraphStyle, at: end, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0 : 0
            let top = origin.y + first.minY - style.topPortion
            let box = NSRect(x: origin.x, y: top, width: textContainer.size.width,
                             height: origin.y + last.maxY - spacing + style.bottomPortion(footer: fold.hasFooter) - top)
            return CodeBoxLayout(key: CodeBlockKey(block: block, in: text), block: block, number: offset + 1,
                                 geometry: CodeBlockGeometry.make(box: box, style: style, copySize: copySize, footer: fold.hasFooter), fold: fold)
        }
    }

    /// One 1pt line per break across the text container, halfway between the last text above (a box's bottom)
    /// and the first text below (a box's top). A break without text on both sides draws nothing.
    func unitLineRects() -> [NSRect] {
        guard !unitBreaks.isEmpty, let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return [] }
        let text = storage.string as NSString
        let shown = CharacterSet.whitespacesAndNewlines.inverted
        let origin = textContainerOrigin
        let boxes = codeBoxes()
        func line(of character: Int) -> NSRect {
            layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: character), effectiveRange: nil)
                .offsetBy(dx: origin.x, dy: origin.y)
        }
        /// The whole box of a code character: blank code lines at the block's ends are inside it.
        func box(of character: Int) -> NSRect? {
            boxes.first { NSLocationInRange(character, $0.block.range) }?.geometry.box
        }
        return unitBreaks.compactMap { offset in
            guard offset > 0, offset < text.length else { return nil }
            let above = text.rangeOfCharacter(from: shown, options: .backwards, range: NSRange(location: 0, length: offset)).location
            let below = text.rangeOfCharacter(from: shown, range: NSRange(location: offset, length: text.length - offset)).location
            guard above != NSNotFound, below != NSNotFound else { return nil }
            let top = box(of: above)?.maxY ?? line(of: above).maxY
            let bottom = box(of: below)?.minY ?? line(of: below).minY
            guard bottom > top else { return nil }
            let middle = (top + bottom) / 2
            return backingAlignedRect(NSRect(x: origin.x, y: middle - 0.5, width: textContainer.size.width, height: 1),
                                      options: .alignAllEdgesNearest)
        }
    }

    /// Redraws where lines were and now are; the text itself does not change for a line.
    func refreshUnitLines() {
        let lines = unitLineRects()
        guard lines != unitLines else { return }
        for line in unitLines + lines { setNeedsDisplay(line.insetBy(dx: 0, dy: -1)) }
        unitLines = lines
    }

    /// One rounded rect per line an inline code span occupies, around the glyphs and their padding.
    func chips(in rect: NSRect) -> [NSRect] {
        guard let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return [] }
        let origin = textContainerOrigin
        let visible = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        let font = style.chip.font.nsFont, pad = style.chip.padding
        var chips: [NSRect] = []
        storage.enumerateAttribute(.deepKInlineCode, in: characters) { value, range, _ in
            guard value != nil else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let bounds = layoutManager.boundingRect(forGlyphRange: part, in: container)
                let baseline = line.minY + layoutManager.location(forGlyphAt: part.location).y
                // The trailing kern is part of the last glyph's advance, with a link's ↗ and pill when the link ends here.
                let isLast = NSMaxRange(part) == NSMaxRange(glyphs)
                let kern = isLast ? storage.attribute(.kern, at: layoutManager.characterIndexForGlyph(at: NSMaxRange(part) - 1),
                                                      effectiveRange: nil) as? CGFloat ?? 0 : 0
                let minX = max(0, bounds.minX - pad)
                let maxX = bounds.maxX - kern + pad
                chips.append(NSRect(x: origin.x + minX, y: origin.y + baseline - font.ascender - 2,
                                    width: maxX - minX, height: font.ascender - font.descender + 4))
            }
        }
        return chips
    }

    /// The characters on the lines that `rect`, grown up and down by `reach`, crosses, across the text's whole width.
    private func characters(near rect: NSRect, reach: CGFloat) -> NSRange {
        guard let layoutManager, let textContainer else { return NSRange(location: 0, length: 0) }
        let origin = textContainerOrigin
        let area = NSRect(x: 0, y: rect.minY - origin.y - reach, width: textContainer.size.width, height: rect.height + 2 * reach)
        return layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(forBoundingRect: area, in: textContainer),
                                            actualGlyphRange: nil)
    }

    /// Where each link's ↗ and pill are drawn: after the glyphs of its last character, and after the chip's padding
    /// when the link ends in a chip. Only links that end on the lines `rect` crosses.
    private func adornmentFrames(in rect: NSRect) -> [(adornment: LinkAdornment, arrow: NSRect?, pill: NSRect?)] {
        guard !adornments.isEmpty, let storage = textStorage, let layoutManager, let textContainer else { return [] }
        let text = storage.string as NSString
        let origin = textContainerOrigin
        let near = characters(near: rect, reach: style.pill.height)
        return adornments.compactMap { adornment in
            guard adornment.range.length > 0, NSMaxRange(adornment.range) <= storage.length,
                  NSMaxRange(adornment.range) > near.location, NSMaxRange(adornment.range) - 1 <= NSMaxRange(near) else { return nil }
            chromeLayouts += 1
            let last = text.rangeOfComposedCharacterSequence(at: NSMaxRange(adornment.range) - 1)
            let glyphs = layoutManager.glyphRange(forCharacterRange: last, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            let kern = storage.attribute(.kern, at: last.location, effectiveRange: nil) as? CGFloat ?? 0
            // Chip padding on a link's last character is the chip's own when the link ends in one, and comes first.
            // Otherwise it is room for a chip right after the link, which comes after the ↗ and pill.
            let chipKern = storage.attribute(.deepKInlineCode, at: last.location, effectiveRange: nil) == nil ? 0
                : storage.attribute(.deepKChipKern, at: last.location, effectiveRange: nil) as? CGFloat ?? 0
            let font = storage.attribute(.font, at: last.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 16)
            let middle = origin.y + line.minY + layoutManager.location(forGlyphAt: glyphs.location).y - font.capHeight / 2
            var x = origin.x + bounds.maxX - kern + chipKern
            var arrow: NSRect?
            if adornment.arrow {
                let size = CodeBlockChrome.arrowSize
                arrow = NSRect(x: x + (CodeBlockChrome.arrowWidth - size) / 2, y: middle - size / 2, width: size, height: size)
                x += CodeBlockChrome.arrowWidth
            }
            let pill = adornment.host.map { _ in
                let pill = style.pill
                return NSRect(x: x + pill.leading, y: middle - pill.height / 2, width: adornment.pillWidth, height: pill.height)
            }
            return (adornment, arrow, pill)
        }
    }

    // MARK: - Drawn controls

    private func isCopyable(_ block: TranslationMarkup.Block) -> Bool {
        !isStale && copyableLength.map { NSMaxRange(block.range) <= $0 } ?? true
    }

    /// The control under a point: a block's copy control while its code may leave the app, a fold footer, or a link's pill.
    func chromeControl(at point: NSPoint) -> ResultChromeControl? {
        chromeControl(at: point, boxes: codeBoxes(in: NSRect(origin: point, size: .zero)))
    }

    /// `boxes` must hold every box that may contain `point`, its footer included.
    private func chromeControl(at point: NSPoint, boxes: [CodeBoxLayout]) -> ResultChromeControl? {
        if let box = boxes.first(where: { $0.geometry.copyHit.contains(point) }) {
            return isCopyable(box.block) ? .copy(box.key) : nil
        }
        if let box = boxes.first(where: { $0.geometry.footer?.contains(point) == true }) { return .fold(box.key) }
        guard !isStale, followsLinks,
              let frame = adornmentFrames(in: NSRect(origin: point, size: .zero)).first(where: { $0.pill?.contains(point) == true })
        else { return nil }
        return .pill(frame.adornment.range)
    }

    /// Runs a control: a click released over it, a VoiceOver action or a test.
    @discardableResult
    func perform(_ control: ResultChromeControl) -> Bool {
        switch control {
        case .copy(let key):
            guard let box = codeBoxes().first(where: { $0.key == key }), isCopyable(box.block), let markup = parsed?.markup else { return false }
            // The block's code as shown, without the break after its last line. A fence's indent belongs to the markdown
            // around it, such as a list item, not to the code, so it is not put back as the copy button does.
            var code = (markup.displayText as NSString).substring(with: box.block.range)
            if code.hasSuffix("\n") || code.hasSuffix("\r\n") { code.removeLast() }
            let pasteboard = TranslationResultTextView.copyPasteboard()
            pasteboard.clearContents()
            guard pasteboard.setString(code, forType: .string) else { return false }
            markCopied(key)
            NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
                .announcement: "코드를 복사했습니다", .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
            return true
        case .fold(let key):
            return toggleFold(key)
        case .pill(let range):
            guard !isStale, followsLinks, NSMaxRange(range) <= (textStorage?.length ?? 0),
                  let link = textStorage?.attribute(.link, at: range.location, effectiveRange: nil) else { return false }
            clicked(onLink: link, at: range.location)
            return true
        }
    }

    /// Folds or expands a block. The reader stays put: the block's header holds its place on screen, or, when the header is
    /// above the screen as after reading a long block to its end, the footer does. Characters, selection and streaming
    /// are untouched.
    private func toggleFold(_ key: CodeBlockKey) -> Bool {
        guard let box = codeBoxes().first(where: { $0.key == key }), box.fold.hasFooter, let markup = parsed?.markup,
              let storage = textStorage else { return false }
        let scroll = enclosingScrollView as? ResultScrollView
        let visible = scroll?.documentVisibleRect ?? visibleRect
        let holdsHeader = box.geometry.box.minY >= visible.minY
        func reference(_ box: CodeBoxLayout) -> CGFloat { holdsHeader ? box.geometry.box.minY : box.geometry.footer?.minY ?? box.geometry.box.maxY }
        let offset = reference(box) - visible.minY
        if expandedBlocks.contains(key) { expandedBlocks.remove(key) } else { expandedBlocks.insert(key) }
        let wasApplying = scroll?.isApplying ?? false
        scroll?.isApplying = true
        // Only the block and the paragraph after it, whose blank-line gap belongs to the box, change.
        let text = storage.string as NSString
        let blockEnd = NSMaxRange(box.block.range)
        let end = blockEnd < text.length ? NSMaxRange(text.paragraphRange(for: NSRange(location: blockEnd, length: 0))) : text.length
        storage.beginEditing()
        restyle(markup, prose: lastProse, stale: isStale, from: box.block.range.location, through: end, changedFrom: storage.length)
        storage.endEditing()
        minSize.height = 0
        TranslationResultTextView.layout(self)
        if let scroll, let after = codeBoxes().first(where: { $0.key == key }) {
            let maxY = max(0, frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: min(max(0, reference(after) - offset), maxY)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        scroll?.isApplying = wasApplying
        refreshChromeRegions()
        scroll?.refreshHint()
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: expandedBlocks.contains(key) ? "코드를 모두 펼쳤습니다" : "코드를 접었습니다",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        return true
    }

    private func markCopied(_ key: CodeBlockKey) {
        copiedBlock = key
        copiedReset?.cancel()
        copiedReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.copiedDuration)
            guard let self, !Task.isCancelled else { return }
            copiedBlock = nil
            needsDisplay = true
        }
        needsDisplay = true
    }

    /// Hover marks for drawn controls, for boxes that show their copy control on hover, and for links that
    /// underline on hover. Nil clears them.
    func updateHover(at point: NSPoint?) {
        let boxes = point.map { codeBoxes(in: NSRect(origin: $0, size: .zero)) } ?? []
        let box = point.flatMap { point in boxes.first { $0.geometry.box.contains(point) }?.key }
        let control = point.flatMap { chromeControl(at: $0, boxes: boxes) }
        if box != hoveredBox || control != hoveredControl {
            hoveredBox = box
            hoveredControl = control
            needsDisplay = true
        }
        let link = point.flatMap(linkRange(at:))
        if link != hoveredLink {
            hoveredLink = link
            if style.link.underline == .hover { needsDisplay = true }
        }
    }

    private func setPressed(_ control: ResultChromeControl?) {
        guard control != pressedControl else { return }
        pressedControl = control
        needsDisplay = true
    }

    /// Drawn controls have no views, so their tooltips are rects; the GitHub copy icon has no words of its own, and a
    /// header label cut short shows whole over its room. Registered again only when a rect or its words change, so a
    /// streamed chunk that moves no box leaves them.
    func refreshChromeRegions() {
        let boxes = codeBoxes()
        let tips = boxes.filter { isCopyable($0.block) }.map { (rect: $0.geometry.copyHit, text: "코드 복사") }
            + boxes.compactMap { box in headerToolTip(of: box).map { (rect: box.geometry.label, text: $0) } }
        guard !tips.elementsEqual(chromeToolTips, by: { $0.rect == $1.rect && $0.text == $1.text }) else { return }
        chromeToolTips.forEach { removeToolTip($0.tag) }
        chromeToolTips = tips.map { (tag: addToolTip($0.rect, owner: self, userData: nil), rect: $0.rect, text: $0.text) }
        chromeRegistrations += 1
    }

    /// AppKit asks for a rect's words when the pointer rests on it.
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        chromeToolTips.first { $0.tag == tag }?.text ?? ""
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // The panel is often not key, so hover is tracked whether or not the app is active.
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
    }

    /// A drawn control has no cursor rect, and the panel is often not key, so the pointing hand is set here and put back
    /// when the pointer leaves the control or the view.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        if hoveredControl != nil {
            NSCursor.pointingHand.set()
            setsPointingHand = true
        } else if setsPointingHand {
            setsPointingHand = false
            // An unselectable view, such as the style picker's sample, has no I-beam and no links to follow.
            (!isSelectable ? NSCursor.arrow : link(at: point) == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHover(at: nil)
        if setsPointingHand {
            setsPointingHand = false
            NSCursor.arrow.set()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        if let event, chromeControl(at: convert(event.locationInWindow, from: nil)) != nil { return true }
        return super.acceptsFirstMouse(for: event)
    }

    /// VoiceOver reaches each block's copy control and fold footer as actions on the text. The text itself is read whole,
    /// folded lines included.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let actions = codeBoxes().flatMap { box in
            var actions: [NSAccessibilityCustomAction] = []
            if isCopyable(box.block) {
                actions.append(NSAccessibilityCustomAction(name: box.copyActionName) { [weak self] in self?.perform(.copy(box.key)) ?? false })
            }
            if box.fold.hasFooter {
                actions.append(NSAccessibilityCustomAction(name: box.foldActionName) { [weak self] in self?.perform(.fold(box.key)) ?? false })
            }
            return actions
        }
        let inherited = super.accessibilityCustomActions() ?? []
        return inherited.isEmpty && actions.isEmpty ? nil : inherited + actions
    }

    // MARK: - Links

    private func linkCharacter(at point: NSPoint) -> Int? {
        guard let storage = textStorage, let layoutManager, let textContainer, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(local) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return storage.attribute(.link, at: character, effectiveRange: nil) == nil ? nil : character
    }

    private func link(at point: NSPoint) -> URL? {
        linkCharacter(at: point).flatMap { textStorage?.attribute(.link, at: $0, effectiveRange: nil) as? URL }
    }

    private func linkRange(at point: NSPoint) -> NSRange? {
        guard let character = linkCharacter(at: point), let storage = textStorage else { return nil }
        var range = NSRange()
        storage.attribute(.link, at: character, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
        return range
    }

    /// The window is shown without activating deepK. NSTextView already takes the first click on a
    /// link; this keeps that click, or one on a drawn control, from ordering the window or activating the app.
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return link(at: point) != nil || chromeControl(at: point) != nil || super.shouldDelayWindowOrdering(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Opening a link or copying a block from the inactive window leaves the reader's app in front.
        if let control = chromeControl(at: point) {
            if !NSApp.isActive { NSApp.preventWindowOrdering() }
            track(control)
            return
        }
        if !NSApp.isActive, link(at: point) != nil { NSApp.preventWindowOrdering() }
        super.mouseDown(with: event)
    }

    /// Follows a press until the button is released; the control runs only when released over it, and the
    /// selection is left alone.
    private func track(_ control: ResultChromeControl) {
        setPressed(control)
        while let event = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let inside = chromeControl(at: convert(event.locationInWindow, from: nil)) == control
            guard event.type == .leftMouseUp else {
                setPressed(inside ? control : nil)
                continue
            }
            setPressed(nil)
            if inside { perform(control) }
            return
        }
        setPressed(nil)
    }

    /// The URL is checked again here; nothing but an allowed web or mail link opens, and nothing from the style sample.
    override func clicked(onLink link: Any, at charIndex: Int) {
        guard followsLinks else { return }
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, SourceLink.isAllowed(url) else { return }
        TranslationResultTextView.openLink(url)
    }

    private var selectionIsCopyable: Bool {
        guard let copyableLength else { return true }
        return selectedRanges.allSatisfy { NSMaxRange($0.rangeValue) <= copyableLength }
    }

    /// A selection inside one block is plain text; one that mixes code and prose, or holds inline code or a
    /// link, carries its structure. Copy, drag and Services all write the same thing. Returns nil for a plain selection.
    private func writeStructuredSelection(to pboard: NSPasteboard) -> Bool? {
        guard let markup = parsed?.markup, selectedRanges.count == 1, markup.needsMarkdown(for: selectedRange()) else { return nil }
        return ResultClipboard.write(selection: selectedRange(), of: markup, fences: fences,
                                     format: TranslationResultTextView.copyFormat(), to: pboard)
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard selectionIsCopyable else { return false }
        return writeStructuredSelection(to: pboard) ?? super.writeSelection(to: pboard, types: types)
    }

    override func copy(_ sender: Any?) {
        guard selectionIsCopyable else { return NSSound.beep() }
        if writeStructuredSelection(to: TranslationResultTextView.copyPasteboard()) == nil { super.copy(sender) }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)), !selectionIsCopyable { return false }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Context menu

    /// The app's actions come first, then the text view's own items. The text view's menu can be a shared
    /// instance, so the items go into a copy.
    override func menu(for event: NSEvent) -> NSMenu? {
        let base = super.menu(for: event)
        guard !menuActions.isEmpty else { return base }
        let menu = (base?.copy() as? NSMenu) ?? NSMenu()
        if !menu.items.isEmpty { menu.insertItem(.separator(), at: 0) }
        for action in menuActions.reversed() { menu.insertItem(ResultMenuActionTarget.item(for: action), at: 0) }
        return menu
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Overlay scrollers grow on hover; keep line endings outside that area.
        // Reserving the space even while hidden also keeps wrapping stable.
        // A legacy scroller has its own column, so no gutter is added beside it.
        // The source pane leaves the same gutter (`TextPaneMetrics`, SourceEditor.swift).
        let width = max(0, newSize.width - TextPaneMetrics.gutter(in: enclosingScrollView))
        if textContainer?.size.width != width { textContainer?.size.width = width }
    }
}

/// Runs and validates one `ResultMenuAction`. A menu item holds its target weakly, so the item keeps it as its
/// represented object.
@MainActor private final class ResultMenuActionTarget: NSObject, NSMenuItemValidation {
    private let action: ResultMenuAction

    private init(_ action: ResultMenuAction) {
        self.action = action
    }

    static func item(for action: ResultMenuAction) -> NSMenuItem {
        let target = ResultMenuActionTarget(action)
        let item = NSMenuItem(title: action.title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }

    @objc private func run(_ sender: Any?) {
        guard action.isEnabled() else { return }
        action.perform()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        action.isEnabled()
    }
}

extension NSAttributedString.Key {
    static let deepKCodeBlock = NSAttributedString.Key("deepK.codeBlock")
    static let deepKCodeLanguage = NSAttributedString.Key("deepK.codeLanguage")
    static let deepKInlineCode = NSAttributedString.Key("deepK.inlineCode")
    /// The part of a character's kern that is chip padding; a link's ↗ and pill add to it.
    static let deepKChipKern = NSAttributedString.Key("deepK.chipKern")
}
