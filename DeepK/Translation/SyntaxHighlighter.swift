import Foundation

/// What a highlighted run of code is. Every style's palette gives each kind a color.
enum SyntaxTokenKind: UInt8, CaseIterable, Sendable {
    case keyword, type, function, string, number, comment, property, tag, command, flag
}

struct SyntaxToken: Equatable, Sendable {
    let kind: SyntaxTokenKind
    /// UTF-16 range: in the line for `SyntaxHighlighter.tokenize`, in the text for `SyntaxHighlightCache`.
    let range: NSRange
}

/// What a line leaves open for the next one. Lines are scanned forward only, so a line's colors depend on the lines
/// before it and never on the ones after.
enum SyntaxLineState: Hashable, Sendable {
    case normal
    /// Inside a block comment, nested `depth` deep.
    case blockComment(depth: Int)
    /// Inside a multi-line string; the index of its delimiter in `SyntaxGrammar.multilineStrings`.
    case string(Int)
    /// Inside a raw string that ends at `close`, with no escapes: Rust `r#"…"#`, C++ `R"x(…)x"`.
    case rawString(close: String)
    case markupComment
    /// Inside a markup tag whose attributes go on.
    case markupTag
    /// Inside a `<script` or `<style` open tag (the index in `rawElements`) whose attributes go on.
    case markupRawTag(Int)
    /// Inside a script or style element, where nothing is a tag until its closing tag.
    case markupRaw(Int)
    /// CSS inside `depth` braces.
    case css(depth: Int)
    case cssComment(depth: Int)
    /// A shell line ended with a backslash; the next line goes on with the same command.
    case continued
}

/// A small line-by-line tokenizer for the languages in `SyntaxLanguages`. It walks UTF-16 units with ASCII rules;
/// units outside ASCII count as name characters, so Korean comments and identifiers keep exact ranges. It is not a
/// parser: regex literals, interpolation and heredocs are read as what they look like.
struct SyntaxHighlighter: Sendable {
    let grammar: SyntaxGrammar

    /// Nil for no tag and for tags no grammar covers; their code keeps one color.
    init?(tag: String?) {
        guard let grammar = SyntaxLanguages.grammar(for: tag) else { return nil }
        self.grammar = grammar
    }

    /// One line without its line break, starting in `state`.
    func tokenize(_ line: some Collection<UInt16>, from state: SyntaxLineState) -> (tokens: [SyntaxToken], end: SyntaxLineState) {
        var scanner = LineScanner(grammar: grammar, units: Array(line))
        let end = scanner.scan(from: state)
        return (scanner.tokens, end)
    }

    /// Every line of `text`, each starting in the state the previous one left.
    func tokenize(_ text: String) -> [[SyntaxToken]] {
        var state = SyntaxLineState.normal
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let result = tokenize(line.utf16, from: state)
            state = result.end
            return result.tokens
        }
    }
}

/// Each block's lines as last scanned: their runs and the state they leave. A block that grows or changes is scanned again
/// from its first changed line only, never from its start on every streamed chunk; lines before that line give back the
/// runs they had.
struct SyntaxHighlightCache {
    private struct Line {
        /// Where the line starts in the text.
        let start: Int
        /// Relative to the line.
        let tokens: [SyntaxToken]
        let end: SyntaxLineState
    }

    private struct Entry {
        let tag: String
        var lines: [Line]
    }

    /// By block start.
    private var entries: [Int: Entry] = [:]
    /// Lines tokenized so far.
    private(set) var linesScanned = 0

    /// Runs, in ranges of `text`, for the lines of `block` from the line holding `from` to the block's end. Lines are scanned
    /// again from the one holding `changedFrom` (by default `from`); the block's text before it must not have changed since
    /// the last call for a block starting at the same place, as the result view's edits guarantee. A different tag, or
    /// lines this cache never saw, start over at the block's start.
    mutating func tokens(in text: NSString, block: NSRange, tag: String, highlighter: SyntaxHighlighter, from: Int,
                         changedFrom: Int? = nil) -> [SyntaxToken] {
        let end = min(NSMaxRange(block), text.length)
        let unchangedTo = max(from, changedFrom ?? from)
        var entry = entries[block.location].flatMap { $0.tag == tag ? $0 : nil } ?? Entry(tag: tag, lines: [])
        /// The index and start of the line holding `offset` (at most `unchangedTo`): the last remembered line starting at or
        /// before it, and only past the last remembered line are breaks counted, so a streamed chunk never walks the block
        /// from its start. Remembered starts after the first changed character may be stale, but they are all after `offset`.
        func line(at offset: Int) -> (index: Int, start: Int) {
            var index = 0, start = block.location
            if !entry.lines.isEmpty {
                var low = 0, high = entry.lines.count - 1
                while low < high {
                    let middle = (low + high + 1) / 2
                    if entry.lines[middle].start <= offset { low = middle } else { high = middle - 1 }
                }
                if entry.lines[low].start <= offset { (index, start) = (low, entry.lines[low].start) }
            }
            for position in start..<max(start, min(offset, end)) where text.character(at: position) == 0x0A {
                index += 1
                start = position + 1
            }
            return (index, start)
        }
        var (first, lineStart) = line(at: from)
        var changed = line(at: unchangedTo).index
        if entry.lines.count < first {
            (first, lineStart, changed) = (0, block.location, 0)
        }
        changed = min(changed, entry.lines.count)
        entry.lines.removeSubrange(changed...)
        var state = changed == 0 ? SyntaxLineState.normal : entry.lines[changed - 1].end
        var tokens: [SyntaxToken] = []
        var index = first
        while lineStart < end {
            var stop: Int
            if index + 1 < changed {
                stop = entry.lines[index + 1].start - 1
            } else {
                stop = lineStart
                while stop < end, text.character(at: stop) != 0x0A { stop += 1 }
            }
            let lineTokens: [SyntaxToken]
            if index < changed {
                lineTokens = entry.lines[index].tokens
            } else {
                var units = [UInt16](repeating: 0, count: stop - lineStart)
                if !units.isEmpty {
                    let range = NSRange(location: lineStart, length: stop - lineStart)
                    units.withUnsafeMutableBufferPointer { text.getCharacters($0.baseAddress!, range: range) }
                }
                let result = highlighter.tokenize(units, from: state)
                state = result.end
                entry.lines.append(Line(start: lineStart, tokens: result.tokens, end: result.end))
                linesScanned += 1
                lineTokens = result.tokens
            }
            let offset = lineStart
            tokens += lineTokens.map { SyntaxToken(kind: $0.kind, range: NSRange(location: offset + $0.range.location, length: $0.range.length)) }
            index += 1
            lineStart = stop + 1
        }
        entries[block.location] = entry
        return tokens
    }

