import Foundation

/// A link captured from the copied page. The model only sees its number; the URL stays in the app.
public struct SourceLink: Hashable, Sendable {
    public let url: URL
    public let text: String

    /// Only web and mail links open; checked at capture, render and click.
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.absoluteString.utf16.count <= 2048 else { return false }
        if scheme == "mailto" { return true }
        guard scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return false }
        return url.user == nil && url.password == nil
    }
}

/// A `<pre>` block of a copied page that the app fenced in the model input. `code` is the exact text
/// of its lines in the cleaned plain text, so the result's block can be checked against it byte for byte.
public struct SourceCodeBlock: Hashable, Sendable {
    /// The page's language as a fence tag `TranslationMarkup` reads as a tag at once; nil for a bare fence.
    public let language: String?
    /// Whole lines joined by "\n", without a final line break; never blank.
    public let code: String
    /// The selected tab the page showed above the code ("Most Agents"), never translated. The plain text has it as
    /// a line of its own right above the code; the opener carries it instead (```text title="Most Agents"`).
    public let title: String?
    /// Backticks of its fences: more than any run inside the code, so no code line can close it.
    public let fence: Int

    /// A `title` the opener cannot carry as written is dropped.
    public init(language: String?, code: String, title: String? = nil) {
        self.language = language
        self.code = code
        self.title = title.flatMap(Self.title)
        var longest = 0, run = 0
        for scalar in code.unicodeScalars {
            run = scalar == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        fence = max(3, longest + 1)
    }

    /// A tab label as a title: trimmed, each run of whitespace one space, and at most 40 characters. A label with a
    /// line break, a control character, a backtick or both kinds of quote cannot be quoted in an opener, so it is none.
    static func title(_ label: String) -> String? {
        guard !label.contains(where: \.isNewline), !label.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        let title = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (1...40).contains(title.count), !title.contains("`"), !(title.contains("\"") && title.contains("'")) else { return nil }
        return title
    }

    var lines: [String] { code.components(separatedBy: "\n") }
    /// The language, or `text` for a titled block without one; `language` stays nil there, only the fence says text.
    var tag: String? { language ?? title.map { _ in "text" } }
    /// The tag, then the title in double quotes, or single ones when it has a double quote.
    var info: String {
        guard let title, let tag else { return language ?? "" }
        let quote = title.contains("\"") ? "'" : "\""
        return tag + " title=" + quote + title + quote
    }
    var opener: String { String(repeating: "`", count: fence) + info }
    var closer: String { String(repeating: "`", count: fence) }
}

/// Links, inline code and code blocks from a copied page, written into the plain text as `<aN>` tags,
/// backticks and fences.
public struct SourceMarkup: Hashable, Sendable {
    public let text: String
    public let links: [SourceLink]
    public let code: Set<String>
    /// Fenced in `text` in this order.
    public let blocks: [SourceCodeBlock]

    public init(text: String, links: [SourceLink], code: Set<String>, blocks: [SourceCodeBlock] = []) {
        self.text = text
        self.links = links
        self.code = code
        self.blocks = blocks
    }

    /// Links or chips, which the model is told about; app fences need no instructions.
    var hasInlineStructure: Bool { !links.isEmpty || !code.isEmpty }
    var inlineOptions: InlineOptions { InlineOptions(code: code.isEmpty ? .off : .only(code), links: links) }
}

/// What a double copy captured. `plain` is the copy with the page's controls removed (tab labels but the
/// selected one above its code, copy buttons, line numbers); it is the identity everywhere. `markup` only goes
/// to the model. `raw` and `removed` are diagnostics and take no part in equality.
public struct CapturedSource: Equatable, Sendable {
    public let plain: String
    public let markup: SourceMarkup?
    /// The copied text before cleaning.
    public let raw: String
    /// UTF-16 ranges of `raw` that cleaning removed: one per removed line, with its line break, or line edge.
    public let removed: [NSRange]

    public init(plain: String, markup: SourceMarkup? = nil, raw: String? = nil, removed: [NSRange] = []) {
        self.plain = plain
        self.markup = markup
        self.raw = raw ?? plain
        self.removed = removed
    }

    public static func == (lhs: CapturedSource, rhs: CapturedSource) -> Bool {
        lhs.plain == rhs.plain && lhs.markup == rhs.markup
    }
}

/// Inline markup a translation may carry. Off by default, so plain results are parsed as before.
struct InlineOptions: Equatable, Sendable {
    enum Code: Equatable, Sendable {
        case off
        /// Every backtick span is a chip (the source itself used backticks).
        case any
        /// Only spans whose content was code in the copied page get a chip; other backticks are hidden.
        case only(Set<String>)
    }

    var code: Code = .off
    /// Values explicitly delimited in the raw source. When a copied chip has the same value,
    /// preserve literal delimiters for both: a translated sentence may reorder identical spans.
    var literalCode: Set<String> = []
    /// Link `<aN>` tags refer to `links[N - 1]`. Empty means tags are not parsed.
    var links: [SourceLink] = []
    var isActive: Bool { code != .off || !links.isEmpty }

    /// Captured chips and literal source code are both shown as chips, but plain exports preserve
    /// only the literal source's delimiters. Without copied chips, literal source code keeps the
    /// existing policy that every output code span is a chip. Backticks of
    /// code blocks the app fenced (template literals) are page code, not the source's own markdown.
    init(source: String, markup: SourceMarkup?) {
        links = markup?.links ?? []
        var probe = source
        if let blocks = markup?.blocks, !blocks.isEmpty {
            probe = ""
            var rest = Substring(source)
            for block in blocks {
                guard let range = rest.range(of: block.code) else { continue }
                probe += rest[..<range.lowerBound]
                rest = rest[range.upperBound...]
            }
            probe += rest
        }
        var authored: Set<String> = []
        if probe.unicodeScalars.contains("`") {
            let parsed = TranslationMarkup(probe, inline: InlineOptions(code: .any))
            let text = parsed.displayText as NSString
            authored = Set(parsed.spans.filter { $0.kind == .code }.map { text.substring(with: $0.range) })
        }
        if let captured = markup?.code, !captured.isEmpty {
            code = .only(captured.union(authored))
            literalCode = authored
        } else {
            code = authored.isEmpty ? .off : .any
        }
    }

