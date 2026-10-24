import Foundation

/// 요청 하나의 모델 출력을 검사하고 고친다. 스트리밍 조각과 완료 결과가 모두 거친다.
/// 원문은 모델이 실제로 본 글(`TranslationRequest.modelInput`)이다. 앱이 넣은 펜스·태그도 코드로 보고 비교한다.
/// - 조각: 한국어 결과면 한자를 독음으로 바꿔 보이고(`HanjaRepair.Stream`), 첫 시도에서는 원문 반복을 일찍 찾는다.
/// - 완료: 한자를 고친 글과 원문 반복 판정을 돌려준다. 반복 판정은 고치기 전 글로 하므로 조각의 판정과 같다.
struct TranslationOutputCheck {
    enum Partial: Equatable {
        /// 원문을 그대로 돌려주고 있다. 남은 스트림을 기다리지 않고 다시 요청한다.
        case echo
        /// 화면에 보일 글. 판정이 남은 끝 한자 묶음은 빠져 있을 수 있다.
        case show(String)
    }

    struct Review: Equatable {
        let text: String
        let echo: Bool
        let coverage: Double
        let candidates: Int
        let hanja: HanjaRepair.Counts
    }

    let attempt: Int
    private let source: String
    private let sourceLanguage: String
    private let targetLanguage: String
    private let probe: EchoProbe
    private let repair: HanjaRepair?
    private var echoStream: EchoProbe.Stream?
    private var hanjaStream: HanjaRepair.Stream?
    private var checkedLength = 0

    /// - Parameters:
    ///   - source: 모델 입력. 원문 반복의 기준이다.
    ///   - protecting: 결과에 있어도 고치지 않을 한자의 출처(모델 입력).
    ///   - retriesEcho: 끄면 조각에서 원문 반복을 찾지 않는다(`outputEchoRetry`). 완료 판정은 그대로 한다.
    ///   - repairsHanja: 끄면 한자를 고치지 않는다(`outputHanjaRepair`).
    init(source: String, protecting: [String], sourceLanguage: String, targetLanguage: String, attempt: Int,
         retriesEcho: Bool = true, repairsHanja: Bool = true) {
        self.attempt = attempt
        self.source = source
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        probe = EchoProbe(source: source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        repair = repairsHanja && targetLanguage == "ko" ? HanjaRepair(protecting: protecting) : nil
        echoStream = retriesEcho && attempt == 1 && probe.count > 0 ? EchoProbe.Stream(probe) : nil
        hanjaStream = repair.map(HanjaRepair.Stream.init)
    }

    /// 조각마다 부른다. 원문 반복 검사는 조각이 24 UTF-16 단위 이상 늘었을 때만 하고, 건너뛴 부분은 완료 검사가 잡는다.
    mutating func partial(_ snapshot: String) -> Partial {
        if var stream = echoStream {
            let length = snapshot.utf16.count
            if length < checkedLength { checkedLength = 0 }
            if length - checkedLength >= 24 {
                checkedLength = length
                let echo = stream.update(with: snapshot).isEcho
                echoStream = stream
                if echo { return .echo }
            }
        }
        guard var stream = hanjaStream else { return .show(snapshot) }
        let shown = stream.repairedPrefix(of: snapshot)
        hanjaStream = stream
        return .show(shown)
    }

    func review(_ raw: String) -> Review {
        let repaired = repair?.apply(to: raw) ?? (text: raw, counts: HanjaRepair.Counts())
        let echo = probe.measure(raw)
        return Review(text: repaired.text, echo: echo.isEcho, coverage: echo.coverage, candidates: probe.count, hanja: repaired.counts)
    }

    /// 보고에 남길 규칙 이름: 마지막 글의 `lint()` 결과에서 원문 반복만 `review`의 판정으로 바꾼다.
    func rules(final text: String, echo: Bool) -> [String] {
        var rules = Set(TranslationOutputLint.lint(source: source, output: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            .map(\.rule.rawValue))
        rules.remove(TranslationOutputLint.Rule.sourceEcho.rawValue)
        if echo { rules.insert(TranslationOutputLint.Rule.sourceEcho.rawValue) }
        return rules.sorted()
    }

    private typealias EchoProbe = TranslationOutputLint.EchoProbe
}

/// 출력 검사 결과의 기록. 규칙 이름과 수만 담고 원문·번역문은 담지 않는다.
public struct TranslationOutputReport: Equatable, Sendable {
    public enum Outcome: String, Sendable {
        case accepted
        case retryingAfterEcho
        case unresolvedEcho
    }

    public let requestID: UUID
    public let provider: String?
    public let attempt: Int
    public let incremental: Bool
    public let outcome: Outcome
    /// 스트리밍 중에 원문 반복을 찾아 중단했다.
    public let early: Bool
    /// 마지막 글의 `TranslationOutputLint.Rule` 이름, 정렬됨.
    public let rules: [String]
    /// 원문 반복 비율과 후보 문장 수(`TranslationOutputLint.EchoProbe`).
    public let coverage: Double
    public let candidates: Int
    public let hanjaReplaced: Int
    public let hanjaUnreadable: Int
    public let hanjaKept: Int
    public let hanjaInCode: Int
    public let preambleRemoved: Bool
    /// 앱이 펜스를 씌운 코드 블록의 가드 결과(`CodeBlockGuard.Outcome`): 그대로, 되돌림, 다시 펜스, 다시 넣음.
    public let codeKept: Int
    public let codeRestored: Int
    public let codeRefenced: Int
    public let codeInserted: Int
}