    /// Forgets blocks that no longer start at these places.
    mutating func keep(blockStarts: Set<Int>) {
        entries = entries.filter { blockStarts.contains($0.key) }
    }

    mutating func removeAll() {
        entries = [:]
    }
}

// MARK: - Scanning

private enum Unit {
    static let tab: UInt16 = 0x09, space: UInt16 = 0x20, quote: UInt16 = 0x22, hash: UInt16 = 0x23, dollar: UInt16 = 0x24
    static let percent: UInt16 = 0x25, ampersand: UInt16 = 0x26, apostrophe: UInt16 = 0x27, openParen: UInt16 = 0x28
    static let closeParen: UInt16 = 0x29, star: UInt16 = 0x2A, plus: UInt16 = 0x2B, comma: UInt16 = 0x2C, minus: UInt16 = 0x2D
    static let dot: UInt16 = 0x2E, slash: UInt16 = 0x2F, colon: UInt16 = 0x3A, semicolon: UInt16 = 0x3B, less: UInt16 = 0x3C
    static let equals: UInt16 = 0x3D, greater: UInt16 = 0x3E, question: UInt16 = 0x3F, at: UInt16 = 0x40
    static let openBracket: UInt16 = 0x5B, backslash: UInt16 = 0x5C, closeBracket: UInt16 = 0x5D, underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60, openBrace: UInt16 = 0x7B, pipe: UInt16 = 0x7C, closeBrace: UInt16 = 0x7D
    static let tilde: UInt16 = 0x7E, exclamation: UInt16 = 0x21

    static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == 0x0D || c == 0x0B || c == 0x0C }
    static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isUpper(_ c: UInt16) -> Bool { c >= 0x41 && c <= 0x5A }
    static func isLetter(_ c: UInt16) -> Bool { isUpper(c) || (c >= 0x61 && c <= 0x7A) }
    static func isHexDigit(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
}

/// Shell commands that run the word after them, which is a command too.
private let prefixCommands: Set<String> = ["sudo", "env", "exec", "nohup", "command", "builtin", "xargs", "time", "doas"]
/// Shell keywords after which a command comes.
private let commandKeywords: Set<String> = ["if", "then", "else", "elif", "while", "until", "do", "time", "!"]
/// Prompts that open a command line in plain text.
private let prompts: [UInt16] = [Unit.dollar, Unit.percent, Unit.greater, 0x203A, 0x276F, Unit.hash]
/// Keywords that stay keywords after a dot: Swift's `.init` and `.self`.
private let memberKeywords: Set<String> = ["init", "self"]
/// Markup elements whose text is not markup.
private let rawElements = ["script", "style"]

private struct LineScanner {
    let g: SyntaxGrammar
    let u: [UInt16]
    var i = 0
    var tokens: [SyntaxToken] = []
    /// CSS: where the search for the next `{`, `;` or `}` last started and what it found, so a long line is searched once.
    var stopSearchedFrom = Int.max
    var stop = 0

    init(grammar: SyntaxGrammar, units: [UInt16]) {
        g = grammar
        u = units
    }

    var n: Int { u.count }

    mutating func scan(from state: SyntaxLineState) -> SyntaxLineState {
        switch g.family {
        case .code: scanCode(from: state)
        case .shell: scanShell(from: state, commandFirst: true)
        case .text: scanText(from: state)
        case .json: scanJSON(from: state)
        case .yaml: scanYAML()
        case .toml: scanTOML(from: state)
        case .markup: scanMarkup(from: state)
        case .css: scanCSS(from: state)
        }
    }

    // MARK: Helpers

    mutating func emit(_ kind: SyntaxTokenKind, _ start: Int, _ end: Int) {
        let end = min(end, n)
        guard end > start else { return }
        tokens.append(SyntaxToken(kind: kind, range: NSRange(location: start, length: end - start)))
    }

    /// Re-kinds the last token, as a string that turns out to be a key.
    mutating func rekindLast(_ kind: SyntaxTokenKind) {
        guard let last = tokens.popLast() else { return }
        tokens.append(SyntaxToken(kind: kind, range: last.range))
    }

    func at(_ k: Int) -> UInt16 { k >= 0 && k < n ? u[k] : 0 }

    func matches(_ text: String, at k: Int) -> Bool {
        var j = k
        for unit in text.utf16 {
            guard j < n, u[j] == unit else { return false }
            j += 1
        }
        return true
    }