    init(code: Code = .off, links: [SourceLink] = []) {
        self.code = code
        self.links = links
    }
}

struct InlineSpan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case code
        /// Index into `InlineOptions.links`.
        case link(Int)
    }

    let kind: Kind
    /// UTF-16 range in `displayText`.
    let range: NSRange
}

/// Backtick-fenced code blocks, inline code and link tags in a translation. Markers never reach the
/// display text and an unfinished tail that may still become markup is held back, so streamed
/// snapshots only grow by appending and the result view keeps its selection and scroll position.
/// Tilde fences are left as prose: the prompts only ask for backticks and `~~~` is a common divider.
/// A fence line whose info is not a language tag carries code (```npm install, as chat apps write it):
/// the block opens with that code as its first line, and may close at the end of a code line
/// (npm run build```). A known command (```pwd) is such code; any other single name outside the
/// recognized tags (```nginx) is a tag unless its block closes before any code or on its first code line.
/// A bare fence followed by a blank line is hidden and opens nothing: it closes a block that began before
/// the text, or the model left it.
struct TranslationMarkup: Equatable, Sendable {
    struct Fence: Equatable, Sendable {
        let length: Int
        let indent: Int
        let info: String
        /// Code written on the fence line itself instead of an info string.
        var inlineCode: String?

        /// The tag, or the first word of a `{…}` group (`{r, echo=FALSE}` and `{.python}` are `r` and `python`).
        var language: String? {
            let tag = info.hasPrefix("{")
                ? info.dropFirst().drop { $0.isWhitespace || $0 == "." }.prefix { !"},".contains($0) && !$0.isWhitespace }
                : info.split(whereSeparator: \.isWhitespace).first?.prefix { $0 != ":" } ?? ""
            return tag.isEmpty ? nil : String(tag.prefix(24))
        }
        var delimiter: String { String(repeating: "`", count: length) }
    }

    enum Kind: Equatable, Sendable { case prose, code(Fence) }

    struct Block: Equatable, Sendable {
        let kind: Kind
        /// UTF-16 range in `displayText`. Code blocks start at a line start.
        let range: NSRange
        /// For code, the spaces the fence's indent took off each line, so copies can put them back.
        var lineIndents: [Int] = []
        var fence: Fence? { if case .code(let fence) = kind { fence } else { nil } }
    }

    /// How copies and insertion treat fences: they follow the source the result replaces.
    enum FenceStyle: Equatable, Sendable {
        /// The source has no code, so fences the model added are left out and the code kept.
        case none
        /// The source fences its code; fences are kept.
        case fenced
        /// The source fences code without language tags, as chat apps do; fences are kept without tags.
        case untagged

        init(source: String) {
            let lines = TranslationMarkup.lines(source)
            let openers = TranslationMarkup.roles(lines).compactMap { if case .opener(let fence) = $0 { fence } else { nil } }
            self = openers.isEmpty ? .none : openers.contains { !$0.info.isEmpty } ? .fenced : .untagged
        }
    }

    let displayText: String
    let blocks: [Block]
    let spans: [InlineSpan]
    let lists: TranslationLists
    /// How inline code and link tags were read; `.link` spans index into its link table.
    let options: InlineOptions
    var links: [SourceLink] { options.links }
    var containsCode: Bool { blocks.contains { $0.fence != nil } }
    var hasInlineStructure: Bool { !spans.isEmpty }
    var containsLists: Bool { !lists.items.isEmpty }

    init(_ markdown: String, streaming: Bool = false, inline: InlineOptions = .init()) {
        self.init(markdown, streaming: streaming, inline: inline, trimsEnd: true)
    }

    private init(_ markdown: String, streaming: Bool, inline: InlineOptions, trimsEnd: Bool) {
        var pieces: [(id: Int, kind: Kind, text: String, indent: Int)] = []
        var spans: [InlineSpan] = []
        var offset = 0
        var id = 0
        let lines = Self.lines(markdown)
        func append(_ kind: Kind, _ text: String, indent: Int = 0) {
            pieces.append((id, kind, text, indent))
            offset += text.utf16.count
        }
        func code(_ fence: Fence, _ content: String, _ terminator: String) {
            let removed = min(fence.indent, content.prefix { $0 == " " }.count)
            append(.code(fence), String(content.dropFirst(removed)) + terminator, indent: removed)
        }
        scan: for (index, (line, role)) in zip(lines, Self.roles(lines, streaming: streaming, provisional: !inline.isActive)).enumerated() {
            switch role {
            case .opener(let fence):
                id += 1
                if let inlineCode = fence.inlineCode {
                    append(.code(fence), inlineCode + Self.carriageReturn(line.content) + line.terminator, indent: fence.indent)
                }
            case .closer: id += 1
            case .code(let fence):
                // A trailing backtick run may still close a chat-style block; showing what precedes it keeps the stream appending.
                let unfinished = streaming && !line.terminated && index == lines.count - 1
                code(fence, unfinished && fence.inlineCode != nil ? Self.trimmingTrailingRun(line.content) : line.content, line.terminator)
            case .closingCode(let fence):
                code(fence, Self.trimmingTrailingRun(line.content), line.terminator)
                id += 1
            case .stray: continue
            case .prose:
                guard inline.isActive else { append(.prose, line.content + line.terminator); continue }
                let unfinished = streaming && !line.terminated && index == lines.count - 1
                let scanned = Self.inlineLine(line.content, options: inline, unfinished: unfinished)
                spans += scanned.spans.map { InlineSpan(kind: $0.kind, range: NSRange(location: $0.range.location + offset, length: $0.range.length)) }
                append(.prose, scanned.text + (scanned.held ? "" : line.terminator))
                if scanned.held { break scan }
            }
        }

        let joined = pieces.map(\.text).joined()
        let display = trimsEnd ? Self.trimmingTrailingWhitespace(joined) : joined
        let length = display.utf16.count
        var blocks: [Block] = []
        var location = 0
        var index = pieces.startIndex
        while index < pieces.endIndex, location < length {
            let piece = pieces[index]
            var size = 0
            var indents: [Int] = []
            while index < pieces.endIndex, pieces[index].id == piece.id {
                size += pieces[index].text.utf16.count
                indents.append(pieces[index].indent)
                index += 1
            }
            let clipped = min(size, length - location)
            if clipped > 0 {
                blocks.append(Block(kind: piece.kind, range: NSRange(location: location, length: clipped),
                                    lineIndents: piece.kind == .prose ? [] : indents))
            }
            location += size
        }
        displayText = display
        self.blocks = blocks
        options = inline
        self.spans = spans.compactMap { span in
            let clipped = NSIntersectionRange(span.range, NSRange(location: 0, length: length))
            return clipped.length > 0 ? InlineSpan(kind: span.kind, range: clipped) : nil
        }
        lists = TranslationLists(display, excluding: blocks.filter { $0.fence != nil }.map(\.range),
                                 excludingMarkers: self.spans.filter { $0.kind == .code }.map(\.range))
    }

