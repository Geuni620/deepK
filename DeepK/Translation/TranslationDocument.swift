import Foundation

public struct TranslationSegment: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// Exact source coverage, including the separator preceding this segment.
    public let separator: String
    public let input: String
    public let text: String
    /// Whitespace and `---` lines typed after `input`. They belong to the source coverage but have
    /// no translation of their own, so they never appear in `text`.
    public var trailing: String = ""
    /// The model still echoed the source after the one automatic retry. Such a unit is shown with a
    /// warning and never cached, alone or as part of a prefix.
    public var unresolvedEcho = false
}

extension TranslationSegment {
    /// Splits edge whitespace off a translated source so that later edits which
    /// only add or remove that whitespace can still be covered exactly.
    init(id: UUID, separator: String, source: String, text: String, unresolvedEcho: Bool = false) {
        let leading = separator.isEmpty ? String(source.prefix { $0.isNewline }) : ""
        let body = String(source.dropFirst(leading.count))
        let end = TranslationDocument.contentEnd(of: body) ?? body.endIndex
        self.init(id: id, separator: separator + leading, input: String(body[..<end]),
                  text: text, trailing: String(body[end...]), unresolvedEcho: unresolvedEcho)
    }
}

struct TranslationDocument: Equatable, Sendable {
    let generation: UUID
    let basis: TranslationResult
    var segments: [TranslationSegment]

    var input: String { segments.map { $0.separator + $0.input + $0.trailing }.joined() }

    var hasUnresolvedEcho: Bool { segments.contains(where: \.unresolvedEcho) }

