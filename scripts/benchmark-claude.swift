import Darwin
import Foundation

// Claude Code 번역 경로의 지연을 arm별로 교차 실행해 기록한다.
//
// 모든 arm은 같은 모델·같은 프롬프트로 매 번역 새 컨텍스트를 쓴다. 차이는 전송 방식,
// 구독 확인 정책, 대기 프로세스 유무뿐이다.
//
// | arm | 설정 |
// |---|---|
// | baseline-json | oneShotJSON, 구독 확인 유효 시간 0. 현재 main과 같은 동작 |
// | baseline-json-proof | oneShotJSON, 유효 시간 30초 + 백그라운드 갱신. 전송 방식 효과만 분리 |
// | stream-warm | automatic. client가 --warm-wait초 쉰 뒤(대기 프로세스 부팅 완료) 전송 |
// | stream-immediate | stream-warm 직후 같은 client로 바로 전송. 교체 대기 프로세스가 아직 부팅 중. stream-warm을 고르지 않으면 lead 요청을 먼저 보낸다 |
// | stream-idle | automatic. client가 --idle-gaps초 쉰 뒤 전송. 간격마다 client를 따로 둔다 |
// | stream-ondemand | streamOnDemand. 대기 프로세스 없이 요청마다 CLI를 띄운다 |
//
// arm마다 client(lane)를 따로 두고, 라운드(표본×반복)마다 arm 순서를 회전해 네트워크 변동이
// 모든 arm에 고르게 섞이게 한다. client를 바꿀 때는 --settle초를 기다려 직전 결과 뒤의 교체
// 기동이 다음 요청과 겹치지 않게 한다. 원문은 저장하지 않고, 번역문은 --store-output일 때만 남긴다.

struct BenchmarkSampleFile: Decodable {
    let version: Int
    let status: String
    let samples: [BenchmarkSample]
}

struct BenchmarkSample: Decodable {
    let id: String
    let source: String
    let target: String
    let size: String
    let text: String
    let checks: [String]

    var direction: String { "\(source)->\(target)" }
}

enum BenchmarkArm: String, CaseIterable {
    case baselineJSON = "baseline-json"
    case baselineJSONProof = "baseline-json-proof"
    case streamWarm = "stream-warm"
    case streamIdle = "stream-idle"
    case streamImmediate = "stream-immediate"
    case streamOnDemand = "stream-ondemand"

    /// stream-idle은 라운드마다 가장 긴 간격만큼 기다리므로 명시했을 때만 넣는다.
    static let defaultSelection: [BenchmarkArm] = [
        .baselineJSON, .baselineJSONProof, .streamWarm, .streamImmediate, .streamOnDemand
    ]
}

struct BenchmarkOptions {
    static let defaultIdleGaps: [TimeInterval] = [90, 300]

    var samplesPath: String
    var resultsPath: String
    var sampleIDs: [String]?
    var arms = BenchmarkArm.defaultSelection
    var repeats = 1
    var idleGaps = defaultIdleGaps
    var warmWait: TimeInterval = 3
    var settle: TimeInterval = 2
    var maxRequests = 120
    var dryRun = false
    var storeOutput = false
    var claudePath: String?
    var model = ClaudeTranslationClient.defaultModel
    var sourceRevision: String?
    var clientSHA256: String?
    var lintSHA256: String?
    var samplesSHA256: String?
}

/// client 하나와 그 설정이다. 한 lane의 요청은 순서대로만 보내 대기 프로세스·구독 증명 상태가
/// 다른 arm과 섞이지 않게 한다.
struct BenchmarkLane {
    let name: String
    let transport: ClaudeTranslationClient.Configuration.Transport
    let subscriptionProofMaxAge: TimeInterval
    /// prewarm 모델을 지정한다. automatic에서는 대기 프로세스를, 그 밖의 전송 방식에서는
    /// 앱과 같은 구독 확인 백그라운드 갱신만 켠다.
    let prewarm: Bool
}

struct BenchmarkStep {
    let arm: String
    let lane: Int
    /// 보내기 전에 lane의 client가 쉬어야 하는 최소 시간이다. 직전 요청 완료(첫 요청은 준비 완료)부터 잰다.
    let minimumIdle: TimeInterval
    let idleGap: TimeInterval?
    let sendPolicy: String
}

struct PlannedRequest {
    let sequence: Int
    let round: Int
    let repeatIndex: Int
    let sample: BenchmarkSample
    let step: BenchmarkStep
}

struct BenchmarkPlan {
    let lanes: [BenchmarkLane]
    let armOrder: [String]
    let unitCount: Int
    let roundCount: Int
    let requests: [PlannedRequest]
    let uncappedRequestCount: Int
}

struct ResolvedExecutable {
    let url: URL
    let source: String
}

struct EnvironmentKeys {
    /// ClaudeTranslationClient가 자식 프로세스 환경에서 지우는 키(세션 변수·API 자격 증명)
    let removedByClient: [String]
    /// client는 남기지만 `open`으로 뜬 앱에는 없는 CLAUDE*/ANTHROPIC* 키. 벤치마크 프로세스에서 지운다.
    let removedByBenchmark: [String]
    /// 그대로 CLI에 전달되는 CLAUDE*/ANTHROPIC* 키
    let passedThrough: [String]
}

// MARK: - 기록 형식

struct TimingRecord: Encodable {
    let path: String
    let preparationMilliseconds: Double
    let turnMilliseconds: Double
    let totalMilliseconds: Double
    let subscriptionWaitMilliseconds: Double
    let spareAgeMilliseconds: Double?
    let firstOutputMilliseconds: Double?
    let firstTextMilliseconds: Double?
    let cliDurationMilliseconds: Double?
    let apiDurationMilliseconds: Double?
    let cliTTFTMilliseconds: Double?
    let fellBackFromStream: Bool

    init(_ timing: ClaudeTranslationClient.TranslationTiming) {
        path = timing.path.rawValue
        preparationMilliseconds = roundedMilliseconds(timing.preparationMilliseconds)
        turnMilliseconds = roundedMilliseconds(timing.turnMilliseconds)
        totalMilliseconds = roundedMilliseconds(timing.totalMilliseconds)
        subscriptionWaitMilliseconds = roundedMilliseconds(timing.subscriptionWaitMilliseconds)
        spareAgeMilliseconds = timing.spareAgeMilliseconds.map(roundedMilliseconds)
        firstOutputMilliseconds = timing.firstOutputMilliseconds.map(roundedMilliseconds)
        firstTextMilliseconds = timing.firstTextMilliseconds.map(roundedMilliseconds)
        cliDurationMilliseconds = timing.cliDurationMilliseconds.map(roundedMilliseconds)
        apiDurationMilliseconds = timing.apiDurationMilliseconds.map(roundedMilliseconds)
        cliTTFTMilliseconds = timing.cliTTFTMilliseconds.map(roundedMilliseconds)
        fellBackFromStream = timing.fellBackFromStream
    }
}

