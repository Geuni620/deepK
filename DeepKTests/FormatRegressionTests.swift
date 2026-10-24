import Foundation
import NaturalLanguage

// Offline replay of captured synthetic responses plus independently specified failure cases.
// This target contains no Codex/Claude clients and cannot make subscription requests.
private struct FormatInput: Decodable, Sendable {
    let id: String
    let label: String
    let source: String
    let target: String
    let text: String
    let html: String?
    let literals: [String]
    let codeLines: [String]
    let minLinks: Int
    let minChips: Int
    let minBlocks: Int
    let expectedURLs: [String]
    let numericTokens: [String]?
    let tableValues: [TableValue]?
    var capture: CapturedSource { RichSourceImporter.copiedSource(plain: text, html: html) }
}

private struct TableValue: Decodable, Sendable {
    let identifier: String
    let column: Int
    let value: String
}

private struct RecordedResponse: Decodable {
    let phase: String
    let input: String
    let modelInput: String
    let rawOutput: String
    let links: Int
    let chips: Int
}

private struct ListInput: Decodable {
    let id: String
    let label: String
    let plain: String
    let html: String
    let items: [String]
    let kind: String
    let numbers: [Int]
    let depths: [Int]
}

private struct ListResponse: Decodable {
    let id: String
    let text: String
    let items: [String]
}

private struct KnownFailure: Codable {
    let id: String
    let check: String
    let reference: String
    let reason: String
}

private struct Inputs: Decodable { let schemaVersion: Int; let cases: [FormatInput] }
private struct Responses: Decodable {
    let schemaVersion: Int
    let sourceRevision: String
    let provider: String
    let model: String
    let requests: [RecordedResponse]
}
private struct Lists: Decodable { let schemaVersion: Int; let cases: [ListInput] }
private struct ListResponses: Decodable { let schemaVersion: Int; let cases: [ListResponse] }
private struct KnownFailures: Decodable { let schemaVersion: Int; let failures: [KnownFailure] }

private struct CheckFailure: Error, CustomStringConvertible {
    let code: String
    let expected: String
    let actual: String
    var description: String { "\(code): expected \(expected); actual \(actual)" }
}

private func check(_ passed: Bool, _ code: String, _ expected: String, _ actual: String) throws {
    if !passed { throw CheckFailure(code: code, expected: expected, actual: actual) }
}

/// Collect independent assertions before classifying a scenario. An expected failure must not
/// prevent the tail, result structure, item order or export checks from running.
private struct CheckFailures: Error, CustomStringConvertible {
    let failures: [CheckFailure]
    var description: String { failures.map(\.description).joined(separator: " | ") }
}

private struct Checks {
    private(set) var failures: [CheckFailure] = []

    mutating func require(_ passed: Bool, _ code: String, _ expected: String, _ actual: String) {
        if !passed { failures.append(CheckFailure(code: code, expected: expected, actual: actual)) }
    }

    mutating func append(_ other: Checks) { failures += other.failures }

    func finish() throws {
        if !failures.isEmpty { throw CheckFailures(failures: failures) }
    }
}

private actor RequestLog {
    private var requests: [TranslationRequest] = []
    func record(_ request: TranslationRequest) { requests.append(request) }
    func snapshot() -> [TranslationRequest] { requests }
}

@MainActor
private final class ReplayBox {
    weak var store: TranslationStore?
    var visibleLinkMarker = false
}

@MainActor
private struct Scenario {
    let id: String
    let label: String
    let scope: String
    let run: @MainActor () async throws -> Void

    init(id: String, label: String, scope: String = "desired_behavior", run: @escaping @MainActor () async throws -> Void) {
        self.id = id
        self.label = label
        self.scope = scope
        self.run = run
    }
}

