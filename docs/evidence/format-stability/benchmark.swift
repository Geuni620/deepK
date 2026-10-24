import Foundation
import Dispatch

@main enum ImporterBenchmark {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: input)
        let fixture = (try JSONSerialization.jsonObject(with: data) as! [String: Any])["cases"] as! [[String: Any]]
        var samples: [(String, String, String)] = fixture.map { ($0["id"] as! String, $0["plain"] as! String, $0["html"] as! String) }
        samples.append(("plain-links-code-control", "Use git to save your work and read the guide before you continue.",
                        "<p>Use <code>git</code> to save your work and read <a href='https://d.dev'>the guide</a> before you continue.</p>"))
        var results: [[String: Any]] = []
        var checksum = 0
        let pattern = #"^([ \t]*)(?:([-+*•])[ \t]+|([+-]?[0-9]+)[.)][ \t]+)(.*)$"#
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        for (name, plain, html) in samples {
            for _ in 0..<100 { checksum += RichSourceImporter.capture(plain: plain, html: html).plain.utf16.count }
            var batches: [Double] = []
            for _ in 0..<7 {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<300 { checksum += RichSourceImporter.capture(plain: plain, html: html).plain.utf16.count }
                batches.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 300 / 1_000)
            }
            let capture = RichSourceImporter.capture(plain: plain, html: html)
            let text = capture.plain as NSString
            let matches = regex.matches(in: capture.plain, range: NSRange(location: 0, length: text.length))
            func value(_ row: NSTextCheckingResult, _ index: Int) -> String {
                row.range(at: index).location == NSNotFound ? "" : text.substring(with: row.range(at: index))
            }
            let indents = matches.map { value($0, 1).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
            let depths = indents.map { $0 / 2 }
            results.append([
                "sample": name, "medianMicroseconds": batches.sorted()[3],
                "minimumBatchMicroseconds": batches.min()!, "maximumBatchMicroseconds": batches.max()!,
                "samplesPerBatch": 300, "batches": 7, "warmupCaptures": 100,
                "quality": ["items": matches.count, "bullets": matches.filter { !value($0, 2).isEmpty }.count,
                            "numbers": matches.compactMap { Int(value($0, 3)) }, "depths": depths,
                            "links": capture.markup?.links.count ?? 0, "chips": capture.markup?.code.count ?? 0,
                            "rawPreserved": capture.raw == plain]
            ])
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["results": results, "checksum": checksum], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