    func word(_ start: Int, _ end: Int) -> String { String(decoding: u[start..<min(end, n)], as: UTF16.self) }

    /// ASCII `text`, written in lowercase, at `k` in any case.
    func matchesIgnoringCase(_ text: String, at k: Int) -> Bool {
        var j = k
        for unit in text.utf16 {
            guard j < n, (Unit.isUpper(u[j]) ? u[j] | 0x20 : u[j]) == unit else { return false }
            j += 1
        }
        return true
    }

    func nextNonSpace(from k: Int) -> Int {
        var j = k
        while j < n, Unit.isSpace(u[j]) { j += 1 }
        return j
    }

    func isNameStart(_ c: UInt16) -> Bool {
        Unit.isLetter(c) || c == Unit.underscore || c >= 0x80 || (g.dollarNames && c == Unit.dollar)
    }

    func isNamePart(_ c: UInt16) -> Bool { isNameStart(c) || Unit.isDigit(c) }

    func nameEnd(from k: Int) -> Int {
        var j = k
        while j < n, isNamePart(u[j]) { j += 1 }
        return j
    }

    /// Digits, a radix prefix, a fraction, an exponent and a suffix: `0x1F`, `1_000`, `2.5e-3`, `10u`, `1.0f`.
    func numberEnd(from k: Int) -> Int {
        var j = k + 1
        let hex = at(k) == 0x30 && (at(k + 1) == 0x78 || at(k + 1) == 0x58)
        while j < n {
            let c = u[j]
            if !hex, c == 0x65 || c == 0x45, at(j + 1) == Unit.plus || at(j + 1) == Unit.minus, Unit.isDigit(at(j + 2)) {
                j += 2
            } else if c < 0x80, isNamePart(c) {
                j += 1
            } else if c == Unit.dot, Unit.isDigit(at(j + 1)) {
                j += 1
            } else {
                break
            }
        }
        return j
    }

    /// A string on one line from the quote at `quote`, with backslash escapes unless `raw`; `start` may be a prefix before it.
    mutating func quoted(from start: Int, quote: Int, raw: Bool = false) {
        let mark = u[quote]
        var j = quote + 1
        while j < n {
            if !raw, u[j] == Unit.backslash {
                j += 2
                continue
            }
            j += 1
            if u[j - 1] == mark { break }
        }
        emit(.string, start, j)
        i = min(j, n)
    }

    func multilineRule(at k: Int) -> Int? { g.multilineStrings.firstIndex { matches($0, at: k) } }

    /// A block comment from `start`: at its opener when `depth` is 0, or going on from the line before. Nil when it closes
    /// on this line; otherwise the state it leaves open.
    mutating func blockComment(from start: Int, depth: Int) -> SyntaxLineState? {
        guard let block = g.blockComment else { return nil }
        var depth = depth
        var j = start
        if depth == 0 {
            j += block.open.utf16.count
            depth = 1
        }
        while j < n {
            if matches(block.close, at: j) {
                j += block.close.utf16.count
                depth -= 1
                if depth == 0 {
                    emit(.comment, start, j)
                    i = j
                    return nil
                }
            } else if g.nestsComments, matches(block.open, at: j) {
                j += block.open.utf16.count
                depth += 1
            } else {
                j += 1
            }
        }
        emit(.comment, start, n)
        i = n
        return .blockComment(depth: depth)
    }

    /// A multi-line string from `start` whose text begins at `content`. Nil when it closes on this line.
    mutating func multilineString(_ rule: Int, from start: Int, content: Int) -> SyntaxLineState? {
        let delimiter = g.multilineStrings[rule]
        let raw = g.rawMultilineStrings.contains(delimiter)
        var j = content
        while j < n {
            if !raw, u[j] == Unit.backslash {
                j += 2
            } else if matches(delimiter, at: j) {
                j += delimiter.utf16.count
                emit(.string, start, j)
                i = j
                return nil
            } else {
                j += 1
            }
        }
        emit(.string, start, n)
        i = n
        return .string(rule)
    }

    /// A raw string from `start` whose text begins at `content` and ends at `close`. Nil when it closes on this line.
    mutating func rawString(close: String, from start: Int, content: Int) -> SyntaxLineState? {
        var j = content
        while j < n {
            if matches(close, at: j) {
                j += close.utf16.count
                emit(.string, start, j)
                i = j
                return nil
            }
            j += 1
        }
        emit(.string, start, n)
        i = n
        return .rawString(close: close)
    }

    /// Where a raw string's text begins and what ends it, when the name from `start` to `end` opens one: Rust `r"…"`,
    /// `br#"…"#`; C++ `R"(…)"`, `u8R"x(…)x"`.
    func rawStringOpening(_ start: Int, _ end: Int) -> (content: Int, close: String)? {
        guard let style = g.rawStrings else { return nil }
        let prefix = word(start, end)
        switch style {
        case .rust:
            guard prefix == "r" || prefix == "br" else { return nil }
            var j = end
            while at(j) == Unit.hash { j += 1 }
            guard at(j) == Unit.quote else { return nil }
            return (j + 1, "\"" + String(repeating: "#", count: j - end))
        case .cpp:
            guard ["R", "u8R", "uR", "UR", "LR"].contains(prefix), at(end) == Unit.quote else { return nil }
            var j = end + 1
            while j < n, j - end <= 17, u[j] != Unit.openParen,
                  !Unit.isSpace(u[j]), ![Unit.closeParen, Unit.backslash, Unit.quote].contains(u[j]) { j += 1 }
            guard at(j) == Unit.openParen else { return nil }
            return (j + 1, ")" + word(end + 1, j) + "\"")
        }
    }

