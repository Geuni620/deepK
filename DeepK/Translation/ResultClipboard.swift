import AppKit

enum ResultCopyFormat: String, CaseIterable, Identifiable, Sendable {
    case rich, markdown

    static let defaultsKey = "resultCopyFormat"
    var id: String { rawValue }
    var title: String { self == .rich ? "서식 포함" : "마크다운만" }
    var detail: String { self == .rich ? "코드 서식과 일반 텍스트를 함께 복사합니다" : "``` 펜스가 있는 마크다운으로 복사합니다" }

    static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .rich
    }
}

@MainActor enum ResultClipboard {
    /// The copy button. Results without code, lists or inline structure keep today's single plain string.
    /// With structure, the rich format carries it in HTML and RTF and puts `plain` on the string type
    /// for plain-text targets; the markdown format resolves link tags to `[text](url)`.
    @discardableResult
    static func write(markdown: String, plain: String, inline: InlineOptions = .init(), format: ResultCopyFormat,
                      to pasteboard: NSPasteboard) -> Bool {
        let markup = TranslationMarkup(markdown, inline: inline)
        let all = NSRange(location: 0, length: (markup.displayText as NSString).length)
        // With link tags or hidden backticks possible, the string follows what is shown, so tags the model left
        // unpaired never reach the clipboard; without them the stored markdown goes out byte for byte.
        return write(markup, range: all, rich: format == .rich && (markup.containsCode || markup.hasInlineStructure || markup.containsLists), plain: plain,
                     markdown: inline.isActive ? markup.markdown(in: all) : markdown, to: pasteboard)
    }

    /// A selection in the result view that mixes code and prose or holds inline code or a link. HTML and
    /// RTF come from the shown blocks, so nothing is lost by writing markdown and reading it back; the
    /// plain text matches the copy button.
    @discardableResult
    static func write(selection range: NSRange, of markup: TranslationMarkup, fences: TranslationMarkup.FenceStyle, format: ResultCopyFormat,
                      to pasteboard: NSPasteboard) -> Bool {
        write(markup, range: range, rich: format == .rich, plain: markup.plainText(in: range, fences: fences),
              markdown: markup.markdown(in: range), to: pasteboard)
    }

    private static func write(_ markup: TranslationMarkup, range: NSRange, rich: Bool, plain: String, markdown: String,
                              to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        if rich {
            item.setString(markup.html(in: range), forType: .html)
            if let rtf = rtf(for: markup, in: range) { item.setData(rtf, forType: .rtf) }
        }
        item.setString(rich ? plain : markdown, forType: .string)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// Prose has no font attribute, so it is written in the RTF default (Helvetica 12).
    static func rtf(for markup: TranslationMarkup, in range: NSRange? = nil) -> Data? {
        let text = NSMutableAttributedString(string: markup.displayText)
        let font = NSFont(name: "Menlo-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        for block in markup.blocks where block.fence != nil {
            text.addAttributes([.font: font, .backgroundColor: NSColor(white: 0.96, alpha: 1)], range: block.range)
        }
        for span in markup.spans {
            if span.kind == .code { text.addAttribute(.font, value: font, range: span.range) }
            if let url = markup.url(of: span) { text.addAttribute(.link, value: url, range: span.range) }
        }
        let all = NSRange(location: 0, length: text.length)
        let selection = range.map { NSIntersectionRange($0, all) } ?? all
        let selected = NSMutableAttributedString(attributedString: text.attributedSubstring(from: selection))
        applyLists(markup, selection: selection, to: selected)
        return selected.rtf(from: NSRange(location: 0, length: selected.length))
    }

    /// NSTextList writes an RTF list table. Literal prefixes must be converted to its tab/marker/tab
    /// convention, otherwise rich-text destinations would show the marker twice. Discontinuous values
    /// start another native list at that exact number because RTF has no HTML-style `li[value]`.
    private static func applyLists(_ markup: TranslationMarkup, selection: NSRange, to text: NSMutableAttributedString) {
        let selected = Set(markup.lists.items.indices.filter {
            let marker = markup.lists.items[$0].markerRange
            return selection.location <= marker.location && NSMaxRange(marker) <= NSMaxRange(selection)
                && NSIntersectionRange(markup.lists.items[$0].range, selection).length > 0
        })
        var native: [Int: [NSTextList]] = [:]
        struct Siblings: Hashable { let parent: Int?; let group: Int; let format: String }
        var siblings: [Siblings: (list: NSTextList, next: Int)] = [:]
        var replacements: [(range: NSRange, value: NSAttributedString)] = []
        func local(_ range: NSRange) -> NSRange {
            let overlap = NSIntersectionRange(range, selection)
            return NSRange(location: overlap.location - selection.location, length: overlap.length)
        }
        for index in markup.lists.items.indices where selected.contains(index) {
            let item = markup.lists.items[index]
            var parent = item.parent
            while let ancestor = parent, !selected.contains(ancestor) { parent = markup.lists.items[ancestor].parent }
            let format: String
            switch item.marker {
            case .ordered(_, let suffix): format = "{decimal}" + suffix
            case .unordered: format = "{disc}"
            }
            let number = item.marker.number ?? 1
            let key = Siblings(parent: parent, group: item.group, format: format)
            let list: NSTextList
            if let previous = siblings[key], !item.marker.isOrdered || previous.next == number {
                list = previous.list
            } else {
                list = NSTextList(markerFormat: .init(rawValue: format), options: 0)
                list.startingItemNumber = number
            }
            siblings[key] = (list, number == Int.max ? number : number + 1)
            let ancestry = (parent.flatMap { native[$0] } ?? []) + [list]
            native[index] = ancestry
            let paragraph = NSMutableParagraphStyle()
            paragraph.textLists = ancestry
            paragraph.firstLineHeadIndent = CGFloat(ancestry.count - 1) * 18
            paragraph.headIndent = CGFloat(ancestry.count) * 18
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.firstLineHeadIndent + 1),
                                  NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
            let line = local(item.range)
            text.addAttribute(.paragraphStyle, value: paragraph, range: line)
            let prefix = local(item.prefixRange)
            replacements.append((prefix, NSAttributedString(string: "\t" + list.marker(forItemNumber: number) + "\t",
                                                            attributes: [.paragraphStyle: paragraph])))
        }
        for continuation in markup.lists.continuations {
            guard let ancestry = native[continuation.item] else { continue }
            let overlap = NSIntersectionRange(continuation.range, selection)
            guard overlap.length > 0 else { continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = CGFloat(ancestry.count) * 18
            paragraph.headIndent = paragraph.firstLineHeadIndent
            text.addAttribute(.paragraphStyle, value: paragraph, range: local(overlap))
            // A continuation has no marker and must not increment the native list's counter.
            let prefix = NSRange(location: continuation.range.location, length: continuation.contentRange.location - continuation.range.location)
            if selection.location <= prefix.location, NSMaxRange(prefix) <= NSMaxRange(selection) {
                replacements.append((local(prefix), NSAttributedString(string: "")))
            }
        }
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            text.replaceCharacters(in: replacement.range, with: replacement.value)
        }
    }
}
