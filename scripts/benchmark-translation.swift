import Dispatch
import Foundation

struct TranslationSampleFile: Decodable {
    let version: Int
    let status: String
    let samples: [TranslationSample]
}

struct TranslationSample: Decodable {
    let id: String
    let source: String
    let target: String
    let size: String
    let text: String
    let checks: [String]
}

struct PilotResult: Encodable {
    let sequence: Int
    let sampleID: String
    let source: String
    let target: String
    let size: String
    let model: String
    let status: String
    let elapsedMs: Double
    let output: String?
    let error: String?
}

struct PilotRun: Encodable {
    let status: String
    let startedAt: String
    let finishedAt: String
    let sampleFixtureVersion: Int
    let sampleFixtureStatus: String
    let plannedRequests: Int
    let attemptedRequests: Int
    let maxRequests: Int
    let models: [String]
    let requestTimeoutSeconds: Int
    let translationTimeoutSeconds: Int
    let reasoningEffortPolicy: String
    let stopReason: String?
    let results: [PilotResult]
}

enum BenchmarkError: Error {
    case usage(String)
    case invalidFixture(String)
    case timeout
    case preflight(String)
}

@main
struct TranslationBenchmark {
    private static let models = [
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.6-sol"
    ]
    private static let requestTimeoutSeconds = 25
    private static let translationTimeoutSeconds = 25
    private static let maxRequests = 30

    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("benchmark failed: \(safeError(error))\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw BenchmarkError.usage("usage: benchmark-translation <samples.json> <results.json>")
        }

        let samplesURL = URL(fileURLWithPath: arguments[1])
        let resultsURL = URL(fileURLWithPath: arguments[2])
        let fixture = try decodeFixture(at: samplesURL)
        guard fixture.samples.count == 10 else {
            throw BenchmarkError.invalidFixture("expected 10 samples, got \(fixture.samples.count)")
        }
        guard fixture.samples.allSatisfy({ !$0.id.isEmpty && !$0.text.isEmpty }) else {
            throw BenchmarkError.invalidFixture("all samples need non-empty ids and text")
        }

        let startedAt = timestamp()
        let configuration = CodexTranslationClient.Configuration(
            requestTimeout: TimeInterval(requestTimeoutSeconds),
            translationTimeout: TimeInterval(translationTimeoutSeconds),
            clientName: "deepK-translation-pilot",
            clientVersion: "0.1.0"
        )
        let client = CodexTranslationClient(configuration: configuration)
        var results: [PilotResult] = []
        var stopReason: String?
        var runStatus = "completed"

        do {
            try await client.connect()
            let visibleModels = try await client.listModels()
            let visibleIDs = Set(visibleModels.flatMap { [$0.id, $0.model] })
            let missing = models.filter { !visibleIDs.contains($0) }
            guard missing.isEmpty else {
                throw BenchmarkError.preflight("requested models unavailable: \(missing.joined(separator: ", "))")
            }
        } catch {
            runStatus = "preflight_failed"
            stopReason = safeError(error)
            await client.disconnect()
            try writeRun(
                PilotRun(
                    status: runStatus,
                    startedAt: startedAt,
                    finishedAt: timestamp(),
                    sampleFixtureVersion: fixture.version,
                    sampleFixtureStatus: fixture.status,
                    plannedRequests: fixture.samples.count * models.count,
                    attemptedRequests: 0,
                    maxRequests: maxRequests,
                    models: models,
                    requestTimeoutSeconds: requestTimeoutSeconds,
                    translationTimeoutSeconds: translationTimeoutSeconds,
                    reasoningEffortPolicy: "Codex client selects the minimum supported effort.",
                    stopReason: stopReason,
                    results: []
                ),
                to: resultsURL
            )
            return
        }