    // MARK: C-like, Python, Ruby, SQL

    mutating func scanCode(from state: SyntaxLineState) -> SyntaxLineState {
        switch state {
        case .blockComment(let depth): if let open = blockComment(from: 0, depth: max(1, depth)) { return open }
        case .string(let rule) where g.multilineStrings.indices.contains(rule):
            if let open = multilineString(rule, from: 0, content: 0) { return open }
        case .rawString(let close): if let open = rawString(close: close, from: 0, content: 0) { return open }
        default: break
        }
        var including = false
        if g.directives, i == 0 {
            let k = nextNonSpace(from: 0)
            if at(k) == Unit.hash, Unit.isLetter(at(k + 1)) {
                let end = nameEnd(from: k + 1)
                emit(.keyword, k, end)
                including = ["include", "import"].contains(word(k + 1, end))
                i = end
            }
        }
        var declared: SyntaxTokenKind?
        while i < n {
            let c = u[i]
            if Unit.isSpace(c) {
                i += 1
                continue
            }
            if g.lineComments.contains(where: { matches($0, at: i) }) {
                emit(.comment, i, n)
                return .normal
            }
            if let block = g.blockComment, matches(block.open, at: i) {
                if let open = blockComment(from: i, depth: 0) { return open }
                continue
            }
            if let rule = multilineRule(at: i) {
                if let open = multilineString(rule, from: i, content: i + g.multilineStrings[rule].utf16.count) { return open }
                continue
            }
            if including, c == Unit.less {
                var j = i + 1
                while j < n, u[j] != Unit.greater { j += 1 }
                emit(.string, i, j + 1)
                i = min(j + 1, n)
                continue
            }
            if isNameStart(c) {
                let end = nameEnd(from: i)
                if let raw = rawStringOpening(i, end) {
                    if let open = rawString(close: raw.close, from: i, content: raw.content) { return open }
                    continue
                }
                // A prefixed string: r"…", f'''…''', b"…".
                if !g.stringPrefixes.isEmpty, g.stringPrefixes.contains(word(i, end).lowercased()) {
                    if let rule = multilineRule(at: end) {
                        if let open = multilineString(rule, from: i, content: end + g.multilineStrings[rule].utf16.count) { return open }
                        continue
                    }
                    if g.quotes.contains(at(end)) {
                        quoted(from: i, quote: end, raw: word(i, end).lowercased().contains("r"))
                        continue
                    }
                }
                i = name(from: i, to: end, declared: &declared)
                continue
            }
            declared = nil
            if g.quotes.contains(c) {
                if g.lifetimes, c == Unit.apostrophe, isNameStart(at(i + 1)), at(nameEnd(from: i + 1)) != Unit.apostrophe {
                    let end = nameEnd(from: i + 1)
                    emit(.type, i, end)
                    i = end
                } else {
                    quoted(from: i, quote: i)
                }
                continue
            }
            if Unit.isDigit(c) || (c == Unit.dot && Unit.isDigit(at(i + 1)) && !isNamePart(at(i - 1))) {
                let end = numberEnd(from: i)
                emit(.number, i, end)
                i = end
                continue
            }
            if c == Unit.at, let kind = g.atNames, isNameStart(at(i + 1)) {
                let end = nameEnd(from: i + 1)
                emit(kind, i, end)
                i = end
                continue
            }
            i += 1
        }
        return .normal
    }

    /// Colors a name by its sets, the declaration before it and what follows it. Returns where scanning goes on.
    mutating func name(from start: Int, to end: Int, declared: inout SyntaxTokenKind?) -> Int {
        let text = word(start, end)
        let key = g.caseInsensitive ? text.lowercased() : text
        // A member's name is not a keyword: `app.get`, `entry.value`, `range.to()`. A spread or range (`...rest`) is no member.
        let member = at(start - 1) == Unit.dot && at(start - 2) != Unit.dot && !memberKeywords.contains(key)
        if !member, g.keywords.contains(key) {
            emit(.keyword, start, end)
            declared = g.definitions[key]
            return end
        }
        defer { declared = nil }
        if !member, g.literals.contains(key) {
            emit(.keyword, start, end)
        } else if let kind = declared {
            emit(kind, start, end)
        } else if g.types.contains(key) {
            emit(.type, start, end)
        } else if g.macros, at(end) == Unit.exclamation, at(end + 1) != Unit.equals {
            emit(.function, start, end + 1)
            return end + 1
        } else if at(nextNonSpace(from: end)) == Unit.openParen {
            emit(.function, start, end)
        } else if g.capitalizedTypes, Unit.isUpper(u[start]) {
            emit(.type, start, end)
        }
        return end
    }

    // MARK: Shell and plain-text commands

    /// Where a shell word ends: at a space, an operator or a quote. A backslash escapes the character after it.
    func shellWordEnd(from k: Int) -> Int {
        var j = k
        while j < n {
            let c = u[j]
            if c == Unit.backslash {
                j = min(j + 2, n)
                continue
            }
            if Unit.isSpace(c) || [Unit.pipe, Unit.ampersand, Unit.semicolon, Unit.openParen, Unit.closeParen, Unit.less, Unit.greater,
                                   Unit.quote, Unit.apostrophe, Unit.backtick, Unit.dollar].contains(c) { break }
            j += 1
        }
        return j
    }