struct RequestRecord: Encodable {
    let sequence: Int
    let round: Int
    let repeatIndex: Int
    let arm: String
    let lane: String
    let idleGapSeconds: TimeInterval?
    let sampleID: String
    let source: String
    let target: String
    let direction: String
    let size: String
    let characters: Int
    let startedAt: String
    let status: String
    /// 보내기 전 client를 쉬게 하려고 기다린 시간
    let waitedBeforeMilliseconds: Double
    /// translate 호출부터 반환까지(벤치마크 측 측정)
    let hostTotalMilliseconds: Double
    /// translate 호출부터 첫 onPartialText까지
    let hostFirstPartialMilliseconds: Double?
    let partialCount: Int
    /// partial이 누적·접두 단조였는지. partial이 없으면 nil
    let partialsMonotonic: Bool?
    /// 마지막 partial이 최종 결과와 같은지. partial이 없으면 nil
    let finalMatchesLastPartial: Bool?
    /// turnMilliseconds − apiDurationMilliseconds
    let cliOverheadMilliseconds: Double?
    let timing: TimingRecord?
    let error: String?
    let errorSignal: String?
    let errorMessage: String?
    let output: String?
    /// 성공한 출력에 `TranslationOutputLint`가 보고한 위반(`rule(severity)`). 출력 내용은 담지 않는다.
    let lintViolations: [String]?
}

struct MetricSummary: Encodable {
    let n: Int
    let p50: Double
    let p95: Double
    /// nearest-rank p95는 n<20이면 사실상 최댓값이다.
    let p95Note: String?
    let min: Double
    let max: Double

    init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        n = sorted.count
        p50 = Self.nearestRank(50, sorted)
        p95 = Self.nearestRank(95, sorted)
        p95Note = sorted.count < 20 ? "n<20" : nil
        min = sorted[0]
        max = sorted[sorted.count - 1]
    }

    private static func nearestRank(_ percentile: Int, _ sorted: [Double]) -> Double {
        let rank = (percentile * sorted.count + 99) / 100
        return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
    }
}

struct CellSummary: Encodable {
    let arm: String
    let direction: String
    let size: String
    let attempts: Int
    let successes: Int
    let errors: Int
    let successRate: Double
    /// 1초 이내에 성공한 비율. 오류도 분모에 넣는다.
    let within1sRate: Double
    let totalMilliseconds: MetricSummary?
    /// 첫 partial(없으면 최종 결과)이 보인 시점
    let firstVisibleMilliseconds: MetricSummary?
    let subscriptionWaitMilliseconds: MetricSummary?
    let cliOverheadMilliseconds: MetricSummary?
    let paths: [String: Int]
    let fellBackFromStream: Int
    /// 번역 출력 검사기에 하나 이상 걸린 성공 출력 수
    let lintFlagged: Int

    init(arm: String, direction: String, size: String, records: [RequestRecord]) {
        let succeeded = records.filter { $0.status == "success" }
        self.arm = arm
        self.direction = direction
        self.size = size
        attempts = records.count
        successes = succeeded.count
        errors = records.count - succeeded.count
        successRate = roundedRate(Double(succeeded.count) / Double(records.count))
        within1sRate = roundedRate(
            Double(succeeded.filter { $0.hostTotalMilliseconds <= 1000 }.count) / Double(records.count)
        )
        totalMilliseconds = MetricSummary(succeeded.map(\.hostTotalMilliseconds))
        firstVisibleMilliseconds = MetricSummary(
            succeeded.map { $0.hostFirstPartialMilliseconds ?? $0.hostTotalMilliseconds }
        )
        subscriptionWaitMilliseconds = MetricSummary(succeeded.compactMap { $0.timing?.subscriptionWaitMilliseconds })
        cliOverheadMilliseconds = MetricSummary(succeeded.compactMap(\.cliOverheadMilliseconds))
        paths = Dictionary(grouping: succeeded.compactMap { $0.timing?.path }, by: { $0 }).mapValues(\.count)
        fellBackFromStream = succeeded.filter { $0.timing?.fellBackFromStream == true }.count
        lintFlagged = succeeded.filter { $0.lintViolations?.isEmpty == false }.count
    }
}

struct OptionsRecord: Encodable {
    let arms: [String]
    let samples: [String]
    let repeats: Int
    let idleGapsSeconds: [TimeInterval]
    let warmWaitSeconds: TimeInterval
    let settleSeconds: TimeInterval
    let maxRequests: Int
    let storeOutput: Bool
}

struct LaneRecord: Encodable {
    let name: String
    let transport: String
    let subscriptionProofMaxAgeSeconds: TimeInterval
    let prewarm: Bool
}

struct EnvironmentRecord: Encodable {
    let cliVersion: String?
    let executablePath: String
    let resolvedExecutablePath: String
    let executableSource: String
    let macOSVersion: String
    let hardwareModel: String?
    let sanitizedEnvironmentKeys: [String]
    let benchmarkRemovedEnvironmentKeys: [String]
    let passedThroughEnvironmentKeys: [String]
    let sourceRevision: String?
    let clientSHA256: String?
    /// lintViolations 판정에 쓴 TranslationOutputLint.swift의 해시
    let lintSHA256: String?
}

/// --store-output 실행 뒤 사람이 채우는 품질 검토 자리다. 20260919-haiku-quality-pilot.json과 같은 키를 쓴다.
struct QualityAssessmentPlaceholder: Encodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case reviewer
        case usableSamples
        case majorErrors
        case perDirection
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
            try container.encodeNil(forKey: key)
        }
    }
}

struct BenchmarkRun: Encodable {
    let status: String
    let stopReason: String?
    let startedAt: String
    let finishedAt: String?
    let model: String
    let sampleFixtureVersion: Int
    let sampleFixtureStatus: String
    let sampleFixturePath: String
    let sampleFixtureSHA256: String?
    let options: OptionsRecord
    let environment: EnvironmentRecord
    let lanes: [LaneRecord]
    let plannedRequests: Int
    let attemptedRequests: Int
    let results: [RequestRecord]
    let summary: [CellSummary]
    let qualityAssessment: QualityAssessmentPlaceholder?
}

enum BenchmarkError: Error {
    case help
    case usage(String)
    case invalidFixture(String)
    case refused(String)
    case setup(String)
}