    /// Final text for the result, cache, copy and insert. Balanced input without empty fence pairs
    /// is returned unchanged, and so is any result whose source itself ends inside a fence: then the
    /// open fence is the user's partial selection, not a model mistake.
    static func normalized(_ markdown: String, source: String? = nil) -> String {
        if let source, openFence(in: source) != nil { return markdown }
        // Strays and empty pairs the source itself has (a selection starting inside code) are kept as written.
        var text = source.map { removingEmptyBlocks($0) != $0 } == true ? markdown : removingEmptyBlocks(markdown)
        while let open = openFence(in: text) {
            guard !open.hasContent else { return text + (text.unicodeScalars.last == "\n" ? "" : "\n") + open.fence.delimiter }
            // A fence the model opened but never filled is the stray trailing ``` seen in results. Cutting it
            // can leave another such fence at the end, which goes too, so normalizing twice changes nothing.
            text = trimmingTrailingWhitespace(String(text[..<open.start]))
        }
        return text
    }

    /// Display offset for a UTF-16 offset into `markdown` that starts a translation unit. Completed
    /// units before it are balanced, so the display of that prefix is a prefix of the full display.
    /// The separator before the unit stays on the completed side, so a finished paragraph selected
    /// with its line break can still be copied while the next one streams.
    static func displayOffset(of rawOffset: Int, in markdown: String, limit: Int, inline: InlineOptions = .init()) -> Int {
        guard rawOffset > 0 else { return 0 }
        let utf16 = markdown.utf16
        guard let end = utf16.index(utf16.startIndex, offsetBy: rawOffset, limitedBy: utf16.endIndex) else { return limit }
        let prefix = TranslationMarkup(String(markdown[..<end]), streaming: false, inline: inline, trimsEnd: false)
        return min(prefix.displayText.utf16.count, limit)
    }

    /// Keeps the target document's format: fence lines the model added to an unfenced source are
    /// dropped, while code lines keep their indentation and the text keeps its line ends. Link tags
    /// leave only their words, and backticks stay only where the source itself wrote them.
    static func insertionText(result: String, source: String, inline: InlineOptions = .init()) -> String {
        var options = inline
        if options.code == .any { options.code = .off }
        let style = FenceStyle(source: source)
        let reshapes = style != .fenced && TranslationMarkup(result).containsCode
        guard reshapes || options.isActive else { return result }
        var text = ""
        var droppedLast = false
        let lines = lines(result)
        for (line, role) in zip(lines, roles(lines)) {
            switch role {
            case .opener(let fence) where reshapes && style == .untagged:
                // A chat app shows a tag as a code line, so only the backticks stay.
                text += fence.inlineCode == nil && !fence.info.isEmpty ? String(repeating: " ", count: fence.indent) + fence.delimiter
                    + carriageReturn(line.content) + line.terminator : line.content + line.terminator
            case .opener(let fence) where reshapes && fence.inlineCode != nil:
                text += String(repeating: " ", count: fence.indent) + fence.inlineCode! + carriageReturn(line.content) + line.terminator
            case .opener where reshapes && style == .none, .closer where reshapes && style == .none:
                droppedLast = true
                continue
            case .closingCode where reshapes && style == .none:
                text += trimmingTrailingRun(line.content) + line.terminator
            case .prose where options.isActive:
                text += inlineLine(line.content, options: options, unfinished: false, preservingLiteralCode: true).text + line.terminator
            default:
                text += line.content + line.terminator
            }
            droppedLast = false
        }
        // A closing fence on the last line ends the text; its preceding line break goes with it.
        if droppedLast, result.unicodeScalars.last != "\n", text.unicodeScalars.last == "\n" {
            text.unicodeScalars.removeLast()
            if text.unicodeScalars.last == "\r" { text.unicodeScalars.removeLast() }
        }
        return text
    }