    /// `NAME=` at the start of a word, as in `NODE_ENV=production npm start`: where its `=` is.
    func assignment(from k: Int, to end: Int) -> Int? {
        guard Unit.isLetter(at(k)) || at(k) == Unit.underscore else { return nil }
        var j = k + 1
        while j < end, Unit.isLetter(u[j]) || Unit.isDigit(u[j]) || u[j] == Unit.underscore { j += 1 }
        return j < end && u[j] == Unit.equals ? j : nil
    }

    /// Commands at the start of a line and after `|`, `&&`, `;` or `$(`, their flags, variables and strings.
    mutating func scanShell(from state: SyntaxLineState, commandFirst: Bool) -> SyntaxLineState {
        var command = commandFirst && state != .continued
        if case .string(let rule) = state, g.multilineStrings.indices.contains(rule) {
            if let open = multilineString(rule, from: 0, content: 0) { return open }
            command = false
        }
        var expectsIn = false
        while i < n {
            let c = u[i]
            if Unit.isSpace(c) {
                i += 1
                continue
            }
            let wordStart = i == 0 || Unit.isSpace(u[i - 1])
            if c == Unit.hash, wordStart {
                emit(.comment, i, n)
                return .normal
            }
            if c == Unit.backslash, nextNonSpace(from: i + 1) == n { return .continued }
            if c == Unit.quote || c == Unit.apostrophe || c == Unit.backtick {
                // A quoted value right after `NAME=` leaves the command still to come.
                if at(i - 1) != Unit.equals { command = false }
                // A quote that starts a word may go on over lines, as `curl -d '{` does. One inside a word (`It's`) ends
                // with its line, so a stray apostrophe colors one line at most.
                let startsWord = i == 0 || Unit.isSpace(u[i - 1])
                    || [Unit.equals, Unit.openParen, Unit.dollar, Unit.pipe, Unit.semicolon, Unit.ampersand].contains(u[i - 1])
                if startsWord, let rule = multilineRule(at: i) {
                    if let open = multilineString(rule, from: i, content: i + 1) { return open }
                    continue
                }
                quoted(from: i, quote: i, raw: c == Unit.apostrophe)
                continue
            }
            if c == Unit.dollar {
                let next = at(i + 1)
                if next == Unit.openParen {
                    emit(.property, i, i + 2)
                    i += 2
                    command = true
                } else if next == Unit.openBrace {
                    var j = i + 2
                    while j < n, u[j] != Unit.closeBrace { j += 1 }
                    emit(.property, i, j + 1)
                    i = min(j + 1, n)
                    command = false
                } else if Unit.isLetter(next) || next == Unit.underscore {
                    var j = i + 2
                    while j < n, Unit.isLetter(u[j]) || Unit.isDigit(u[j]) || u[j] == Unit.underscore { j += 1 }
                    emit(.property, i, j)
                    i = j
                    command = false
                } else if Unit.isDigit(next) || [Unit.at, Unit.hash, Unit.question, Unit.star, Unit.exclamation, Unit.dollar, Unit.minus].contains(next) {
                    emit(.property, i, i + 2)
                    i += 2
                    command = false
                } else {
                    i += 1
                }
                continue
            }
            if [Unit.pipe, Unit.ampersand, Unit.semicolon, Unit.openParen].contains(c) {
                i += at(i + 1) == c ? 2 : 1
                command = true
                continue
            }
            if [Unit.closeParen, Unit.less, Unit.greater].contains(c) {
                i += 1
                command = false
                continue
            }
            if c == Unit.minus, wordStart, Unit.isLetter(at(i + 1)) || at(i + 1) == Unit.minus {
                var j = i + 1
                while j < n, !Unit.isSpace(u[j]), u[j] != Unit.equals, ![Unit.pipe, Unit.semicolon, Unit.ampersand, Unit.closeParen].contains(u[j]) {
                    j += 1
                }
                emit(.flag, i, j)
                i = j
                command = false
                continue
            }
            let end = max(shellWordEnd(from: i), i + 1)
            if let equals = assignment(from: i, to: end) {
                // The value is not a command; the word after the assignment may be.
                emit(.property, i, equals)
                i = shellWordEnd(from: equals + 1)
                continue
            }
            let text = word(i, end)
            if command {
                if g.keywords.contains(text) {
                    emit(.keyword, i, end)
                    command = commandKeywords.contains(text)
                    expectsIn = ["for", "select", "case"].contains(text)
                } else {
                    emit(.command, i, end)
                    command = prefixCommands.contains(text)
                }
            } else if expectsIn, text == "in" {
                emit(.keyword, i, end)
                expectsIn = false
            } else if text.utf16.allSatisfy(Unit.isDigit) {
                emit(.number, i, end)
            }
            i = end
        }
        return .normal
    }

    /// Plain text stays plain except a command line: a prompt and the command after it, or a slash command such as
    /// `/impeccable document`. A path (`/usr/bin`) is not a slash command.
    mutating func scanText(from state: SyntaxLineState) -> SyntaxLineState {
        if state == .continued { return scanShell(from: .continued, commandFirst: false) }
        let k = nextNonSpace(from: 0)
        guard k < n else { return .normal }
        if prompts.contains(u[k]), at(k + 1) == Unit.space {
            emit(.comment, k, k + 1)
            i = k + 1
            return scanShell(from: .normal, commandFirst: true)
        }
        if u[k] == Unit.slash, Unit.isLetter(at(k + 1)) {
            let end = shellWordEnd(from: k)
            guard !u[(k + 1)..<end].contains(Unit.slash) else { return .normal }
            i = k
            return scanShell(from: .normal, commandFirst: true)
        }
        return .normal
    }