    /// Returns the completed units covering `source` exactly, allowing only a delimiter
    /// (whitespace, `---` lines, a dash being typed) after the last kept unit. Dropping
    /// later units is safe because each unit was translated independently.
    func covering(_ source: String) -> TranslationDocument? {
        // The planner keeps a prefix exactly when this holds, so an empty tail is always covered (I1).
        let contentEnd = IncrementalTranslationPlanner.unitEnd(of: source)
        var prefix = ""
        for index in segments.indices {
            let segment = segments[index]
            prefix += segment.separator + segment.input
            guard source.utf8.starts(with: prefix.utf8) else { return nil }
            if contentEnd <= prefix.utf8.count {
                let rest = String(decoding: source.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
                var covered = self
                covered.segments = Array(segments[...index])
                covered.segments[index].trailing = rest
                return covered
            }
            prefix += segment.trailing
        }
        return nil
    }

    /// Only drop complete translation units. A substring of a unit has no proven
    /// corresponding substring in its translated text.
    func retainingSuffix(for source: String) -> TranslationDocument? {
        guard segments.count > 1 else { return nil }
        let leadingSeparator = IncrementalTranslationPlanner.leadingDelimiter(of: source)
        for start in segments.indices.dropFirst() {
            var candidate = self
            candidate.segments = Array(segments[start...])
            let first = candidate.segments[0]
            candidate.segments[0] = TranslationSegment(
                id: first.id, separator: leadingSeparator, input: first.input, text: first.text, trailing: first.trailing,
                unresolvedEcho: first.unresolvedEcho
            )
            if candidate.input == source || IncrementalTranslationPlanner.tail(after: candidate.input, in: source) != nil {
                return candidate
            }
            // Trailing whitespace may have been removed together with the leading units.
            if let covered = candidate.covering(source) { return covered }
        }
        return nil
    }

    var text: String { rendered.text }

    /// The joined translation and, for each unit after an explicit boundary, the UTF-16 offset where the
    /// unit above it ends (where the result view draws its line).
    var rendered: (text: String, unitBreaks: [Int]) {
        var result = ""
        var breaks: [Int] = []
        for (index, segment) in segments.enumerated() {
            let previous = index > 0 ? segments[index - 1] : nil
            let explicit = previous.map { Self.isExplicit($0, before: segment.separator) } ?? false
            if explicit, !result.isEmpty { breaks.append(result.utf16.count) }
            result = Self.join(result, precedingSourceNewlines: previous.map(Self.trailingNewlines) ?? 0,
                               separator: segment.separator, explicit: explicit, next: segment.text)
        }
        return (result, breaks)
    }

    /// Joins a not-yet-completed unit exactly as `text` will join it once it
    /// completes. A streamed snapshot is therefore always a prefix of the final
    /// text, which keeps the reader's screen from being rewritten.
    func text(appending next: String, separator: String) -> (text: String, tailStart: Int) {
        let base = text
        let preceding = segments.last.map(Self.trailingNewlines) ?? 0
        return (Self.join(base, precedingSourceNewlines: preceding, separator: separator,
                          explicit: appendsExplicitly(separator: separator), next: next), base.utf16.count)
    }

    /// Whether a unit appended with `separator` follows an explicit boundary.
    func appendsExplicitly(separator: String) -> Bool {
        segments.last.map { Self.isExplicit($0, before: separator) } ?? false
    }

    /// Keeps the longest run of leading units after which `source` can be planned, dropping later units only
    /// at an explicit boundary: editing a completed lower block requests only that block. The last kept unit's
    /// trailing is also tried empty, for dashes held there that the edit turned into content (P0-1).
    /// The first tail with text decides: when `accepting` rejects it (another language, D5), dropping more
    /// units would only send unchanged blocks again with the same text, so the source is not replanned.
    func replanned(for source: String, accepting: (IncrementalTranslationPlanner.Tail) -> Bool)
        -> (TranslationDocument, IncrementalTranslationPlanner.Tail)? {
        for count in stride(from: segments.count, through: 1, by: -1) {
            if count < segments.count, !Self.isExplicit(segments[count - 1], before: segments[count].separator) { continue }
            var head = self
            head.segments = Array(segments[..<count])
            for clearsTrailing in [false, true] {
                if clearsTrailing {
                    guard !head.segments[count - 1].trailing.isEmpty else { continue }
                    head.segments[count - 1].trailing = ""
                }
                // An empty tail is a delimiter that `covering` already keeps.
                guard let tail = IncrementalTranslationPlanner.tail(after: head.input, in: source), !tail.input.isEmpty else { continue }
                return accepting(tail) ? (head, tail) : nil
            }
        }
        return nil
    }

    /// UTF-16 offset where the newest unit's translation begins, if there is more than one unit.
    var lastSegmentStart: Int? {
        guard segments.count > 1 else { return nil }
        var head = self
        head.segments.removeLast()
        return head.text.utf16.count
    }

    static func isBlank(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    /// The end of `text` without trailing whitespace, or nil when it is all whitespace.
    static func contentEnd(of text: String) -> String.Index? {
        text.lastIndex { !isBlank($0) }.map(text.index(after:))
    }

    private static func trailingNewlines(_ segment: TranslationSegment) -> Int {
        (segment.input + segment.trailing).reversed().prefix { $0.isNewline }.count
    }

    /// The boundary bytes may be split between the unit's trailing and the next separator.
    private static func isExplicit(_ segment: TranslationSegment, before separator: String) -> Bool {
        IncrementalTranslationPlanner.isExplicitGap(segment.trailing + separator)
    }

    private static func join(_ base: String, precedingSourceNewlines: Int, separator: String, explicit: Bool, next: String) -> String {
        guard !base.isEmpty else { return next }
        // Providers may already return trailing newlines. Do not alter the old
        // text or duplicate the paragraph delimiter when appending a new result.
        let existing = base.reversed().prefix { $0.isNewline }.count
        let leading = next.prefix { $0.isNewline }.count
        // Units across an explicit boundary are joined by one blank line; the line is drawn, not written.
        let desired = explicit ? 2 : max(2, separator.filter(\.isNewline).count + precedingSourceNewlines)
        return base + String(repeating: "\n", count: max(0, desired - existing - leading)) + next
    }
}
