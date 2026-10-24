import Foundation

/// Keeps the code blocks the app fenced in a model input intact in the model's output. Comments may come
/// back translated; any other change to a code line goes back to the page's bytes, and a block the model
/// unfenced, rewrote or dropped is fenced, restored or inserted again where the source had it. Its opener is
/// always the source's, title included. Blocks of text, console output and data stay byte for byte. Pure and
/// deterministic: restoring its own output changes nothing.
enum CodeBlockGuard {
    struct Outcome: Equatable, Sendable {
        /// Found fenced, every line kept or only its comment translated.
        var kept = 0
        /// Found fenced but changed; changed lines went back to the source.
        var restored = 0
        /// Found as prose, or as a translated command line, and fenced again.
        var refenced = 0
        /// Not found; inserted where the source had it.
        var inserted = 0
        /// The model input does not carry these blocks, or the repair would not read back; the output is unchanged.
        var skipped = false
    }

    /// `modelInput` is the text the model got, with `blocks` fenced in it in order.
    static func restore(_ output: String, source modelInput: String, blocks: [SourceCodeBlock]) -> (text: String, outcome: Outcome) {
        guard !blocks.isEmpty else { return (output, Outcome()) }
        let source = TranslationMarkup.layout(modelInput)
        guard source.blocks.count == blocks.count, zip(source.blocks, blocks).allSatisfy({ $0.code == $1.lines }) else {
            return (output, Outcome(skipped: true))
        }
        let expected = blocks.map(Expected.init), titles = titleLines(source, of: blocks)
        let ordinals = source.proseOrdinals(skipping: titles)
        let places = source.blocks.map { block in
            (slot: ordinals[block.opener], gap: (0..<block.opener).reversed().prefix { source.kinds[$0] == .blank }.count)
        }
        var repair = Repair(layout: TranslationMarkup.layout(output), blocks: expected, places: places)
        repair.run()
        let text = removingTitleLines(repair.text(), blocks: blocks, source: source)
        // Every block must read back as written, in order, and restoring again must change nothing; otherwise the
        // output stays as the model wrote it.
        var check = Repair(layout: TranslationMarkup.layout(text), blocks: expected, places: places)
        check.run()
        guard readsBack(text, expected), check.outcome.kept == blocks.count, check.text() == text else { return (output, Outcome(skipped: true)) }
        return (text, repair.outcome)
    }

    /// Whether each block reads back from `text`, in order, as a block of its own: its opener's info and length, a
    /// closer, and as many lines as it has, each one it accepts.
    private static func readsBack(_ text: String, _ blocks: [Expected]) -> Bool {
        var remaining = blocks[...]
        for block in TranslationMarkup.layout(text).blocks {
            guard let expected = remaining.first else { break }
            if block.closer != nil, block.fence.inlineCode == nil, block.fence.length == expected.block.fence, block.fence.info == expected.block.info,
               block.code.count == expected.lines.count, expected.lines.indices.allSatisfy({ expected.accepts($0, block.code[$0]) }) {
                remaining.removeFirst()
            }
        }
        return remaining.isEmpty
    }

    /// The lines a block could start on unfenced: all its lines pass there as prose, at least one byte for byte.
    private static func proseStarts(_ layout: TranslationMarkup.LineLayout, of expected: Expected) -> [Int] {
        let length = expected.lines.count
        return layout.lines.indices.filter { start in
            let lines = start..<(start + length)
            return lines.upperBound <= layout.lines.count
                && lines.allSatisfy { (layout.kinds[$0] == .prose || layout.kinds[$0] == .blank) && expected.accepts($0 - start, layout.lines[$0]) }
                && lines.contains { layout.kinds[$0] == .prose && expected.isExact($0 - start, layout.lines[$0]) }
        }
    }

    /// All lines where some block could stand unfenced (`proseStarts`).
    private static func proseCode(_ layout: TranslationMarkup.LineLayout, _ blocks: [Expected]) -> Set<Int> {
        Set(blocks.flatMap { expected in proseStarts(layout, of: expected).flatMap { $0..<($0 + expected.lines.count) } })
    }

    /// A line that would open or close a fence once a model fence around it is gone.
    private static func isFenceLine(_ line: String) -> Bool {
        guard let parts = TranslationMarkup.fenceParts(line) else { return false }
        return parts.run >= 3 && !parts.rest.contains("`")
    }