    /// A selection that touches code and something else, or inline code or a link, is copied with
    /// its structure; anything else is plain text.
    func needsMarkdown(for range: NSRange) -> Bool {
        let touched = blocks.filter { NSIntersectionRange($0.range, range).length > 0 }
        return touched.count > 1 && touched.contains { codeSlice(of: $0, in: range) != nil }
            || spans.contains { NSIntersectionRange($0.range, range).length > 0 }
            || lists.items.contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    /// The code a selection takes from a block, and where it starts. Line breaks alone, such as a selection
    /// that starts after a block's last character, are not code; neither is the break that ends the code
    /// line a selection starts at the end of. An empty code line the selection starts with stays.
    private func codeSlice(of block: Block, in range: NSRange) -> (text: String, location: Int)? {
        let overlap = NSIntersectionRange(block.range, range)
        guard block.fence != nil, overlap.length > 0 else { return nil }
        let text = displayText as NSString
        var slice = text.substring(with: overlap)
        guard !slice.allSatisfy(\.isWhitespace) else { return nil }
        var location = overlap.location
        if location > block.range.location, text.character(at: location - 1) != 0x0A, slice.hasPrefix("\n") || slice.hasPrefix("\r\n") {
            location += slice.hasPrefix("\r\n") ? 2 : 1
            slice.removeFirst()
        }
        return (slice, location)
    }

    /// Code lines of a selection with the spaces their fence's indent took off put back, line by line;
    /// a line the selection starts in the middle of gets none.
    private func reindented(_ slice: String, at location: Int, in block: Block) -> String {
        let text = displayText as NSString
        var line = text.substring(with: NSRange(location: block.range.location, length: location - block.range.location))
            .unicodeScalars.filter { $0 == "\n" }.count
        let startsLine = location == block.range.location || text.character(at: location - 1) == 0x0A
        return Self.lines(slice).enumerated().map { offset, piece in
            defer { line += 1 }
            let spaces = offset == 0 && !startsLine ? 0 : block.lineIndents.indices.contains(line) ? block.lineIndents[line] : 0
            return String(repeating: " ", count: spaces) + piece.content + piece.terminator
        }.joined()
    }

    /// The copy button's plain text for a selection: fences as the source has them, code lines back at
    /// the indent they had under their fence, link words without URLs, and backticks only where the
    /// source wrote them.
    func plainText(in range: NSRange, fences: FenceStyle) -> String {
        let text = displayText as NSString
        let selected = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        return blocks.compactMap { block -> String? in
            let overlap = NSIntersectionRange(block.range, selected)
            guard overlap.length > 0 else { return nil }
            guard block.fence != nil, let code = codeSlice(of: block, in: selected) else {
                return renderInline(overlap, text: { $0 }, code: { $0 }, preservingLiteralCode: true, link: { inner, _ in inner })
            }
            if fences != .none { return markdown(in: overlap, tags: fences == .fenced) }
            return reindented(text.substring(with: NSRange(location: code.location, length: NSMaxRange(overlap) - code.location)),
                              at: code.location, in: block)
        }.joined()
    }

    /// The URL a link span opens, if it passes the policy.
    func url(of span: InlineSpan) -> URL? {
        guard case .link(let index) = span.kind, links.indices.contains(index), SourceLink.isAllowed(links[index].url) else { return nil }
        return links[index].url
    }

    /// Markdown for a selection of the display text, with each code slice fenced at its original indent.
    func markdown(in range: NSRange, tags: Bool = true) -> String {
        let text = displayText as NSString
        let selected = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        return blocks.compactMap { block -> String? in
            let overlap = NSIntersectionRange(block.range, selected)
            guard overlap.length > 0 else { return nil }
            guard let fence = block.fence, let (slice, location) = codeSlice(of: block, in: selected) else {
                return renderInline(overlap, text: { $0 }, linkText: Self.escapingBrackets, code: Self.markdownCode, link: { inner, url in
                    let target = url.absoluteString
                    return "[\(inner)](" + (target.contains { "() ".contains($0) } ? "<\(target)>" : target) + ")"
                })
            }
            let indent = String(repeating: " ", count: fence.indent)
            let body = reindented(slice, at: location, in: block)
            let terminated = slice.unicodeScalars.last == "\n"
            // A content line made of backticks must not close the rebuilt fence early.
            let longest = Self.lines(slice).compactMap { Self.fenceParts($0.content)?.run }.max() ?? 0
            let delimiter = String(repeating: "`", count: max(fence.length, longest + 1))
            return indent + delimiter + (tags ? fence.info : "") + "\n" + body + (terminated ? "" : "\n") + indent + delimiter + (terminated ? "\n" : "")
        }.joined()
    }

    var html: String { html(in: NSRange(location: 0, length: (displayText as NSString).length)) }

    func html(in range: NSRange) -> String {
        let text = displayText as NSString
        let selected = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        return "<meta charset=\"utf-8\">" + blocks.compactMap { block -> String? in
            let overlap = NSIntersectionRange(block.range, selected)
            guard overlap.length > 0 else { return nil }
            if let fence = block.fence, let slice = codeSlice(of: block, in: selected)?.text.replacingOccurrences(of: "\r\n", with: "\n") {
                let code = slice.hasSuffix("\n") ? String(slice.dropLast()) : slice
                let language = fence.language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
                return "<pre style=\"background:#f6f5f2;border-radius:6px;padding:10px 12px;white-space:pre-wrap;"
                    + "font:13px ui-monospace,SFMono-Regular,Menlo,monospace\"><code\(language)>\(Self.escape(code))</code></pre>"
            }
            return proseHTML(in: overlap)
        }.joined()
    }

    /// The rich representation removes only markers actually selected. Starting in an item's body
    /// gives ordinary prose; copying a child without its parent starts a new list at that child's number.
    private func proseHTML(in range: NSRange) -> String {
        let text = displayText as NSString
        func inline(_ part: NSRange) -> String {
            renderInline(part, text: Self.escape, code: { "<code>" + Self.escape($0) + "</code>" },
                         link: { "<a href=\"\(Self.escape($1.absoluteString))\">\($0)</a>" })
        }
        func paragraphs(_ part: NSRange) -> String {
            inline(part).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
                .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }.joined()
        }
        guard containsLists else { return paragraphs(range) }
        let selectedItems = Set(lists.items.indices.filter {
            let marker = lists.items[$0].markerRange
            return range.location <= marker.location && NSMaxRange(marker) <= NSMaxRange(range)
                && NSIntersectionRange(lists.items[$0].range, range).length > 0
        })
        guard !selectedItems.isEmpty else { return paragraphs(range) }
        let itemAt = Dictionary(uniqueKeysWithValues: selectedItems.map { (lists.items[$0].range.location, $0) })
        let continuationAt = Dictionary(uniqueKeysWithValues: lists.continuations.map { ($0.range.location, $0) })
        var result = "", stack: [Int] = [], proseStart: Int?, location = range.location, blankLines = 0
        func close(to count: Int) {
            while stack.count > count {
                let item = lists.items[stack.removeLast()]
                result += item.marker.isOrdered ? "</li></ol>" : "</li></ul>"
            }
        }
        func flushProse(through end: Int) {
            if let start = proseStart, end > start { result += paragraphs(NSRange(location: start, length: end - start)) }
            proseStart = nil
        }
        while location < NSMaxRange(range) {
            var lineStart = 0, end = 0
            text.getLineStart(&lineStart, end: &end, contentsEnd: nil, for: NSRange(location: location, length: 0))
            let selectedLine = NSRange(location: location, length: min(end, NSMaxRange(range)) - location)
            defer { location = NSMaxRange(selectedLine) }
            if let index = itemAt[lineStart] {
                flushProse(through: location)
                let item = lists.items[index]
                if blankLines > 0, stack.last.map({ lists.items[$0].group == item.group }) == true {
                    result += String(repeating: "<br>", count: blankLines + 1)
                }
                blankLines = 0
                var parent = item.parent
                while let ancestor = parent, !selectedItems.contains(ancestor) { parent = lists.items[ancestor].parent }
                let depth = parent.flatMap { stack.firstIndex(of: $0).map { $0 + 1 } } ?? 0
                if stack.first.map({ lists.items[$0].group != item.group }) == true { close(to: 0) }
                close(to: depth + 1)
                if stack.count == depth + 1 {
                    let previous = lists.items[stack.removeLast()]
                    result += "</li>"
                    if previous.marker.isOrdered == item.marker.isOrdered {
                        stack.append(index)
                    } else {
                        result += previous.marker.isOrdered ? "</ol>" : "</ul>"
                    }
                }
                if stack.count == depth {
                    result += item.marker.number.map { "<ol start=\"\($0)\">" } ?? "<ul>"
                    stack.append(index)
                }
                result += item.marker.number.map { "<li value=\"\($0)\">" } ?? "<li>"
                let body = NSIntersectionRange(item.contentRange, range)
                if body.length > 0 { result += inline(body) }
            } else if let continuation = continuationAt[lineStart],
                      selectedItems.contains(continuation.item), let level = stack.firstIndex(of: continuation.item) {
                flushProse(through: location)
                close(to: level + 1)
                result += String(repeating: "<br>", count: blankLines + 1) + inline(NSIntersectionRange(continuation.contentRange, range))
                blankLines = 0
            } else if text.substring(with: selectedLine).allSatisfy(\.isWhitespace), !stack.isEmpty {
                blankLines += 1
            } else {
                blankLines = 0
                close(to: 0)
                if proseStart == nil { proseStart = location }
            }
        }
        flushProse(through: NSMaxRange(range))
        close(to: 0)
        return result
    }