        for (sampleIndex, sample) in fixture.samples.enumerated() {
            let order = rotatedModelOrder(startingAt: sampleIndex)
            for model in order {
                guard results.count < maxRequests else {
                    runStatus = "stopped"
                    stopReason = "max_requests_reached"
                    break
                }

                let sequence = results.count + 1
                let start = DispatchTime.now().uptimeNanoseconds
                do {
                    let output = try await translateWithTimeout(
                        client: client,
                        sample: sample,
                        model: model
                    )
                    let elapsedMs = elapsedMilliseconds(since: start)
                    results.append(
                        PilotResult(
                            sequence: sequence,
                            sampleID: sample.id,
                            source: sample.source,
                            target: sample.target,
                            size: sample.size,
                            model: model,
                            status: "success",
                            elapsedMs: elapsedMs,
                            output: output,
                            error: nil
                        )
                    )
                } catch {
                    let elapsedMs = elapsedMilliseconds(since: start)
                    let shouldStop = isAuthenticationOrRateLimit(error)
                    if shouldStop {
                        runStatus = "stopped"
                        stopReason = safeError(error)
                    }
                    results.append(
                        PilotResult(
                            sequence: sequence,
                            sampleID: sample.id,
                            source: sample.source,
                            target: sample.target,
                            size: sample.size,
                            model: model,
                            status: "error",
                            elapsedMs: elapsedMs,
                            output: nil,
                            error: safeError(error)
                        )
                    )
                    if shouldStop {
                        break
                    }
                }
            }
            if stopReason != nil {
                break
            }
        }

        await client.disconnect()
        try writeRun(
            PilotRun(
                status: runStatus,
                startedAt: startedAt,
                finishedAt: timestamp(),
                sampleFixtureVersion: fixture.version,
                sampleFixtureStatus: fixture.status,
                plannedRequests: fixture.samples.count * models.count,
                attemptedRequests: results.count,
                maxRequests: maxRequests,
                models: models,
                requestTimeoutSeconds: requestTimeoutSeconds,
                translationTimeoutSeconds: translationTimeoutSeconds,
                reasoningEffortPolicy: "Codex client selects the minimum supported effort.",
                stopReason: stopReason,
                results: results
            ),
            to: resultsURL
        )
    }

    private static func decodeFixture(at url: URL) throws -> TranslationSampleFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TranslationSampleFile.self, from: data)
    }

    private static func rotatedModelOrder(startingAt index: Int) -> [String] {
        (0..<models.count).map { models[($0 + index) % models.count] }
    }

    private static func translateWithTimeout(
        client: CodexTranslationClient,
        sample: TranslationSample,
        model: String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await client.translate(
                    text: sample.text,
                    source: sample.source,
                    target: sample.target,
                    model: model
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(translationTimeoutSeconds) * 1_000_000_000)
                throw BenchmarkError.timeout
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw BenchmarkError.timeout
            }
            return first
        }
    }

    private static func writeRun(_ run: PilotRun, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(run)
        try data.write(to: url, options: .atomic)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }

    private static func isAuthenticationOrRateLimit(_ error: Error) -> Bool {
        if let clientError = error as? CodexTranslationClient.ClientError {
            switch clientError {
            case .notAuthenticated, .unsupportedAccountType:
                return true
            case let .rpc(code, message):
                if [401, 403, 429].contains(code) { return true }
                return containsLimitOrAuthSignal(message)
            case let .turnFailed(message):
                return containsLimitOrAuthSignal(message)
            default:
                return false
            }
        }
        return false
    }

    private static func containsLimitOrAuthSignal(_ message: String) -> Bool {
        let value = message.lowercased()
        return [
            "rate limit", "ratelimit", "quota", "usage limit", "too many requests",
            "unauthorized", "authentication", "forbidden", "401", "403", "429"
        ].contains { value.contains($0) }
    }

    private static func safeError(_ error: Error) -> String {
        if let error = error as? BenchmarkError {
            switch error {
            case let .usage(message), let .invalidFixture(message), let .preflight(message):
                return message
            case .timeout:
                return "timeout_25s"
            }
        }

        guard let error = error as? CodexTranslationClient.ClientError else {
            return "unknown_error"
        }

        switch error {
        case .notAuthenticated:
            return "not_authenticated"
        case .unsupportedAccountType:
            return "unsupported_account_type"
        case let .rpc(code, _):
            return "rpc_\(code)"
        case .timeout:
            return "client_timeout"
        case .turnInterrupted:
            return "turn_interrupted"
        case .turnFailed:
            return "turn_failed"
        case .modelUnavailable:
            return "model_unavailable"
        case .emptyTranslation:
            return "empty_translation"
        case .toolsEnabled:
            return "tools_enabled"
        case .processStartFailed:
            return "process_start_failed"
        case .processTerminated:
            return "process_terminated"
        case .notConnected:
            return "not_connected"
        case .malformedResponse:
            return "malformed_response"
        case .invalidInput:
            return "invalid_input"
        case .writeFailed:
            return "write_failed"
        case .executableNotFound:
            return "executable_not_found"
        case .executableUnsupported:
            return "executable_unsupported"
        case .configuredExecutableInvalid:
            return "configured_executable_invalid"
        }
    }
}
