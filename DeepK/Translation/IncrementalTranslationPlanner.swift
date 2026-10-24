import Foundation

/// Only exact, independent units may share a completed translation: plain-text paragraphs, and any
/// block after an explicit `---` line. Offsets are never carried from one Swift String snapshot into
/// another; every position is a UTF-8 offset into the string it was computed from.
enum IncrementalTranslationPlanner {
    struct Tail: Equatable, Sendable {
        let separator: String
        let input: String
        /// The tail follows an explicit `---` boundary. Derived for the language rule, never stored.
        var explicit = false
    }

    static func tail(after prefix: String, in source: String) -> Tail? {
        guard !prefix.isEmpty, source.utf8.starts(with: prefix.utf8) else { return nil }
        let head = Layout(prefix)
        // The completed content ends before whitespace, `---` lines and a dash being typed (P0-1).
        let contentEnd = head.unitEnd, prefixEnd = prefix.utf8.count
        guard contentEnd > 0 else { return nil }
        let rest = Layout(String(decoding: source.utf8.dropFirst(contentEnd), as: UTF8.self), fence: head.fence)
        guard rest.lines[0].kind == .blank else { return nil }
        guard let first = rest.lines.indices.dropFirst().first(where: { rest.lines[$0].kind == .content }) else {
            // Only a delimiter follows: keep the prefix, including while the delimiter is typed.
            return Tail(separator: slice(source, prefixEnd, source.utf8.count), input: "",
                        explicit: rest.lines.contains { $0.kind == .dash || $0.kind == .partialDash })
        }
        let line = rest.lines[first]
        // Text that turns held dashes into content was never translated.
        guard contentEnd + line.firstContent >= prefixEnd else { return nil }
        let explicit = rest.lines[1..<first].contains { $0.kind == .dash }
        let last = rest.unitLastLine(from: first)
        let inputEnd = contentEnd + rest.inputEnd(last: last)
        if !explicit {
            // Lists, quotes, code and open text may continue across a blank line. A `---` line ends any of
            // them except a fence, so only the block after the prefix's last boundary is checked (D8).
            let scope = head.plainScopeStart
            let scopeEnd = last == rest.lastContent ? source.utf8.count : inputEnd
            guard first >= 2, isPlainText(slice(prefix, scope, prefixEnd)), isPlainText(slice(source, scope, scopeEnd)) else { return nil }
        }
        let inputStart = max(prefixEnd, contentEnd + line.start)
        return Tail(separator: slice(source, prefixEnd, inputStart), input: slice(source, inputStart, inputEnd), explicit: explicit)
    }

    /// The first unit of a request without copied structure: cut at the first explicit boundary, without the
    /// delimiter at its end. A leading boundary becomes the separator only with a blank line, so front matter
    /// (`---⏎title:`) stays content.
    static func firstUnit(in source: String) -> Tail {
        let layout = Layout(source)
        guard let first = layout.firstContent else { return Tail(separator: "", input: "") }
        let start = layout.hasLeadingBoundary ? layout.lines[first].start : 0
        let end = layout.inputEnd(last: layout.unitLastLine(from: first))
        return Tail(separator: slice(source, 0, start), input: slice(source, start, end))
    }

    /// Copied structure describes the entire copied prefix, including any `---` within it. Only
    /// boundaries entered after that unchanged prefix divide later translation units.
    static func firstUnit(in source: String, preservingPrefix prefix: String) -> Tail {
        guard !prefix.isEmpty, source.utf8.starts(with: prefix.utf8) else { return firstUnit(in: source) }
        let layout = Layout(source)
        guard let first = layout.firstContent else { return Tail(separator: "", input: prefix) }
        let copiedEnd = prefix.utf8.count
        let last = layout.unitLastLine(from: first, boundariesAfter: copiedEnd)
        let end = max(copiedEnd, layout.inputEnd(last: last))
        return Tail(separator: "", input: slice(source, 0, end))
    }

    /// UTF-8 offset where the content ends, before trailing whitespace, `---` lines and a dash being typed.
    /// Inside an open fence only whitespace is trailing.
    static func unitEnd(of text: String) -> Int { Layout(text).unitEnd }

    /// Whitespace, `---` lines and a dash being typed only: nothing to translate.
    static func isBlankSource(_ text: String) -> Bool { Layout(text).firstContent == nil }

