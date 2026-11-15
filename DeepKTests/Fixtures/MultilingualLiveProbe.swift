import Foundation

/// Explicitly opted-in, bounded subscription requests. All input comes from authored synthetic fixtures.
@main struct MultilingualLiveProbe {
    struct Corpus: Decodable { let samples: [Sample] }
    struct Sample: Decodable { let id: String; let numbers: [String]; let literals: [String]; let text: [String: String] }
    struct Result: Codable {
        let provider: String; let model: String; let source: String; let target: String; let sample: String
        let input: String; let output: String?; let milliseconds: Double; let failures: [String]; let error: String?; let fidelityRevisions: Int
    }
    static func main() async throws {
        guard [4, 5].contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--live" else {
            print("Usage: MultilingualLiveProbe --live <synthetic-corpus.json> <result.json>"); return
        }
        let providers = CommandLine.arguments.count == 5 ? [CommandLine.arguments[4]] : ["codex", "claude"]
        guard providers.allSatisfy({ ["codex", "claude"].contains($0) }) else { throw NSError(domain: "deepk-provider", code: 1) }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let destination = URL(fileURLWithPath: CommandLine.arguments[3])
        let names = ["ko":"Korean (한국어)", "en":"English", "ja":"Japanese",
                     "zh-Hant":"Traditional Chinese (Taiwan; use Taiwanese vocabulary and traditional characters)",
                     "zh-Hans":"Simplified Chinese (use simplified characters)"]
        let directions = [("ja","ko"),("zh-Hant","ko"),("zh-Hans","ko"),
                          ("ko","ja"),("ko","zh-Hant"),("ko","zh-Hans"),
                          ("en","ja"),("en","zh-Hant"),("en","zh-Hans"),
                          ("zh-Hant","zh-Hans"),("zh-Hans","zh-Hant")]
        let codex = CodexTranslationClient(configuration: .init(prewarmEnabled: false))
        let claude = ClaudeTranslationClient(configuration: .init(transport: .streamOnDemand))
        var results: [Result] = []
        for provider in providers {
            var stopped = false
            for (source, target) in directions {
                for sample in corpus.samples {
                    if stopped { continue }
                    guard let input = sample.text[source], let sourceName = names[source], let targetName = names[target] else {
                        throw NSError(domain: "deepk-corpus", code: 1)
                    }
                    let start = ContinuousClock.now
                    let model = provider == "codex" ? TranslationProvider.codex.defaultModel : TranslationProvider.claude.defaultModel
                    do {
                        let output: String
                        if provider == "codex" {
                            output = try await codex.translate(text: input, source: sourceName, target: targetName, model: model)
                        } else {
                            output = try await claude.translate(text: input, source: sourceName, target: targetName, model: model)
                        }
                        let duration = start.duration(to: .now).components
                        var failures = sample.numbers.filter { !output.contains($0) }.map { "missing number: " + $0 }
                        failures += sample.literals.filter { !output.contains($0) }.map { "missing literal: " + $0 }
                        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failures.append("empty output") }
                        results.append(Result(provider: provider, model: model, source: source, target: target, sample: sample.id,
                                              input: input, output: output,
                                              milliseconds: Double(duration.seconds)*1000 + Double(duration.attoseconds)/1e15,
                                              failures: failures, error: nil, fidelityRevisions: provider == "claude" ? await claude.lastFidelityRevisionCount : 0))
                    } catch {
                        let duration = start.duration(to: .now).components
                        results.append(Result(provider: provider, model: model, source: source, target: target, sample: sample.id,
                                              input: input, output: nil,
                                              milliseconds: Double(duration.seconds)*1000 + Double(duration.attoseconds)/1e15,
                                              failures: [], error: error.localizedDescription, fidelityRevisions: provider == "claude" ? await claude.lastFidelityRevisionCount : 0))
                        stopped = true // no fallback, retry loop, or further subscription requests after a transport failure
                    }
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    try encoder.encode(results).write(to: destination, options: .atomic)
                    print("Completed", results.count, "of at most", directions.count * corpus.samples.count * providers.count, provider, source, target, sample.id); fflush(stdout)
                }
            }
        }
        await codex.disconnect(); await claude.disconnect()
    }
}