    /// A block's title the model also wrote as lines of their own right above the block, verbatim or as all their text,
    /// goes: the opener carries it, and the result shows it once. A line the model input has above the block as well,
    /// right there or with blank lines between, stays.
    private static func removingTitleLines(_ text: String, blocks: [SourceCodeBlock], source: TranslationMarkup.LineLayout) -> String {
        let layout = TranslationMarkup.layout(text)
        func isTitle(_ line: Int, of block: SourceCodeBlock, in layout: TranslationMarkup.LineLayout) -> Bool {
            line >= 0 && layout.kinds[line] == .prose && CodeBlockGuard.isTitle(layout.lines[line], of: block)
        }
        var removed: Set<Int> = []
        var index = 0
        for block in layout.blocks where index < blocks.count && layout.lines[block.opener] == blocks[index].opener && block.code.count == blocks[index].lines.count {
            // The input's own line may sit a blank line above the block; the model may drop that blank line.
            let above = (0..<source.blocks[index].opener).last { source.kinds[$0] != .blank } ?? -1
            if !isTitle(above, of: blocks[index], in: source) {
                var line = block.opener - 1
                while isTitle(line, of: blocks[index], in: layout) {
                    removed.insert(line)
                    line -= 1
                }
            }
            index += 1
        }
        guard !removed.isEmpty else { return text }
        return layout.lines.indices.filter { !removed.contains($0) }.map { layout.lines[$0] }.joined(separator: "\n") + (layout.terminated ? "\n" : "")
    }

    /// A line that is a block's title and nothing else.
    private static func isTitle(_ line: String, of block: SourceCodeBlock) -> Bool {
        block.title != nil && SourceCodeBlock.title(trimmed(line)) == block.title
    }

    /// Prose lines that are a block's title and nothing else. The model input has the block's opener in their place, so
    /// where blocks go they count as no prose, in the input and in the output alike.
    private static func titleLines(_ layout: TranslationMarkup.LineLayout, of blocks: [SourceCodeBlock]) -> Set<Int> {
        let titles = Set(blocks.compactMap(\.title))
        guard !titles.isEmpty else { return [] }
        return Set(layout.lines.indices.filter { layout.kinds[$0] == .prose && SourceCodeBlock.title(trimmed(layout.lines[$0])).map(titles.contains) == true })
    }

    // MARK: - Matching

    /// A source block with the rule for each of its lines.
    private struct Expected {
        let block: SourceCodeBlock
        let lines: [String]
        let rules: [LineRule]

        init(_ block: SourceCodeBlock) {
            self.block = block
            lines = block.lines
            rules = CodeBlockGuard.rules(for: lines, comments: CodeBlockGuard.comments(for: block.language))
        }

