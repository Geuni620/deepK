import Foundation
import NaturalLanguage
import Observation

/// Raw values are `NLLanguage` codes, so a recognized language maps by its code. The prompt names a language by the same code.
public enum TranslationLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"
    case vietnamese = "vi"

    /// Each language in its own script, as language menus usually list them.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        case .japanese: "日本語"
        case .simplifiedChinese: "中文(简体)"
        case .traditionalChinese: "中文(繁體)"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .italian: "Italiano"
        case .russian: "Русский"
        case .vietnamese: "Tiếng Việt"
        }
    }

    /// The top of the language menu. The rest are under '다른 언어'.
    public static let common: [TranslationLanguage] = [.english, .japanese, .simplifiedChinese, .german, .french, .spanish]
    public static var others: [TranslationLanguage] { allCases.filter { $0 != .korean && !common.contains($0) } }

    /// Short English is often ranked below another language written in the same letters.
    fileprivate var writesLatinLetters: Bool {
        switch self {
        case .english, .german, .french, .spanish, .portuguese, .italian, .vietnamese: true
        case .korean, .japanese, .simplifiedChinese, .traditionalChinese, .russian: false
        }
    }
}

/// Korean becomes `koreanTarget`; every other language becomes Korean. `source` nil detects the source language.
/// Equal directions translate alike: a fixed non-Korean source ignores `koreanTarget`, so it compares by `rawValue`.
public struct TranslationDirection: RawRepresentable, Hashable, Codable, Sendable {
    public let source: TranslationLanguage?
    public let koreanTarget: TranslationLanguage

    public init(source: TranslationLanguage?, koreanTarget: TranslationLanguage = .english) {
        self.source = source
        self.koreanTarget = koreanTarget == .korean ? .english : koreanTarget
    }

    public static let automatic = TranslationDirection(source: nil)
    public static let englishToKorean = TranslationDirection(source: .english)
    public static let koreanToEnglish = TranslationDirection(source: .korean)

    /// `auto` and `en-ko`/`ko-en` keep the values saved before more languages; `auto>ja` is automatic with Korean → 日本語.
    public var rawValue: String {
        guard let source else { return koreanTarget == .english ? "auto" : "auto>\(koreanTarget.rawValue)" }
        return "\(source.rawValue)-\(target(for: source).rawValue)"
    }

    public init?(rawValue: String) {
        if rawValue == "auto" { self = .automatic; return }
        if rawValue.hasPrefix("auto>") {
            guard let target = TranslationLanguage(rawValue: String(rawValue.dropFirst(5))), target != .korean else { return nil }
            self.init(source: nil, koreanTarget: target)
            return
        }
        // Codes contain '-' (zh-Hans), so the split is where both sides are codes.
        for source in TranslationLanguage.allCases where rawValue.hasPrefix(source.rawValue + "-") {
            guard let target = TranslationLanguage(rawValue: String(rawValue.dropFirst(source.rawValue.count + 1))),
                  (source == .korean) != (target == .korean) else { continue }
            self.init(source: source, koreanTarget: source == .korean ? target : .english)
            return
        }
        return nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var isAutomatic: Bool { source == nil }

    public func target(for source: TranslationLanguage) -> TranslationLanguage {
        source == .korean ? koreanTarget : .korean
    }

    /// The same source rule with Korean translated into `target`.
    public func withKoreanTarget(_ target: TranslationLanguage) -> TranslationDirection {
        TranslationDirection(source: source, koreanTarget: target)
    }

    fileprivate var fixedLanguages: (source: TranslationLanguage, target: TranslationLanguage)? {
        source.map { ($0, target(for: $0)) }
    }
}

public struct TranslationRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let inputVersion: UInt64
    public let input: String
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    /// 요청이 만들어질 때 고정한 제공자·모델이다. 선택이 바뀌어도
    /// 진행 중인 요청과 결과가 어떤 계정에서 만들어졌는지 잃지 않는다.
    public let provider: String?
    public let model: String?
    public let modelLabel: String?
    public let cacheContext: String
    /// Links and inline code of a copied page. The model gets `markup.text` instead of `input`.
    public let markup: SourceMarkup?
    /// 2 for the one automatic re-request after the model echoed the source.
    public let attempt: Int

    public init(
        id: UUID = UUID(),
        inputVersion: UInt64,
        input: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        provider: String? = nil,
        model: String? = nil,
        modelLabel: String? = nil,
        cacheContext: String = "default",
        markup: SourceMarkup? = nil,
        attempt: Int = 1
    ) {
        self.id = id
        self.inputVersion = inputVersion
        self.input = input
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.provider = provider
        self.model = model
        self.modelLabel = modelLabel
        self.cacheContext = cacheContext
        self.markup = markup
        self.attempt = attempt
    }

    /// The text the model translates.
    public var modelInput: String { markup?.text ?? input }
    /// Links or chips come with instructions for the model; app-made code fences alone keep the prompt a plain copy gets.
    public var usesInlineMarkup: Bool { markup?.hasInlineStructure == true }
}

public struct TranslationResult: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let inputVersion: UInt64
    public let input: String
    public let direction: TranslationDirection
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    public let text: String
    /// 선택이 변경된 뒤에도 화면에 표시 중인 결과의 실제 처리 모델을 보존한다.
    public let provider: String?
    public let model: String?
    public let modelLabel: String?
    public let cacheContext: String
    /// The source structure the first translated unit was requested with; its link table resolves `<aN>` tags.
    public let markup: SourceMarkup?

    public init(
        id: UUID,
        inputVersion: UInt64,
        input: String,
        direction: TranslationDirection,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        text: String,
        provider: String? = nil,
        model: String? = nil,
        modelLabel: String? = nil,
        cacheContext: String = "default",
        markup: SourceMarkup? = nil
    ) {
        self.id = id
        self.inputVersion = inputVersion
        self.input = input
        self.direction = direction
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.text = text
        self.provider = provider
        self.model = model
        self.modelLabel = modelLabel
        self.cacheContext = cacheContext
        self.markup = markup
    }

    var inlineOptions: InlineOptions { InlineOptions(source: input, markup: markup) }
}

public enum TranslationStoreError: Error, Equatable, LocalizedError, Sendable {
    case emptyInput
    case inputTooLong(limit: Int)
    case unsupportedLanguage
    case engineUnavailable
    case timedOut
    case emptyResult
    case resultTooLong
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "번역할 원문을 입력하세요."
        case let .inputTooLong(limit):
            "원문은 최대 \(limit)자까지 입력할 수 있습니다."
        case .unsupportedLanguage:
            "원문 언어를 정하지 못했어요."
        case .engineUnavailable:
            "번역 엔진이 연결되지 않았습니다."
        case .timedOut:
            "번역 요청 시간이 초과되었습니다."
        case .emptyResult:
            "번역 엔진이 빈 결과를 반환했습니다."
        case .resultTooLong:
            "번역 결과가 너무 큽니다. 원문을 나누어 다시 시도하세요."
        case let .provider(message):
            message
        }
    }
}

/// What the result surface shows. `identity` changes only when the shown text
/// stops being a continuation of what the reader was looking at, so the surface
/// may reset its scroll position only then.
public struct TranslationDisplay: Equatable, Sendable {
    public let identity: UUID
    public let text: String?
    /// UTF-16 offset where the newest unit's translation begins.
    public let tailStart: Int?
    /// An earlier translation kept readable until its replacement completes.
    public let isStale: Bool
    /// How inline code and link tags in `text` are read.
    let inline: InlineOptions
    /// UTF-16 offsets in `text` where a unit above an explicit `---` boundary ends. The result view
    /// draws a line there; the text itself holds no `---`.
    public let unitBreaks: [Int]

    init(identity: UUID, text: String?, tailStart: Int?, isStale: Bool, inline: InlineOptions = .init(), unitBreaks: [Int] = []) {
        self.identity = identity
        self.text = text
        self.tailStart = tailStart
        self.isStale = isStale
        self.inline = inline
        self.unitBreaks = unitBreaks
    }
}

public enum TranslationStatus: Equatable, Sendable {
    case idle
    case disconnected
    case waiting
    case translating
    case success
    case error(TranslationStoreError)
}

/// What the runtime output check tells the reader about the current translation.
public enum TranslationOutputNotice: Equatable, Sendable {
    /// The first answer repeated the source; a fresh request is running.
    case retryingAfterEcho
    /// The re-requested answer still repeats the source. It stays usable, with a warning.
    case unresolvedEcho
}

/// 인증·모델·통신 구현은 주입한 번역 함수에 맡기고, 엔진 준비 상태는 별도로 전달받는다.
@MainActor
@Observable
public final class TranslationStore {
    public typealias Translator = @Sendable (TranslationRequest) async throws -> String