private enum Outcome: String, Codable {
    case pass, knownFailure = "known_failure", failure, unexpectedPass = "unexpected_pass"
    var label: String {
        switch self {
        case .pass: "PASS"
        case .knownFailure: "XFAIL"
        case .failure: "FAIL"
        case .unexpectedPass: "XPASS"
        }
    }
}

private func classify(failures: [CheckFailure], expected: KnownFailure?) -> Outcome {
    guard !failures.isEmpty else { return expected == nil ? .pass : .unexpectedPass }
    return expected.map { known in failures.allSatisfy { $0.code == known.check } } == true ? .knownFailure : .failure
}

private struct ScenarioResult: Codable {
    let id: String
    let label: String
    let scope: String
    let outcome: Outcome
    let detail: String?
    let knownFailure: KnownFailure?
}

private struct Report: Encodable {
    let schemaVersion = 1
    let replaySourceRevision: String
    let replayProvider: String
    let replayModel: String
    let strict: Bool
    let elapsedMilliseconds: Int
    let liveProviderRequests = 0
    let results: [ScenarioResult]
    var passed: Int { results.filter { $0.outcome == .pass }.count }
    var knownFailures: Int { results.filter { $0.outcome == .knownFailure }.count }
    var failures: Int { results.filter { $0.outcome == .failure }.count }
    var unexpectedPasses: Int { results.filter { $0.outcome == .unexpectedPass }.count }
    var exitCode: Int32 { failures > 0 || unexpectedPasses > 0 || (strict && knownFailures > 0) ? 1 : 0 }
}

@MainActor
private struct FixtureSuite {
    let inputs: Inputs
    let responses: Responses
    let lists: Lists
    let listResponses: ListResponses

    private func input(_ id: String) throws -> FormatInput {
        guard let input = inputs.cases.first(where: { $0.id == id }) else {
            throw CheckFailure(code: "fixture.input", expected: id, actual: "missing")
        }
        return input
    }

    private func initialResponse(_ fixture: FormatInput) throws -> RecordedResponse {
        let matches = responses.requests.filter { $0.phase == fixture.id + ".initial" }
        try check(matches.count == 1, "fixture.response", "one response for \(fixture.id)", "\(matches.count)")
        return matches[0]
    }