        func accepts(_ index: Int, _ line: String) -> Bool { CodeBlockGuard.accepts(rules[index], lines[index], line) }
        /// Byte for byte, trailing spaces aside, not just a translated comment.
        func isExact(_ index: Int, _ line: String) -> Bool { CodeBlockGuard.trimmed(lines[index]) == CodeBlockGuard.trimmed(line) }
        /// Lines of the model's that may stand for the source's, in order: a longest common subsequence.
        func overlap(_ code: [String]) -> Int {
            var row = [Int](repeating: 0, count: code.count + 1)
            for index in lines.indices {
                var diagonal = 0
                for (offset, line) in code.enumerated() {
                    let above = row[offset + 1]
                    row[offset + 1] = accepts(index, line) ? diagonal + 1 : max(above, row[offset])
                    diagonal = above
                }
            }
            return row[code.count]
        }
        /// The first offset in `code`, from `start`, where all its lines follow.
        func contained(in code: [String], from start: Int) -> Int? {
            guard code.count - start >= lines.count else { return nil }
            return (start...(code.count - lines.count)).first { offset in lines.indices.allSatisfy { accepts($0, code[offset + $0]) } }
        }
        /// The model's line where it is accepted, the source's where it is not.
        func merged(_ code: ArraySlice<String>) -> [String] {
            zip(lines.indices, code).map { accepts($0, $1) ? $1 : lines[$0] }
        }
        /// All its lines for model lines that stand for its first ones: theirs where they pass, then its own.
        func completed(_ code: ArraySlice<String>) -> [String] { merged(code) + lines[code.count...] }
        /// Model lines that are its lines with words translated, from its first line on: the first of `starts` that
        /// translates its first line, and how many lines from there, before `end` and where `eligible`, stand for its own.
        func commands(in code: [String], startingAt starts: some Sequence<Int>, before end: Int,
                      where eligible: (Int) -> Bool = { _ in true }) -> (start: Int, count: Int)? {
            guard let start = starts.first(where: { CodeBlockGuard.anchored(lines[0], code[$0]) }) else { return nil }
            return (start, 1 + (1..<lines.count).prefix { offset in
                start + offset < end && eligible(start + offset)
                    && (accepts(offset, code[start + offset]) || CodeBlockGuard.anchored(lines[offset], code[start + offset]))
            }.count)
        }
        /// The model lines from the first to the last that pass for one of its lines or translate one.
        func span(in code: [String]) -> ClosedRange<Int>? {
            let matching = code.indices.filter { at in lines.indices.contains { accepts($0, code[at]) || CodeBlockGuard.anchored(lines[$0], code[at]) } }
            return matching.first.map { $0...matching[matching.count - 1] }
        }
        var fenced: [String] { [block.opener] + lines + [block.closer] }
        /// A fence line that reads as code but starts with its tag: its opener with the title written wrong
        /// (```text title=Most Agents, without quotes). Right above its lines, it is its opener all the same.
        func isOpener(_ line: String) -> Bool { block.tag.map { CodeBlockGuard.firstToken(line)?.lowercased() == $0 } == true }
    }

    private struct Repair {
        /// Where a block stands intact: from a code line of a model fence on, or as prose lines.
        enum Intact: Equatable { case fence(Int, offset: Int), prose(start: Int) }

        let layout: TranslationMarkup.LineLayout
        let blocks: [Expected]
        /// For each block, the non-blank prose lines before it in the source but for title lines, and the blank lines right before it.
        let places: [(slot: Int, gap: Int)]
        /// Lines that are a block's title, which count as no prose (`titleLines`).
        private let titles: Set<Int>
        var outcome = Outcome()
        /// Replacements of output lines, in order; an empty range inserts.
        private var edits: [(range: Range<Int>, lines: [String])] = []
        /// Output lines before this are settled.
        private var cursor = 0
        private var used: Set<Int> = []
        /// Blocks found intact, chosen together before any other repair, so a block never takes another's place.
        private var intact: [Int: Intact] = [:]
        /// Prose lines that are a block's code; they are no prose of the translation.
        private var code: Set<Int> = []
        /// Non-blank prose lines before each line, and in all at the end, not counting `code` or `titles`.
        private var ordinals: [Int]
        /// A model fence split around blocks found in it, in order: where each starts in its code, how many lines it
        /// takes there (none for a block inserted), and the block's lines.
        private var open: (fence: Int, end: Int, parts: [(offset: Int, count: Int, block: Int, lines: [String])])?

        init(layout: TranslationMarkup.LineLayout, blocks: [Expected], places: [(slot: Int, gap: Int)]) {
            self.layout = layout
            self.blocks = blocks
            self.places = places
            titles = CodeBlockGuard.titleLines(layout, of: blocks.map(\.block))
            ordinals = layout.proseOrdinals(skipping: titles)
        }

        mutating func run() {
            intact = intactPlaces()
            for case let (index, .prose(start)) in intact { code.formUnion(start..<(start + blocks[index].lines.count)) }
            markCode()
            for index in blocks.indices {
                if let place = intact[index] { take(index, place) } else { place(index) }
            }
            close()
        }

        func text() -> String {
            var lines: [String] = []
            var next = 0
            for edit in edits {
                lines += layout.lines[next..<edit.range.lowerBound]
                lines += edit.lines
                next = edit.range.upperBound
            }
            lines += layout.lines[next...]
            return lines.joined(separator: "\n") + (layout.terminated ? "\n" : "")
        }

        /// Counts prose again once `lines` are a block's code.
        private mutating func markCode(_ lines: Range<Int> = 0..<0) {
            code.formUnion(lines)
            ordinals = layout.proseOrdinals(skipping: code.union(titles))
        }