    public struct Configuration: Sendable, Equatable {
        public var maximumInputLength: Int
        public var typingDebounce: Duration
        public var requestTimeout: Duration?
        public var cacheCapacity: Int
        public var cacheLifetime: Duration
        public var maximumResultBytes: Int
        public var maximumCacheBytes: Int

        public init(
            maximumInputLength: Int = 4_000,
            typingDebounce: Duration = .milliseconds(500),
            requestTimeout: Duration? = .seconds(30),
            cacheCapacity: Int = 32,
            cacheLifetime: Duration = .seconds(300),
            maximumResultBytes: Int = 256_000,
            maximumCacheBytes: Int = 2_000_000
        ) {
            precondition(maximumInputLength > 0, "The maximum input length must be greater than zero.")
            precondition(typingDebounce >= .zero, "The typing debounce cannot be negative.")
            if let requestTimeout {
                precondition(requestTimeout > .zero, "The request timeout must be greater than zero.")
            }

            self.maximumInputLength = maximumInputLength
            self.typingDebounce = typingDebounce
            precondition(cacheCapacity >= 0 && cacheLifetime >= .zero)
            self.requestTimeout = requestTimeout
            self.cacheCapacity = cacheCapacity
            self.cacheLifetime = cacheLifetime
            precondition(maximumResultBytes > 0 && maximumCacheBytes >= 0)
            self.maximumResultBytes = maximumResultBytes
            self.maximumCacheBytes = maximumCacheBytes
        }
    }

    public private(set) var sourceText = ""
    public private(set) var latestResult: TranslationResult?
    public private(set) var status: TranslationStatus
    public private(set) var direction: TranslationDirection = .automatic
    /// The reader's pick for this source when detection could not decide. Automatic direction only;
    /// a new copy, an emptied source or another direction drops it.
    public private(set) var sourceLanguageOverride: TranslationLanguage?
    @ObservationIgnored private var likelyLanguagesMemo: (source: String, languages: [TranslationLanguage])?
    public private(set) var engineReady: Bool
    public private(set) var inputVersion: UInt64 = 0
    public private(set) var isComposing = false
    public private(set) var lastResultWasCached = false
    /// 선택한 제공자·모델이 화면에 표시 중인 결과와 다를 때 재번역을 요구한다.
    public private(set) var requiresRetranslation = false
    /// The active request is the re-request made after the first answer echoed the source.
    public private(set) var isRetryingAfterEcho = false
    /// Emergency switches, read from `outputEchoRetry` and `outputHanjaRepair` by the app.
    /// Without the echo retry an echoed answer is shown at once with the unresolved warning.
    @ObservationIgnored public var retriesSourceEcho = true
    @ObservationIgnored public var repairsHanja = true

    /// Reads the emergency switches; a missing key keeps the check on.
    /// `defaults write com.deepk.app outputEchoRetry -bool false` (or `outputHanjaRepair`) turns one off after a relaunch.
    public func applyOutputCheckSwitches(from defaults: UserDefaults) {
        retriesSourceEcho = defaults.object(forKey: "outputEchoRetry") as? Bool ?? true
        repairsHanja = defaults.object(forKey: "outputHanjaRepair") as? Bool ?? true
    }
    /// Each checked answer: names and counts only, never source or translation text.
    @ObservationIgnored public var onOutputReport: ((TranslationOutputReport) -> Void)?

    private var document: TranslationDocument?
    public var displaySegments: [TranslationSegment] { document?.segments ?? [] }
    public private(set) var streamingText: String?
    @ObservationIgnored private var pendingStreamingText: String?
    @ObservationIgnored private var streamingTask: Task<Void, Never>?

    private struct LanguagePair: Equatable {
        let source: TranslationLanguage
        let target: TranslationLanguage
    }
    private var displayIdentity = UUID()
    /// The translation the reader was looking at before a whole-document request.
    /// It stays readable, dimmed, until the replacement completes.
    private var superseded: String?
    @ObservationIgnored private var supersededSource: String?
    @ObservationIgnored private var supersededInline = InlineOptions()
    @ObservationIgnored private var supersededBreaks: [Int] = []
    /// The latest double copy. Its structure survives extensions of its exact plain-text prefix.
    /// Changes inside that prefix are conservative: translate plain text until the prefix is restored.
    @ObservationIgnored private var capturedSource: CapturedSource?
    @ObservationIgnored private var inlineMemo: (source: String, markup: SourceMarkup?, options: InlineOptions)?
    @ObservationIgnored private var boundaryMemo: (source: String, sent: Range<Int>, lines: [NSRange])?
    private var lastLanguages: LanguagePair?

    public var display: TranslationDisplay {
        if let superseded {
            return TranslationDisplay(identity: displayIdentity, text: superseded, tailStart: nil, isStale: true,
                                      inline: supersededInline, unitBreaks: supersededBreaks)
        }
        let inline = inlineOptions
        // Whitespace at the end of a snapshot may still be trimmed by the provider.
        let preview = streamingText.map(Self.trimmingTrailingWhitespace) ?? ""
        if let token = activeToken, token.incremental, let document {
            let rendered = document.rendered
            guard !preview.isEmpty else {
                // The line below the completed units appears with the tail's first text.
                return TranslationDisplay(identity: displayIdentity, text: rendered.text, tailStart: rendered.text.utf16.count,
                                          isStale: false, inline: inline, unitBreaks: rendered.unitBreaks)
            }
            let joined = document.text(appending: preview, separator: token.separator)
            let breaks = rendered.unitBreaks + (document.appendsExplicitly(separator: token.separator) ? [joined.tailStart] : [])
            return TranslationDisplay(identity: displayIdentity, text: joined.text, tailStart: joined.tailStart, isStale: false,
                                      inline: inline, unitBreaks: breaks)
        }
        if !preview.isEmpty {
            return TranslationDisplay(identity: displayIdentity, text: preview, tailStart: 0, isStale: false, inline: inline)
        }
        let rendered = document?.rendered
        return TranslationDisplay(identity: displayIdentity, text: rendered?.text, tailStart: document?.lastSegmentStart,
                                  isStale: false, inline: inline, unitBreaks: rendered?.unitBreaks ?? [])
    }

    /// UTF-16 ranges of the source's `---` lines that are boundaries, not translated text: none while the
    /// source is a structured copy sent whole, and none inside a structured first unit's text (its separator
    /// was not sent). Every request without structure is cut at its first boundary (D1), so the source alone
    /// decides. A first unit left after the structured one was removed holds no boundary line, so excluding
    /// its text changes nothing (segment ids do not tell: a cache restore gives the basis a new id).
    public var sourceBoundaryLines: [NSRange] {
        var sent = 0..<0
        let unit = firstRequestUnit(in: sourceText)
        if markup(for: unit.input) != nil {
            sent = unit.separator.utf8.count..<(unit.separator.utf8.count + unit.input.utf8.count)
        } else if let document, document.basis.markup != nil, let first = document.segments.first {
            let start = first.separator.utf8.count
            sent = start..<(start + first.input.utf8.count)
        } else if document == nil, let request = activeRequest, request.markup != nil, let token = activeToken, !token.incremental {
            sent = token.separator.utf8.count..<token.snapshot.utf8.count
        }
        if let memo = boundaryMemo, memo.source == sourceText, memo.sent == sent { return memo.lines }
        let lines = IncrementalTranslationPlanner.boundaryLineRanges(in: sourceText, excludingUTF8: sent)
        boundaryMemo = (sourceText, sent, lines)
        return lines
    }

    /// The document's structure governs once it exists, so a typed tail keeps the links above it.
    private var inlineOptions: InlineOptions {
        let markup = document?.basis.markup ?? activeRequest?.markup
        if let memo = inlineMemo, memo.source == sourceText, memo.markup == markup { return memo.options }
        let options = InlineOptions(source: sourceText, markup: markup)
        inlineMemo = (sourceText, markup, options)
        return options
    }

    /// The copied prefix's structure, followed by the exact text entered after it.
    private var activeMarkup: SourceMarkup? { markup(for: sourceText) }