    // MARK: - Inline code and links

    /// Prose in `range` with code spans and allowed links wrapped by the given writers.
    /// A code span may sit inside a link, never the other way round.
    private func renderInline(_ range: NSRange, text write: (String) -> String, linkText: (String) -> String = { $0 },
                              code: (String) -> String, preservingLiteralCode: Bool = false,
                              link: (_ inner: String, _ url: URL) -> String) -> String {
        let text = displayText as NSString
        let codes = spans.filter { $0.kind == .code }.map { span in
            (range: NSIntersectionRange(span.range, range),
             literal: options.code == .any || options.literalCode.contains(text.substring(with: span.range)))
        }.filter { $0.range.length > 0 }.sorted { $0.range.location < $1.range.location }
        let links = spans.compactMap { span in url(of: span).map { (NSIntersectionRange(span.range, range), $0) } }
            .filter { $0.0.length > 0 }.sorted { $0.0.location < $1.0.location }
        func prose(_ part: NSRange, inLink: Bool = false) -> String {
            func words(_ piece: String) -> String { inLink ? linkText(write(piece)) : write(piece) }
            var out = ""
            var location = part.location
            for (span, literal) in codes where span.location >= location && NSMaxRange(span) <= NSMaxRange(part) {
                out += words(text.substring(with: NSRange(location: location, length: span.location - location)))
                let content = text.substring(with: span)
                out += preservingLiteralCode && literal ? Self.markdownCode(content) : code(content)
                location = NSMaxRange(span)
            }
            return out + words(text.substring(with: NSRange(location: location, length: NSMaxRange(part) - location)))
        }
        var out = ""
        var location = range.location
        for (span, url) in links where span.location >= location {
            out += prose(NSRange(location: location, length: span.location - location))
            out += link(prose(span, inLink: true), url)
            location = NSMaxRange(span)
        }
        return out + prose(NSRange(location: location, length: NSMaxRange(range) - location))
    }

    /// Link words in markdown: brackets and backslashes are escaped so page text cannot end the link or start another.
    private static func escapingBrackets(_ words: String) -> String {
        words.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    /// A code span delimited by a longer backtick run than any inside it.
    private static func markdownCode(_ content: String) -> String {
        var longest = 0, run = 0
        for scalar in content.unicodeScalars {
            run = scalar == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let delimiter = String(repeating: "`", count: longest + 1)
        let pad = content.hasPrefix("`") || content.hasSuffix("`") ? " " : ""
        return delimiter + pad + content + pad + delimiter
    }

    /// Display text and spans of one prose line. When `unfinished`, stops before a tail that may still
    /// become markup: a partial link tag, a backtick run at the end, or an open code span that may close.
    private static func inlineLine(_ line: String, options: InlineOptions, unfinished: Bool, preservingLiteralCode: Bool = false)
        -> (text: String, spans: [InlineSpan], held: Bool) {
        let scalars = Array(line.unicodeScalars)
        var out = String.UnicodeScalarView()
        var length = 0
        var spans: [InlineSpan] = []
        var openLink: (index: Int, start: Int)?
        func emit<S: Sequence>(_ part: S) where S.Element == Unicode.Scalar {
            for scalar in part { out.append(scalar); length += scalar.utf16.count }
        }
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == "`", options.code != .off {
                let run = scalars[i...].prefix { $0 == "`" }.count
                switch codeSpanEnd(scalars, opening: i, run: run, unfinished: unfinished) {
                case let .closed(end):
                    var content = scalars[(i + run)..<end]
                    if content.count >= 2, content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
                        content = content.dropFirst().dropLast()
                    }
                    let start = length
                    let text = String(String.UnicodeScalarView(content))
                    if preservingLiteralCode && options.literalCode.contains(text) {
                        emit(scalars[i..<(end + run)])
                    } else { emit(content) }
                    if case .only(let code) = options.code, !code.contains(text) {} else {
                        spans.append(InlineSpan(kind: .code, range: NSRange(location: start, length: length - start)))
                    }
                    i = end + run
                    continue
                case .pending:
                    return (String(out), spans, true)
                case .literal:
                    emit(scalars[i..<(i + run)])
                    i += run
                    continue
                }
            }
            if scalar == "<", !options.links.isEmpty {
                if let tag = linkTag(scalars, at: i) {
                    if tag.closing {
                        if let link = openLink, link.index == tag.number - 1 {
                            spans.append(InlineSpan(kind: .link(link.index), range: NSRange(location: link.start, length: length - link.start)))
                            openLink = nil
                        }
                    } else if openLink == nil, tag.number >= 1, tag.number <= options.links.count {
                        openLink = (tag.number - 1, length)
                    }
                    i += tag.length
                    continue
                }
                if unfinished, mayBecomeLinkTag(scalars[i...]) { return (String(out), spans, true) }
            }
            emit(CollectionOfOne(scalar))
            i += 1
        }
        return (String(out), spans, false)
    }

