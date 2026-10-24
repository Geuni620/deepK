import Foundation

/// 저장된 벤치마크 출력(`--store-output`)에 `TranslationOutputLint`를 돌려 규칙별 탐지 결과를 보여 준다.
/// 앱의 실행 중 판정(`TranslationOutputCheck`)도 함께 보여 준다: 원문 반복 비율이 기준을 넘는 출력과
/// 한자를 독음으로 고친 뒤에도 남는 foreignScript.
/// usage: lint-benchmark-outputs <samples.json> <results.json>...
@main
struct LintBenchmarkOutputs {
    struct SampleFile: Decodable { let samples: [Sample] }
    struct Sample: Decodable { let id: String; let source: String; let target: String; let text: String }
    struct RunFile: Decodable { let model: String; let results: [Record] }
    struct Record: Decodable { let sampleID: String; let repeatIndex: Int; let status: String; let output: String? }

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: lint-benchmark-outputs <samples.json> <results.json>...\n".utf8))
            exit(64)
        }
        let samples = try JSONDecoder().decode(SampleFile.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
        let byID = Dictionary(uniqueKeysWithValues: samples.samples.map { ($0.id, $0) })
        var total = 0
        var flagged = 0
        var echoes = 0
        var foreignAfterRepair = 0
        for path in arguments.dropFirst() {
            let run = try JSONDecoder().decode(RunFile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            let outputs = run.results.filter { $0.status == "success" && $0.output != nil }
            // 다른 표본 파일을 주면 일부 기록이 조용히 빠지므로 멈춘다.
            let unknown = Set(outputs.map(\.sampleID)).subtracting(byID.keys).sorted()
            guard unknown.isEmpty else {
                let name = URL(fileURLWithPath: path).lastPathComponent
                FileHandle.standardError.write(Data("\(name): 표본 파일에 없는 sampleID \(unknown.joined(separator: ", ")). 결과를 만든 표본 파일을 주세요.\n".utf8))
                exit(1)
            }
            var lines: [String] = []
            var ruleCounts: [String: Int] = [:]
            var echoed: [String] = []
            var highestOther = 0.0
            var foreign = (raw: 0, repaired: 0)
            for record in outputs {
                guard let sample = byID[record.sampleID], let output = record.output else { continue }
                let violations = TranslationOutputLint.lint(
                    source: sample.text, output: output, sourceLanguage: sample.source, targetLanguage: sample.target
                )
                let check = TranslationOutputCheck(source: sample.text, protecting: [sample.text],
                                                   sourceLanguage: sample.source, targetLanguage: sample.target, attempt: 1)
                let review = check.review(output)
                if review.echo {
                    echoed.append("\(record.sampleID)#\(record.repeatIndex) " + String(format: "%.2f", review.coverage))
                } else {
                    highestOther = max(highestOther, review.coverage)
                }
                if violations.contains(where: { $0.rule == .foreignScript }) { foreign.raw += 1 }
                if check.rules(final: review.text, echo: review.echo).contains(TranslationOutputLint.Rule.foreignScript.rawValue) { foreign.repaired += 1 }
                guard !violations.isEmpty else { continue }
                for violation in violations { ruleCounts[violation.rule.rawValue, default: 0] += 1 }
                let summary = violations.map { "\($0.rule.rawValue)(\($0.severity.rawValue)): \($0.detail)" }
                lines.append("  \(record.sampleID)#\(record.repeatIndex)  " + summary.joined(separator: " | "))
            }
            total += outputs.count
            flagged += lines.count
            echoes += echoed.count
            foreignAfterRepair += foreign.repaired
            let rules = ruleCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            print("\(URL(fileURLWithPath: path).lastPathComponent) [\(run.model)]: \(lines.count)/\(outputs.count) flagged\(rules.isEmpty ? "" : " (\(rules))")")
            lines.forEach { print($0) }
            print("  > runtime echo (coverage): \(echoed.count)/\(outputs.count)\(echoed.isEmpty ? "" : " " + echoed.joined(separator: ", "))"
                  + String(format: "; highest other %.2f", highestOther))
            print("  > foreignScript after Hanja repair: \(foreign.repaired)/\(outputs.count) (raw \(foreign.raw))")
        }
        print("total: \(flagged)/\(total) flagged")
        print("total runtime echo: \(echoes)/\(total), foreignScript after Hanja repair: \(foreignAfterRepair)/\(total)")
    }
}
