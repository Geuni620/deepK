import Foundation

@main
struct Benchmark {
    static func main() {
        for count in [1000, 2000, 4000, 8000] {
            let input = String(repeating: "Intro.\n```text\n- value\n```\n\n", count: count)
            let start = ContinuousClock.now
            let markup = TranslationMarkup(input)
            let elapsed = start.duration(to: .now)
            print("blocks=\(count) bytes=\(input.utf8.count) resultBlocks=\(markup.blocks.count) display=\(markup.displayText.utf8.count) duration=\(elapsed)")
        }
    }
}