    private enum CodeSpanEnd { case closed(Int), pending, literal }

    /// A code span closes at a run of exactly the opening length on the same line, within 96 UTF-16 units.
    /// In an unfinished line, a run touching the end may still grow, so it settles nothing yet.
    private static func codeSpanEnd(_ scalars: [Unicode.Scalar], opening: Int, run: Int, unfinished: Bool) -> CodeSpanEnd {
        var j = opening + run
        var units = 0
        while j < scalars.count, units <= 96 {
            guard scalars[j] == "`" else { units += scalars[j].utf16.count; j += 1; continue }
            let closing = scalars[j...].prefix { $0 == "`" }.count
            if unfinished && j + closing == scalars.count { return .pending }
            if closing == run { return units <= 96 ? .closed(j) : .literal }
            units += closing
            j += closing
        }
        return unfinished && units <= 96 && j == scalars.count ? .pending : .literal
    }

    /// `<aN>` or `</aN>` with one to three digits.
    private static func linkTag(_ scalars: [Unicode.Scalar], at index: Int) -> (closing: Bool, number: Int, length: Int)? {
        var j = index + 1
        let closing = j < scalars.count && scalars[j] == "/"
        if closing { j += 1 }
        guard j < scalars.count, scalars[j] == "a" else { return nil }
        j += 1
        let digits = scalars[j...].prefix { $0.properties.numericType == .decimal && $0.isASCII }
        guard (1...3).contains(digits.count), j + digits.count < scalars.count, scalars[j + digits.count] == ">",
              let number = Int(String(String.UnicodeScalarView(digits))) else { return nil }
        return (closing, number, j + digits.count + 1 - index)
    }

    /// The end of an unfinished line that is a prefix of a link tag, such as `<`, `</a` or `<a12`.
    private static func mayBecomeLinkTag(_ tail: ArraySlice<Unicode.Scalar>) -> Bool {
        var rest = tail.dropFirst()
        if rest.first == "/" { rest = rest.dropFirst() }
        guard let first = rest.first else { return true }
        guard first == "a" else { return false }
        let digits = rest.dropFirst()
        return digits.count <= 3 && digits.allSatisfy { $0.properties.numericType == .decimal && $0.isASCII }
    }

    // MARK: - Line layout

    /// A final text line by line, read as the display reads it, for repairs that rewrite whole lines.
    struct LineLayout {
        enum Kind: Equatable { case prose, blank, stray, opener(Int), code(Int), closer(Int) }

        struct Block: Equatable {
            let fence: Fence
            let opener: Int
            /// The closing fence line; nil when the last code line closes the block chat-style, or nothing does.
            let closer: Int?
            /// The last line the block takes.
            let end: Int
            /// Code lines as displayed; a chat-style block starts with the code on its fence line.
            let code: [String]
        }

        /// Line contents without their "\n".
        let lines: [String]
        /// Whether the last line ends with a line break.
        let terminated: Bool
        let kinds: [Kind]
        let blocks: [Block]

        /// Non-blank prose lines outside blocks before each line, and in all at the end, but for `skipped` ones.
        func proseOrdinals(skipping skipped: Set<Int> = []) -> [Int] {
            var ordinals = [0]
            for (line, kind) in kinds.enumerated() { ordinals.append(ordinals[line] + (kind == .prose && !skipped.contains(line) ? 1 : 0)) }
            return ordinals
        }
    }

    /// The layout of a final text: blocks, strays and prose exactly as `TranslationMarkup(markdown)` shows them.
    static func layout(_ markdown: String) -> LineLayout {
        let lines = lines(markdown)
        var kinds: [LineLayout.Kind] = []
        var blocks: [LineLayout.Block] = []
        var open: (fence: Fence, opener: Int, code: [String])?
        func close(at end: Int, closer: Int?) {
            guard let block = open else { return }
            blocks.append(LineLayout.Block(fence: block.fence, opener: block.opener, closer: closer, end: end, code: block.code))
            open = nil
        }
        for (index, (line, role)) in zip(lines, roles(lines)).enumerated() {
            switch role {
            case .opener(let fence):
                open = (fence, index, fence.inlineCode.map { [$0 + carriageReturn(line.content)] } ?? [])
                kinds.append(.opener(blocks.count))
            case .code(let fence):
                open?.code.append(dedent(line.content, fence.indent))
                kinds.append(.code(blocks.count))
            case .closingCode(let fence):
                open?.code.append(dedent(trimmingTrailingRun(line.content), fence.indent))
                kinds.append(.code(blocks.count))
                close(at: index, closer: nil)
            case .closer:
                kinds.append(.closer(blocks.count))
                close(at: index, closer: index)
            case .stray: kinds.append(.stray)
            case .prose: kinds.append(line.content.allSatisfy(\.isWhitespace) ? .blank : .prose)
            }
        }
        close(at: lines.count - 1, closer: nil)
        return LineLayout(lines: lines.map(\.content), terminated: lines.last?.terminated ?? false, kinds: kinds, blocks: blocks)
    }

    // MARK: - Lines and fences

    private struct Line {
        let start: String.Index
        let content: String
        let terminated: Bool
        var terminator: String { terminated ? "\n" : "" }
    }

    /// Splits on U+000A by scalar so a CRLF grapheme is never split or merged across lines.
    private static func lines(_ text: String) -> [Line] {
        let scalars = text.unicodeScalars
        var lines: [Line] = []
        var start = scalars.startIndex
        var index = start
        while index < scalars.endIndex {
            if scalars[index] == "\n" {
                lines.append(Line(start: start, content: String(scalars[start..<index]), terminated: true))
                start = scalars.index(after: index)
            }
            index = scalars.index(after: index)
        }
        if start < scalars.endIndex {
            lines.append(Line(start: start, content: String(scalars[start..<scalars.endIndex]), terminated: false))
        }
        return lines
    }

    /// Strays and blocks with nothing but blank lines display nothing, so they must not reach copies either.
    private static func removingEmptyBlocks(_ text: String) -> String {
        let lines = lines(text)
        let roles = roles(lines)
        var kept = ""
        var index = 0
        var removedAtEnd = false
        while index < lines.count {
            let line = lines[index]
            switch roles[index] {
            case .stray:
                index += 1
                removedAtEnd = true
                continue
            default: break
            }
            kept += line.content + line.terminator
            // Only blank lines may follow a removal that ends the text.
            if !line.content.allSatisfy(\.isWhitespace) { removedAtEnd = false }
            index += 1
        }
        return removedAtEnd ? trimmingTrailingWhitespace(kept) : kept
    }

