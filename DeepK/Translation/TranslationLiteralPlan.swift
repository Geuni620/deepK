import Foundation

/// Keeps long opaque code literals out of model generation and restores their exact bytes.
/// Human-readable code strings and fenced code blocks remain ordinary translation input.
struct TranslationLiteralPlan: Sendable {
    private struct Entry: Sendable {
        let marker: String
        let original: String
    }

    let input: String
    private let prefix: String
    private let entries: [Entry]
    var count: Int { entries.count }

    init(text: String, enabled: Bool = true) {
        guard enabled,
              let regex = try? NSRegularExpression(pattern: "(?<!`)`[^`\\r\\n]+`(?!`)"),
              // A fence of three or more backticks runs to a closing line at least as long, so code that holds ``` stays
              // inside its block (the app fences such code with four), or to a code line that ends in such a run, as chat
              // apps close blocks (npm run build```); one-line chat fences keep the short forms.
              let fences = try? NSRegularExpression(pattern: "(?ms)^ {0,3}(`{3,})[^`\\n]*\\n.*?(?:^ {0,3}|^[ \\t]*[^ \\t\\n`][^\\n]*?)\\1`*[ \\t]*$|```.*?```|~~~.*?~~~") else {
            input = text; prefix = ""; entries = []; return
        }
        let nsText = text as NSString
        let wholeRange = NSRange(location: 0, length: nsText.length)
        let fencedRanges = fences.matches(in: text, range: wholeRange).map(\.range)
        let matches = regex.matches(in: text, range: wholeRange).filter { match in
            guard !fencedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return false }
            let literal = nsText.substring(with: match.range)
            let value = String(literal.dropFirst().dropLast())
            guard value.utf8.count >= 80,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
            if let url = URLComponents(string: value),
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
                return true
            }
            return value.range(of: "^[A-Za-z0-9_./:?=&%#@+\\-]+$", options: .regularExpression) != nil
        }
        guard !matches.isEmpty else { input = text; prefix = ""; entries = []; return }
        var markerPrefix = "__DK_LITERAL_"
        while text.range(of: markerPrefix, options: .caseInsensitive) != nil { markerPrefix += "X" }
        prefix = markerPrefix
        entries = matches.enumerated().map { index, match in
            Entry(marker: "`\(markerPrefix)\(index)__`", original: nsText.substring(with: match.range))
        }
        let encoded = NSMutableString(string: text)
        for (index, match) in matches.enumerated().reversed() {
            encoded.replaceCharacters(in: match.range, with: entries[index].marker)
        }
        input = encoded as String
    }

    func restore(_ text: String) throws -> String {
        guard !entries.isEmpty else { return text }
        var restored = text
        for entry in entries {
            guard text.components(separatedBy: entry.marker).count == 2 else {
                throw CodexTranslationClient.ClientError.malformedResponse("긴 원문 문자열의 복원 표시가 누락되거나 변경되었습니다. 다시 번역해 주세요.")
            }
            restored = restored.replacingOccurrences(of: entry.marker, with: entry.original)
        }
        guard restored.range(of: prefix, options: .caseInsensitive) == nil else {
            throw CodexTranslationClient.ClientError.malformedResponse("알 수 없는 원문 복원 표시가 반환되었습니다. 다시 번역해 주세요.")
        }
        return restored
    }

    /// Withhold incomplete markers so cumulative snapshots never expose or later replace a marker prefix.
    func restoredPrefix(_ text: String) -> String {
        guard !entries.isEmpty else { return text }
        var safe = text
        if !entries.contains(where: { text.hasSuffix($0.marker) }) {
            var withheld = 0
            for entry in entries {
                for length in 1..<entry.marker.count where length <= text.count {
                    if String(text.suffix(length)).caseInsensitiveCompare(String(entry.marker.prefix(length))) == .orderedSame {
                        withheld = max(withheld, length)
                    }
                }
            }
            if withheld > 0 { safe = String(text.dropLast(withheld)) }
        }
        for entry in entries { safe = safe.replacingOccurrences(of: entry.marker, with: entry.original) }
        if let range = safe.range(of: prefix, options: .caseInsensitive) {
            let start = range.lowerBound > safe.startIndex && safe[safe.index(before: range.lowerBound)] == "`"
                ? safe.index(before: range.lowerBound) : range.lowerBound
            safe = String(safe[..<start])
        }
        return safe
    }
}