        private func ordinal(before line: Int) -> Int { ordinals[min(max(line, 0), ordinals.count - 1)] }
        private func isProse(_ line: Int) -> Bool { ordinals[line + 1] > ordinals[line] }

        /// The most blocks that stand intact, in order, then those nearest where the source had them. A block's
        /// lines all pass inside a model fence (several blocks may share one when the whole answer is fenced), or
        /// stand unfenced with at least one line byte for byte.
        private func intactPlaces() -> [Int: Intact] {
            typealias Found = (start: Int, place: Intact, distance: Int)
            enum Step { case skipBlock, skipLine, take(Found) }
            let count = layout.lines.count
            // Distances leave out lines where a block may stand unfenced: a block the model unfenced moves no fenced
            // block after it (the source has no such line in its place).
            let starts = blocks.map { CodeBlockGuard.proseStarts(layout, of: $0) }
            let near = layout.proseOrdinals(skipping: titles.union(CodeBlockGuard.proseCode(layout, blocks)))
            // Each block's intact places by the line they end on.
            let found: [[Int: [Found]]] = blocks.indices.map { index in
                let expected = blocks[index], length = expected.lines.count
                func distance(_ start: Int) -> Int { abs(near[start] - places[index].slot) }
                var ends: [Int: [Found]] = [:]
                for (fence, block) in layout.blocks.enumerated() {
                    let first = block.fence.inlineCode == nil ? block.opener + 1 : block.opener
                    var from = 0
                    while let offset = expected.contained(in: block.code, from: from) {
                        ends[first + offset + length - 1, default: []].append((first + offset, .fence(fence, offset: offset), distance(first + offset)))
                        from = offset + 1
                    }
                }
                for start in starts[index] {
                    ends[start + length - 1, default: []].append((start, .prose(start: start), distance(start)))
                }
                return ends
            }
            func better(_ a: (found: Int, distance: Int), _ b: (found: Int, distance: Int)) -> Bool {
                a.found > b.found || a.found == b.found && a.distance < b.distance
            }
            // best[i][line]: blocks before i placed in the lines before `line`.
            var best = [[(found: Int, distance: Int)]](repeating: Array(repeating: (0, 0), count: count + 1), count: blocks.count + 1)
            var steps = [[Step]](repeating: Array(repeating: .skipBlock, count: count + 1), count: blocks.count + 1)
            for index in blocks.indices {
                for line in 0...count {
                    var score = best[index][line], step = Step.skipBlock
                    if line > 0, better(best[index + 1][line - 1], score) { (score, step) = (best[index + 1][line - 1], .skipLine) }
                    for place in line > 0 ? found[index][line - 1] ?? [] : [] {
                        let taken = (best[index][place.start].found + 1, best[index][place.start].distance + place.distance)
                        if better(taken, score) { (score, step) = (taken, .take(place)) }
                    }
                    best[index + 1][line] = score
                    steps[index + 1][line] = step
                }
            }
            var result: [Int: Intact] = [:]
            var index = blocks.count, line = count
            while index > 0 {
                switch steps[index][line] {
                case .skipBlock: index -= 1
                case .skipLine: line -= 1
                case .take(let place):
                    result[index - 1] = place.place
                    (index, line) = (index - 1, place.start)
                }
            }
            return result
        }

        private mutating func take(_ index: Int, _ place: Intact) {
            let expected = blocks[index], count = expected.lines.count
            switch place {
            case let .fence(fence, offset):
                if open?.fence != fence {
                    close()
                    used.insert(fence)
                    open = (fence, 0, [])
                }
                open?.parts.append((offset, count, index, Array(layout.blocks[fence].code[offset..<(offset + count)])))
                open?.end = offset + count
                outcome.kept += 1
            case let .prose(start):
                close()
                replace(start..<(start + count), with: [expected.block.opener] + expected.merged(layout.lines[start..<(start + count)]) + [expected.block.closer])
                outcome.refenced += 1
            }
        }

