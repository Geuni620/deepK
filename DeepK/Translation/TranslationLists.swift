import Foundation

/// Literal list markers stay in the text sent to providers and plain-text destinations. These UTF-16
/// ranges only describe their layout and rich-copy structure; fenced and indented code are not lists.
struct TranslationLists: Equatable, Sendable {
    enum Marker: Equatable, Sendable {
        case unordered(String)
        case ordered(Int, String)

        var number: Int? { if case .ordered(let number, _) = self { number } else { nil } }
        var isOrdered: Bool { number != nil }
    }

    struct Item: Equatable, Sendable {
        /// The marker's complete logical line, including its line break.
        let range: NSRange
        /// The marker and following whitespace, without the leading indentation.
        let markerRange: NSRange
        /// The body of the line, without its line break.
        let contentRange: NSRange
        let marker: Marker
        let indent: Int
        let bodyColumn: Int
        let depth: Int
        let parent: Int?
        let group: Int

        var prefixRange: NSRange { NSRange(location: range.location, length: contentRange.location - range.location) }
    }

    struct Continuation: Equatable, Sendable {
        let range: NSRange
        let contentRange: NSRange
        let item: Int
    }

    let items: [Item]
    let continuations: [Continuation]

    /// `excluding` removes whole code-block lines. `excludingMarkers` only suppresses a candidate
    /// whose marker token overlaps inline code; code in an ordinary list item's body is retained.
    init(_ source: String, excluding excluded: [NSRange] = [], excludingMarkers inlineCodeRanges: [NSRange] = []) {
        let text = source as NSString
        var codeBlocks = RangeSweep(excluded, limit: text.length)
        var inlineCode = RangeSweep(inlineCodeRanges, limit: text.length)
        var items: [Item] = [], continuations: [Continuation] = []
        var stack: [Int] = [], group = 0, location = 0
        var fence: (character: UInt16, count: Int)?
        func reset() { if !stack.isEmpty { stack.removeAll(); group += 1 } }
        while location < text.length {
            var end = 0, contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: location, length: end - location)
            defer { location = end }
            if codeBlocks.intersects(line) { reset(); continue }
            var cursor = location, indent = 0
            while cursor < contentsEnd {
                let char = text.character(at: cursor)
                if char == 0x20 { indent += 1 } else if char == 0x09 { indent += 4 - indent % 4 } else { break }
                cursor += 1
            }
            if cursor == contentsEnd { continue }
            let character = text.character(at: cursor)
            if character == 0x60 || character == 0x7E {
                var finish = cursor
                while finish < contentsEnd, text.character(at: finish) == character { finish += 1 }
                if let opened = fence {
                    if opened.character == character, finish - cursor >= opened.count,
                       text.substring(with: NSRange(location: finish, length: contentsEnd - finish)).allSatisfy(\.isWhitespace) {
                        fence = nil
                    }
                    reset(); continue
                } else if finish - cursor >= 3 {
                    fence = (character, finish - cursor)
                    reset(); continue
                }
            }
            if fence != nil { reset(); continue }

            var marker: Marker?, markerEnd = cursor
            if (0x30...0x39).contains(character) || [UInt16(0x2D), 0x2B].contains(character) {
                if character == 0x2D || character == 0x2B { markerEnd += 1 }
                let digitStart = markerEnd
                while markerEnd < contentsEnd, (0x30...0x39).contains(text.character(at: markerEnd)), markerEnd - digitStart < 18 { markerEnd += 1 }
                if markerEnd < contentsEnd, [UInt16(0x2E), 0x29].contains(text.character(at: markerEnd)),
                   markerEnd > digitStart,
                   let number = Int(text.substring(with: NSRange(location: cursor, length: markerEnd - cursor))) {
                    marker = .ordered(number, text.substring(with: NSRange(location: markerEnd, length: 1)))
                    markerEnd += 1
                }
            }
            if marker == nil, [UInt16(0x2D), 0x2A, 0x2B, 0x2022, 0x25E6, 0x25AA, 0x25AB].contains(character) {
                markerEnd = cursor + 1
                marker = .unordered(text.substring(with: NSRange(location: cursor, length: 1)))
            }
            if let marker, markerEnd == contentsEnd || [UInt16(0x20), 0x09].contains(text.character(at: markerEnd)) {
                if inlineCode.intersects(NSRange(location: cursor, length: markerEnd - cursor)) { reset(); continue }
                let body = text.substring(with: NSRange(location: cursor, length: contentsEnd - cursor))
                // Markdown thematic rules and a first four-space-indented code line remain ordinary text.
                let rule = body.filter { !$0.isWhitespace }
                if (rule.count >= 3 && Set(rule).count == 1 && "-*".contains(rule.first!)) || (indent >= 4 && stack.isEmpty) {
                    reset(); continue
                }
                var bodyStart = markerEnd, bodyColumn = indent + markerEnd - cursor
                while bodyStart < contentsEnd {
                    let char = text.character(at: bodyStart)
                    if char == 0x20 { bodyColumn += 1 } else if char == 0x09 { bodyColumn += 4 - bodyColumn % 4 } else { break }
                    bodyStart += 1
                }
                while let last = stack.last, items[last].indent >= indent { stack.removeLast() }
                let parent = stack.last
                items.append(Item(range: line, markerRange: NSRange(location: cursor, length: bodyStart - cursor),
                                  contentRange: NSRange(location: bodyStart, length: contentsEnd - bodyStart), marker: marker,
                                  indent: indent, bodyColumn: max(bodyColumn, indent + 2),
                                  depth: parent.map { items[$0].depth + 1 } ?? 0, parent: parent, group: group))
                stack.append(items.count - 1)
            } else if let owner = stack.reversed().first(where: { items[$0].bodyColumn <= indent }) {
                while stack.last != owner { stack.removeLast() }
                continuations.append(Continuation(range: line, contentRange: NSRange(location: cursor, length: contentsEnd - cursor), item: owner))
            } else {
                reset()
            }
        }
        self.items = items
        self.continuations = continuations
    }

    /// Both the text and candidate markers advance monotonically. Normalize the caller's potentially
    /// unsorted/overlapping ranges once, then visit each range at most once instead of rescanning all
    /// code blocks for every logical line.
    private struct RangeSweep {
        private var ranges: [NSRange] = []
        private var index = 0

        init(_ source: [NSRange], limit: Int) {
            let clipped = source.compactMap { range -> NSRange? in
                guard range.location >= 0, range.location < limit, range.length > 0 else { return nil }
                return NSRange(location: range.location, length: min(range.length, limit - range.location))
            }.sorted { $0.location < $1.location }
            for range in clipped {
                if let last = ranges.last, range.location <= NSMaxRange(last) {
                    ranges[ranges.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
                } else { ranges.append(range) }
            }
        }

        mutating func intersects(_ range: NSRange) -> Bool {
            while index < ranges.count, NSMaxRange(ranges[index]) <= range.location { index += 1 }
            return index < ranges.count && ranges[index].location < NSMaxRange(range)
        }
    }
}