    /// The source's leading blank lines and boundary, as the separator of a unit that lost its predecessors.
    static func leadingDelimiter(of source: String) -> String {
        let layout = Layout(source)
        guard let first = layout.firstContent else { return "" }
        let run = layout.lines[..<first]
        guard layout.hasLeadingBoundary || !run.contains(where: { $0.kind == .dash }) else { return "" }
        return slice(source, 0, layout.lines[first].start)
    }

    /// Whether `gap` (the text after a unit's content up to the next unit) holds a `---` line.
    static func isExplicitGap(_ gap: String) -> Bool {
        Layout(gap).lines.dropFirst().contains { $0.kind == .dash }
    }

    /// The dashes of boundary lines, in UTF-16 for the source pane. Lines starting in `sent` (the text of a
    /// structured unit sent whole, without its separator) went to the model as content. Without content there is
    /// nothing to divide: a lone `---` stays text, so typing below it never turns a rule back into dashes.
    static func boundaryLineRanges(in source: String, excludingUTF8 sent: Range<Int> = 0..<0) -> [NSRange] {
        let layout = Layout(source)
        guard let first = layout.firstContent else { return [] }
        return layout.lines.indices.compactMap { index in
            let line = layout.lines[index]
            guard line.kind == .dash, !sent.contains(line.start) else { return nil }
            if index < first, !layout.hasLeadingBoundary { return nil }
            return NSRange(location: line.start16, length: line.dashes)
        }
    }

    /// What ⌘↩ appends to end the source with a boundary and an empty line. nil without content or inside an open fence.
    static func boundaryInsertion(after source: String) -> String? {
        let layout = Layout(source)
        guard let last = layout.lastContent, layout.fence == nil else { return nil }
        let trailing = layout.lines[(last + 1)...]
        if let typed = trailing.last, typed.kind == .partialDash {
            return String(repeating: "-", count: 3 - typed.dashes) + "\n\n"
        }
        if let line = trailing.lastIndex(where: { $0.kind == .dash }) {
            return String(repeating: "\n", count: max(0, 2 - (layout.lines.count - 1 - line)))
        }
        let blank = slice(source, layout.lines[last].contentEnd, source.utf8.count)
        let enter = blank.last?.isNewline == true ? "" : "\n"
        let newlines = blank.filter(\.isNewline).count + enter.count
        return enter + String(repeating: "\n", count: max(0, 2 - newlines)) + "---\n\n"
    }

    /// The text outside fenced code blocks, for language detection.
    static func proseOutsideFences(_ text: String) -> String {
        Layout(text).lines.filter { !$0.fenced }.map { slice(text, $0.start, $0.end) }.joined(separator: "\n")
    }

