import Foundation
@main struct WorkBound {
    static func main() {
        let n = 8_000, line = "Intro.\n- value\n\n"
        let source = String(repeating: line, count: n)
        let ranges = (0..<n).map { NSRange(location: $0 * line.utf16.count + 7, length: 8) }
        let parsed = TranslationLists(source, excluding: ranges)
        let bound = 10 * (3 * n + n)
        let ok = parsed.items.isEmpty && reviewSearchWork <= bound
        print("\(ok ? "PASS" : "FAIL") ranges=\(n) lineQueries=\(3 * n) searchWork=\(reviewSearchWork) bound=\(bound) items=\(parsed.items.count)")
        exit(ok ? 0 : 1)
    }
}
