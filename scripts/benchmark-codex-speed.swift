import Foundation

// Codex 번역 지연을 세 비교군으로 교차 실측한다(계획 6절).
// - baseline: DEEPK_BASELINE_REF의 클라이언트(액터 이름만 바꿔 같은 모듈로 컴파일). 84a24f0은 Fast 고정·주입 그대로다.
// - fast-off / fast-on: 현재 클라이언트에서 계층만 바꾼 것이다.
// 세 비교군 모두 같은 Codex 실행 파일을 고정하고, 매 turn 전에 대기 스레드 준비 완료를 기다린 뒤 3초를 둔다.

private struct Fixture: Decodable { let samples: [Sample] }
private struct Sample: Decodable {
    let id: String
    let source: String
    let target: String
    let size: String
    let text: String
}
private struct Record: Encodable {
    let arm: String
    let sampleID: String
    let size: String
    let orderPosition: Int
    let totalMilliseconds: Double
    let firstTextMilliseconds: Double?
    let preparedBeforeTurn: Bool
    let usedPreparedThread: Bool
    let preservedLiteralCount: Int
    let output: String?
    let error: String?
}
private struct Executable: Encodable {
    let path: String
    let displayPath: String
    let version: String?
    let source: String
}
private struct ArmSummary: Encodable {
    let arm: String
    let size: String
    let count: Int
    let errors: Int
    let p50TotalMilliseconds: Double?
    let p50FirstTextMilliseconds: Double?
}
private struct Run: Encodable {
    let baselineRef: String
    let sourceRevision: String
    let model: String
    let modelSource: String
    let codex: Executable
    let arms: [String]
    let prewarmLeadSeconds: Int
    let scope: String
    let summary: [ArmSummary]
    let records: [Record]
}
private struct ScheduledTurn: Encodable {
    let sampleID: String
    let size: String
    let arm: String
    let orderPosition: Int
}
private final class FirstText: @unchecked Sendable {
    private let lock = NSLock()
    private var first: UInt64?
    func record() { lock.lock(); if first == nil { first = DispatchTime.now().uptimeNanoseconds }; lock.unlock() }
    func elapsed(from start: UInt64) -> Double? { lock.lock(); defer { lock.unlock() }; return first.map { Double($0-start)/1_000_000 } }
}

/// 비교군마다 다른 액터 타입을 같은 절차로 다루기 위한 묶음이다.
private struct Arm: Sendable {
    let name: String
    let connect: @Sendable () async throws -> [String]
    let setPrewarm: @Sendable (String) async -> Void
    let warmUp: @Sendable () async -> Void
    let isPrepared: @Sendable () async -> Bool
    let translate: @Sendable (Sample, String, @escaping @Sendable (String) -> Void) async throws -> String
    let timing: @Sendable () async -> (prepared: Bool, literals: Int)?
    let disconnect: @Sendable () async -> Void

    static func baseline(_ client: BaselineCodexTranslationClient) -> Arm {
        Arm(name: "baseline",
            connect: { try await client.connect(); return try await client.listModels().map(\.model) },
            setPrewarm: { await client.setPrewarm(model: $0, generation: 1) },
            warmUp: { await client.warmUp() },
            isPrepared: { await client.hasPreparedThread },
            translate: { sample, model, partial in
                try await client.translate(text: sample.text, source: sample.source, target: sample.target,
                                           model: model, onPartialText: partial)
            },
            timing: { await client.lastCompletedTiming.map { ($0.usedPreparedThread, $0.preservedLiteralCount) } },
            disconnect: { await client.disconnect() })
    }

    static func current(_ client: CodexTranslationClient, fast: Bool) -> Arm {
        Arm(name: fast ? "fast-on" : "fast-off",
            connect: { try await client.connect(); return try await client.listModels().map(\.model) },
            setPrewarm: { await client.setPrewarm(model: $0, fastServiceTier: fast, generation: 1) },
            warmUp: { await client.warmUp() },
            isPrepared: { await client.hasPreparedThread },
            translate: { sample, model, partial in
                try await client.translate(text: sample.text, source: sample.source, target: sample.target,
                                           model: model, fastServiceTier: fast, onPartialText: partial)
            },
            timing: { await client.lastCompletedTiming.map { ($0.usedPreparedThread, $0.preservedLiteralCount) } },
            disconnect: { await client.disconnect() })
    }
}