    private func store(translator: @escaping TranslationStore.Translator) -> TranslationStore {
        TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: .seconds(3)),
                         engineReady: true, translator: translator)
    }

    private func complete(_ store: TranslationStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline {
            if store.status == .success { return }
            if case .error = store.status { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(false, "translation.completion", "success", String(describing: store.status))
    }

    private func rendered(_ store: TranslationStore) -> TranslationMarkup {
        TranslationMarkup(store.resultText ?? "", streaming: false, inline: store.display.inline)
    }

    private func structure(_ store: TranslationStore, links: Int, chips: Int, blocks: Int) -> Checks {
        var checks = Checks()
        let result = rendered(store)
        let linkCount = result.spans.filter { if case .link = $0.kind { return true }; return false }.count
        let chipCount = result.spans.filter { if case .code = $0.kind { return true }; return false }.count
        let blockCount = result.blocks.filter { $0.fence != nil }.count
        checks.require(linkCount >= links, "result.links", "at least \(links)", "\(linkCount)")
        checks.require(chipCount >= chips, "result.chips", "at least \(chips)", "\(chipCount)")
        checks.require(blockCount >= blocks, "result.blocks", "at least \(blocks)", "\(blockCount)")
        checks.require(!result.displayText.contains("<a1>") && !result.displayText.contains("</a1>"),
                       "result.internalMarkers", "no visible link protocol tags", result.displayText)
        return checks
    }

    private func lines(_ text: String, matching pattern: String) -> [String] {
        text.components(separatedBy: "\n").filter { $0.range(of: pattern, options: .regularExpression) != nil }
    }

    private func numericTokens(in text: String) -> [String] {
        // A version such as v2.4.1 is one token; it cannot stand in for a missing retry count 2.
        let pattern = try! NSRegularExpression(pattern: #"[0-9]+(?:\.[0-9]+)*"#)
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private func content(_ fixture: FormatInput, output: String) -> Checks {
        var checks = Checks()
        for token in fixture.literals {
            checks.require(output.contains(token), "replay.literal", token, output)
        }
        for line in fixture.codeLines {
            checks.require(output.contains(line), "replay.code", line, output)
        }
        if let expected = fixture.numericTokens {
            let actual = numericTokens(in: output)
            checks.require(actual == expected, "replay.numbers", "\(expected)", "\(actual)")
        }
        if fixture.id == "markdown-list" {
            for (pattern, count) in [("^[-*•] ", 3), ("^[0-9]+\\. ", 2), ("^# ", 1), ("^> ", 1)] {
                let actual = lines(output, matching: pattern).count
                checks.require(actual == count, "replay.listShape", "\(count) lines matching \(pattern)", "\(actual)")
            }
        }
        if fixture.id == "markdown-table" {
            let rows = lines(output, matching: "^\\|")
            checks.require(rows.count == 4 && rows.allSatisfy { $0.filter { $0 == "|" }.count == 4 },
                           "replay.tableShape", "four rows with three columns", "\(rows)")
        }
        if let values = fixture.tableValues {
            let rows = lines(output, matching: "^\\|").map { line in
                line.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            }
            for value in values {
                let matching = rows.filter { $0.contains(where: { $0.contains(value.identifier) }) }
                let actual = matching.first.flatMap { $0.indices.contains(value.column) ? $0[value.column] : nil }
                checks.require(matching.count == 1 && actual == value.value, "replay.tableValue",
                               "\(value.identifier) column \(value.column) = \(value.value)", "\(matching)")
            }
        }
        return checks
    }

    private func replay(_ record: RecordedResponse, capture: CapturedSource, fixture: FormatInput? = nil) async throws {
        let log = RequestLog(), box = ReplayBox()
        let sut = store { request in
            await log.record(request)
            let characters = Array(record.rawOutput)
            for end in Set([1, characters.count / 3, characters.count * 2 / 3, characters.count]).sorted() where end > 0 {
                let snapshot = String(characters.prefix(end))
                await MainActor.run {
                    guard let sut = box.store else { return }
                    sut.receivePartialText(snapshot, for: request)
                    let shown = TranslationMarkup(sut.display.text ?? "", streaming: true, inline: sut.display.inline).displayText
                    if shown.contains("<a1>") || shown.contains("</a1>") { box.visibleLinkMarker = true }
                }
            }
            return record.rawOutput
        }
        box.store = sut
        sut.setDirection(fixture?.source == "ko" ? .koreanToEnglish : .englishToKorean)
        sut.invokeCopiedSource(capture)
        try await complete(sut)
        let requests = await log.snapshot()
        try check(requests.count == 1, "replay.requestCount", "one request", "\(requests.count)")
        let request = requests[0]
        try check(request.input == record.input && request.modelInput == record.modelInput,
                  "replay.payload", record.modelInput, request.modelInput)
        var checks = Checks()
        if let fixture {
            checks.require(request.sourceLanguage.rawValue == fixture.source && request.targetLanguage.rawValue == fixture.target,
                           "replay.direction", "\(fixture.source) -> \(fixture.target)",
                           "\(request.sourceLanguage.rawValue) -> \(request.targetLanguage.rawValue)")
        }
        checks.require(!box.visibleLinkMarker, "replay.partialMarkers", "no visible protocol tags during partial replay", "visible tag")
        let output = sut.resultText ?? ""
        checks.require(output == TranslationMarkup.normalized(record.rawOutput, source: record.input),
                       "replay.archivedOutput", "the archived output after fence normalization", output)
        if let fixture {
            checks.append(content(fixture, output: output))
            checks.append(structure(sut, links: fixture.minLinks, chips: fixture.minChips, blocks: fixture.minBlocks))
            let urls = sut.result?.markup?.links.map { $0.url.absoluteString } ?? []
            checks.require(urls == fixture.expectedURLs, "replay.urls", "\(fixture.expectedURLs)", "\(urls)")
            if fixture.id == "math" || fixture.id == "error-log" {
                checks.require(!rendered(sut).containsCode, "replay.prose", "formula/log remains prose", output)
            }
        } else {
            checks.append(structure(sut, links: record.links, chips: record.chips, blocks: 0))
            let actualLinks = rendered(sut).spans.filter { if case .link = $0.kind { return true }; return false }.count
            checks.require(actualLinks == record.links, "replay.archivedLinks", "\(record.links) archived links", "\(actualLinks)")
        }
        try checks.finish()
    }

    func replay(_ fixture: FormatInput) async throws {
        try await replay(initialResponse(fixture), capture: fixture.capture, fixture: fixture)
    }

    func archived(_ record: RecordedResponse) async throws {
        // These are historical provider responses, including the pre-fix replies that had no
        // links after an append. Preserve that evidence without using it as a desired contract.
        let rich = try input("html-links-code").capture
        let capture = record.modelInput == record.input ? CapturedSource(plain: record.input) : rich
        try await replay(record, capture: capture)
    }

    func numericOracle() throws {
        let fixture = try input("plain-numbers"), record = try initialResponse(fixture)
        let changed = record.rawOutput.replacingOccurrences(of: "최대 2회", with: "최대 3회")
        try check(changed != record.rawOutput && fixture.literals.allSatisfy { changed.contains($0) },
                  "oracle.numericMutation", "a changed count that the former substring checks missed", changed)
        try check(content(fixture, output: changed).failures.contains { $0.code == "replay.numbers" },
                  "oracle.numericRejected", "wrong independent retry count rejected", changed)
    }

    func tableOracle() throws {
        let fixture = try input("markdown-table"), record = try initialResponse(fixture)
        let changed = record.rawOutput.replacingOccurrences(of: "| 120 |", with: "| __swap__ |")
            .replacingOccurrences(of: "| 45 |", with: "| 120 |")
            .replacingOccurrences(of: "| __swap__ |", with: "| 45 |")
        try check(changed != record.rawOutput && fixture.literals.allSatisfy { changed.contains($0) },
                  "oracle.tableMutation", "swapped values that the former presence checks missed", changed)
        try check(content(fixture, output: changed).failures.filter { $0.code == "replay.tableValue" }.count == 2,
                  "oracle.tableRejected", "both mismatched row values rejected", changed)
    }

    func knownFailurePolicy() throws {
        let known = KnownFailure(id: "test", check: "known", reference: "runner self-check", reason: "expected")
        let expected = CheckFailure(code: "known", expected: "preserved", actual: "missing")
        let newFailure = CheckFailure(code: "new-tail-loss", expected: "tail", actual: "missing")
        var checks = Checks()
        checks.require(false, expected.code, expected.expected, expected.actual)
        checks.require(false, newFailure.code, newFailure.expected, newFailure.actual)
        try check(classify(failures: checks.failures, expected: known) == .failure,
                  "runner.independentFailure", "a new failure after a known failure fails the scenario", "incorrectly quarantined")
        try check(classify(failures: [expected], expected: known) == .knownFailure,
                  "runner.expectedFailure", "only the known check is XFAIL", "incorrect classification")
        try check(classify(failures: [], expected: known) == .unexpectedPass,
                  "runner.unexpectedPass", "resolved known failure is XPASS", "incorrect classification")
    }

    func automaticDirection(_ id: String) async throws {
        let fixture = try input(id), log = RequestLog()
        let sut = store { request in
            await log.record(request)
            return "공포의 냄새가 납니다. 두 행과 값을 유지하세요."
        }
        sut.invokeCopiedSource(fixture.capture)
        if sut.status != .error(.unsupportedLanguage) { try await complete(sut) }
        let requests = await log.snapshot()
        let detector = NLLanguageRecognizer()
        detector.processString(fixture.text)
        let correct = requests.count == 1 && requests[0].sourceLanguage == .english && requests[0].targetLanguage == .korean
        try check(correct, "language.direction", "English -> Korean reaches the translator",
                  "requests=\(requests.count), status=\(sut.status), detected=\(detector.dominantLanguage?.rawValue ?? "nil")")
    }

    func document(explicit: Bool, whole: Bool) async throws {
        let fixture = try input("html-links-code"), record = try initialResponse(fixture), log = RequestLog()
        let tail = "Please bring 12 printed copies.", translatedTail = "인쇄본 12부를 가져와 주세요."
        let sut = store { request in
            await log.record(request)
            if request.input == tail { return translatedTail }
            let first = request.usesInlineMarkup ? record.rawOutput : "cancel()을 호출하기 전에 문서를 읽으세요."
            return first + (request.input.contains(tail) ? "\n\n" + translatedTail : "")
        }
        sut.setDirection(.englishToKorean)
        sut.invokeCopiedSource(fixture.capture)
        try await complete(sut)
        try structure(sut, links: 1, chips: 1, blocks: 0).finish()
        let prefix = sut.resultText ?? "", seedCount = await log.snapshot().count
        let combined = fixture.capture.plain + (explicit ? "\n\n---\n\n" : "\n\n") + tail
        sut.editSource(combined, isComposing: false)
        try await complete(sut)
        var start = seedCount
        if whole {
            start = await log.snapshot().count
            sut.retranslateWholeDocument()
            try await complete(sut)
        }
        let requests = Array((await log.snapshot()).dropFirst(start))
        var checks = Checks()
        checks.require(!requests.isEmpty, "structure.requests", "a new translation request", "none")
        for request in requests where request.input.contains(fixture.capture.plain) {
            let hasStructure = request.markup?.links.map { $0.url.absoluteString } == fixture.expectedURLs
                && request.markup?.code.contains("cancel()") == true
            checks.require(hasStructure, "structure.forwarding", "preserved link URL and cancel() code metadata",
                           "links=\(request.markup?.links.count ?? 0), chips=\(request.markup?.code.count ?? 0)")
        }
        checks.append(structure(sut, links: 1, chips: 1, blocks: 0))
        let output = sut.resultText ?? ""
        checks.require(output.contains(translatedTail), "structure.tail", translatedTail, output)
        checks.require(sut.resultInsertionText?.contains(translatedTail) == true,
                       "structure.insertionTail", translatedTail, sut.resultInsertionText ?? "nil")
        if explicit {
            let expected = whole ? [fixture.capture.plain, tail] : [tail]
            checks.require(requests.map(\.input) == expected, "structure.boundaryPayload", "\(expected)", "\(requests.map(\.input))")
            if !whole { checks.require(output.hasPrefix(prefix), "structure.prefix", prefix, output) }
            checks.require(sut.display.unitBreaks.count == 1 && !output.components(separatedBy: "\n").contains("---"),
                           "structure.boundaryDisplay", "one display break without literal ---", "\(sut.display.unitBreaks)")
        }
        try checks.finish()
    }

    private func listShape(_ source: String, fixture: ListInput, items: [String], stage: String) throws -> Checks {
        var checks = Checks()
        let pattern = #"^([ \t]*)(?:([-+*•])[ \t]+|([0-9]+)[.)][ \t]+)(.*)$"#
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        let ns = source as NSString
        let rows = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        func value(_ match: NSTextCheckingResult, _ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
        if fixture.kind == "ordered" {
            let numbers = rows.compactMap { Int(value($0, 3)) }
            checks.require(numbers == fixture.numbers, "list.numbering", "\(stage): \(fixture.numbers)", "\(numbers); source=\(source)")
        } else if fixture.kind == "nested" {
            let indents = rows.map { value($0, 1).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
            checks.require(indents == fixture.depths.map { $0 * 2 }, "list.depth",
                           "\(stage): two spaces for each depth \(fixture.depths)", "\(indents); source=\(source)")
        } else {
            checks.require(rows.count == items.count && rows.allSatisfy { !value($0, 2).isEmpty },
                           "list.markers", "\(stage): \(items.count) bullet items", "\(rows.count); source=\(source)")
        }
        let bodies = rows.map { value($0, 4).replacingOccurrences(of: "**", with: "") }
        checks.require(bodies == items, "list.itemOrder", "\(stage): \(items)", "\(bodies)")
        return checks
    }

    func list(_ fixture: ListInput) throws {
        let capture = RichSourceImporter.copiedSource(plain: fixture.plain, html: fixture.html)
        var checks = try listShape(capture.plain, fixture: fixture, items: fixture.items, stage: "source pane")
        checks.append(try listShape(capture.markup?.text ?? capture.plain, fixture: fixture, items: fixture.items, stage: "model source"))
        try checks.finish()
    }

    private func listResult(_ store: TranslationStore, fixture: ListInput, response: ListResponse, stage: String) throws -> Checks {
        var checks = Checks()
        let result = rendered(store)
        let all = NSRange(location: 0, length: result.displayText.utf16.count)
        let copies = store.resultCopy
        let texts = [
            ("stored result", store.resultText),
            ("display", Optional(result.displayText)),
            ("insertion", store.resultInsertionText),
            ("copy plain", copies?.plain),
            ("copy markdown", copies?.markdown),
            ("selection markdown", Optional(result.markdown(in: all))),
            ("selection plain", Optional(result.plainText(in: all, fences: store.resultFenceStyle)))
        ]
        for (name, text) in texts {
            checks.require(text != nil, "list.resultAvailable", "\(stage): \(name)", "missing")
            checks.append(try listShape(text ?? "", fixture: fixture, items: response.items, stage: "\(stage): \(name)"))
        }
        checks.require(store.canCopy && store.canInsert, "list.currentResult", "\(stage): a current copyable and insertable result", "copy=\(store.canCopy), insert=\(store.canInsert)")
        return checks
    }

    func listLifecycle(_ fixture: ListInput) async throws {
        guard let response = listResponses.cases.first(where: { $0.id == fixture.id }) else {
            throw CheckFailure(code: "fixture.listResponse", expected: fixture.id, actual: "missing")
        }
        let capture = RichSourceImporter.copiedSource(plain: fixture.plain, html: fixture.html)
        let log = RequestLog()
        let tail = "Please bring 12 printed copies.", translatedTail = "인쇄본 12부를 가져와 주세요."
        let sut = store { request in
            await log.record(request)
            if request.input == tail { return translatedTail }
            return response.text + (request.input.contains(tail) ? "\n\n" + translatedTail : "")
        }
        sut.setDirection(.englishToKorean)
        sut.invokeCopiedSource(capture)
        try await complete(sut)
        var checks = try listShape(sut.sourceText, fixture: fixture, items: fixture.items, stage: "source pane after invoke")
        checks.append(try listResult(sut, fixture: fixture, response: response, stage: "initial"))
        sut.editSource(capture.plain + "\n\n" + tail, isComposing: false)
        try await complete(sut)
        checks.append(try listResult(sut, fixture: fixture, response: response, stage: "append"))
        checks.require(sut.resultInsertionText?.contains(translatedTail) == true,
                       "list.appendTail", "appended paragraph survives insertion", sut.resultInsertionText ?? "nil")
        let beforeWhole = await log.snapshot().count
        sut.retranslateWholeDocument()
        try await complete(sut)
        checks.append(try listResult(sut, fixture: fixture, response: response, stage: "whole retranslation"))
        checks.require(sut.resultInsertionText?.contains(translatedTail) == true,
                       "list.retranslationTail", "appended paragraph survives whole retranslation", sut.resultInsertionText ?? "nil")
        let requests = await log.snapshot()
        checks.require(requests.count > beforeWhole && beforeWhole >= 2,
                       "list.requestLifecycle", "requests for initial, append and whole retranslation", "\(requests.count), before whole=\(beforeWhole)")
        for (index, request) in requests.enumerated() where request.input != tail {
            checks.append(try listShape(request.modelInput, fixture: fixture, items: fixture.items, stage: "request \(index)"))
        }
        try checks.finish()
    }

    func plainProseIsNotAList() throws {
        let source = "Describe the outcome: use ordinary language.\nAsk for a review: choose where to start."
        let capture = RichSourceImporter.copiedSource(plain: source, html: nil)
        try check(capture.plain == source && (capture.markup?.text ?? source) == source,
                  "list.plainProse", "unmarked prose unchanged", capture.markup?.text ?? capture.plain)
    }

    var scenarios: [Scenario] {
        var result = inputs.cases.map { fixture in
            Scenario(id: "replay/" + fixture.id, label: fixture.label, scope: "recorded_response") { try await replay(fixture) }
        }
        result += responses.requests.enumerated().filter { !$0.element.phase.hasSuffix(".initial") }.map { index, record in
            Scenario(id: "archive/\(index)-" + record.phase, label: "과거 응답 보존: " + record.phase, scope: "recorded_response") {
                try await archived(record)
            }
        }
        result.append(Scenario(id: "oracle/numeric-count", label: "다른 식별자에 있는 숫자가 잘못된 횟수를 가리지 않음", scope: "test_oracle") { try numericOracle() })
        result.append(Scenario(id: "oracle/table-row-values", label: "표의 행 사이에 뒤바뀐 값을 거절", scope: "test_oracle") { try tableOracle() })
        result.append(Scenario(id: "runner/known-failure-isolation", label: "알려진 실패 뒤의 새 실패와 XPASS를 구분", scope: "test_oracle") { try knownFailurePolicy() })
        for id in ["short-english", "markdown-table"] {
            result.append(Scenario(id: "language/" + id, label: "자동 감지: " + id) { try await automaticDirection(id) })
        }
        for explicit in [false, true] {
            for whole in [false, true] {
                let id = "document/" + (explicit ? "explicit" : "plain") + (whole ? "-whole-retranslation" : "-append")
                result.append(Scenario(id: id, label: (explicit ? "경계 있음" : "경계 없음") + (whole ? " · 전체 재번역" : " · 문단 추가")) {
                    try await document(explicit: explicit, whole: whole)
                })
            }
        }
        result += lists.cases.map { fixture in
            Scenario(id: "list/" + fixture.id, label: fixture.label) { try list(fixture) }
        }
        result += lists.cases.map { fixture in
            Scenario(id: "list-lifecycle/" + fixture.id, label: "목록 입력·편집·재번역·삽입·내보내기: " + fixture.label) {
                try await listLifecycle(fixture)
            }
        }
        result.append(Scenario(id: "list/plain-prose", label: "일반 문장을 목록으로 만들지 않음") { try plainProseIsNotAList() })
        return result
    }
}

@main
private struct FormatRegressionTests {
    private static func emit(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    private static func load<T: Decodable>(_ type: T.Type, _ root: URL, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(name)))
    }

    @MainActor
    static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            guard !arguments.isEmpty else { throw CheckFailure(code: "usage", expected: "fixture directory [--strict] [--report path]", actual: "no arguments") }
            let root = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
            var strict = false
            var reportPath: String?
            while !arguments.isEmpty {
                switch arguments.removeFirst() {
                case "--strict": strict = true
                case "--report" where !arguments.isEmpty: reportPath = arguments.removeFirst()
                default: throw CheckFailure(code: "usage", expected: "--strict or --report path", actual: "unknown/incomplete option")
                }
            }
            let inputs = try load(Inputs.self, root, "inputs.json")
            let responses = try load(Responses.self, root, "recorded-responses.json")
            let lists = try load(Lists.self, root, "list-inputs.json")
            let listResponses = try load(ListResponses.self, root, "desired-list-responses.json")
            let known = try load(KnownFailures.self, root, "known-failures.json")
            try check([inputs.schemaVersion, responses.schemaVersion, lists.schemaVersion, listResponses.schemaVersion, known.schemaVersion].allSatisfy { $0 == 1 },
                      "fixture.schema", "schema version 1", "unsupported schema")
            try check(responses.requests.count == 20, "fixture.archivedCount",
                      "all 20 responses from the fixed 2026-10-17 audit", "\(responses.requests.count)")
            let initialIDs = responses.requests.filter { $0.phase.hasSuffix(".initial") }.map { String($0.phase.dropLast(".initial".count)) }
            try check(Set(initialIDs) == Set(inputs.cases.map(\.id)) && initialIDs.count == inputs.cases.count,
                      "fixture.recordCoverage", "exactly one archived initial record per input", "\(initialIDs)")
            try check(Set(listResponses.cases.map(\.id)) == Set(lists.cases.map(\.id)) && listResponses.cases.count == lists.cases.count,
                      "fixture.listResponses", "exactly one desired response per list fixture", "\(listResponses.cases.map(\.id))")
            let suite = FixtureSuite(inputs: inputs, responses: responses, lists: lists, listResponses: listResponses)
            let scenarios = suite.scenarios
            let ids = Set(scenarios.map(\.id))
            try check(ids.count == scenarios.count, "fixture.ids", "unique scenario IDs", "duplicate ID")
            let knownIDs = Set(known.failures.map(\.id))
            try check(knownIDs.count == known.failures.count && knownIDs.isSubset(of: ids),
                      "fixture.knownIDs", "unique known failure IDs referring to existing scenarios", "\(knownIDs)")
            let start = Date()
            var results: [ScenarioResult] = []
            for scenario in scenarios {
                let expected = known.failures.first { $0.id == scenario.id }
                let outcome: Outcome
                var detail: String?
                do {
                    try await scenario.run()
                    outcome = classify(failures: [], expected: expected)
                    if expected != nil { detail = "Expected behavior now passes. Remove the resolved known-failure entry." }
                } catch {
                    detail = String(describing: error)
                    if let failures = error as? CheckFailures {
                        outcome = classify(failures: failures.failures, expected: expected)
                    } else if let failure = error as? CheckFailure {
                        outcome = classify(failures: [failure], expected: expected)
                    } else { outcome = .failure }
                }
                results.append(ScenarioResult(id: scenario.id, label: scenario.label, scope: scenario.scope, outcome: outcome, detail: detail, knownFailure: expected))
                emit("\(outcome.label) \(scenario.id)" + (detail.map { " — " + $0 } ?? ""))
            }
            let report = Report(replaySourceRevision: responses.sourceRevision, replayProvider: responses.provider,
                replayModel: responses.model, strict: strict, elapsedMilliseconds: Int(Date().timeIntervalSince(start) * 1000), results: results)
            emit("Format regressions: \(results.count) cases; PASS=\(report.passed) XFAIL=\(report.knownFailures) FAIL=\(report.failures) XPASS=\(report.unexpectedPasses); live requests=0; strict=\(strict)")
            emit("XFAIL entries are unresolved desired-behavior failures, not passing tests.")
            if let reportPath {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(report).write(to: URL(fileURLWithPath: reportPath), options: .withoutOverwriting)
            }
            exit(report.exitCode)
        } catch {
            emit("Format regression runner failed: \(error)")
            exit(2)
        }
    }
}