    // MARK: Data

    mutating func scanJSON(from state: SyntaxLineState) -> SyntaxLineState {
        if case .blockComment(let depth) = state, let open = blockComment(from: 0, depth: max(1, depth)) { return open }
        while i < n {
            let c = u[i]
            if Unit.isSpace(c) {
                i += 1
            } else if matches("//", at: i) {
                emit(.comment, i, n)
                return .normal
            } else if matches("/*", at: i) {
                if let open = blockComment(from: i, depth: 0) { return open }
            } else if c == Unit.quote || c == Unit.apostrophe {
                quoted(from: i, quote: i)
                if at(nextNonSpace(from: i)) == Unit.colon { rekindLast(.property) }
            } else if Unit.isDigit(c) || (c == Unit.minus && Unit.isDigit(at(i + 1))) {
                let end = numberEnd(from: c == Unit.minus ? i + 1 : i)
                emit(.number, i, end)
                i = end
            } else if isNameStart(c) {
                let end = nameEnd(from: i)
                if g.literals.contains(word(i, end)) {
                    emit(.keyword, i, end)
                } else if at(nextNonSpace(from: end)) == Unit.colon {
                    emit(.property, i, end)
                }
                i = end
            } else {
                i += 1
            }
        }
        return .normal
    }

    /// Where a YAML key at `k` ends, at its colon, or nil when the line holds no key.
    func yamlKeyEnd(from k: Int) -> Int? {
        guard k < n else { return nil }
        if u[k] == Unit.quote || u[k] == Unit.apostrophe {
            var j = k + 1
            while j < n, u[j] != u[k] { j += 1 }
            return at(j + 1) == Unit.colon && (j + 2 >= n || Unit.isSpace(at(j + 2))) ? j + 1 : nil
        }
        guard ![Unit.openBracket, Unit.openBrace, Unit.hash, Unit.ampersand, Unit.star, Unit.exclamation, Unit.pipe, Unit.greater].contains(u[k]) else {
            return nil
        }
        var j = k
        while j < n {
            if u[j] == Unit.colon, j + 1 >= n || Unit.isSpace(u[j + 1]) { return j > k ? j : nil }
            if u[j] == Unit.hash, j > k, Unit.isSpace(u[j - 1]) { return nil }
            j += 1
        }
        return nil
    }

    mutating func scanYAML() -> SyntaxLineState {
        var k = nextNonSpace(from: 0)
        while at(k) == Unit.minus, k + 1 >= n || Unit.isSpace(at(k + 1)) { k = nextNonSpace(from: k + 1) }
        if let colon = yamlKeyEnd(from: k) {
            emit(.property, k, colon)
            i = colon + 1
        } else {
            i = k
        }
        while i < n {
            let c = u[i]
            let wordStart = i == 0 || Unit.isSpace(u[i - 1])
            if Unit.isSpace(c) {
                i += 1
            } else if c == Unit.hash, wordStart {
                emit(.comment, i, n)
                return .normal
            } else if c == Unit.quote || c == Unit.apostrophe {
                quoted(from: i, quote: i, raw: c == Unit.apostrophe)
            } else if wordStart, [Unit.ampersand, Unit.star, Unit.exclamation].contains(c), i + 1 < n, !Unit.isSpace(u[i + 1]) {
                var j = i + 1
                while j < n, !Unit.isSpace(u[j]) { j += 1 }
                emit(.type, i, j)
                i = j
            } else if [Unit.comma, Unit.openBracket, Unit.closeBracket, Unit.openBrace, Unit.closeBrace].contains(c) {
                i += 1
            } else {
                // A plain scalar: a number, a literal, a key in a flow mapping, or words.
                var j = i
                while j < n, !Unit.isSpace(u[j]), ![Unit.comma, Unit.closeBracket, Unit.closeBrace].contains(u[j]) { j += 1 }
                var end = j
                if at(end - 1) == Unit.colon { end -= 1 }
                let text = word(i, end)
                if end < j {
                    emit(.property, i, end)
                } else if g.literals.contains(text) {
                    emit(.keyword, i, end)
                } else if Unit.isDigit(c) || ((c == Unit.minus || c == Unit.plus || c == Unit.dot) && Unit.isDigit(at(i + 1))) {
                    emit(.number, i, end)
                }
                i = j
            }
        }
        return .normal
    }