    private func markup(for input: String) -> SourceMarkup? {
        guard let capturedSource, !capturedSource.plain.isEmpty, let markup = capturedSource.markup,
              input.utf8.starts(with: capturedSource.plain.utf8) else { return nil }
        let suffix = String(decoding: input.utf8.dropFirst(capturedSource.plain.utf8.count), as: UTF8.self)
        guard !suffix.isEmpty else { return markup }
        // An HTML block ends in an app-made closing fence. A same-line extension of its code
        // cannot be appended after that fence without changing the request's meaning. Translate
        // it as plain text; a new line after the block is a safe structural boundary.
        var firstLine = suffix.unicodeScalars.prefix { $0 != "\n" }
        if firstLine.last == "\r", suffix.unicodeScalars.contains("\n") { firstLine = firstLine.dropLast() }
        if firstLine.contains(where: { $0 != " " && $0 != "\t" }), let block = markup.blocks.last {
            let extendsCode = capturedSource.plain.utf8.suffix(block.code.utf8.count).elementsEqual(block.code.utf8)
            let closesAtEnd = markup.text.last?.isNewline != true
                && markup.text.split(whereSeparator: \.isNewline).last.map { String($0).trimmingCharacters(in: .whitespaces) == block.closer } == true
            if extendsCode || closesAtEnd { return nil }
        }
        return SourceMarkup(text: markup.text + suffix, links: markup.links, code: markup.code, blocks: markup.blocks)
    }

    private func firstRequestUnit(in source: String) -> IncrementalTranslationPlanner.Tail {
        if let capturedSource, capturedSource.markup != nil {
            return IncrementalTranslationPlanner.firstUnit(in: source, preservingPrefix: capturedSource.plain)
        }
        return IncrementalTranslationPlanner.firstUnit(in: source)
    }

    /// The current, non-stale translation text.
    public var displayedText: String? {
        let display = display
        return display.isStale ? nil : display.text
    }
    /// Completed units are shown while later ones are pending. Not while an earlier translation is kept
    /// dimmed: a block-by-block replacement replaces it once, when it covers the whole source.
    public var hasPartialResult: Bool { document != nil && !hasCurrentResult && superseded == nil }
    public var isIncrementalResult: Bool { displaySegments.count > 1 }
    public var outputNotice: TranslationOutputNotice? {
        if status == .translating && isRetryingAfterEcho { return .retryingAfterEcho }
        if hasCurrentResult && document?.hasUnresolvedEcho == true { return .unresolvedEcho }
        return nil
    }
    public var displayedSourceLanguage: TranslationLanguage? {
        document?.basis.sourceLanguage ?? activeRequest?.sourceLanguage ?? lastLanguages?.source
    }
    public var displayedTargetLanguage: TranslationLanguage? {
        document?.basis.targetLanguage ?? activeRequest?.targetLanguage ?? lastLanguages?.target
    }

    public var result: TranslationResult? {
        latestResult
    }

    public var resultText: String? {
        latestResult?.text
    }

    /// What copy's plain text and insert use: the result without fences the model added to an unfenced source,
    /// link words without URLs, and backticks only where the source wrote them.
    public var resultInsertionText: String? {
        latestResult.map { TranslationMarkup.insertionText(result: $0.text, source: Self.fenceSource($0.input, markup: $0.markup), inline: $0.inlineOptions) }
    }

    /// What the copy button writes: the stored markdown, and the plain text that insert also uses.
    public var resultCopy: (markdown: String, plain: String)? {
        guard let latestResult, let plain = resultInsertionText else { return nil }
        return (latestResult.text, plain)
    }

    /// How the source of the shown result fences its code; the result view's copies follow it.
    var resultFenceStyle: TranslationMarkup.FenceStyle {
        TranslationMarkup.FenceStyle(source: latestResult.map { Self.fenceSource($0.input, markup: $0.markup) } ?? sourceText)
    }

    /// The source as copies and insert read its fences. Code of the app's own blocks was a `<pre>` on the page, which showed no
    /// fences, so it is left out: code with ``` lines of its own would otherwise make an unfenced page read as fenced, and plain
    /// copy and insert would write the app's four-backtick fences.
    static func fenceSource(_ input: String, markup: SourceMarkup?) -> String {
        guard let blocks = markup?.blocks, !blocks.isEmpty else { return input }
        var source = ""
        var rest = Substring(input)
        for block in blocks {
            guard let range = rest.range(of: block.code) else { continue }
            source += rest[..<range.lowerBound]
            rest = rest[range.upperBound...]
        }
        return source + rest
    }

    /// 현재 결과를 실제로 만든 제공자·모델을 화면에 표시할 때 사용한다.
    public var resultModelLabel: String? {
        document?.basis.modelLabel ?? latestResult?.modelLabel
    }

    /// 원문이 바뀐 뒤 이전 번역 결과를 복사하지 못하게 한다.
    public var canCopy: Bool {
        hasCurrentResult
    }

    /// 여기서는 결과의 최신 여부만 확인한다. 실제 대상 앱과 편집 가능 여부는 Mac 연동에서 확인한다.
    public var canInsert: Bool {
        hasCurrentResult
    }

    @ObservationIgnored
    private let translator: Translator?

    @ObservationIgnored
    private let configuration: Configuration

    private enum PendingInput { case typing, copied }
    @ObservationIgnored private var pendingInput: (version: UInt64, kind: PendingInput)?

    @ObservationIgnored
    private var debounceTask: Task<Void, Never>?

    @ObservationIgnored
    private var requestTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var activeRequest: TranslationRequest?

    @ObservationIgnored
    private var activeRequestDirection: TranslationDirection?

    /// Checks and repairs the active request's answer, streamed and final.
    @ObservationIgnored
    private var activeCheck: TranslationOutputCheck?

    /// A token belongs to an immutable source prefix in one document generation.
    /// Adding a later paragraph does not invalidate it; modifying its prefix does.
    private struct SegmentRequestToken {
        let generation: UUID
        var snapshot: String
        let separator: String
        let incremental: Bool
    }
    @ObservationIgnored private var documentGeneration = UUID()
    @ObservationIgnored private var activeToken: SegmentRequestToken?
    @ObservationIgnored private var bypassCache = false
    @ObservationIgnored private var retryNeedsWholeDocument = false
    @ObservationIgnored private var lastInputKind: PendingInput = .typing
    @ObservationIgnored private var nextRequestAfter: ContinuousClock.Instant?

    private struct CacheKey: Hashable {
        let context: String
        let direction: String
        let source: String
        let target: String
        let input: String
        let markup: String?
        let provider: String?
        let model: String?
        let mode: String
    }
    private struct CacheEntry {
        let text: String
        let created: ContinuousClock.Instant
        let document: TranslationDocument?
        let byteCount: Int
    }
    @ObservationIgnored private var cacheContext: String
    @ObservationIgnored private var contextProvider: String?
    @ObservationIgnored private var contextModel: String?
    @ObservationIgnored private var contextModelLabel: String?
    @ObservationIgnored private var cache: [CacheKey: CacheEntry] = [:]
    @ObservationIgnored private var cacheOrder: [CacheKey] = []
    @ObservationIgnored private var cacheBytes = 0
    @ObservationIgnored private var activeCacheKey: CacheKey?
    @ObservationIgnored private let clock = ContinuousClock()

    public init(
        configuration: Configuration = Configuration(),
        engineReady: Bool = false,
        cacheContext: String = "default",
        translator: Translator? = nil
    ) {
        self.configuration = configuration
        self.cacheContext = cacheContext
        self.engineReady = engineReady
        self.translator = translator
        status = engineReady ? .idle : .disconnected
    }

    deinit {
        debounceTask?.cancel()
        requestTask?.cancel()
    }

    /// 연결 전의 최신 사용자 입력만 재개한다. 설정 변경은 대기 입력을 취소하므로 재번역하지 않는다.
    public func setEngineReady(_ ready: Bool) {
        guard ready != engineReady else { return }

        let pending = pendingInput
        let resumeInterruptedInput = !ready && (activeRequest != nil || debounceTask != nil)
        cancelActiveWork()
        engineReady = ready
        if resumeInterruptedInput { pendingInput = (inputVersion, lastInputKind) }
        if ready, let pending, pending.version == inputVersion, !requiresRetranslation, !isComposing {
            switch pending.kind {
            case .typing: scheduleAutomaticRequest()
            case .copied: startRequest()
            }
            return
        }

        if !ready {
            status = .disconnected
        } else if hasCurrentResult {
            status = .success
        } else {
            status = .idle
        }
    }

    /// 제공자·모델 선택만 변경한다. 진행 중인 요청은 취소하지만 현재 결과와
    /// 그 결과의 실제 모델 표시는 유지한다. 새 선택은 `retranslateSelection()`에서
    /// 사용자가 명시적으로 요청할 때만 번역 요청에 반영된다.
    public func setTranslationContext(
        cacheContext: String,
        provider: String?,
        model: String?,
        modelLabel: String?
    ) {
        let changed = self.cacheContext != cacheContext
            || contextProvider != provider
            || contextModel != model
            || contextModelLabel != modelLabel
        guard changed else { return }

        self.cacheContext = cacheContext
        contextProvider = provider
        contextModel = model
        contextModelLabel = modelLabel
        markProviderChangePrepared()
    }