        /// A block not found intact, looked for only between the blocks around it that were.
        private mutating func place(_ index: Int) {
            let expected = blocks[index], (slot, gap) = places[index], count = expected.lines.count
            let next = intact.filter { $0.key > index }.min { $0.key < $1.key }?.value
            // A model fence split around blocks found in it (a whole answer fenced at once) is prose there: its translated
            // commands become the block, and a block missing between two found in it goes in after the first.
            if let open {
                let code = layout.blocks[open.fence].code
                let end = if case .fence(let fence, let offset)? = next, fence == open.fence { offset } else { code.count }
                if let (start, taken) = expected.commands(in: code, startingAt: open.end..<end, before: end) {
                    self.open?.parts.append((start, taken, index, expected.completed(code[start..<(start + taken)])))
                    self.open?.end = start + taken
                    outcome.refenced += 1
                    return
                }
                if end < code.count {
                    self.open?.parts.append((open.end, 0, index, expected.lines))
                    outcome.inserted += 1
                    return
                }
            }
            close()
            let limit = switch next {
            case .fence(let fence, _)?: layout.blocks[fence].opener
            case .prose(let start)?: start
            case nil: layout.lines.count
            }
            let fences = layout.blocks.indices.filter { !used.contains($0) && layout.blocks[$0].opener >= cursor && layout.blocks[$0].end < limit }
            // B. A model fence that is mostly this block.
            if let fence = fences.first(where: { expected.overlap(layout.blocks[$0].code) * 2 >= count }) { return restore(index, from: fence) }
            // C. Prose lines where the block was, mostly its lines or its command with words translated.
            // A line away from the slot only where no later missing block shows itself right at its own (`claimed`).
            let candidates = (cursor..<limit).filter { line in
                isProse(line) && abs(ordinal(before: line) - slot) <= 1
                    && (ordinal(before: line) == slot || !claimed(line, after: index) { $0.accepts(0, layout.lines[line]) || CodeBlockGuard.anchored($0.lines[0], layout.lines[line]) })
            }
            for start in candidates where start + count <= limit {
                let lines = Array(layout.lines[start..<(start + count)])
                guard (start..<(start + count)).allSatisfy({ layout.kinds[$0] == .prose || layout.kinds[$0] == .blank }) else { continue }
                let accepted = lines.indices.filter { expected.accepts($0, lines[$0]) }.count
                let anchored = lines.indices.filter { !expected.accepts($0, lines[$0]) && CodeBlockGuard.anchored(expected.lines[$0], lines[$0]) }.count
                let anchorsCount = count <= 2 || ordinal(before: start) == slot
                    && CodeBlockGuard.firstToken(lines[0]) == CodeBlockGuard.firstToken(expected.lines[0])
                guard accepted + anchored == count, (accepted + (anchorsCount ? anchored : 0)) * 2 >= count else { continue }
                markCode(start..<(start + count))
                replace(start..<(start + count), with: [expected.block.opener] + expected.merged(lines[...]) + [expected.block.closer])
                outcome.refenced += 1
                return
            }
            // No block twice: prose lines that are its translated commands, from its first line on, become the block.
            let kinds = layout.kinds, prose = { (line: Int) in kinds[line] == .prose }
            if let (line, taken) = expected.commands(in: layout.lines, startingAt: candidates, before: limit, where: prose) {
                markCode(line..<(line + taken))
                replace(line..<(line + taken), with: [expected.block.opener] + expected.completed(layout.lines[line..<(line + taken)]) + [expected.block.closer])
                outcome.refenced += 1
                return
            }
            // B. A model fence where the block was that is not the next block and shows this one: a line that passes or
            // is a translated command ("```text\n/impeccable 문서"), or its tag on no more lines than it has.
            let following = index + 1 < blocks.count ? blocks[index + 1] : nil
            if let fence = fences.first(where: { fence in
                let block = layout.blocks[fence]
                return abs(ordinal(before: block.opener) - slot) <= 1
                    && (ordinal(before: block.opener) == slot || !claimed(block.opener, after: index) { $0.span(in: block.code) != nil })
                    && following.map { $0.overlap(block.code) * 2 >= $0.lines.count } != true
                    && (expected.span(in: block.code) != nil
                        || expected.block.tag.map { block.fence.language?.lowercased() == $0 } == true && block.code.count <= count)
            }) { return restore(index, from: fence) }
            // The next model fence, before the block found in it: its translated commands there become the block.
            if case .fence(let fence, let offset)? = next {
                let code = layout.blocks[fence].code
                if let (start, taken) = expected.commands(in: code, startingAt: 0..<offset, before: offset) {
                    used.insert(fence)
                    open = (fence, start + taken, [(start, taken, index, expected.completed(code[start..<(start + taken)]))])
                    outcome.refenced += 1
                    return
                }
            }
            // D. Missing: after as many prose lines as the source had before it, and the blank lines it had between.
            var after = slot == 0 ? cursor : (0..<layout.lines.count).first { isProse($0) && ordinal(before: $0) == slot - 1 }.map { $0 + 1 } ?? layout.lines.count
            after += (after..<layout.lines.count).prefix { layout.kinds[$0] == .blank }.prefix(gap).count
            // A title line the model kept there stays above it, right where a duplicate of the opener's title goes.
            after += (after..<layout.lines.count).prefix { layout.kinds[$0] == .prose && CodeBlockGuard.isTitle(layout.lines[$0], of: expected.block) }.count
            let at = min(max(after, cursor), limit)
            replace(at..<at, with: expected.fenced)
            outcome.inserted += 1
        }