@main private enum Benchmark {
    static let armNames = ["baseline", "fast-off", "fast-on"]
    static let prewarmLeadSeconds = 3

    static func main() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 3 else { fail("usage: benchmark <samples.json> <results.json> <baseline-ref> [options]") }
        let samplesPath = args.removeFirst(), resultsPath = args.removeFirst(), baselineRef = args.removeFirst()
        var codexPath: String?, sourceRevision = "unknown", dryRun = false
        // 모델은 --model → DEEPK_BENCHMARK_MODEL → 앱 설정(com.deepk.app의 Codex 모델, 읽기만 한다) 순서다.
        // 사용자가 실제로 쓰는 모델로 판정해야 하므로 고정 기본값을 두지 않는다.
        let environmentModel = ProcessInfo.processInfo.environment["DEEPK_BENCHMARK_MODEL"].flatMap { $0.isEmpty ? nil : $0 }
        var model = environmentModel
            ?? TranslationSelection.model(for: .codex, in: UserDefaults(suiteName: "com.deepk.app") ?? .standard)
        var modelSource = environmentModel == nil ? "app" : "environment"
        while !args.isEmpty {
            switch args.removeFirst() {
            case "--dry-run": dryRun = true
            case "--codex" where !args.isEmpty: codexPath = args.removeFirst()
            case "--model" where !args.isEmpty: model = args.removeFirst(); modelSource = "argument"
            case "--source-revision" where !args.isEmpty: sourceRevision = args.removeFirst()
            case let other: fail("unknown or incomplete option: \(other)")
            }
        }
        guard dryRun || ProcessInfo.processInfo.environment["DEEPK_RUN_LIVE_BENCHMARK"] == "1" else {
            fail("Live benchmark opt-in required (DEEPK_RUN_LIVE_BENCHMARK=1)")
        }