    mutating func scanTOML(from state: SyntaxLineState) -> SyntaxLineState {
        if case .string(let rule) = state, g.multilineStrings.indices.contains(rule),
           let open = multilineString(rule, from: 0, content: 0) { return open }
        if i == 0 {
            let k = nextNonSpace(from: 0)
            if at(k) == Unit.openBracket {
                var j = k + 1
                while j < n, u[j] != Unit.closeBracket { j += 1 }
                if at(j + 1) == Unit.closeBracket { j += 1 }
                emit(.type, k, j + 1)
                i = min(j + 1, n)
            }
        }
        func isKey(_ c: UInt16) -> Bool { Unit.isLetter(c) || Unit.isDigit(c) || c == Unit.underscore || c == Unit.minus || c == Unit.dot }
        while i < n {
            let c = u[i]
            if Unit.isSpace(c) {
                i += 1
            } else if c == Unit.hash {
                emit(.comment, i, n)
                return .normal
            } else if let rule = multilineRule(at: i) {
                if let open = multilineString(rule, from: i, content: i + g.multilineStrings[rule].utf16.count) { return open }
            } else if c == Unit.quote || c == Unit.apostrophe {
                quoted(from: i, quote: i, raw: c == Unit.apostrophe)
                let next = nextNonSpace(from: i)
                if at(next) == Unit.equals, at(next + 1) != Unit.equals { rekindLast(.property) }
            } else if Unit.isDigit(c) || ((c == Unit.plus || c == Unit.minus) && Unit.isDigit(at(i + 1))) {
                var j = i + 1
                while j < n, isKey(u[j]) || u[j] == Unit.colon || u[j] == Unit.plus { j += 1 }
                emit(.number, i, j)
                i = j
            } else if isKey(c) {
                var j = i
                while j < n, isKey(u[j]) { j += 1 }
                let next = nextNonSpace(from: j)
                if at(next) == Unit.equals, at(next + 1) != Unit.equals {
                    emit(.property, i, j)
                } else if g.literals.contains(word(i, j)) {
                    emit(.keyword, i, j)
                }
                i = j
            } else {
                i += 1
            }
        }
        return .normal
    }

    // MARK: Markup

    /// A markup comment from `start`; nil when it closes on this line.
    mutating func markupComment(from start: Int, content: Int) -> SyntaxLineState? {
        var j = content
        while j < n, !matches("-->", at: j) { j += 1 }
        guard j < n else {
            emit(.comment, start, n)
            i = n
            return .markupComment
        }
        emit(.comment, start, j + 3)
        i = j + 3
        return nil
    }

    /// The text of a script or style element from `start`: nothing in it is a tag, as `i<items` in a loop is not, until the
    /// element's closing tag. Nil when that tag is on this line, where scanning goes on.
    mutating func rawContent(_ element: Int, from start: Int) -> SyntaxLineState? {
        let close = "</" + rawElements[element]
        var j = start
        while j < n {
            if u[j] == Unit.less, matchesIgnoringCase(close, at: j), !isNamePart(at(j + close.utf16.count)) {
                i = j
                return nil
            }
            j += 1
        }
        i = n
        return .markupRaw(element)
    }