        /// Whether a later block, missing as well before the next one found intact, shows itself at `line` right at its own slot.
        private func claimed(_ line: Int, after index: Int, _ shows: (Expected) -> Bool) -> Bool {
            var later = index + 1
            while later < blocks.count, intact[later] == nil {
                if places[later].slot == ordinal(before: line), shows(blocks[later]) { return true }
                later += 1
            }
            return false
        }

        /// The source's block in place of a model fence: the model's lines where they pass, if it has as many. In a
        /// longer fence (a whole answer fenced at once) lines before and after all that stand for the block's leave it as
        /// prose, but for fence lines.
        private mutating func restore(_ index: Int, from fence: Int) {
            let expected = blocks[index], block = layout.blocks[fence]
            used.insert(fence)
            let span = block.code.count > expected.lines.count ? expected.span(in: block.code) : nil
            let code = span.map { block.code[$0] } ?? block.code[...]
            let lines = code.count == expected.lines.count ? expected.merged(code) : expected.lines
            var before = span.map { block.code[..<$0.lowerBound].filter { !CodeBlockGuard.isFenceLine($0) } } ?? []
            let after = span.map { block.code[($0.upperBound + 1)...].filter { !CodeBlockGuard.isFenceLine($0) } } ?? []
            if block.fence.inlineCode != nil, before.count == 1, before.first.map(expected.isOpener) == true { before = [] }
            replace(block.opener..<(block.end + 1), with: before + [expected.block.opener] + lines + [expected.block.closer] + after)
            outcome.restored += 1
        }

        /// Writes the open model fence: its lines around the blocks found in it leave the fence as prose, but for an opener
        /// written wrong right above the first and fence lines (a model fence around an opener of the app's, its closer
        /// missing, or ```markdown around the whole answer), which would fence the prose or add to a block.
        private mutating func close() {
            guard let open else { return }
            self.open = nil
            let fence = layout.blocks[open.fence]
            var lines: [String] = []
            var next = 0
            if fence.fence.inlineCode != nil, let first = open.parts.first, first.offset == 1, blocks[first.block].isOpener(fence.code[0]) { next = 1 }
            for (offset, count, index, code) in open.parts {
                lines += fence.code[next..<offset].filter { !CodeBlockGuard.isFenceLine($0) }
                lines += [blocks[index].block.opener] + code + [blocks[index].block.closer]
                next = offset + count
            }
            lines += fence.code[next...].filter { !CodeBlockGuard.isFenceLine($0) }
            replace(fence.opener..<(fence.end + 1), with: lines)
        }

        private mutating func replace(_ range: Range<Int>, with lines: [String]) {
            edits.append((range, lines))
            cursor = range.upperBound
        }
    }

    // MARK: - Comments

    /// How a language writes comments.
    private struct Comments {
        var line: [String] = []
        var block: [(open: String, close: String)] = []
        /// Text, console output and data: every line stays byte for byte.
        var verbatim = false
        /// No or an unknown language: markers count only with a space after them, and a comment may change only
        /// after code on its line, or in a block of nothing but comments (`# apt install` is a root prompt).
        /// `--` is no marker here: shells end options with it (`git checkout -- README.md`).
        var generic = false
        var apostrophe = Apostrophe.quote
    }