    public func setDirection(_ direction: TranslationDirection) {
        guard self.direction != direction else { return }

        self.direction = direction
        sourceLanguageOverride = nil
        requiresRetranslation = false
        inputVersion &+= 1
        invalidateResultAndWork(.reset)

        guard validateSourceForScheduling() else { return }

        if isComposing {
            status = engineReady ? .waiting : .disconnected
        } else {
            scheduleAutomaticRequest()
        }
    }

    /// Translates the current source as `language`, for a source whose language was not decided.
    public func translateSource(as language: TranslationLanguage) {
        guard direction.isAutomatic, sourceLanguageOverride != language else { return }

        sourceLanguageOverride = language
        requiresRetranslation = false
        inputVersion &+= 1
        // A click, not typing: no debounce.
        nextRequestAfter = clock.now
        invalidateResultAndWork(.reset)

        guard validateSourceForScheduling() else { return }

        if isComposing {
            status = engineReady ? .waiting : .disconnected
        } else {
            scheduleAutomaticRequest()
        }
    }

    /// The languages to offer while the source language is not decided; empty otherwise.
    public var undecidedLanguageCandidates: [TranslationLanguage] {
        guard status == .error(.unsupportedLanguage) else { return [] }
        if let memo = likelyLanguagesMemo, memo.source == sourceText { return memo.languages }
        let languages = Self.likelyLanguages(in: IncrementalTranslationPlanner.proseOutsideFences(sourceText))
        likelyLanguagesMemo = (sourceText, languages)
        return languages
    }

    /// 선택 변경을 준비한다. 이전 결과를 지우거나 새 요청을 시작하지 않는다.
    /// 선택 변경 직후에도 원문·결과·실제 결과 모델을 계속 확인할 수 있어야 한다.
    public func prepareForProviderChange(cacheContext: String? = nil) {
        if let cacheContext {
            self.cacheContext = cacheContext
        }
        markProviderChangePrepared()
    }

    /// 사용자가 메인 창의 ‘다시 번역’을 눌렀을 때만 현재 선택으로 요청한다.
    public func retranslateSelection() {
        requiresRetranslation = false
        inputVersion &+= 1
        invalidateResultAndWork(.keep)

        guard validateSourceForScheduling() else { return }

        if isComposing {
            status = engineReady ? .waiting : .disconnected
        } else {
            scheduleAutomaticRequest()
        }
    }

    /// Explicitly request whole-document context, bypassing both reuse layers.
    public func retranslateWholeDocument() {
        requiresRetranslation = false
        inputVersion &+= 1
        invalidateResultAndWork(.keep)
        bypassCache = true
        retryNeedsWholeDocument = true
        guard validateSourceForScheduling() else { return }
        scheduleAutomaticRequest()
    }

    /// Repeats the last request kind for the current source. A failed whole-document
    /// retranslation is retried as one, not answered from the per-paragraph cache.
    public func retry() {
        if retryNeedsWholeDocument { retranslateWholeDocument() } else { invokeCopiedText(sourceText) }
    }

    /// Whether an earlier translation is kept dimmed while its replacement is pending.
    public var isShowingSupersededText: Bool { superseded != nil }

    /// 짧은 호출부를 위한 별칭이며, 자동 재번역을 의미하지 않는다.
    public func retranslate() {
        retranslateSelection()
    }

    /// 이전 이름을 사용하는 호출부가 새 계약을 우회하지 않도록 준비 동작으로
    /// 남겨 둔다. 실제 재번역은 반드시 `retranslateSelection()`으로 요청한다.
    public func retranslateForProviderChange(cacheContext: String? = nil) {
        prepareForProviderChange(cacheContext: cacheContext)
    }

    /// IME 조합 중에는 요청하지 않고, 조합이 끝난 뒤 디바운스를 시작한다.
    public func editSource(_ text: String, isComposing: Bool) {
        guard sourceText != text || self.isComposing != isComposing else { return }

        retryNeedsWholeDocument = false
        sourceText = text
        if IncrementalTranslationPlanner.isBlankSource(text) { sourceLanguageOverride = nil }
        self.isComposing = isComposing
        requiresRetranslation = false
        inputVersion &+= 1
        lastInputKind = .typing
        nextRequestAfter = clock.now.advanced(by: configuration.typingDebounce)
        if reuseEquivalentActiveRequest() { return }
        if reconcileInput() { return }

        guard validateSourceForScheduling() else { return }

        if isComposing {
            status = engineReady ? .waiting : .disconnected
        } else {
            scheduleAutomaticRequest()
        }
    }

    public func beginComposition() {
        guard !isComposing else { return }

        isComposing = true
        inputVersion &+= 1
        // The IME callback has no edited range yet, so conservatively cancel the
        // in-flight work, but keep completed source coverage on screen.
        latestResult = nil
        lastResultWasCached = false
        cancelActiveWork()

        guard validateSourceForScheduling() else { return }
        status = engineReady ? .waiting : .disconnected
    }

    public func updateComposition(_ text: String) {
        editSource(text, isComposing: true)
    }

    public func endComposition(_ text: String? = nil) {
        editSource(text ?? sourceText, isComposing: false)
    }

    /// 같은 원문을 다시 요청할 때(다시 시도, 연결 후 재개)는 마지막 복사의 구조를 그대로 쓴다.
    /// 마지막 복사는 그대로 두므로, 편집 뒤 다시 시도해도 보존된 복사 접두부의 구조를 다시 붙이고
    /// 복사 영역 안을 편집한 뒤 원문을 되돌리면 링크가 돌아온다.
    public func invokeCopiedText(_ text: String) {
        if let capturedSource, capturedSource.plain == text { invokeCopiedSource(capturedSource) } else { invokeCopied(CapturedSource(plain: text)) }
    }

    /// 두 번 복사는 즉시 처리한다. 연결 전에는 최신 입력 하나만 보관한다.
    /// 새 복사는 구조가 없어도 이전 복사의 링크를 항상 대체한다.
    public func invokeCopiedSource(_ source: CapturedSource) {
        capturedSource = source
        invokeCopied(source)
    }

    private func invokeCopied(_ source: CapturedSource) {
        let text = source.plain
        guard requiresRetranslation || !isSameActiveOrCompletedSnapshot(input: text, markup: source.markup) else { return }

        retryNeedsWholeDocument = false
        if sourceText != text { sourceLanguageOverride = nil }
        sourceText = text
        isComposing = false
        requiresRetranslation = false
        inputVersion &+= 1
        lastInputKind = .copied
        nextRequestAfter = nil
        if reuseEquivalentActiveRequest() { return }
        if reconcileInput() { return }

        guard validateSourceForExplicitInvocation() else { return }
        // Text already on screen needs neither a provider nor a connection.
        if restoreCompletedDocument() { return }
        guard engineReady else {
            pendingInput = (inputVersion, .copied)
            status = .disconnected
            return
        }

        startRequest()
    }

    private var hasCurrentResult: Bool {
        guard let latestResult else { return false }

        return latestResult.inputVersion == inputVersion
            && latestResult.input == sourceText
            && latestResult.direction == direction
            && !isComposing
    }

    private func isSameActiveOrCompletedSnapshot(input: String, markup: SourceMarkup?) -> Bool {
        if let activeRequest {
            return sourceText == input
                && activeRequestDirection == direction
                && (document?.basis.markup ?? activeRequest.markup) == markup
        }

        guard let latestResult else { return false }
        return latestResult.inputVersion == inputVersion
            && latestResult.input == input
            && latestResult.direction == direction
            && latestResult.markup == markup
    }

    private func baseStatus() -> TranslationStatus {
        engineReady ? .idle : .disconnected
    }

    private func validateSourceForScheduling() -> Bool {
        if sourceText.count > configuration.maximumInputLength {
            status = .error(.inputTooLong(limit: configuration.maximumInputLength))
            return false
        }

        if IncrementalTranslationPlanner.isBlankSource(sourceText) {
            status = baseStatus()
            return false
        }

        return true
    }

    private func validateSourceForExplicitInvocation() -> Bool {
        if IncrementalTranslationPlanner.isBlankSource(sourceText) {
            status = .error(.emptyInput)
            return false
        }

        if sourceText.count > configuration.maximumInputLength {
            status = .error(.inputTooLong(limit: configuration.maximumInputLength))
            return false
        }

        return true
    }

    private enum DisplayContinuity { case automatic, keep, reset }