    private static func openFence(in text: String) -> (fence: Fence, start: String.Index, hasContent: Bool)? {
        var open: (fence: Fence, start: String.Index, hasContent: Bool)?
        let lines = lines(text)
        for (line, role) in zip(lines, roles(lines)) {
            switch role {
            case .opener(let fence): open = (fence, line.start, fence.inlineCode != nil)
            case .closer, .closingCode: open = nil
            case .code: if !line.content.allSatisfy(\.isWhitespace) { open?.hasContent = true }
            case .prose, .stray: break
            }
        }
        return open
    }

    private enum Role: Equatable { case opener(Fence), closer, code(Fence), closingCode(Fence), prose, stray }

    /// How each line reads; parsing, normalization and insertion all share it. While streaming, it stops
    /// before a line that may still become markup, so nothing from there on is shown yet.
    /// - A bare fence opens a block only if the next fence line that could pair with it closes it. Otherwise
    ///   it is a stray: the closer of a block that began before the text (a selection starting inside code)
    ///   or a fence the model left. While streaming, with no closer yet, its next line decides for now: the
    ///   shown text is the same either way, only the box may change. An indented one waits for its closer.
    /// - A fence line with code instead of an info string opens a block that also closes at the end of
    ///   a code line, as chat apps write them.
    private static func roles(_ lines: [Line], streaming: Bool = false, provisional allowsProvisional: Bool = true) -> [Role] {
        var roles: [Role] = []
        var open: Fence?
        // Set while streaming once a bare fence is opened or skipped for now: later fence lines wait.
        var provisional = false
        var holdAt = Int.max
        var openedAt = 0
        scan: for (index, line) in lines.enumerated() {
            let unfinished = streaming && !line.terminated && index == lines.count - 1
            if index >= holdAt { break }
            if let fence = open {
                if unfinished && (mayClose(line.content) || provisional && fenceLine(line.content) != nil) { break }
                if isCloser(line.content, fence) {
                    open = nil
                    // A block with nothing but blank lines shows nothing, like a stray.
                    if fence.inlineCode == nil, lines[(openedAt + 1)..<index].allSatisfy({ $0.content.allSatisfy(\.isWhitespace) }) {
                        roles.replaceSubrange(openedAt..<index, with: repeatElement(.stray, count: index - openedAt))
                        roles.append(.stray)
                    } else {
                        roles.append(.closer)
                    }
                }
                else if !unfinished, closesChatBlock(line.content, fence) { open = nil; roles.append(.closingCode(fence)) }
                else { roles.append(.code(fence)) }
                continue
            }
            if unfinished, fenceLine(line.content) != nil || mayOpen(line.content) { break }
            guard var fence = fenceLine(line.content) else { roles.append(.prose); continue }
            switch reading(of: fence.info) {
            case .info: break
            case .code: fence = Fence(length: fence.length, indent: fence.indent, info: "", inlineCode: fence.info)
            case .name:
                // Nothing from here on is shown until the name is read, so the display only appends.
                guard let tag = namesLanguage(fence, after: index, in: lines, streaming: streaming) else { break scan }
                if !tag { fence = Fence(length: fence.length, indent: fence.indent, info: "", inlineCode: fence.info) }
            }
            if fence.info.isEmpty, fence.inlineCode == nil {
                switch pairing(of: fence, after: index, in: lines, streaming: streaming) {
                case .closed: break
                case .stray: roles.append(.stray); continue
                case .open(let laterFence):
                    guard streaming else { roles.append(.stray); continue }
                    // With inline markup, prose hides tags and backticks that code shows, so the answer changes the
                    // shown text; an indented fence changes its lines' indent. Both wait for the closer.
                    guard allowsProvisional, index + 1 < lines.count, fence.indent == 0 else { break scan }
                    // How later fence lines read depends on the answer, so they wait for it.
                    provisional = true
                    holdAt = min(holdAt, laterFence ?? Int.max)
                    let next = lines[index + 1]
                    let blank = next.content.allSatisfy(\.isWhitespace)
                    if !next.terminated, index + 1 == lines.count - 1, blank { break scan }
                    if blank { roles.append(.stray); continue }
                }
            }
            open = fence
            openedAt = index
            roles.append(.opener(fence))
        }
        return roles
    }

    private enum Pairing { case closed, stray, open(laterFence: Int?) }

    /// Whether a later line closes a bare fence. Lines between are content, as in CommonMark, except after a
    /// blank line: code never starts with one, so a fence with an info string there is the block the model
    /// meant, and the bare fence before it is a stray. With no closer (yet) it stays open, noting the first
    /// other fence line after it. While streaming, an unfinished last line may still change and settles nothing.
    private static func pairing(of fence: Fence, after index: Int, in lines: [Line], streaming: Bool) -> Pairing {
        let blankAfter = lines.indices.contains(index + 1) && lines[index + 1].content.allSatisfy(\.isWhitespace)
        var laterFence: Int?
        for (offset, line) in lines[(index + 1)...].enumerated() {
            if streaming && !line.terminated && index + 1 + offset == lines.count - 1 { break }
            guard let next = fenceLine(line.content) else { continue }
            if isCloser(line.content, fence) { return .closed }
            if blankAfter, !next.info.isEmpty { return .stray }
            laterFence = laterFence ?? index + 1 + offset
        }
        return .open(laterFence: laterFence)
    }