        // literals 표본은 제외한다(계획 6절: 반복 1회 × 표본 10개 × 비교군 3 = 30 turn).
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: samplesPath)))
        let samples = fixture.samples.filter { $0.size != "literals" }
        // 표본마다 비교군 순서를 한 칸씩 돌린다.
        let schedule = samples.enumerated().flatMap { index, sample in
            (0..<armNames.count).map { position in
                ScheduledTurn(sampleID: sample.id, size: sample.size,
                              arm: armNames[(index + position) % armNames.count], orderPosition: position)
            }
        }

        // 세 비교군이 같은 바이너리를 쓰도록 앱과 같은 탐색으로 한 번 고르고 executableURL로 고정한다.
        // --codex나 CODEX_EXECUTABLE(CODEX_CLI_PATH)은 사용자 지정 경로로 엄격하게 검증한다. 환경변수 단계로 넘기면
        // 경로 오타·버전 미달일 때 조용히 다른 Codex로 넘어가 30 turn을 다른 바이너리로 재게 된다.
        let environment = ProcessInfo.processInfo.environment
        let userPath = codexPath ?? ["CODEX_EXECUTABLE", "CODEX_CLI_PATH"].lazy
            .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let resolver = CodexTranslationClient.ExecutableResolver(inputs: .live(
            environment: ProcessInfo.processInfo.environment,
            userExecutablePath: { userPath }
        ))
        let resolution: CodexTranslationClient.ExecutableResolver.Resolution
        do {
            resolution = try await resolver.resolve()
        } catch {
            fail("Codex 실행 파일을 확인하지 못했습니다\(userPath.map { "(\($0))" } ?? ""): \(error.localizedDescription)")
        }
        let info = resolver.info(for: resolution)
        let codex = Executable(path: info.path, displayPath: info.displayPath, version: info.version, source: info.source.rawValue)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if dryRun {
            struct Plan: Encodable {
                let baselineRef: String, sourceRevision: String, model: String, modelSource: String, codex: Executable
                let prewarmLeadSeconds: Int, turns: Int, schedule: [ScheduledTurn]
            }
            let plan = Plan(baselineRef: baselineRef, sourceRevision: sourceRevision, model: model,
                            modelSource: modelSource, codex: codex,
                            prewarmLeadSeconds: prewarmLeadSeconds, turns: schedule.count, schedule: schedule)
            print(String(decoding: try encoder.encode(plan), as: UTF8.self))
            return
        }

        let fixed = resolution.executable
        let arms = [
            Arm.baseline(BaselineCodexTranslationClient(configuration: .init(executableURL: fixed))),
            Arm.current(CodexTranslationClient(configuration: .init(executableURL: fixed)), fast: false),
            Arm.current(CodexTranslationClient(configuration: .init(executableURL: fixed)), fast: true)
        ]
        let armsByName = Dictionary(uniqueKeysWithValues: arms.map { ($0.name, $0) })
        let samplesByID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        var records: [Record] = []

        func save() throws {
            try encoder.encode(Run(baselineRef: baselineRef, sourceRevision: sourceRevision, model: model,
                modelSource: modelSource, codex: codex,
                arms: armNames, prewarmLeadSeconds: prewarmLeadSeconds,
                scope: "Engine completion time. Every arm waits for its standby thread, then \(prewarmLeadSeconds) s, before each turn. Synthetic outputs stored for quality review.",
                summary: summarize(records), records: records)).write(to: URL(fileURLWithPath: resultsPath), options: .atomic)
        }

        do {
            for arm in arms {
                let available = try await arm.connect()
                guard available.contains(model) else { fail("\(arm.name): model \(model) is not in the account catalog") }
                await arm.setPrewarm(model)
            }
            for turn in schedule {
                guard let arm = armsByName[turn.arm], let sample = samplesByID[turn.sampleID] else { continue }
                // 모든 비교군에 같은 준비 절차: 대기 스레드 요청 → 준비 완료 대기(최대 15초) → 3초.
                await arm.warmUp()
                var prepared = false
                for _ in 0..<300 {
                    if await arm.isPrepared() { prepared = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try await Task.sleep(for: .seconds(prewarmLeadSeconds))

                let first = FirstText(), start = DispatchTime.now().uptimeNanoseconds
                var output: String?, failure: String?
                do {
                    output = try await arm.translate(sample, model, { _ in first.record() })
                } catch { failure = error.localizedDescription }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                let timing = failure == nil ? await arm.timing() : nil
                records.append(Record(arm: arm.name, sampleID: sample.id, size: sample.size,
                    orderPosition: turn.orderPosition, totalMilliseconds: elapsed,
                    firstTextMilliseconds: first.elapsed(from: start), preparedBeforeTurn: prepared,
                    usedPreparedThread: timing?.prepared ?? false, preservedLiteralCount: timing?.literals ?? 0,
                    output: output, error: failure))
                try save()
                print("\(records.count)/\(schedule.count): \(arm.name) \(sample.id) \(Int(elapsed))ms ready=\(prepared) prepared=\(timing?.prepared ?? false) error=\(failure ?? "none")")
                fflush(nil)
                if let failure { throw NSError(domain: "benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            }
        } catch {
            for arm in arms { await arm.disconnect() }
            throw error
        }
        for arm in arms { await arm.disconnect() }
    }

    private static func summarize(_ records: [Record]) -> [ArmSummary] {
        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted(), middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        let sizes = records.reduce(into: [String]()) { if !$0.contains($1.size) { $0.append($1.size) } }
        return armNames.flatMap { arm in
            sizes.compactMap { size -> ArmSummary? in
                let group = records.filter { $0.arm == arm && $0.size == size }
                guard !group.isEmpty else { return nil }
                let succeeded = group.filter { $0.error == nil }
                return ArmSummary(arm: arm, size: size, count: group.count, errors: group.count - succeeded.count,
                                  p50TotalMilliseconds: median(succeeded.map(\.totalMilliseconds)),
                                  p50FirstTextMilliseconds: median(succeeded.compactMap(\.firstTextMilliseconds)))
            }
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(64)
    }
}