    /// What `'` is in a language.
    private enum Apostrophe {
        /// It quotes strings, as `"` does.
        case quote
        /// It quotes one character (`'a'`, `'\n'`, `'"'`) and is otherwise part of the code: a Rust lifetime (`&'a str`),
        /// a Haskell prime (`foldl'`).
        case character
        /// It quotes nothing (Lisp's `'(1 2)`).
        case plain
    }

    private static func comments(for language: String?) -> Comments {
        switch language {
        case "python", "py", "python3", "rb", "ruby", "sh", "bash", "zsh", "shell", "fish", "yaml", "yml", "toml", "perl", "pl", "r",
             "makefile", "dockerfile", "powershell", "ps1", "elixir", "ex", "julia", "jl", "cmake", "graphql", "gql":
            Comments(line: ["#"])
        case "ini": Comments(line: [";", "#"])
        case "php": Comments(line: ["//", "#"], block: [("/*", "*/")])
        case "c", "h", "cpp", "c++", "cc", "cxx", "hpp", "cs", "csharp", "c#", "objc", "objective-c", "swift", "js", "javascript", "jsx",
             "ts", "typescript", "tsx", "go", "golang", "java", "kotlin", "kt", "scala", "dart", "jsonc", "scss", "sass",
             "less", "proto", "protobuf", "vue", "svelte", "astro":
            Comments(line: ["//"], block: [("/*", "*/")])
        case "rust", "rs": Comments(line: ["//"], block: [("/*", "*/")], apostrophe: .character)
        case "css": Comments(block: [("/*", "*/")])
        case "sql": Comments(line: ["--"], block: [("/*", "*/")])
        case "lua": Comments(line: ["--"])
        case "haskell", "hs": Comments(line: ["--"], apostrophe: .character)
        case "lisp", "clojure", "clj": Comments(line: [";"], apostrophe: .plain)
        case "tex", "latex", "erlang", "erl", "matlab": Comments(line: ["%"])
        case "html", "htm", "xml", "md", "markdown", "mdx", "svg": Comments(block: [("<!--", "-->")])
        case "text", "txt", "plaintext", "plain", "json", "diff", "patch", "csv", "console", "terminal", "shell-session": Comments(verbatim: true)
        default: Comments(line: ["# ", "// "], block: [("/*", "*/")], generic: true)
        }
    }

    private enum LineRule: Equatable {
        /// Byte for byte, trailing spaces aside.
        case exact
        /// The code through the comment marker, then anything, then the comment's closer and what follows it.
        case comment(prefix: String, suffix: String)
        /// Inside a block comment: the same indent and `*` gutter, then anything, then the closer if it is here.
        case interior(indent: String, star: Bool, suffix: String)
    }