    /// `.automatic` keeps the shown translation readable when the new source
    /// still continues what the reader was looking at, and starts a fresh
    /// surface otherwise.
    private func invalidateResultAndWork(_ continuity: DisplayContinuity = .automatic) {
        let shown = display
        let shownSource = supersededSource ?? document?.input ?? activeToken?.snapshot
        let blank = IncrementalTranslationPlanner.isBlankSource(sourceText)
        let keep = switch continuity {
        case .keep: !blank
        case .reset: false
        // Dashes left of a source that started with a boundary still share its first bytes, but nothing is shown for them.
        case .automatic: !blank && (shownSource.map { Self.continues($0, as: sourceText, copied: lastInputKind == .copied) } ?? false)
        }
        // Only a completed translation is kept; an unfinished draft is not.
        if keep, superseded == nil, let rendered = document?.rendered, !rendered.text.isEmpty {
            superseded = rendered.text
            supersededBreaks = rendered.unitBreaks
            supersededSource = document?.input
            // Read the kept translation as its own source and structure did, not the edited source.
            supersededInline = document.map { InlineOptions(source: $0.input, markup: $0.basis.markup) } ?? shown.inline
        } else if !keep {
            if shown.text?.isEmpty == false { displayIdentity = UUID() }
            releaseSuperseded()
        }
        if !keep { lastLanguages = nil }

        lastResultWasCached = false
        latestResult = nil
        cancelActiveWork()
        document = nil
        documentGeneration = UUID()
        bypassCache = false
    }

    /// Edits keep the start or the end of the text the reader was looking at.
    /// A newly copied selection must also keep most of it and may not merely
    /// share the first or last few characters of a word ("Yes" → "Yesterday")
    /// or a signature.
    private static func continues(_ shown: String, as source: String, copied: Bool) -> Bool {
        let required = min(24, shown.utf8.count, source.utf8.count)
        guard required > 0, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let prefix = zip(shown.utf8, source.utf8).prefix { $0 == $1 }.count
        let suffix = zip(shown.utf8.reversed(), source.utf8.reversed()).prefix { $0 == $1 }.count
        guard prefix >= required || suffix >= required else { return false }
        guard copied else { return true }
        let shownLength = shown.utf8.count
        guard 2 * min(shownLength, prefix + suffix) >= shownLength else { return false }
        if prefix == shownLength, continuesWord(source.utf8.dropFirst(prefix).first) { return false }
        if suffix == shownLength, continuesWord(source.utf8.dropLast(suffix).last) { return false }
        return true
    }

    private static func continuesWord(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        // Any byte of a multi-byte scalar, or an ASCII letter or digit, belongs to a word.
        return byte >= 0x80 || (byte >= 0x30 && byte <= 0x39) || ((byte | 0x20) >= 0x61 && (byte | 0x20) <= 0x7A)
    }

    private func releaseSuperseded() {
        superseded = nil
        supersededSource = nil
        supersededBreaks = []
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        TranslationDocument.contentEnd(of: text).map { String(text[..<$0]) } ?? ""
    }

    private func markProviderChangePrepared() {
        cancelActiveWork()
        lastResultWasCached = false
        requiresRetranslation = !IncrementalTranslationPlanner.isBlankSource(sourceText)
        status = hasCurrentResult ? .success : baseStatus()
    }

    private func clearStreamingText() {
        streamingTask?.cancel()
        streamingTask = nil
        pendingStreamingText = nil
        streamingText = nil
    }