    static func isPlainText(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        // Lists, quotes, headings, indentation and code can continue across blank lines.
        guard !normalized.contains("\t"),
              normalized.range(of: #"(?m)^(?: {4}|\s*[-*+] |\s*\d+[.)] |\s*[#>])"#, options: .regularExpression) == nil
        else { return false }
        // URLs, apostrophes, slashes and closed parentheses are ordinary prose.
        let prose = normalized.replacingOccurrences(of: #"https?://[^\s<>()"']+"#, with: " ", options: .regularExpression)
        guard prose.range(of: #"[`{}\[\]=;<>|\\*]"#, options: .regularExpression) == nil,
              prose.range(of: #"[A-Za-z_][A-Za-z0-9_]*\("#, options: .regularExpression) == nil
        else { return false }
        return prose.components(separatedBy: "\n\n").allSatisfy(closesWithinParagraph)
    }

    /// An unclosed parenthesis or quote may continue into the next paragraph.
    private static func closesWithinParagraph(_ paragraph: String) -> Bool {
        var depth = 0
        for character in paragraph {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0 && paragraph.filter { $0 == "\"" }.count.isMultiple(of: 2)
    }

    private static func slice(_ text: String, _ start: Int, _ end: Int) -> String {
        String(decoding: text.utf8.dropFirst(start).prefix(max(0, end - start)), as: UTF8.self)
    }
}

/// The boundary grammar, line by line. Whitespace is `TranslationDocument.isBlank` without line breaks
/// (NBSP included), and a line break is `Character.isNewline` (CRLF is one).
///
///     blank    SP*
///     dash     -{3,} SP*          outside a fence; "- - -", "***", "  ---" and "---x" are content
///     partial  - or --            the last line only: a boundary being typed
///
/// A `---` line between two content lines is an explicit boundary. A fence opens at ` {0,3}`{3,}` without a
/// backtick in its info string and closes at a line of at least as many backticks; one left open stays open.
/// `~~~` is not a fence (plans/result-structure.md).
private struct Layout {
    enum Kind { case blank, dash, partialDash, content }

    struct Line {
        var start = 0, firstContent = 0, contentEnd = 0, end = 0
        var start16 = 0
        var dashes = 0
        var kind = Kind.blank
        /// The line belongs to a fenced code block (opener, body or closer).
        var fenced = false
    }

    private(set) var lines: [Line] = []
    /// Backticks of the fence still open at the end.
    private(set) var fence: Int?

    init(_ text: String, fence open: Int? = nil) {
        var bodies: [(text: String, line: Line)] = []
        var body = "", line = Line(), offset = 0, offset16 = 0
        for character in text {
            if character.isNewline {
                line.end = offset
                bodies.append((body, line))
                body = ""
                line = Line(start: offset + character.utf8.count, start16: offset16 + character.utf16.count)
            } else {
                body.append(character)
            }
            offset += character.utf8.count
            offset16 += character.utf16.count
        }
        line.end = offset
        bodies.append((body, line))

        var fence = open
        for (index, (body, base)) in bodies.enumerated() {
            var line = base
            let leading = body.prefix(while: Self.isSpace), trailing = body.reversed().prefix(while: Self.isSpace)
            line.firstContent = line.start + leading.utf8.count
            line.contentEnd = line.end - String(trailing).utf8.count
            line.dashes = body.prefix { $0 == "-" }.count
            let insideFence = fence != nil
            if let ticks = fence {
                if Self.backticks(body, closing: ticks) != nil { fence = nil }
            } else if let ticks = Self.backticks(body, closing: nil) {
                fence = ticks
            }
            line.fenced = insideFence || fence != nil
            line.kind = if leading.count == body.count { .blank }
                else if line.fenced { .content }
                else if line.dashes >= 3, body.dropFirst(line.dashes).allSatisfy(Self.isSpace) { .dash }
                else if line.dashes == body.count, index == bodies.count - 1 { .partialDash }
                else { .content }
            lines.append(line)
        }
        self.fence = fence
    }

    var firstContent: Int? { lines.firstIndex { $0.kind == .content } }
    var lastContent: Int? { lines.lastIndex { $0.kind == .content } }
    var unitEnd: Int { lastContent.map { lines[$0].contentEnd } ?? 0 }

    /// The lines before the first content hold a `---` line and a blank line.
    var hasLeadingBoundary: Bool {
        guard let first = firstContent else { return false }
        let run = lines[..<first]
        return run.contains { $0.kind == .dash } && run.contains { $0.kind == .blank }
    }

    /// The last content line of the unit starting at content line `first`.
    func unitLastLine(from first: Int, boundariesAfter copiedEnd: Int = 0) -> Int {
        var last = first, boundary = false
        for index in lines.indices.dropFirst(first + 1) {
            switch lines[index].kind {
            case .content:
                if boundary { return last }
                last = index
            case .dash: if lines[index].start >= copiedEnd { boundary = true }
            case .blank, .partialDash: break
            }
        }
        return last
    }

    /// Where a unit whose last content line is `last` ends. A final `-` or `--` line is content only because
    /// text follows it, so it keeps that line break (or its spaces); otherwise the unit, read back as a prefix,
    /// would end with a dash being typed.
    func inputEnd(last: Int) -> Int {
        let line = lines[last]
        guard !line.fenced, (1...2).contains(line.dashes), line.contentEnd - line.start == line.dashes else { return line.contentEnd }
        return last + 1 < lines.count ? lines[last + 1].start : line.end
    }

    /// Where the block after the last explicit boundary starts.
    var plainScopeStart: Int {
        var scope = hasLeadingBoundary ? lines[firstContent!].start : 0
        var seenContent = false, boundary = false
        for line in lines {
            switch line.kind {
            case .content:
                if seenContent, boundary { scope = line.start }
                seenContent = true
                boundary = false
            case .dash: boundary = true
            case .blank, .partialDash: break
            }
        }
        return scope
    }

    private static func isSpace(_ character: Character) -> Bool {
        !character.isNewline && TranslationDocument.isBlank(character)
    }

    /// The backtick count of a fence opener (`closing == nil`) or of a closer for a fence of `closing` backticks.
    private static func backticks(_ body: String, closing: Int?) -> Int? {
        let indent = body.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = body.dropFirst(indent)
        let ticks = rest.prefix { $0 == "`" }.count
        let info = rest.dropFirst(ticks)
        guard ticks >= 3 else { return nil }
        if let closing { return ticks >= closing && info.allSatisfy(isSpace) ? ticks : nil }
        return info.contains("`") ? nil : ticks
    }
}