/// onPartialText 스냅샷에서 시각·개수·단조성만 남긴다. 텍스트는 저장하지 않는다.
final class PartialRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var firstAt: ContinuousClock.Instant?
    private var count = 0
    private var previous = ""
    private var monotonic = true

    func record(_ text: String) {
        let now = ContinuousClock.now
        lock.lock()
        defer { lock.unlock() }
        if firstAt == nil { firstAt = now }
        count += 1
        if !text.unicodeScalars.starts(with: previous.unicodeScalars) { monotonic = false }
        previous = text
    }

    func snapshot() -> (firstAt: ContinuousClock.Instant?, count: Int, monotonic: Bool, last: String) {
        lock.lock()
        defer { lock.unlock() }
        return (firstAt, count, monotonic, previous)
    }
}

private func roundedMilliseconds(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

private func roundedRate(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
}

private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}

private func formatSeconds(_ value: TimeInterval) -> String {
    String(format: "%gs", value)
}

private func padded(_ value: String, _ width: Int) -> String {
    value + String(repeating: " ", count: max(0, width - value.count))
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@main
struct ClaudeBenchmark {
    private static let usage = """
    usage: benchmark-claude <samples.json> <results.json> [options]
      --samples ID,...       sample IDs (default: every sample in the fixture)
      --arms ARM,...         baseline-json, baseline-json-proof, stream-warm, stream-idle,
                             stream-immediate, stream-ondemand (default: all except stream-idle)
      --repeats N            rounds per sample (default 1)
      --idle-gaps S,...      stream-idle client idle seconds before each request (default 90,300)
      --warm-wait S          stream-warm client idle seconds so the spare finishes booting (default 3)
      --settle S             seconds between a result and the next request on another client (default 2)
      --max-requests N       request cap, stream-immediate leads included (default 120)
      --claude PATH          Claude Code executable (default: app setting, then the client's search order)
      --model ID             Claude model ID to translate with (default: the app's default model)
      --store-output         keep translated text for the quality review (off by default)
      --dry-run              print the schedule only; starts no CLI process and sends no request
      --source-revision REV  recorded as-is (set by benchmark-claude.sh)
      --client-sha256 HASH   recorded as-is (set by benchmark-claude.sh)
      --lint-sha256 HASH     recorded as-is (set by benchmark-claude.sh)
      --samples-sha256 HASH  recorded as-is (set by benchmark-claude.sh)
    Live runs consume Claude subscription quota and require DEEPK_RUN_LIVE_BENCHMARK=1.
    """

    static func main() async {
        do {
            try await run()
        } catch let error as BenchmarkError {
            switch error {
            case .help:
                print(usage)
                Foundation.exit(0)
            case let .usage(message):
                writeStandardError("benchmark-claude: \(message)\n\(usage)")
                Foundation.exit(64)
            case let .refused(message):
                writeStandardError("benchmark-claude: \(message)")
                Foundation.exit(64)
            case let .invalidFixture(message), let .setup(message):
                writeStandardError("benchmark-claude: \(message)")
                Foundation.exit(1)
            }
        } catch {
            writeStandardError("benchmark-claude failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
        let fixture = try decodeFixture(at: URL(fileURLWithPath: options.samplesPath))
        let samples = try selectSamples(from: fixture, ids: options.sampleIDs)
        let plan = makePlan(options: options, samples: samples)
        guard !plan.requests.isEmpty else {
            throw BenchmarkError.usage("no unit fits within --max-requests \(options.maxRequests)")
        }

        let environment = ProcessInfo.processInfo.environment
        let executable = try resolveExecutable(explicit: options.claudePath, environment: environment)
        let keys = classifyEnvironment(environment)

        if options.dryRun {
            printDryRun(
                options: options,
                plan: plan,
                samples: samples,
                executable: executable,
                keys: keys,
                environment: environment
            )
            return
        }

        guard environment["DEEPK_RUN_LIVE_BENCHMARK"] == "1" else {
            throw BenchmarkError.refused(
                "live runs consume Claude subscription quota. Set DEEPK_RUN_LIVE_BENCHMARK=1 explicitly or pass --dry-run."
            )
        }
        guard let executable else {
            throw BenchmarkError.setup("Claude Code executable not found. Pass --claude PATH.")
        }
        guard !FileManager.default.fileExists(atPath: options.resultsPath) else {
            throw BenchmarkError.setup("result file already exists; choose a new path: \(options.resultsPath)")
        }

        // 앱은 `open`으로 떠서 상위 Claude Code 세션의 변수를 물려받지 않는다. client가 지우지 않는
        // 나머지 변수도 이 프로세스에서 지워 같은 조건으로 잰다. client가 환경을 읽기 전에 끝낸다.
        for key in keys.removedByBenchmark {
            unsetenv(key)
        }

        try await execute(
            options: options,
            fixture: fixture,
            samples: samples,
            plan: plan,
            executable: executable,
            keys: keys,
            environment: environment
        )
    }

    // MARK: - 입력 해석

    private static func parseOptions(_ arguments: [String]) throws -> BenchmarkOptions {
        let valueOptions: Set<String> = [
            "--samples", "--arms", "--repeats", "--idle-gaps", "--warm-wait", "--settle",
            "--max-requests", "--claude", "--model", "--source-revision", "--client-sha256",
            "--lint-sha256", "--samples-sha256"
        ]
        var positional: [String] = []
        var values: [String: String] = [:]
        var dryRun = false
        var storeOutput = false

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                throw BenchmarkError.help
            case "--dry-run":
                dryRun = true
            case "--store-output":
                storeOutput = true
            default:
                if valueOptions.contains(argument) {
                    // `--samples --dry-run`처럼 값이 빠지면 다음 옵션을 값으로 삼키지 않는다.
                    guard let value = iterator.next(), !value.hasPrefix("--") else {
                        throw BenchmarkError.usage("\(argument) needs a value")
                    }
                    guard values[argument] == nil else {
                        throw BenchmarkError.usage("\(argument) was given more than once")
                    }
                    values[argument] = value
                } else if argument.hasPrefix("-") {
                    throw BenchmarkError.usage("unknown option \(argument)")
                } else {
                    positional.append(argument)
                }
            }
        }
        guard positional.count == 2 else {
            throw BenchmarkError.usage("expected <samples.json> <results.json>")
        }

        var options = BenchmarkOptions(samplesPath: positional[0], resultsPath: positional[1])
        options.dryRun = dryRun
        options.storeOutput = storeOutput
        options.claudePath = values["--claude"]
        if let value = values["--model"] {
            let model = value.trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { throw BenchmarkError.usage("--model needs a model ID") }
            options.model = model
        }
        options.sourceRevision = values["--source-revision"]
        options.clientSHA256 = values["--client-sha256"]
        options.lintSHA256 = values["--lint-sha256"]
        options.samplesSHA256 = values["--samples-sha256"]

        if let value = values["--samples"] {
            options.sampleIDs = try uniqueList(value, flag: "--samples")
        }
        if let value = values["--arms"] {
            options.arms = try uniqueList(value, flag: "--arms").map { name in
                guard let arm = BenchmarkArm(rawValue: name) else {
                    throw BenchmarkError.usage("unknown arm \(name)")
                }
                return arm
            }
        }
        if let value = values["--repeats"] {
            guard let repeats = Int(value), repeats >= 1 else {
                throw BenchmarkError.usage("--repeats must be a positive integer")
            }
            options.repeats = repeats
        }
        if let value = values["--max-requests"] {
            guard let maxRequests = Int(value), maxRequests >= 1 else {
                throw BenchmarkError.usage("--max-requests must be a positive integer")
            }
            options.maxRequests = maxRequests
        }
        if let value = values["--idle-gaps"] {
            // "90"과 "90.0"이 같은 lane 이름을 두 번 만들지 않게 값으로 중복을 없앤다.
            var gaps: [TimeInterval] = []
            for text in try uniqueList(value, flag: "--idle-gaps") {
                guard let seconds = TimeInterval(text), seconds.isFinite, seconds > 0 else {
                    throw BenchmarkError.usage("--idle-gaps values must be positive seconds")
                }
                if !gaps.contains(seconds) { gaps.append(seconds) }
            }
            options.idleGaps = gaps
        }
        if let value = values["--warm-wait"] {
            guard let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 else {
                throw BenchmarkError.usage("--warm-wait must be zero or positive seconds")
            }
            options.warmWait = seconds
        }
        if let value = values["--settle"] {
            guard let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 else {
                throw BenchmarkError.usage("--settle must be zero or positive seconds")
            }
            options.settle = seconds
        }
        return options
    }

    private static func uniqueList(_ value: String, flag: String) throws -> [String] {
        var seen: Set<String> = []
        var items: [String] = []
        for raw in value.split(separator: ",") {
            let item = raw.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            if seen.insert(item).inserted { items.append(item) }
        }
        guard !items.isEmpty else {
            throw BenchmarkError.usage("\(flag) needs at least one value")
        }
        return items
    }

    private static func decodeFixture(at url: URL) throws -> BenchmarkSampleFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BenchmarkError.invalidFixture("cannot read \(url.path): \(error.localizedDescription)")
        }
        let fixture: BenchmarkSampleFile
        do {
            fixture = try JSONDecoder().decode(BenchmarkSampleFile.self, from: data)
        } catch {
            throw BenchmarkError.invalidFixture("cannot decode \(url.path): \(error)")
        }
        guard !fixture.samples.isEmpty,
              fixture.samples.allSatisfy({ !$0.id.isEmpty && !$0.text.isEmpty && !$0.source.isEmpty && !$0.target.isEmpty })
        else {
            throw BenchmarkError.invalidFixture("samples need non-empty ids, languages and text")
        }
        guard Set(fixture.samples.map(\.id)).count == fixture.samples.count else {
            throw BenchmarkError.invalidFixture("sample ids must be unique")
        }
        return fixture
    }

    private static func selectSamples(from fixture: BenchmarkSampleFile, ids: [String]?) throws -> [BenchmarkSample] {
        guard let ids else { return fixture.samples }
        let byID = Dictionary(uniqueKeysWithValues: fixture.samples.map { ($0.id, $0) })
        let missing = ids.filter { byID[$0] == nil }
        guard missing.isEmpty else {
            throw BenchmarkError.usage("unknown sample ids: \(missing.joined(separator: ", "))")
        }
        return ids.compactMap { byID[$0] }
    }

    // MARK: - 일정

    /// lane과 실행 단위를 만들고, 라운드마다 단위 순서를 한 칸씩 회전한다.
    /// `--max-requests`를 넘는 단위는 통째로 뺀다(stream-immediate가 lead 없이 남지 않게).
    private static func makePlan(options: BenchmarkOptions, samples: [BenchmarkSample]) -> BenchmarkPlan {
        let defaultProofMaxAge = ClaudeTranslationClient.Configuration().subscriptionProofMaxAge
        var lanes: [BenchmarkLane] = []
        var units: [[BenchmarkStep]] = []

        func addLane(_ lane: BenchmarkLane) -> Int {
            lanes.append(lane)
            return lanes.count - 1
        }

        var spareUnitAdded = false
        for arm in options.arms {
            switch arm {
            case .baselineJSON:
                let lane = addLane(BenchmarkLane(
                    name: arm.rawValue, transport: .oneShotJSON, subscriptionProofMaxAge: 0, prewarm: false
                ))
                units.append([BenchmarkStep(
                    arm: arm.rawValue, lane: lane, minimumIdle: 0, idleGap: nil,
                    sendPolicy: "auth status + one-shot json every request"
                )])
            case .baselineJSONProof:
                let lane = addLane(BenchmarkLane(
                    name: arm.rawValue, transport: .oneShotJSON,
                    subscriptionProofMaxAge: defaultProofMaxAge, prewarm: true
                ))
                units.append([BenchmarkStep(
                    arm: arm.rawValue, lane: lane, minimumIdle: 0, idleGap: nil,
                    sendPolicy: "one-shot json, reuses proof"
                )])
            case .streamWarm, .streamImmediate:
                // 두 arm은 같은 client를 쓴다. stream-warm 결과 뒤에 뜬 교체 대기 프로세스를
                // stream-immediate가 부팅 중에 가져간다. stream-warm이 없으면 lead 요청을 먼저 보낸다.
                guard !spareUnitAdded else { continue }
                spareUnitAdded = true
                let lane = addLane(BenchmarkLane(
                    name: "stream-spare", transport: .automatic,
                    subscriptionProofMaxAge: defaultProofMaxAge, prewarm: true
                ))
                var steps: [BenchmarkStep] = []
                if options.arms.contains(.streamWarm) {
                    steps.append(BenchmarkStep(
                        arm: BenchmarkArm.streamWarm.rawValue, lane: lane, minimumIdle: options.warmWait,
                        idleGap: nil, sendPolicy: "client idle >= \(formatSeconds(options.warmWait))"
                    ))
                } else {
                    steps.append(BenchmarkStep(
                        arm: "stream-immediate-lead", lane: lane, minimumIdle: 0, idleGap: nil,
                        sendPolicy: "lead for stream-immediate"
                    ))
                }
                if options.arms.contains(.streamImmediate) {
                    steps.append(BenchmarkStep(
                        arm: BenchmarkArm.streamImmediate.rawValue, lane: lane, minimumIdle: 0, idleGap: nil,
                        sendPolicy: "right after previous result"
                    ))
                }
                units.append(steps)
            case .streamIdle:
                for gap in options.idleGaps {
                    let name = "stream-idle-\(formatSeconds(gap))"
                    let lane = addLane(BenchmarkLane(
                        name: name, transport: .automatic,
                        subscriptionProofMaxAge: defaultProofMaxAge, prewarm: true
                    ))
                    units.append([BenchmarkStep(
                        arm: name, lane: lane, minimumIdle: gap, idleGap: gap,
                        sendPolicy: "client idle >= \(formatSeconds(gap))"
                    )])
                }
            case .streamOnDemand:
                let lane = addLane(BenchmarkLane(
                    name: arm.rawValue, transport: .streamOnDemand,
                    subscriptionProofMaxAge: defaultProofMaxAge, prewarm: true
                ))
                units.append([BenchmarkStep(
                    arm: arm.rawValue, lane: lane, minimumIdle: 0, idleGap: nil,
                    sendPolicy: "spawn per request"
                )])
            }
        }

        var requests: [PlannedRequest] = []
        var uncapped = 0
        var capped = false
        var round = 0
        for repeatIndex in 0..<options.repeats {
            for sample in samples {
                for offset in 0..<units.count {
                    let steps = units[(offset + round) % units.count]
                    uncapped += steps.count
                    guard !capped, requests.count + steps.count <= options.maxRequests else {
                        capped = true
                        continue
                    }
                    for step in steps {
                        requests.append(PlannedRequest(
                            sequence: requests.count + 1,
                            round: round + 1,
                            repeatIndex: repeatIndex + 1,
                            sample: sample,
                            step: step
                        ))
                    }
                }
                round += 1
            }
        }

        var armOrder: [String] = []
        for step in units.flatMap({ $0 }) where !armOrder.contains(step.arm) {
            armOrder.append(step.arm)
        }
        return BenchmarkPlan(
            lanes: lanes,
            armOrder: armOrder,
            unitCount: units.count,
            roundCount: round,
            requests: requests,
            uncappedRequestCount: uncapped
        )
    }

    // MARK: - 실행 환경

    /// `--claude`, 앱 설정(`com.deepk.app claudeExecutablePath`), client의 탐색 순서 순으로 찾는다.
    /// 찾은 경로를 모든 client에 명시적으로 넘겨 기록한 경로와 실행한 경로가 같게 한다.
    private static func resolveExecutable(
        explicit: String?,
        environment: [String: String]
    ) throws -> ResolvedExecutable? {
        let fileManager = FileManager.default
        if let explicit {
            let path = (explicit as NSString).expandingTildeInPath
            guard fileManager.isExecutableFile(atPath: path) else {
                throw BenchmarkError.usage("--claude is not an executable file: \(explicit)")
            }
            return ResolvedExecutable(url: URL(fileURLWithPath: path), source: "argument")
        }
        if let appPath = UserDefaults(suiteName: "com.deepk.app")?.string(forKey: "claudeExecutablePath"),
           !appPath.isEmpty
        {
            return ResolvedExecutable(url: URL(fileURLWithPath: appPath), source: "app-defaults")
        }

        let home = environment["HOME"]
        let candidates = [
            environment["CLAUDE_EXECUTABLE"],
            environment["CLAUDE_CLI_PATH"],
            home.map { "\($0)/.local/bin/claude" },
            home.map { "\($0)/.npm-global/bin/claude" },
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return ResolvedExecutable(url: URL(fileURLWithPath: path), source: "search")
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return ResolvedExecutable(url: candidate, source: "PATH")
            }
        }
        return nil
    }

    /// ClaudeTranslationClient.sanitizedEnvironment가 지우는 키와 같아야 한다(세션 변수, API 자격 증명).
    private static let clientRemovedKeys: Set<String> = [
        "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_INCLUDE_PARTIAL_MESSAGES", "CLAUDE_CODE_STARTUP_FAILURE_RESULTS", "CLAUDE_PID",
        "CLAUDE_CODE_SSE_PORT", "CLAUDE_CODE_HUB_ROOT", "CLAUDE_CODE_EXECPATH",
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL",
        "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_REFRESH_TOKEN", "CLAUDE_CODE_OAUTH_SCOPES",
        "ANTHROPIC_PROFILE", "ANTHROPIC_CONFIG_DIR", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY", "CLAUDE_CODE_SKIP_BEDROCK_AUTH", "CLAUDE_CODE_SKIP_VERTEX_AUTH",
        "CLAUDE_CODE_SKIP_FOUNDRY_AUTH", "AWS_PROFILE", "AWS_REGION", "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "GOOGLE_CLOUD_PROJECT",
        "GOOGLE_APPLICATION_CREDENTIALS", "AZURE_SUBSCRIPTION_ID", "AZURE_TENANT_ID", "AZURE_CLIENT_ID",
        "AZURE_CLIENT_SECRET"
    ]

    private static let clientRemovedPrefixes = [
        "CLAUDE_CODE_MESSAGING_", "CLAUDE_CODE_SESSION_", "CLAUDE_CODE_EMIT_", "CLAUDE_AGENT_SDK_",
        "ANTHROPIC_AWS_", "ANTHROPIC_VERTEX_", "ANTHROPIC_FOUNDRY_"
    ]

    /// 실행 대상 탐색과 설정 위치만 정하므로 앱 조건을 바꾸지 않는다.
    private static let keptClaudeKeys: Set<String> = ["CLAUDE_EXECUTABLE", "CLAUDE_CLI_PATH", "CLAUDE_CONFIG_DIR"]

    private static func classifyEnvironment(_ environment: [String: String]) -> EnvironmentKeys {
        var removedByClient: [String] = []
        var removedByBenchmark: [String] = []
        var passedThrough: [String] = []
        for key in environment.keys.sorted() {
            if clientRemovedKeys.contains(key) || clientRemovedPrefixes.contains(where: { key.hasPrefix($0) }) {
                removedByClient.append(key)
            } else if key.hasPrefix("CLAUDE") || key.hasPrefix("ANTHROPIC") {
                if keptClaudeKeys.contains(key) {
                    passedThrough.append(key)
                } else {
                    removedByBenchmark.append(key)
                }
            }
        }
        return EnvironmentKeys(
            removedByClient: removedByClient,
            removedByBenchmark: removedByBenchmark,
            passedThrough: passedThrough
        )
    }

    private static func displayPath(_ path: String, environment: [String: String]) -> String {
        guard let home = environment["HOME"], !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func environmentRecord(
        cliVersion: String?,
        executable: ResolvedExecutable,
        keys: EnvironmentKeys,
        options: BenchmarkOptions,
        environment: [String: String]
    ) -> EnvironmentRecord {
        EnvironmentRecord(
            cliVersion: cliVersion,
            executablePath: displayPath(executable.url.path, environment: environment),
            resolvedExecutablePath: displayPath(executable.url.resolvingSymlinksInPath().path, environment: environment),
            executableSource: executable.source,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModel(),
            sanitizedEnvironmentKeys: keys.removedByClient,
            benchmarkRemovedEnvironmentKeys: keys.removedByBenchmark,
            passedThroughEnvironmentKeys: keys.passedThrough,
            sourceRevision: options.sourceRevision,
            clientSHA256: options.clientSHA256,
            lintSHA256: options.lintSHA256
        )
    }

    // MARK: - dry-run

    private static func printDryRun(
        options: BenchmarkOptions,
        plan: BenchmarkPlan,
        samples: [BenchmarkSample],
        executable: ResolvedExecutable?,
        keys: EnvironmentKeys,
        environment: [String: String]
    ) {
        func list(_ values: [String]) -> String { values.isEmpty ? "(none)" : values.joined(separator: ", ") }

        print("Claude benchmark dry-run: no CLI process is started and no request is sent.")
        print("model: \(options.model)")
        if let executable {
            let path = displayPath(executable.url.path, environment: environment)
            let resolved = displayPath(executable.url.resolvingSymlinksInPath().path, environment: environment)
            print("executable: \(path) (\(executable.source)) -> \(resolved)")
        } else {
            print("executable: not found (a live run would stop here; pass --claude PATH)")
        }
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString), hardware: \(hardwareModel() ?? "unknown")")
        print("client strips: \(list(keys.removedByClient))")
        print("benchmark unsets: \(list(keys.removedByBenchmark))")
        print("passed through: \(list(keys.passedThrough))")
        print("source: \(options.sourceRevision ?? "unknown"), client sha256: \(options.clientSHA256 ?? "unknown"), lint sha256: \(options.lintSHA256 ?? "unknown")")
        print("samples: \(options.samplesPath) (sha256 \(options.samplesSHA256 ?? "unknown"))")
        print("results path (not written in dry-run): \(options.resultsPath)")
        if !options.arms.contains(.streamIdle), options.idleGaps != BenchmarkOptions.defaultIdleGaps {
            print("note: --idle-gaps is ignored because stream-idle is not selected")
        }

        print("")
        print("lanes (one client each):")
        for lane in plan.lanes {
            print(
                "  \(padded(lane.name, 22)) transport \(padded(lane.transport.rawValue, 15)) "
                    + "proof max age \(padded(formatSeconds(lane.subscriptionProofMaxAge), 5)) "
                    + "prewarm \(lane.prewarm ? "on" : "off")"
            )
        }

        print("")
        let cappedNote = plan.uncappedRequestCount > plan.requests.count
            ? ", \(plan.uncappedRequestCount - plan.requests.count) dropped by --max-requests"
            : ""
        print(
            "schedule: \(plan.requests.count) requests (max \(options.maxRequests)\(cappedNote)), "
                + "\(plan.roundCount) rounds x \(plan.unitCount) units, unit order rotates every round"
        )
        print("  every request switching clients waits >= \(formatSeconds(options.settle)) after the previous result")
        print("  seq  round  rep  \(padded("sample", 15)) \(padded("dir", 7)) \(padded("size", 10)) \(padded("arm", 22)) before send")
        for request in plan.requests {
            print(
                "  \(padded(String(request.sequence), 4)) \(padded(String(request.round), 6)) "
                    + "\(padded(String(request.repeatIndex), 4)) \(padded(request.sample.id, 15)) "
                    + "\(padded(request.sample.direction, 7)) \(padded(request.sample.size, 10)) "
                    + "\(padded(request.step.arm, 22)) \(request.step.sendPolicy)"
            )
        }

        print("")
        print("planned requests per cell:")
        print("  \(padded("arm", 22)) \(padded("dir", 7)) \(padded("size", 10)) n")
        for cell in plannedCells(plan: plan, samples: samples) {
            print("  \(padded(cell.arm, 22)) \(padded(cell.direction, 7)) \(padded(cell.size, 10)) \(cell.count)")
        }

        let idleLowerBound = plan.lanes.indices.compactMap { index -> TimeInterval? in
            let laneRequests = plan.requests.filter { $0.step.lane == index }
            guard let gap = laneRequests.first?.step.idleGap else { return nil }
            return gap * Double(laneRequests.count)
        }.max()
        if let idleLowerBound {
            print("")
            print("stream-idle waiting alone takes at least \(Int((idleLowerBound / 60).rounded(.up))) min.")
        }
    }

    private static func plannedCells(
        plan: BenchmarkPlan,
        samples: [BenchmarkSample]
    ) -> [(arm: String, direction: String, size: String, count: Int)] {
        var cells: [(arm: String, direction: String, size: String, count: Int)] = []
        for arm in plan.armOrder {
            for direction in uniqueOrdered(samples.map(\.direction)) {
                for size in uniqueOrdered(samples.map(\.size)) {
                    let count = plan.requests.filter {
                        $0.step.arm == arm && $0.sample.direction == direction && $0.sample.size == size
                    }.count
                    if count > 0 { cells.append((arm, direction, size, count)) }
                }
            }
        }
        return cells
    }

    private static func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - 실측

    private static func execute(
        options: BenchmarkOptions,
        fixture: BenchmarkSampleFile,
        samples: [BenchmarkSample],
        plan: BenchmarkPlan,
        executable: ResolvedExecutable,
        keys: EnvironmentKeys,
        environment: [String: String]
    ) async throws {
        let model = options.model
        let clock = ContinuousClock()
        let startedAt = Date().ISO8601Format()
        let partialPath = options.resultsPath + ".partial"
        var clients: [ClaudeTranslationClient] = []
        var idleSince: [ContinuousClock.Instant] = []
        var lastCompletion: (lane: Int, at: ContinuousClock.Instant)?
        var cliVersion: String?
        var records: [RequestRecord] = []
        var status = "running"
        var stopReason: String?

        func makeRun(finished: Bool) -> BenchmarkRun {
            BenchmarkRun(
                status: status,
                stopReason: stopReason,
                startedAt: startedAt,
                finishedAt: finished ? Date().ISO8601Format() : nil,
                model: model,
                sampleFixtureVersion: fixture.version,
                sampleFixtureStatus: fixture.status,
                sampleFixturePath: options.samplesPath,
                sampleFixtureSHA256: options.samplesSHA256,
                options: OptionsRecord(
                    arms: options.arms.map(\.rawValue),
                    samples: samples.map(\.id),
                    repeats: options.repeats,
                    idleGapsSeconds: options.idleGaps,
                    warmWaitSeconds: options.warmWait,
                    settleSeconds: options.settle,
                    maxRequests: options.maxRequests,
                    storeOutput: options.storeOutput
                ),
                environment: environmentRecord(
                    cliVersion: cliVersion,
                    executable: executable,
                    keys: keys,
                    options: options,
                    environment: environment
                ),
                lanes: plan.lanes.map {
                    LaneRecord(
                        name: $0.name,
                        transport: $0.transport.rawValue,
                        subscriptionProofMaxAgeSeconds: $0.subscriptionProofMaxAge,
                        prewarm: $0.prewarm
                    )
                },
                plannedRequests: plan.requests.count,
                attemptedRequests: records.count,
                results: records,
                summary: summarize(records, armOrder: plan.armOrder, samples: samples),
                qualityAssessment: options.storeOutput ? QualityAssessmentPlaceholder() : nil
            )
        }

        // 준비: lane마다 `--version`과 `auth status`로 연결한다(추론 요청 없음). prewarm lane은
        // 앱처럼 모델을 알리고 capture 힌트를 줘 대기 프로세스·구독 확인 갱신을 시작한다.
        do {
            for lane in plan.lanes {
                let client = ClaudeTranslationClient(configuration: .init(
                    executableURL: executable.url,
                    transport: lane.transport,
                    subscriptionProofMaxAge: lane.subscriptionProofMaxAge
                ))
                clients.append(client)
                try await client.connect()
                if cliVersion == nil { cliVersion = await client.installedVersion }
                if lane.prewarm {
                    await client.setPrewarm(model: model, generation: 1)
                    await client.warmUp(.capture)
                }
                idleSince.append(clock.now)
            }
        } catch {
            if cliVersion == nil, let client = clients.last { cliVersion = await client.installedVersion }
            status = "preflight_failed"
            stopReason = errorCategory(error)
            await shutDown(clients)
            try writeRun(makeRun(finished: true), to: options.resultsPath, overwrite: false)
            throw BenchmarkError.setup("preflight failed (\(errorCategory(error))); wrote \(options.resultsPath)")
        }

        for request in plan.requests {
            let laneIndex = request.step.lane
            let client = clients[laneIndex]
            let sample = request.sample

            var readyAt = idleSince[laneIndex].advanced(by: .seconds(request.step.minimumIdle))
            // 직전 결과 뒤 뜨는 교체 대기 프로세스·은퇴 프로세스가 다른 arm의 요청과 겹치지 않게 한다.
            // 회전해도 단위의 이웃 관계는 그대로라 겹침이 특정 arm에 몰리기 때문이다.
            if let lastCompletion, lastCompletion.lane != laneIndex {
                readyAt = max(readyAt, lastCompletion.at.advanced(by: .seconds(options.settle)))
            }
            let waitStart = clock.now
            if readyAt > waitStart {
                let seconds = milliseconds(waitStart.duration(to: readyAt)) / 1000
                if seconds >= 5 {
                    writeStandardError("waiting \(Int(seconds.rounded())) s before \(request.step.arm) (\(request.step.sendPolicy))")
                }
                try? await Task.sleep(until: readyAt, clock: .continuous)
            }
            let waited = milliseconds(waitStart.duration(to: clock.now))

            // 앱이 두 번째 ⌘C에서 보내는 힌트와 같다. prewarm이 꺼진 lane에서는 아무것도 하지 않는다.
            await client.warmUp(.capture)
            let recorder = PartialRecorder()
            let requestStartedAt = Date().ISO8601Format()
            let start = clock.now
            var output: String?
            var timing: ClaudeTranslationClient.TranslationTiming?
            var failure: Error?
            do {
                output = try await client.translate(
                    text: sample.text,
                    source: sample.source,
                    target: sample.target,
                    model: model,
                    onPartialText: { recorder.record($0) }
                )
                timing = await client.lastCompletedTiming
            } catch {
                failure = error
            }
            let end = clock.now
            idleSince[laneIndex] = end
            lastCompletion = (laneIndex, end)

            let partials = recorder.snapshot()
            let signal = failure.flatMap(errorSignal)
            let record = RequestRecord(
                sequence: request.sequence,
                round: request.round,
                repeatIndex: request.repeatIndex,
                arm: request.step.arm,
                lane: plan.lanes[laneIndex].name,
                idleGapSeconds: request.step.idleGap,
                sampleID: sample.id,
                source: sample.source,
                target: sample.target,
                direction: sample.direction,
                size: sample.size,
                characters: sample.text.count,
                startedAt: requestStartedAt,
                status: failure == nil ? "success" : "error",
                waitedBeforeMilliseconds: roundedMilliseconds(waited),
                hostTotalMilliseconds: roundedMilliseconds(milliseconds(start.duration(to: end))),
                hostFirstPartialMilliseconds: partials.firstAt.map { roundedMilliseconds(milliseconds(start.duration(to: $0))) },
                partialCount: partials.count,
                partialsMonotonic: partials.count > 0 ? partials.monotonic : nil,
                finalMatchesLastPartial: partials.count > 0 && output != nil ? partials.last == output : nil,
                cliOverheadMilliseconds: timing.flatMap { timing in
                    timing.apiDurationMilliseconds.map {
                        roundedMilliseconds(timing.turnMilliseconds - $0)
                    }
                },
                timing: timing.map(TimingRecord.init),
                error: failure.map(errorCategory),
                errorSignal: signal,
                errorMessage: options.storeOutput ? failure.map { String($0.localizedDescription.prefix(500)) } : nil,
                output: options.storeOutput ? output : nil,
                lintViolations: output.map { output in
                    TranslationOutputLint.lint(
                        source: sample.text, output: output, sourceLanguage: sample.source, targetLanguage: sample.target
                    ).map { "\($0.rule.rawValue)(\($0.severity.rawValue))" }
                }
            )
            records.append(record)
            writeStandardError(progressLine(record, total: plan.requests.count))

            // 장시간 실행이 중간에 끊겨도 쿼터를 쓴 기록이 남게 한다.
            do {
                try writeRun(makeRun(finished: false), to: partialPath, overwrite: true)
            } catch {
                writeStandardError("warning: could not write \(partialPath): \(error.localizedDescription)")
            }

            if let failure, let signal {
                status = "stopped"
                stopReason = "\(errorCategory(failure)):\(signal)"
                break
            }
        }

        if status == "running" {
            if plan.uncappedRequestCount > plan.requests.count {
                status = "stopped"
                stopReason = "max_requests_reached"
            } else {
                status = "completed"
            }
        }

        await shutDown(clients)
        let run = makeRun(finished: true)
        try writeRun(run, to: options.resultsPath, overwrite: false)
        try? FileManager.default.removeItem(atPath: partialPath)
        printSummary(run)
        print("Claude benchmark results written to \(options.resultsPath)")
    }

    /// 대기·진행·은퇴 중인 CLI를 모두 끝낸다. SIGTERM 뒤 SIGKILL 확인(2초)이 끝날 때까지 기다린다.
    private static func shutDown(_ clients: [ClaudeTranslationClient]) async {
        for client in clients {
            await client.disconnect()
        }
        try? await Task.sleep(for: .milliseconds(2500))
    }

    private static func progressLine(_ record: RequestRecord, total: Int) -> String {
        var line = "[\(record.sequence)/\(total)] \(record.arm) \(record.sampleID) \(record.direction) \(record.size): "
        if let error = record.error {
            line += "error \(error) after \(Int(record.hostTotalMilliseconds)) ms"
            if let signal = record.errorSignal { line += " (stop: \(signal))" }
            return line
        }
        line += "\(Int(record.hostTotalMilliseconds)) ms"
        var details: [String] = []
        if let timing = record.timing {
            details.append(timing.path)
            if timing.subscriptionWaitMilliseconds > 0 { details.append("auth \(Int(timing.subscriptionWaitMilliseconds)) ms") }
            if timing.fellBackFromStream { details.append("fell back") }
        }
        if let first = record.hostFirstPartialMilliseconds { details.append("first text \(Int(first)) ms") }
        if record.waitedBeforeMilliseconds >= 1 { details.append("waited \(Int(record.waitedBeforeMilliseconds)) ms") }
        if let lint = record.lintViolations, !lint.isEmpty { details.append("lint " + lint.joined(separator: " ")) }
        if !details.isEmpty { line += " (" + details.joined(separator: ", ") + ")" }
        return line
    }

    // MARK: - 결과

    private static func summarize(
        _ records: [RequestRecord],
        armOrder: [String],
        samples: [BenchmarkSample]
    ) -> [CellSummary] {
        var cells: [CellSummary] = []
        for arm in armOrder {
            for direction in uniqueOrdered(samples.map(\.direction)) {
                for size in uniqueOrdered(samples.map(\.size)) {
                    let group = records.filter { $0.arm == arm && $0.direction == direction && $0.size == size }
                    guard !group.isEmpty else { continue }
                    cells.append(CellSummary(arm: arm, direction: direction, size: size, records: group))
                }
            }
        }
        return cells
    }

    private static func printSummary(_ run: BenchmarkRun) {
        func value(_ metric: MetricSummary?) -> String {
            metric.map { String(format: "%.0f", $0.p50) } ?? "-"
        }
        func p95(_ metric: MetricSummary?) -> String {
            guard let metric else { return "-" }
            let text = String(format: "%.0f", metric.p95)
            return metric.p95Note.map { "\(text) (\($0))" } ?? text
        }

        print("")
        print("status: \(run.status)\(run.stopReason.map { " (\($0))" } ?? ""), \(run.attemptedRequests)/\(run.plannedRequests) requests, CLI \(run.environment.cliVersion ?? "unknown")")
        print("| arm | dir | size | n | ok | total p50 | total p95 | first visible p50 | auth wait p50 | CLI overhead p50 | paths |")
        print("|---|---|---|---|---|---|---|---|---|---|---|")
        for cell in run.summary {
            let paths = cell.paths.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            print(
                "| \(cell.arm) | \(cell.direction) | \(cell.size) | \(cell.attempts) | \(cell.successes) "
                    + "| \(value(cell.totalMilliseconds)) | \(p95(cell.totalMilliseconds)) "
                    + "| \(value(cell.firstVisibleMilliseconds)) | \(value(cell.subscriptionWaitMilliseconds)) "
                    + "| \(value(cell.cliOverheadMilliseconds)) | \(paths.isEmpty ? "-" : paths) |"
            )
        }
    }

    private static func writeRun(_ run: BenchmarkRun, to path: String, overwrite: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(run)
        try data.write(to: URL(fileURLWithPath: path), options: overwrite ? .atomic : .withoutOverwriting)
    }

    // MARK: - 오류 분류

    /// 오류 원문(CLI stderr 등)은 기본 기록에 남기지 않고 분류만 남긴다.
    private static func errorCategory(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        guard let error = error as? ClaudeTranslationClient.ClientError else { return "unknown_error" }
        switch error {
        case .cliUnavailable: return "cli_unavailable"
        case .processStartFailed: return "process_start_failed"
        case .processTerminated: return "process_terminated"
        case let .cliFailed(status, _): return "cli_failed_\(status)"
        case .authenticationRequired: return "authentication_required"
        case .malformedResponse: return "malformed_response"
        case .timeout: return "timeout"
        case .emptyTranslation: return "empty_translation"
        case .invalidInput: return "invalid_input"
        case .modelUnavailable: return "model_unavailable"
        case .logoutUnsupported: return "logout_unsupported"
        case .turnFailed: return "turn_failed"
        }
    }

    /// 이후 요청도 같은 이유로 실패하거나 쿼터만 쓸 오류면 신호를 돌려준다. 신호가 있으면 실행을 멈춘다.
    private static func errorSignal(_ error: Error) -> String? {
        guard let error = error as? ClaudeTranslationClient.ClientError else { return nil }
        switch error {
        case .authenticationRequired:
            return "auth"
        case .cliUnavailable:
            return "cli_unavailable"
        case .modelUnavailable:
            return "model_unavailable"
        case let .turnFailed(message), let .cliFailed(_, message):
            let value = message.lowercased()
            // Claude Code 2.1.x의 구독 한도 문구("You've hit your limit · resets …" 등)도 함께 잡는다.
            if ["rate limit", "rate_limit", "ratelimit", "usage limit", "limit reached", "quota",
                "too many requests", "429", "hit your limit", "spend limit", "out of usage credits",
                "usage credits", "shared budget"].contains(where: { value.contains($0) }) {
                return "rate_limit"
            }
            if ["unauthorized", "authentication", "forbidden", "401", "403"].contains(where: { value.contains($0) }) {
                return "auth"
            }
            return nil
        default:
            return nil
        }
    }
}