    /// Cumulative snapshots are coalesced to avoid relayout on every token.
    /// The request identity and document generation also reject late callbacks.
    /// A snapshot shows with Han already read as Hangul; a first answer that echoes the source is
    /// abandoned at once and requested again.
    public func receivePartialText(_ text: String, for request: TranslationRequest) {
        guard accepts(request), !text.isEmpty,
              text.utf8.count <= configuration.maximumResultBytes,
              let outcome = activeCheck?.partial(text) else { return }
        guard case .show(let shown) = outcome else {
            if let review = activeCheck?.review(text) { retryAfterEcho(early: true, review: review) }
            return
        }
        guard !shown.isEmpty else { return }
        let previous = pendingStreamingText ?? streamingText ?? ""
        guard shown.utf8.starts(with: previous.utf8) else { return }
        pendingStreamingText = shown
        guard streamingTask == nil else { return }
        streamingTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            guard let self, self.accepts(request), !Task.isCancelled else { return }
            self.streamingText = self.pendingStreamingText
            self.pendingStreamingText = nil
            self.streamingTask = nil
        }
    }

    private func cancelActiveWork() {
        clearStreamingText()
        pendingInput = nil
        debounceTask?.cancel()
        debounceTask = nil

        requestTask?.cancel()
        requestTask = nil
        activeRequestID = nil
        activeRequest = nil
        activeRequestDirection = nil
        activeCacheKey = nil
        activeToken = nil
        activeCheck = nil
        isRetryingAfterEcho = false
    }

    /// The document must also have been translated with the structure the current copy gives its
    /// source. A new structured copy is translated whole; text entered after an unchanged copy may
    /// still use the existing prefix and its independently translated tail.
    private var documentMatchesSelection: Bool {
        guard let basis = document?.basis else { return false }
        return basis.cacheContext == cacheContext && basis.direction == direction
            && basis.provider == contextProvider && basis.model == contextModel
            && basis.markup == markup(for: basis.input)
            && (capturedSource?.plain != sourceText || activeMarkup == nil || basis.markup == activeMarkup)
    }

    /// Preserve only proven, exact source coverage. Returns true when the existing
    /// request still owns its unchanged prefix and no new request should be started.
    private func reconcileInput() -> Bool {
        latestResult = nil
        lastResultWasCached = false
        bypassCache = false
        guard documentMatchesSelection, var current = document else {
            if continuesFirstRequest() {
                status = .translating
                return true
            }
            invalidateResultAndWork()
            return false
        }

        // Prefer the existing prefix/truncation path when repeated paragraphs
        // could also look like removal of a leading unit.
        if !sourceText.utf8.starts(with: current.input.utf8),
           !current.input.utf8.starts(with: sourceText.utf8),
           let suffix = current.retainingSuffix(for: sourceText) {
            current = suffix
            document = suffix
            // Removing completed leading units does not change an active tail's
            // translation target. Rebase its coverage only when the exact tail is
            // still present after the retained completed units.
            if let request = activeRequest, let token = activeToken, token.incremental {
                let snapshot = suffix.input + token.separator + request.input
                if Self.extendsWithWhitespace(snapshot, to: sourceText)
                    || IncrementalTranslationPlanner.tail(after: snapshot, in: sourceText) != nil {
                    activeToken = SegmentRequestToken(generation: token.generation, snapshot: snapshot,
                                                      separator: token.separator, incremental: true)
                }
            }
        }

        let language = current.basis.sourceLanguage
        if current.input != sourceText {
            let accepts = { (tail: IncrementalTranslationPlanner.Tail) in
                tail.input.isEmpty || self.isComposing || self.tailMatchesLanguage(tail, language: language)
            }
            // Truncation is safe only at a known completed segment boundary.
            // A delimiter typed after that boundary belongs to the same coverage.
            if let covered = current.covering(sourceText) {
                current = covered
                document = covered
            } else if let tail = IncrementalTranslationPlanner.tail(after: current.input, in: sourceText), accepts(tail) {
                // The completed prefix remains valid, including while entering a delimiter.
            } else if activeTailOwnsSource(language: language, incrementalOnly: true) {
                // The pending tail is still exactly in the source; what follows it is planned once it completes (P0-2).
                // E.g. a block the fallback sent without a language check, with whitespace typed after it (3.8).
                status = .translating
                return true
            } else if let (head, _) = current.replanned(for: sourceText, accepting: accepts) {
                // A unit after an explicit boundary changed: keep the units above it (D4). A pending
                // request was planned against the dropped units or another trailing, so it goes too.
                // A rejected language is not replanned: the units stay dimmed in the fallback below (h).
                document = head
                cancelActiveWork()
                return false
            } else {
                invalidateResultAndWork()
                return false
            }
        }

        if activeTailOwnsSource(language: language, incrementalOnly: false) {
            status = .translating
            return true
        }
        cancelActiveWork()
        return false
    }

    /// The active request still translates an exact prefix of the source, followed by whitespace or a plannable tail.
    private func activeTailOwnsSource(language: TranslationLanguage, incrementalOnly: Bool) -> Bool {
        guard sourceText.count <= configuration.maximumInputLength, let token = activeToken,
              token.generation == documentGeneration, token.incremental || !incrementalOnly else { return false }
        if !isComposing, Self.extendsWithWhitespace(token.snapshot, to: sourceText) { return true }
        guard let tail = IncrementalTranslationPlanner.tail(after: token.snapshot, in: sourceText),
              !isComposing || !tail.input.isEmpty else { return false }
        return tail.input.isEmpty || isComposing || tailMatchesLanguage(tail, language: language)
    }

    /// While the first translation of a document is still pending, appending a
    /// paragraph or whitespace must not restart it. The new paragraph is requested
    /// after the first one completes.
    private func continuesFirstRequest() -> Bool {
        guard document == nil, sourceText.count <= configuration.maximumInputLength,
              let request = activeRequest, let token = activeToken, !token.incremental,
              token.generation == documentGeneration, activeRequestDirection == direction,
              request.cacheContext == cacheContext, request.provider == contextProvider,
              request.model == contextModel,
              // A new copy of the same words, with other links or none, replaces the structure being translated.
              request.markup == markup(for: request.input),
              capturedSource?.plain != sourceText || activeMarkup == nil || activeMarkup == request.markup else { return false }
        if !isComposing, Self.extendsWithWhitespace(token.snapshot, to: sourceText) { return true }
        guard let tail = IncrementalTranslationPlanner.tail(after: token.snapshot, in: sourceText),
              !isComposing || !tail.input.isEmpty else { return false }
        return tail.input.isEmpty || isComposing || tailMatchesLanguage(tail, language: request.sourceLanguage)
    }

    private func tailMatchesLanguage(_ tail: IncrementalTranslationPlanner.Tail, language: TranslationLanguage) -> Bool {
        if direction.fixedLanguages != nil { return true }
        // A block after an explicit boundary is independent and often code: only text that is
        // confidently the other supported language goes back to the whole source (D5).
        if tail.explicit { return !Self.isConfidently(otherThan: language, tail.input) }
        let paragraphs = tail.input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.allSatisfy {
            // Numbers and dates carry no language of their own.
            guard $0.contains(where: \.isLetter) else { return true }
            return Self.detectedLanguage(in: $0) == language
        }
    }

    /// Fenced code is left out; text without letters, or in another language, is not confident.
    private static func isConfidently(otherThan language: TranslationLanguage, _ text: String) -> Bool {
        let prose = IncrementalTranslationPlanner.proseOutsideFences(text)
        guard prose.contains(where: \.isLetter) else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(prose)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              let other = TranslationLanguage(rawValue: top.key.rawValue) else { return false }
        return other != language && top.value >= 0.8
    }

    private func restoreCompletedDocument() -> Bool {
        guard !isComposing, documentMatchesSelection,
              sourceText.count <= configuration.maximumInputLength,
              let covered = document?.covering(sourceText) else { return false }
        document = covered
        publishDocument(id: UUID())
        return true
    }

    /// A pending source may grow by whitespace without changing what is being translated.
    private static func extendsWithWhitespace(_ snapshot: String, to source: String) -> Bool {
        guard source.utf8.starts(with: snapshot.utf8) else { return false }
        return String(decoding: source.utf8.dropFirst(snapshot.utf8.count), as: UTF8.self)
            .allSatisfy(TranslationDocument.isBlank)
    }

    private func publishDocument(id: UUID) {
        guard let document, document.input == sourceText, !isComposing else { return }
        let basis = document.basis
        releaseSuperseded()
        lastLanguages = LanguagePair(source: basis.sourceLanguage, target: basis.targetLanguage)
        latestResult = TranslationResult(
            id: id, inputVersion: inputVersion, input: sourceText, direction: direction,
            sourceLanguage: basis.sourceLanguage, targetLanguage: basis.targetLanguage,
            text: document.text, provider: basis.provider, model: basis.model,
            modelLabel: basis.modelLabel, cacheContext: basis.cacheContext, markup: basis.markup
        )
        status = .success
    }

    private func scheduleAutomaticRequest() {
        if restoreCompletedDocument() { return }
        guard engineReady else {
            pendingInput = (inputVersion, .typing)
            status = .disconnected
            return
        }

        guard !isComposing else {
            status = .waiting
            return
        }

        guard let languages = resolveLanguages() else {
            status = .error(.unsupportedLanguage)
            return
        }

        if restoreCachedResult(source: languages.source, target: languages.target) { return }

        let scheduledVersion = inputVersion
        let scheduledDirection = direction
        let delay = nextRequestAfter.map { max(.zero, clock.now.duration(to: $0)) }
            ?? configuration.typingDebounce

        debounceTask?.cancel()
        status = .waiting
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.inputVersion == scheduledVersion,
                  self.direction == scheduledDirection,
                  !self.isComposing,
                  self.engineReady,
                  self.resolveLanguages() != nil else {
                return
            }

            self.debounceTask = nil
            self.startRequest(sourceLanguage: languages.source, targetLanguage: languages.target)
        }
    }

    private func resolveLanguages() -> (source: TranslationLanguage, target: TranslationLanguage)? {
        if let fixedLanguages = direction.fixedLanguages {
            return fixedLanguages
        }

        if documentMatchesSelection, let document { return (document.basis.sourceLanguage, document.basis.targetLanguage) }

        guard let source = sourceLanguageOverride ?? Self.detectedLanguage(in: sourceText) else { return nil }
        return (source, direction.target(for: source))
    }

    /// The recognizer can rank short English and table-heavy prose below another Latin language
    /// ("I smell fear" → Norwegian). Accept English only as a substantial alternative to an uncertain result
    /// in Latin letters. Do not constrain the recognizer to the supported languages: that would silently accept
    /// unrelated ones.
    static func detectedLanguage(in text: String) -> TranslationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let supported = TranslationLanguage(rawValue: dominant.rawValue)
        if supported == .english || supported?.writesLatinLetters == false { return supported }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 8)
        guard (hypotheses[dominant] ?? 1) < 0.8, (hypotheses[.english] ?? 0) >= 0.2 else { return supported }
        let prose = IncrementalTranslationPlanner.proseOutsideFences(text)
        let letters = prose.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty, letters.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) }) else { return supported }
        return .english
    }

    /// Supported languages the recognizer finds likely, most likely first: what the reader picks from when
    /// the source language is not decided (Привет мир ranks Kazakh first). A near-zero hypothesis is noise
    /// (Norwegian also lists German and Vietnamese), not a suggestion.
    static func likelyLanguages(in text: String, limit: Int = 3) -> [TranslationLanguage] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 12).filter { $0.value >= 0.05 }.sorted { $0.value > $1.value }
            .compactMap { TranslationLanguage(rawValue: $0.key.rawValue) }
            .prefix(limit).map { $0 }
    }

    private func startRequest(
        sourceLanguage: TranslationLanguage? = nil,
        targetLanguage: TranslationLanguage? = nil
    ) {
        if restoreCompletedDocument() { return }
        guard engineReady else {
            status = .disconnected
            return
        }

        guard !isComposing else {
            status = .waiting
            return
        }

        guard !IncrementalTranslationPlanner.isBlankSource(sourceText) else {
            status = .error(.emptyInput)
            return
        }

        guard sourceText.count <= configuration.maximumInputLength else {
            status = .error(.inputTooLong(limit: configuration.maximumInputLength))
            return
        }

        guard let languages = sourceLanguage.flatMap({ source in
            targetLanguage.map { target in (source: source, target: target) }
        }) ?? resolveLanguages() else {
            status = .error(.unsupportedLanguage)
            return
        }

        if restoreCachedResult(source: languages.source, target: languages.target) { return }

        let prefix = documentMatchesSelection ? document?.input : nil
        let tail = prefix.flatMap { IncrementalTranslationPlanner.tail(after: $0, in: sourceText) }
        if let tail, tail.input.isEmpty {
            // A delimiter alone is covered by the completed document above (I1).
            assertionFailure("A delimiter-only tail must be published by restoreCompletedDocument")
            status = .waiting
            return
        }
        let incremental = tail != nil
        // A request without copied structure is cut at its first explicit boundary; the next block
        // follows once it completes (D1). A structured copy goes whole.
        let unit = tail ?? firstRequestUnit(in: sourceText)
        if incremental, restoreCachedTail(input: unit.input, separator: unit.separator,
                                          source: languages.source, target: languages.target) { return }

        let request = TranslationRequest(
            inputVersion: inputVersion,
            input: unit.input,
            sourceLanguage: languages.source,
            targetLanguage: languages.target,
            provider: contextProvider,
            model: contextModel,
            modelLabel: contextModelLabel,
            cacheContext: cacheContext,
            // A cut first unit that is exactly the copy carries its structure, so the document matches the selection (I6).
            markup: incremental ? nil : markup(for: unit.input)
        )
        launch(request,
               // The source this request covers, without the delimiter or later blocks after it (I5).
               token: SegmentRequestToken(generation: documentGeneration,
                                          snapshot: (incremental ? prefix ?? "" : "") + unit.separator + unit.input,
                                          separator: unit.separator, incremental: incremental),
               cacheKey: cacheKey(input: request.input, markup: request.markup, source: request.sourceLanguage,
                                  target: request.targetLanguage, incremental: incremental))
    }

    /// Sends a request for the token's source coverage. The echo retry sends its second attempt here too.
    private func launch(_ request: TranslationRequest, token: SegmentRequestToken, cacheKey: CacheKey) {
        guard let translator else {
            status = .error(.engineUnavailable)
            return
        }
        let timeout = configuration.requestTimeout

        clearStreamingText()
        activeRequestID = request.id
        activeCacheKey = cacheKey
        activeRequest = request
        activeRequestDirection = direction
        activeToken = token
        // Checks read what the model saw, app-made markup included, never `request.input`.
        activeCheck = outputCheck(for: request)
        lastLanguages = LanguagePair(source: request.sourceLanguage, target: request.targetLanguage)
        lastResultWasCached = false
        status = .translating

        requestTask = Task { [weak self, translator] in
            do {
                let text = try await Self.execute(
                    request: request,
                    translator: translator,
                    timeout: timeout
                )

                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.complete(
                    request: request,
                    text: text
                )
            } catch {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.fail(request: request, error: error)
            }
        }
    }

    private func complete(request: TranslationRequest, text raw: String) {
        guard accepts(request), let current = activeRequest, let token = activeToken else { return }
        let check = activeCheck ?? outputCheck(for: current)
        finalizeOutput(review: check.review(raw), check: check, current: current, token: token)
    }

    /// Turns a model answer into the unit's result. Nothing reaches the screen as complete, the cache,
    /// copy or insert without passing these steps in this order.
    private func finalizeOutput(review: TranslationOutputCheck.Review, check: TranslationOutputCheck,
                                current: TranslationRequest, token: SegmentRequestToken) {
        // 1. `review` read leaked Han as Hangul and measured the echo, both on the raw answer.
        // 2. A first answer that repeats the source is requested once more.
        if review.echo && current.attempt == 1 && retriesSourceEcho {
            retryAfterEcho(early: false, review: review)
            return
        }
        // 3. Segments, cache, copy and insert all share balanced fences; partials stay raw.
        var text = TranslationMarkup.normalized(review.text, source: current.input)
        // 4. Empty, also when only fences are left.
        guard !TranslationMarkup(text).displayText.isEmpty else {
            fail(request: current, error: TranslationStoreError.emptyResult)
            return
        }
        // 5. A leading "번역:" label is cut off; the rest keeps its bytes.
        let trimmed = TranslationOutputLint.removingPreamble(from: text, source: current.modelInput)
        if let trimmed { text = trimmed }
        // 6. Code blocks the app fenced come back as the page wrote them, wherever the model put them; comments may stay translated.
        let guarded = CodeBlockGuard.restore(text, source: current.modelInput, blocks: current.markup?.blocks ?? [])
        text = guarded.text
        // 7-8. The size limit, on the segment that carries the remaining echo.
        let segment = TranslationSegment(id: current.id, separator: token.separator,
                                         source: current.input, text: text, unresolvedEcho: review.echo)
        var updatedDocument = document
        if token.incremental { updatedDocument?.segments.append(segment) }
        let resultBytes = token.incremental ? (updatedDocument?.text.utf8.count ?? Int.max) : text.utf8.count
        guard resultBytes <= configuration.maximumResultBytes else {
            fail(request: current, error: TranslationStoreError.resultTooLong)
            return
        }

        clearStreamingText()
        activeRequestID = nil
        activeRequest = nil
        activeRequestDirection = nil
        requestTask = nil
        activeCheck = nil
        isRetryingAfterEcho = false

        // 9. An answer that still echoes is never cached.
        let key = cacheKey(input: current.input, source: current.sourceLanguage,
                           target: current.targetLanguage, incremental: token.incremental)
        if token.incremental && !review.echo { saveCache(text, for: key) }
        lastResultWasCached = false
        activeCacheKey = nil
        activeToken = nil
        // 10. The report: rule names and counts only.
        report(current, incremental: token.incremental, outcome: review.echo ? .unresolvedEcho : .accepted, early: false,
               review: review, rules: check.rules(final: text, echo: review.echo), preambleRemoved: trimmed != nil, code: guarded.outcome)
        let basis = TranslationResult(
            id: current.id,
            inputVersion: current.inputVersion,
            input: current.input,
            direction: direction,
            sourceLanguage: current.sourceLanguage,
            targetLanguage: current.targetLanguage,
            text: text,
            provider: current.provider,
            model: current.model,
            modelLabel: current.modelLabel,
            cacheContext: current.cacheContext,
            markup: current.markup
        )
        if token.incremental { document = updatedDocument }
        else {
            document = TranslationDocument(generation: documentGeneration, basis: basis, segments: [segment])
            // A block-by-block replacement replaces the earlier translation once, when it covers the source.
            if document?.covering(sourceText) != nil { releaseSuperseded() }
        }
        finishSegment(id: current.id)
    }

    /// The first answer repeated the source. It is dropped and the same unit is requested once more;
    /// the new request id makes `accepts` reject every late callback of the first attempt.
    private func retryAfterEcho(early: Bool, review: TranslationOutputCheck.Review) {
        guard let request = activeRequest, let token = activeToken, let key = activeCacheKey,
              request.attempt == 1 else { return }
        // A streamed echo is cut short. A completed one is this very task, which ends on return.
        if early { requestTask?.cancel() }
        requestTask = nil
        clearStreamingText()
        report(request, incremental: token.incremental, outcome: .retryingAfterEcho, early: early, review: review,
               rules: [TranslationOutputLint.Rule.sourceEcho.rawValue])
        isRetryingAfterEcho = true
        // Only the cleared draft was on screen; the second answer starts a fresh surface.
        if document == nil && superseded == nil { displayIdentity = UUID() }
        launch(TranslationRequest(inputVersion: request.inputVersion, input: request.input,
                                  sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage,
                                  provider: request.provider, model: request.model, modelLabel: request.modelLabel,
                                  cacheContext: request.cacheContext, markup: request.markup, attempt: 2),
               token: token, cacheKey: key)
    }

    /// Only the unit's own model input protects Han, so a cached paragraph depends on its key alone.
    private func outputCheck(for request: TranslationRequest) -> TranslationOutputCheck {
        TranslationOutputCheck(source: request.modelInput, protecting: [request.modelInput],
                               sourceLanguage: request.sourceLanguage.rawValue, targetLanguage: request.targetLanguage.rawValue,
                               attempt: request.attempt, retriesEcho: retriesSourceEcho, repairsHanja: repairsHanja)
    }

    private func report(_ request: TranslationRequest, incremental: Bool, outcome: TranslationOutputReport.Outcome,
                        early: Bool, review: TranslationOutputCheck.Review, rules: [String], preambleRemoved: Bool = false,
                        code: CodeBlockGuard.Outcome = .init()) {
        onOutputReport?(TranslationOutputReport(
            requestID: request.id, provider: request.provider, attempt: request.attempt, incremental: incremental,
            outcome: outcome, early: early, rules: rules, coverage: review.coverage, candidates: review.candidates,
            hanjaReplaced: review.hanja.replaced, hanjaUnreadable: review.hanja.unreadable,
            hanjaKept: review.hanja.kept, hanjaInCode: review.hanja.inCode, preambleRemoved: preambleRemoved,
            codeKept: code.kept, codeRestored: code.restored, codeRefenced: code.refenced, codeInserted: code.inserted
        ))
    }

    private func accepts(_ request: TranslationRequest) -> Bool {
        guard activeRequestID == request.id, let current = activeRequest, let token = activeToken,
              token.generation == documentGeneration, activeRequestDirection == direction,
              current.cacheContext == cacheContext, current.provider == contextProvider,
              current.model == contextModel else { return false }
        return token.snapshot == sourceText
            || Self.extendsWithWhitespace(token.snapshot, to: sourceText)
            || IncrementalTranslationPlanner.tail(after: token.snapshot, in: sourceText) != nil
    }

    private func finishSegment(id: UUID) {
        guard let document else { return }
        // Cache each complete prefix with its alignment metadata. This does not
        // depend on the latest input version, which may already include a later tail.
        // A prefix that holds a unit still echoing the source is not cached.
        let key = cacheKey(input: document.input, markup: markup(for: document.input), source: document.basis.sourceLanguage,
                           target: document.basis.targetLanguage)
        if !document.hasUnresolvedEcho { saveCache(document.text, for: key, document: document) }
        if !isComposing, let covered = document.covering(sourceText) {
            // A whole retranslation bypasses the cache for every block until the source is covered.
            bypassCache = false
            retryNeedsWholeDocument = false
            // Whitespace typed while the unit was pending is part of the same coverage.
            self.document = covered
            publishDocument(id: id)
        }
        else if isComposing { status = .waiting }
        else if lastInputKind == .copied { startRequest() }
        else { scheduleAutomaticRequest() }
    }

    private func fail(request: TranslationRequest, error: Error) {
        guard accepts(request) else { return }

        clearStreamingText()
        activeRequestID = nil
        activeRequest = nil
        activeRequestDirection = nil
        requestTask = nil
        activeToken = nil
        activeCacheKey = nil
        activeCheck = nil
        isRetryingAfterEcho = false

        if let storeError = error as? TranslationStoreError {
            status = .error(storeError)
        } else if error is CancellationError {
            status = baseStatus()
        } else {
            status = .error(.provider(error.localizedDescription))
        }
    }

    public func isActiveRequest(_ request: TranslationRequest) -> Bool {
        accepts(request)
    }

    /// A structured source is keyed by its markup too (link numbers and app fences, never URLs): the same words with
    /// or without links or code blocks are different requests.
    private func cacheKey(input: String, markup: SourceMarkup? = nil, source: TranslationLanguage, target: TranslationLanguage,
                          incremental: Bool = false) -> CacheKey {
        CacheKey(context: cacheContext, direction: direction.rawValue,
                 source: source.rawValue, target: target.rawValue, input: Self.normalizedCacheInput(input),
                 markup: markup?.text, provider: contextProvider, model: contextModel,
                 mode: incremental ? "paragraph-v1" : markup == nil ? "document-v1" : "document-inline-v1")
    }

    private static func normalizedCacheInput(_ input: String) -> String {
        let text = input.replacingOccurrences(of: "\r\n", with: "\n")
        // 코드·목록·인용·들여쓰기는 공백이 데이터나 형식이므로 원문 그대로 비교한다.
        let structured = text.contains("\t")
            || text.range(of: #"[`"{}\[\]()=<>;+*/\\]"#, options: .regularExpression) != nil
            || text.range(of: #"'[^'\n]*'"#, options: .regularExpression) != nil
            || text.range(of: #"(?m)^(?: {4}|\s*[-*+] |\s*\d+[.)] |\s*[#>|])"#, options: .regularExpression) != nil
        if structured { return input }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
    }

    private func reuseEquivalentActiveRequest() -> Bool {
        guard !isComposing, sourceText.count <= configuration.maximumInputLength,
              let token = activeToken, !token.incremental,
              let request = activeRequest, let activeCacheKey,
              activeRequestDirection == direction else { return false }
        // Compare the unit a new request would send: blocks after a boundary wait for this one (D1).
        let unit = firstRequestUnit(in: sourceText)
        let unitMarkup = markup(for: unit.input)
        guard !unit.input.isEmpty, cacheKey(input: unit.input, markup: unitMarkup, source: request.sourceLanguage,
                                             target: request.targetLanguage) == activeCacheKey else { return false }
        activeRequest = TranslationRequest(
            id: request.id,
            inputVersion: inputVersion,
            input: unit.input,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            provider: request.provider,
            model: request.model,
            modelLabel: request.modelLabel,
            cacheContext: request.cacheContext,
            // The model input is the same; only the app's link table may be new.
            markup: unitMarkup,
            attempt: request.attempt
        )
        activeToken = SegmentRequestToken(generation: token.generation, snapshot: unit.separator + unit.input,
                                          separator: unit.separator, incremental: false)
        latestResult = nil
        lastResultWasCached = false
        status = .translating
        return true
    }

    private func restoreCachedResult(source: TranslationLanguage, target: TranslationLanguage) -> Bool {
        guard !bypassCache else { return false }
        if let document, Self.normalizedCacheInput(document.input) != Self.normalizedCacheInput(sourceText) {
            // A previously cached whole translation must not overwrite a pinned
            // prefix (e.g. one the user has explicitly retranslated since then).
            return false
        }
        let markup = activeMarkup
        let key = cacheKey(input: sourceText, markup: markup, source: source, target: target)
        guard let entry = cachedEntry(for: key) else { return false }
        latestResult = TranslationResult(
            id: UUID(),
            inputVersion: inputVersion,
            input: sourceText,
            direction: direction,
            sourceLanguage: source,
            targetLanguage: target,
            text: entry.text,
            provider: contextProvider,
            model: contextModel,
            modelLabel: contextModelLabel,
            cacheContext: cacheContext,
            // The key holds link numbers only; the links resolve to what was just copied.
            markup: markup
        )
        if let stored = entry.document?.covering(sourceText) {
            document = TranslationDocument(generation: documentGeneration, basis: latestResult!, segments: stored.segments)
        } else {
            document = TranslationDocument(generation: documentGeneration, basis: latestResult!, segments: [
                TranslationSegment(id: latestResult!.id, separator: "", source: sourceText, text: entry.text)
            ])
        }
        releaseSuperseded()
        lastLanguages = LanguagePair(source: source, target: target)
        lastResultWasCached = true
        status = .success
        return true
    }

    private func restoreCachedTail(input: String, separator: String,
                                   source: TranslationLanguage, target: TranslationLanguage) -> Bool {
        guard !bypassCache,
              var updatedDocument = document,
              let entry = cachedEntry(for: cacheKey(input: input, source: source, target: target, incremental: true)) else { return false }
        let id = UUID()
        updatedDocument.segments.append(TranslationSegment(id: id, separator: separator, source: input, text: entry.text))
        guard updatedDocument.text.utf8.count <= configuration.maximumResultBytes else { return false }
        document = updatedDocument
        lastResultWasCached = true
        finishSegment(id: id)
        return true
    }

    private func cachedEntry(for key: CacheKey) -> CacheEntry? {
        purgeExpiredCache(now: clock.now)
        guard let entry = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return entry
    }

    private func saveCache(_ text: String, for key: CacheKey, document: TranslationDocument? = nil) {
        guard configuration.cacheCapacity > 0, configuration.cacheLifetime > .zero else { return }
        let now = clock.now
        purgeExpiredCache(now: now)
        // Count retained payloads conservatively: the source key, the result, the document's
        // segments and its basis's source and translation. Strings that share storage are
        // counted again, which only makes the byte limit stricter; short metadata is not counted.
        let markupBytes: Int = key.markup?.utf8.count ?? 0
        let byteCount = key.input.utf8.count + markupBytes + text.utf8.count
            + (document.map { $0.input.utf8.count + $0.text.utf8.count + $0.basis.input.utf8.count + $0.basis.text.utf8.count } ?? 0)
        guard byteCount <= configuration.maximumCacheBytes else { return }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        let replaced = cache.updateValue(CacheEntry(text: text, created: now, document: document, byteCount: byteCount), forKey: key)
        cacheBytes += byteCount - (replaced?.byteCount ?? 0)
        while cacheOrder.count > configuration.cacheCapacity || cacheBytes > configuration.maximumCacheBytes {
            guard !cacheOrder.isEmpty else {
                // Unreachable while cacheBytes matches the entries; recover instead of trapping.
                assertionFailure("The cache byte total drifted from its entries")
                cacheBytes = 0
                break
            }
            cacheBytes -= cache.removeValue(forKey: cacheOrder.removeFirst())?.byteCount ?? 0
        }
    }

    /// Lifetime counts from creation, not from the last hit, so an expired entry can
    /// sit anywhere in the LRU order. Dropping it first keeps it from displacing live ones.
    private func purgeExpiredCache(now: ContinuousClock.Instant) {
        let expired = cache.filter { $0.value.created.duration(to: now) >= configuration.cacheLifetime }
        guard !expired.isEmpty else { return }
        for (key, entry) in expired {
            cache.removeValue(forKey: key)
            cacheBytes -= entry.byteCount
        }
        cacheOrder.removeAll { expired[$0] != nil }
    }

    private static func execute(
        request: TranslationRequest,
        translator: @escaping Translator,
        timeout: Duration?
    ) async throws -> String {
        guard let timeout else {
            return try await translator(request)
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await translator(request)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TranslationStoreError.timedOut
            }

            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

#if TRANSLATION_STORE_STANDALONE
extension TranslationStore {
    var testCacheEntryCount: Int { cache.count }

    /// The byte total matches the entries, the LRU order lists each key once,
    /// and both limits hold.
    var testCacheIsConsistent: Bool {
        let total = cache.values.reduce(0) { $0 + $1.byteCount }
        let sameKeys = cacheOrder.count == cache.count && Set(cacheOrder) == Set(cache.keys)
        return sameKeys && cacheBytes == total
            && cache.count <= configuration.cacheCapacity && cacheBytes <= configuration.maximumCacheBytes
    }
}
#endif