    /// Where a comment starts on a line, outside string literals (quotes paired by parity, escapes skipped) and
    /// character literals. Line markers need a space or the line start before them.
    private static func commentStart(_ line: String, _ comments: Comments) -> (index: String.Index, marker: String, close: String?)? {
        var quote: Character?
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if let open = quote {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == open { quote = nil }
            } else if character == "\"" || character == "`" || character == "'" && comments.apostrophe == .quote {
                quote = character
            } else if character == "'", comments.apostrophe == .character, let end = characterLiteralEnd(line, from: index) {
                index = end
                continue
            } else {
                let rest = line[index...]
                let spaced = index == line.startIndex || line[line.index(before: index)].isWhitespace
                if spaced, let marker = comments.line.first(where: { rest.hasPrefix($0) }) { return (index, marker, nil) }
                if let pair = comments.block.first(where: { rest.hasPrefix($0.open) }) { return (index, pair.open, pair.close) }
            }
            index = line.index(after: index)
        }
        return nil
    }

    /// Past a character literal that starts at `start`: one character, or an escape, then `'`.
    private static func characterLiteralEnd(_ line: String, from start: String.Index) -> String.Index? {
        var index = line.index(after: start)
        guard index < line.endIndex else { return nil }
        if line[index] == "\\" {
            // An escape: `'\''`, `'\n'`, `'\u{1F600}'`.
            index = line.index(after: index)
            guard index < line.endIndex else { return nil }
            index = line.index(after: index)
            guard let close = line[index...].prefix(10).firstIndex(of: "'") else { return nil }
            return line.index(after: close)
        }
        guard line[index] != "'" else { return nil }
        index = line.index(after: index)
        return index < line.endIndex && line[index] == "'" ? line.index(after: index) : nil
    }

    private static func rules(for lines: [String], comments: Comments) -> [LineRule] {
        guard !comments.verbatim else { return lines.map { _ in .exact } }
        // One pass reads where comments are; for an unknown language a second decides which may change.
        var scanned: [(rule: LineRule, codeFirst: Bool, comment: Bool)] = []
        var waiting: String?
        for line in lines {
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            if let close = waiting {
                let star = line.dropFirst(indent.count).hasPrefix("*")
                if let end = line.range(of: close) {
                    waiting = nil
                    scanned.append((.interior(indent: indent, star: star, suffix: trimmed(String(line[end.lowerBound...]))), false, true))
                } else {
                    scanned.append((.interior(indent: indent, star: star, suffix: ""), false, true))
                }
                continue
            }
            guard let start = commentStart(line, comments) else {
                scanned.append((.exact, true, line.allSatisfy(\.isWhitespace)))
                continue
            }
            let prefix = String(line[..<start.index]) + start.marker
            let codeFirst = !line[..<start.index].allSatisfy(\.isWhitespace)
            var suffix = ""
            if let close = start.close {
                let body = line.index(start.index, offsetBy: start.marker.count)
                if let end = line[body...].range(of: close) { suffix = trimmed(String(line[end.lowerBound...])) } else { waiting = close }
            }
            scanned.append((.comment(prefix: prefix, suffix: suffix), codeFirst, !codeFirst))
        }
        guard comments.generic else { return scanned.map(\.rule) }
        let onlyComments = scanned.allSatisfy(\.comment)
        return scanned.map { onlyComments || $0.codeFirst && $0.rule != .exact ? $0.rule : .exact }
    }

    private static func trimmed(_ line: String) -> String {
        var end = line.endIndex
        while end > line.startIndex, " \t\r".contains(line[line.index(before: end)]) { end = line.index(before: end) }
        return String(line[..<end])
    }

    private static func accepts(_ rule: LineRule, _ source: String, _ output: String) -> Bool {
        let source = trimmed(source), output = trimmed(output)
        if source == output { return true }
        switch rule {
        case .exact:
            return false
        case let .comment(prefix, suffix):
            return output.hasPrefix(prefix) && output.hasSuffix(suffix) && output.count >= prefix.count + suffix.count
        case let .interior(indent, star, suffix):
            let rest = output.dropFirst(indent.count)
            return output.hasPrefix(indent) && rest.first.map({ $0 != " " && $0 != "\t" }) != false
                && (!star || rest.hasPrefix("*")) && output.hasSuffix(suffix)
        }
    }

    // MARK: - Translated commands

    private static func firstToken(_ line: String) -> Substring? {
        line.split(whereSeparator: \.isWhitespace).first
    }

    /// A prose line that is a source code line with some words translated: its first word is the code's first token,
    /// it has no more words than the code has tokens and keeps at least half of them in order, and it is no more
    /// foreign letters than ASCII. A translated sentence that mentions the command never counts ("Install express
    /// with npm." is not `npm install express`, nor "npm install을 먼저 실행하세요:" `npm install`).
    private static func anchored(_ source: String, _ line: String) -> Bool {
        let tokens = source.split(whereSeparator: \.isWhitespace), words = line.split(whereSeparator: \.isWhitespace)
        guard let first = tokens.first, words.first == first, words.count <= tokens.count else { return false }
        var row = [Int](repeating: 0, count: words.count + 1)
        for token in tokens {
            var diagonal = 0
            for (offset, word) in words.enumerated() {
                let above = row[offset + 1]
                row[offset + 1] = token == word ? diagonal + 1 : max(above, row[offset])
                diagonal = above
            }
        }
        let ascii = line.unicodeScalars.filter { $0.isASCII && !$0.properties.isWhitespace }.count
        let foreign = line.unicodeScalars.filter { !$0.isASCII && $0.properties.isAlphabetic }.count
        return row[words.count] * 2 >= tokens.count && ascii >= foreign
    }
}