    /// In a block opened with code on its fence line, a code line ending in a run at least as long as the fence closes it.
    private static func closesChatBlock(_ line: String, _ fence: Fence) -> Bool {
        guard fence.inlineCode != nil else { return false }
        let content = line.unicodeScalars.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }
        let run = content.prefix { $0 == "`" }.count
        return run >= fence.length && run < content.count
    }

    /// A line without its trailing backtick run and the spaces before it; a CRLF line keeps its CR.
    private static func trimmingTrailingRun(_ line: String) -> String {
        var scalars = Substring(line).unicodeScalars
        while let last = scalars.last, last == " " || last == "\t" || last == "\r" { scalars.removeLast() }
        while scalars.last == "`" { scalars.removeLast() }
        while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
        return String(scalars) + carriageReturn(line)
    }

    /// The CR of a CRLF line, which fence parsing strips from the fence's info.
    private static func carriageReturn(_ line: String) -> String { line.unicodeScalars.last == "\r" ? "\r" : "" }

    /// Indent, backtick run and the rest of a line, ignoring a trailing CR.
    static func fenceParts(_ line: String) -> (indent: Int, run: Int, rest: Substring.UnicodeScalarView)? {
        var scalars = Substring(line).unicodeScalars
        if scalars.last == "\r" { scalars.removeLast() }
        let indent = scalars.prefix { $0 == " " }.count
        guard indent <= 3, scalars.dropFirst(indent).first == "`" else { return nil }
        let run = scalars.dropFirst(indent).prefix { $0 == "`" }.count
        return (indent, run, Substring.UnicodeScalarView(scalars.dropFirst(indent + run)))
    }

    /// Any backtick fence line by CommonMark's rules. An unfinished line like this may still become an opener.
    private static func fenceLine(_ line: String) -> Fence? {
        guard let parts = fenceParts(line), parts.run >= 3, !parts.rest.contains("`") else { return nil }
        return Fence(length: parts.run, indent: parts.indent, info: String(parts.rest).trimmingCharacters(in: .whitespaces))
    }

    /// How a fence line's text reads: an info string, code written on the fence line, or a single name
    /// whose reading depends on what follows it.
    private enum Reading { case info, code, name }

    /// Recognized tags read as tags at once, and win when a name is also an executable (```python).
    /// The importer fences copied code only with these, so its fences never wait on what follows.
    static let knownLanguageTags: Set<String> = [
        "bash", "sh", "shell", "zsh", "fish", "console", "terminal", "shell-session",
        "powershell", "ps1", "bat", "batch", "cmd",
        "c", "h", "cpp", "c++", "cc", "cxx", "hpp", "cs", "csharp", "c#", "objc", "objective-c",
        "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "py", "python", "python3",
        "rb", "ruby", "go", "golang", "rust", "rs", "java", "kotlin", "kt", "scala", "php",
        "perl", "pl", "lua", "r", "dart", "elixir", "ex", "erlang", "erl", "haskell", "hs",
        "clojure", "clj", "lisp", "julia", "jl", "sql", "html", "htm", "xml", "css", "scss", "sass", "less",
        "json", "jsonc", "yaml", "yml", "toml", "ini", "text", "txt", "plaintext", "plain",
        "md", "markdown", "mdx", "diff", "patch", "dockerfile", "makefile", "cmake",
        "graphql", "gql", "proto", "protobuf", "vue", "svelte", "astro", "mermaid", "regex", "regexp"
    ]

    /// A tag a fence can carry that reads as a tag at once, whatever follows it.
    static func isFenceLanguage(_ tag: String) -> Bool { !tag.isEmpty && reading(of: tag) == .info }

    /// Commands that are never language names: code even when more code follows (```pwd then ls -la then ```).
    private static let commands: Set<String> = [
        "pwd", "ls", "ll", "cd", "whoami", "clear", "cls", "date", "uptime", "hostname", "history",
        "exit", "top", "htop", "ps", "df", "du", "id", "uname", "printenv", "ifconfig", "ipconfig"
    ]

    /// An info string is empty, a `{…}` group or a recognized tag, or a name followed by `{…}` groups and quoted
    /// attributes (`title="a.js"`); bare flags (`showLineNumbers`) count only next to those. Any other single
    /// name, `lang:file` included, is read from what follows it unless it is a known command. Known commands
    /// and anything else (```npm install) are code.
    private static func reading(of info: String) -> Reading {
        if info.isEmpty { return .info }
        let head = #"(?:[A-Za-z0-9_+#.\-]{1,24}(?::\S+)?|\{[^{}]*\})"#
        let attribute = #"(?:\{[^{}]*\}|[a-z][A-Za-z0-9_\-]*=(?:"[^"]*"|'[^']*'))"#
        let flag = #"[A-Za-z][A-Za-z0-9_\-]*"#
        if info.range(of: "^\(head)$", options: .regularExpression) != nil {
            if info.hasPrefix("{") || knownLanguageTags.contains(info.lowercased()) { return .info }
            return commands.contains(info.lowercased()) ? .code : .name
        }
        return info.range(of: "^\(head)(?:\\s+(?:\(attribute)|\(flag)))*$", options: .regularExpression) != nil
            && info.range(of: "\\s\(attribute)", options: .regularExpression) != nil ? .info : .code
    }

    /// A single name neither list knows (```nginx, ```hcl) is a language tag when code follows it, as in
    /// CommonMark, and the block's first code line when the block closes before any code (```deploy then ```)
    /// or its first code line closes it chat-style (```node then node -v```). Blank lines decide nothing.
    /// With nothing after it the fence is a tag, so a stray ```nginx is still cut.
    /// While streaming, nil until the deciding line is complete.
    private static func namesLanguage(_ fence: Fence, after index: Int, in lines: [Line], streaming: Bool) -> Bool? {
        let chat = Fence(length: fence.length, indent: fence.indent, info: "", inlineCode: fence.info)
        for (offset, line) in lines[(index + 1)...].enumerated() {
            if streaming && !line.terminated && index + 1 + offset == lines.count - 1 { return nil }
            if isCloser(line.content, fence) { return false }
            if line.content.allSatisfy(\.isWhitespace) { continue }
            return !closesChatBlock(line.content, chat)
        }
        return streaming ? nil : true
    }

    private static func isCloser(_ line: String, _ fence: Fence) -> Bool {
        mayClose(line) && (fenceParts(line)?.run ?? 0) >= fence.length
    }

    /// The unfinished line could still become (or already is) a closing fence.
    private static func mayClose(_ line: String) -> Bool {
        fenceParts(line)?.rest.allSatisfy { $0 == " " || $0 == "\t" } ?? false
    }

    /// The unfinished line could still become an opening fence.
    private static func mayOpen(_ line: String) -> Bool {
        guard let parts = fenceParts(line) else { return false }
        return parts.run < 3 && parts.rest.isEmpty
    }

    private static func dedent(_ line: String, _ indent: Int) -> String {
        String(line.dropFirst(min(indent, line.prefix { $0 == " " }.count)))
    }

    static func trimmingTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        return String(text[..<end])
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