    mutating func scanMarkup(from state: SyntaxLineState) -> SyntaxLineState {
        var inTag = false
        /// The open tag being read is a script or style element's, whose text is raw after its `>`.
        var raw: Int?
        switch state {
        case .markupTag: inTag = true
        case .markupRawTag(let element):
            inTag = true
            raw = element
        case .markupRaw(let element): if let open = rawContent(element, from: 0) { return open }
        case .markupComment: if let open = markupComment(from: 0, content: 0) { return open }
        default: break
        }
        func isTagName(_ c: UInt16) -> Bool { isNamePart(c) || c == Unit.minus || c == Unit.colon || c == Unit.dot }
        /// Template braces open on this line (`{#if a<b}`, `{{ a<b }}`); an open tag does not start inside them.
        var braces = 0
        while i < n {
            let c = u[i]
            if inTag {
                if Unit.isSpace(c) {
                    i += 1
                } else if c == Unit.greater {
                    emit(.tag, i, i + 1)
                    i += 1
                    inTag = false
                    if let element = raw {
                        raw = nil
                        if let open = rawContent(element, from: i) { return open }
                    }
                } else if c == Unit.slash || c == Unit.question, at(i + 1) == Unit.greater {
                    emit(.tag, i, i + 2)
                    i += 2
                    inTag = false
                    raw = nil
                } else if c == Unit.quote || c == Unit.apostrophe {
                    quoted(from: i, quote: i, raw: true)
                } else if c == Unit.equals {
                    i += 1
                    if i < n, !Unit.isSpace(u[i]), u[i] != Unit.quote, u[i] != Unit.apostrophe {
                        var j = i
                        while j < n, !Unit.isSpace(u[j]), u[j] != Unit.greater { j += 1 }
                        emit(.string, i, j)
                        i = j
                    }
                } else {
                    var j = i
                    while j < n, !Unit.isSpace(u[j]), ![Unit.equals, Unit.greater, Unit.slash, Unit.quote, Unit.apostrophe].contains(u[j]) { j += 1 }
                    emit(.property, i, max(j, i + 1))
                    i = max(j, i + 1)
                }
                continue
            }
            if c == Unit.openBrace {
                braces += 1
            } else if c == Unit.closeBrace, braces > 0 {
                braces -= 1
            }
            if c == Unit.less {
                if matches("<!--", at: i) {
                    if let open = markupComment(from: i, content: i + 4) { return open }
                    continue
                }
                if at(i + 1) == Unit.exclamation || at(i + 1) == Unit.question {
                    var j = i + 2
                    while j < n, u[j] != Unit.greater { j += 1 }
                    emit(.keyword, i, j + 1)
                    i = min(j + 1, n)
                    continue
                }
                let closing = at(i + 1) == Unit.slash
                let name = closing ? i + 2 : i + 1
                if Unit.isLetter(at(name)), closing || braces == 0 {
                    var j = name
                    while j < n, isTagName(u[j]) { j += 1 }
                    emit(.tag, i, j)
                    if !closing { raw = rawElements.firstIndex(of: word(name, j).lowercased()) }
                    i = j
                    inTag = true
                    continue
                }
            }
            if c == Unit.ampersand {
                var j = i + 1
                while j < n, Unit.isLetter(u[j]) || Unit.isDigit(u[j]) || u[j] == Unit.hash { j += 1 }
                if j > i + 1, at(j) == Unit.semicolon {
                    emit(.number, i, j + 1)
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
        guard inTag else { return .normal }
        return raw.map { .markupRawTag($0) } ?? .markupTag
    }

    // MARK: CSS

    func cssNameEnd(from k: Int) -> Int {
        var j = k
        while j < n, isNamePart(u[j]) || u[j] == Unit.minus { j += 1 }
        return j
    }

    /// Whether the rest of the line opens a block before it ends a declaration: `a:hover {` is a selector, `color: red;` is not.
    /// The next `{`, `;` or `}` is the same for every place before it, so a long line is searched once.
    mutating func opensBlock(from k: Int) -> Bool {
        if !(stopSearchedFrom <= k && k <= stop) {
            var j = k
            while j < n, u[j] != Unit.openBrace, u[j] != Unit.semicolon, u[j] != Unit.closeBrace { j += 1 }
            (stopSearchedFrom, stop) = (k, j)
        }
        return stop < n && u[stop] == Unit.openBrace
    }

    mutating func scanCSS(from state: SyntaxLineState) -> SyntaxLineState {
        var depth = 0
        switch state {
        case .css(let open): depth = open
        case .cssComment(let open):
            depth = open
            var j = 0
            while j < n, !matches("*/", at: j) { j += 1 }
            guard j < n else {
                emit(.comment, 0, n)
                return state
            }
            emit(.comment, 0, j + 2)
            i = j + 2
        default: break
        }
        var declaration = false
        while i < n {
            let c = u[i]
            if Unit.isSpace(c) {
                i += 1
                continue
            }
            if matches("/*", at: i) {
                var j = i + 2
                while j < n, !matches("*/", at: j) { j += 1 }
                guard j < n else {
                    emit(.comment, i, n)
                    return .cssComment(depth: depth)
                }
                emit(.comment, i, j + 2)
                i = j + 2
                continue
            }
            if matches("//", at: i), at(i - 1) != Unit.colon {
                emit(.comment, i, n)
                break
            }
            switch c {
            case Unit.openBrace:
                depth += 1
                declaration = false
                i += 1
                continue
            case Unit.closeBrace:
                depth = max(0, depth - 1)
                declaration = false
                i += 1
                continue
            case Unit.semicolon:
                declaration = false
                i += 1
                continue
            case Unit.quote, Unit.apostrophe:
                quoted(from: i, quote: i)
                continue
            default: break
            }
            if !declaration, c == Unit.dollar || c == Unit.at, isNameStart(at(i + 1)) {
                // A variable declared at any depth: SCSS `$primary: #333;`, Less `@primary: #333;`.
                let end = cssNameEnd(from: i + 1)
                let colon = nextNonSpace(from: end)
                if at(colon) == Unit.colon {
                    emit(.property, i, end)
                    i = colon + 1
                    declaration = true
                    continue
                }
            }
            if c == Unit.at, isNameStart(at(i + 1)) {
                // An at-rule's prelude (`@media (max-width: 600px)`) reads like a value.
                let end = cssNameEnd(from: i + 1)
                emit(.keyword, i, end)
                i = end
                declaration = true
                continue
            }
            if c == Unit.exclamation, matches("important", at: i + 1) {
                emit(.keyword, i, i + 10)
                i += 10
                continue
            }
            if declaration {
                if c == Unit.hash, Unit.isHexDigit(at(i + 1)) {
                    let end = cssNameEnd(from: i + 1)
                    emit(.number, i, end)
                    i = end
                } else if Unit.isDigit(c) || ([Unit.dot, Unit.minus, Unit.plus].contains(c) && Unit.isDigit(at(i + 1))) {
                    var j = i + 1
                    while j < n, Unit.isDigit(u[j]) || Unit.isLetter(u[j]) || u[j] == Unit.dot || u[j] == Unit.percent { j += 1 }
                    emit(.number, i, j)
                    i = j
                } else if isNameStart(c) || c == Unit.minus {
                    let end = cssNameEnd(from: i)
                    if at(end) == Unit.openParen {
                        emit(.function, i, end)
                        let isURL = word(i, end).lowercased() == "url"
                        i = end
                        if isURL {
                            var j = end + 1
                            while j < n, u[j] != Unit.closeParen { j += 1 }
                            if at(nextNonSpace(from: end + 1)) != Unit.quote, at(nextNonSpace(from: end + 1)) != Unit.apostrophe {
                                emit(.string, end + 1, j)
                                i = j
                            }
                        }
                    } else {
                        i = end
                    }
                } else {
                    i += 1
                }
                continue
            }
            if depth > 0, isNameStart(c) || c == Unit.minus {
                let end = cssNameEnd(from: i)
                let colon = nextNonSpace(from: end)
                if at(colon) == Unit.colon, !opensBlock(from: colon) {
                    emit(.property, i, end)
                    i = colon + 1
                    declaration = true
                    continue
                }
            }
            if isNameStart(c) || [Unit.dot, Unit.hash, Unit.colon, Unit.ampersand, Unit.star, Unit.minus].contains(c) {
                // A selector: `.class`, `#id`, `:hover`, `&`, `*`, or a name. A colon alone is punctuation.
                var j = i
                while j < n, [Unit.dot, Unit.hash, Unit.colon, Unit.ampersand, Unit.star].contains(u[j]) { j += 1 }
                j = cssNameEnd(from: j)
                if u[(i)..<j].contains(where: { $0 != Unit.colon }) { emit(.tag, i, j) }
                i = max(j, i + 1)
                continue
            }
            i += 1
        }
        return depth == 0 ? .normal : .css(depth: depth)
    }
}
