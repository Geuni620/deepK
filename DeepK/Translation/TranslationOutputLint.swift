import Foundation

/// 모델 출력이 "번역문만 반환한다"는 계약을 지키는지 규칙으로 검사한다.
/// 프롬프트는 이 계약을 요청할 뿐 보장하지 못하므로 결과를 쓰기 전에 코드로 확인한다.
/// 규칙은 2026-10-08 측정에서 실제로 나온 실패(원문 섞임, 지시문 머리말, 한자 섞임)를 기준으로 한다.
/// 언어는 `TranslationLanguage`의 raw value(`en`, `ko`)를 받는다.
enum TranslationOutputLint {
    enum Rule: String, Sendable {
        /// 원문 문장이 결과에 그대로 들어 있다.
        case sourceEcho
        /// "Here is the translation:", "다음 텍스트를 …번역" 같은 메타 문장이 붙었다.
        case preamble
        /// 대상 언어에 맞지 않는 문자 체계가 섞였다.
        case foreignScript
        /// 원문의 코드·자리표시자·URL이 결과에 같은 개수로 남지 않았다.
        case literalMismatch
        /// 문단 수가 다르거나 길이가 원문 섞임 수준으로 늘었다.
        case structure
    }

    enum Severity: String, Sendable {
        /// 해당 부분만 지우면 된다(`removingPreamble(from:source:)`).
        case fixable
        /// 같은 모델로 다시 요청해야 한다.
        case retry
    }

    struct Violation: Equatable, Sendable {
        let rule: Rule
        let severity: Severity
        let detail: String
    }

    static func lint(source: String, output: String, sourceLanguage: String, targetLanguage: String) -> [Violation] {
        let source = normalizingNewlines(source)
        let output = normalizingNewlines(output)
        var violations: [Violation] = []
        if let echoed = EchoProbe(source: source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage).echoedSentence(in: output) {
            violations.append(Violation(rule: .sourceEcho, severity: .retry, detail: "원문 문장이 그대로 있음: \(echoed.prefix(40))"))
        }
        violations += preambleViolations(source: source, output: output)
        if let characters = foreignCharacters(source: source, output: output, targetLanguage: targetLanguage) {
            violations.append(Violation(rule: .foreignScript, severity: .retry, detail: "대상 언어가 아닌 문자: \(characters)"))
        }
        violations += literalViolations(source: source, output: output)
        // 지울 수 있는 머리말은 구조 판정에서 빼야 같은 출력에 fixable과 retry가 함께 나오지 않는다.
        let body = removingPreamble(from: output, source: source) ?? output
        violations += structureViolations(source: source, output: body, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        return violations
    }

    /// 첫 줄 맨 앞의 "…번역해 주세요:" 같은 머리말만 지운 결과다. 지울 수 있는 머리말이 없으면 nil.
    /// 원래 문자열에서 잘라 내므로 나머지 글의 줄바꿈(CRLF 포함)은 그대로다.
    static func removingPreamble(from output: String, source: String) -> String? {
        let source = normalizingNewlines(source)
        guard !preambleIsAmbiguous(source) else { return nil }
        let body = output.drop(while: \.isWhitespace)
        let firstLine = body.prefix(while: { !$0.isNewline })
        // 머리말 문구 뒤 같은 문장 안의 첫 콜론까지만 머리말로 본다. 그 사이에 문장이 끝나면
        // 콜론은 번역문에 속하므로(예: "Let me translate this. 시간: 오후 3시") 지우지 않는다.
        guard let phrase = preambleMatch(in: String(firstLine)),
              let colon = firstLine.firstIndex(where: { $0 == ":" || $0 == "：" })
        else { return nil }
        let phraseEnd = firstLine.index(firstLine.startIndex, offsetBy: phrase.count, limitedBy: firstLine.endIndex) ?? firstLine.endIndex
        if colon > phraseEnd, firstLine[phraseEnd..<colon].contains(where: { ".!?。".contains($0) }) { return nil }
        let remainder = body[firstLine.index(after: colon)...].drop(while: \.isWhitespace)
        return remainder.isEmpty ? nil : String(remainder)
    }

    // MARK: - 규칙

    private static let preamblePatterns: [String] = [
        "^(here is|here's|below is)\\b[^\\n]{0,40}\\btranslation\\b",
        "^(translation|translated text)\\s*[:：]",
        "^let me (correct|fix|redo|retranslate|translate)\\b",
        "^wait[.!,]\\s*(let me|here|actually)\\b",
        "^(번역|번역문|번역 결과)\\s*[:：]",
        "^다음\\s*(텍스트|문장|글|내용)[을를]?[^\\n]{0,20}번역",
        "^(please )?translate the following\\b"
    ]

    /// 줄 맨 앞의 머리말 문구를 찾는다.
    private static func preambleMatch(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for pattern in preamblePatterns {
            if let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(trimmed[range])
            }
        }
        return nil
    }

    /// 원문만으로 머리말과 번역문을 구별할 수 없으면 머리말 검사(보고와 제거)를 하지 않는다. 런타임 제거와 `lint()`가 같은 조건을 쓴다.
    private static func preambleIsAmbiguous(_ source: String) -> Bool {
        hasLabelLine(source) || mentionsTranslation(source)
    }

    /// 원문에 "번역: …", "Translate the following …:", "Time: 3 PM" 같은 라벨·지시문 줄이 있으면
    /// 결과에도 그 번역이 정상적으로 들어 있으므로 머리말과 구별할 수 없다.
    private static func hasLabelLine(_ source: String) -> Bool {
        source.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return preambleMatch(in: trimmed) != nil
                || trimmed.range(of: "^[^.!?。:：]{1,30}[:：]", options: .regularExpression) != nil
        }
    }

    /// 원문이 콜론 앞에서 번역 자체를 말하면(번역, translat-, 翻訳, 翻译) 결과의 "Below is an introduction to the English
    /// translation …:", "Let me fix the translation …:" 같은 첫 문장도 충실한 번역일 수 있다. 머리말 제거는 결과 첫 줄의 콜론까지
    /// 자르므로, 그 콜론이 원문 콜론의 번역일 때만 헷갈린다. 콜론 없는 원문의 낱말("start translating …")만으로는 끄지 않는다.
    /// 그런 원문에 붙은 "다음 텍스트를 한국어로 번역해 주세요:"는 2026-10-08 벤치마크에서 실제로 나온 머리말이다.
    private static func mentionsTranslation(_ source: String) -> Bool {
        source.split(whereSeparator: \.isNewline).contains { line in
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
            let head = line[..<colon]
            return head.contains("번역") || head.contains("翻訳") || head.contains("翻译")
                || head.range(of: "translat", options: .caseInsensitive) != nil
        }
    }

    private static func preambleViolations(source: String, output: String) -> [Violation] {
        guard !preambleIsAmbiguous(source) else { return [] }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let firstIsFixable = removingPreamble(from: output, source: source) != nil
        return lines.enumerated().compactMap { index, line in
            guard let phrase = preambleMatch(in: line) else { return nil }
            let severity: Severity = index == 0 && firstIsFixable ? .fixable : .retry
            return Violation(rule: .preamble, severity: severity, detail: "머리말: \(phrase)")
        }
    }

    private static func foreignCharacters(source: String, output: String, targetLanguage: String) -> String? {
        let plainSource = removingLiterals(from: source)
        let plainOutput = removingLiterals(from: output)
        let foreign = plainOutput.unicodeScalars.filter { scalar in
            switch targetLanguage {
            case "ko":
                // 한국어 결과에 한자·가나가 나오면 원문에 있던 문자일 때만 허용한다.
                return (isHan(scalar) || isKana(scalar)) && !plainSource.unicodeScalars.contains(scalar)
            case "en":
                // 자음·모음 단독 문자(ㅋㅋ, ㅠㅠ, ㄷㄷ 등)는 단어가 아닌 감정 표현이므로 허용한다.
                // 문자 단위 규칙의 한계와 재설계는 issue #47에서 다룬다.
                return (isHangul(scalar) && !isCompatibilityJamo(scalar)) || isHan(scalar) || isKana(scalar)
            default:
                return false
            }
        }
        guard !foreign.isEmpty else { return nil }
        var seen = Set<Unicode.Scalar>()
        return String(String.UnicodeScalarView(foreign.filter { seen.insert($0).inserted }.prefix(10)))
    }

    private static let literalPatterns: [(name: String, pattern: String)] = [
        ("코드", "(?<!`)`[^`\\r\\n]+`(?!`)"),
        ("자리표시자", "\\{[A-Za-z_][A-Za-z0-9_.]*\\}|%(\\d+\\$)?[@dsf]"),
        ("URL", "https?://[^\\s<>()`]+[^\\s<>()`.,;:!?]")
    ]

    private static func literalViolations(source: String, output: String) -> [Violation] {
        var missing: [String] = []
        for (name, pattern) in literalPatterns {
            var counts: [String: Int] = [:]
            for literal in matches(of: pattern, in: source) where !containsHangul(literal) {
                counts[literal, default: 0] += 1
            }
            for (literal, count) in counts.sorted(by: { $0.key < $1.key })
            where output.components(separatedBy: literal).count - 1 < count {
                missing.append("\(name) \(literal)")
            }
        }
        guard !missing.isEmpty else { return [] }
        return [Violation(rule: .literalMismatch, severity: .retry, detail: "보존되지 않음: \(missing.prefix(5).joined(separator: ", "))")]
    }

    /// 이 비율을 넘으면 번역문보다 원문이 섞였을 가능성이 크다. 2026-10-08 정상 출력의 최대값은 0.92였다.
    private static let maximumLengthRatio: [String: Double] = ["en>ko": 1.3]

    private static func structureViolations(source: String, output: String, sourceLanguage: String, targetLanguage: String) -> [Violation] {
        var violations: [Violation] = []
        let sourceParagraphs = paragraphCount(source)
        let outputParagraphs = paragraphCount(output)
        if sourceParagraphs != outputParagraphs {
            violations.append(Violation(rule: .structure, severity: .retry, detail: "문단 수 \(sourceParagraphs) → \(outputParagraphs)"))
        }
        let sourceLength = nonWhitespaceCount(source)
        if let limit = maximumLengthRatio["\(sourceLanguage)>\(targetLanguage)"], sourceLength >= 40 {
            let ratio = Double(nonWhitespaceCount(output)) / Double(sourceLength)
            if ratio > limit {
                violations.append(Violation(rule: .structure, severity: .retry, detail: String(format: "길이 비율 %.2f > %.2f", ratio, limit)))
            }
        }
        return violations
    }

    // MARK: - 원문 반복

    /// 원문 문장이 결과에 그대로 남았는지 본다. 코드는 원문과 결과 양쪽에서 빼고 비교하므로 원문 코드를 그대로
    /// 옮긴 결과(펜스가 있든 없든)는 반복이 아니다. URL과 `<aN>` 태그는 반복이면 그대로 복사되므로 남긴다.
    /// 산문 문장만 본다: 25자·원문 언어 글자 10자 이상, 코드 신호 없음, 영어는 4단어 이상이고 기능어가 있는 문장.
    /// 실행 중 판정의 후보는 여기서 번역에서도 그대로 두는 것을 더 뺀다: 링크만 있는 내비게이션 줄, 참고문헌 항목,
    /// 따옴표로 감싼 문장, 제목처럼 모든 낱말이 대문자로 시작하는 문장. `lint()`의 문장 규칙은 이것을 빼지 않으므로
    /// 벤치마크 판정이 줄지 않는다.
    struct EchoProbe: Sendable {
        struct Echo: Equatable, Sendable {
            /// 결과에 그대로 있는 후보 문장 수
            let found: Int
            /// 그 문장들의 원문 언어 글자 수 / 모든 후보의 원문 언어 글자 수
            let coverage: Double
            let isEcho: Bool
        }

        private struct Candidate: Sendable {
            let text: String
            let scalars: [Unicode.Scalar]
            let letters: Int
        }

        /// 실행 중 판정(`measure`, `Stream`)의 후보
        private let candidates: [Candidate]
        /// `lint()`의 문장 규칙이 보는 산문 문장. 그대로 두는 줄·문장도 들어 있다.
        private let allSentences: [Candidate]
        private let letters: Int
        private let longest: Int
        var count: Int { candidates.count }

        init(source: String, sourceLanguage: String, targetLanguage: String) {
            var candidates: [Candidate] = []
            var allSentences: [Candidate] = []
            let text = sourceLanguage == targetLanguage ? ""
                : prose(of: source.replacingOccurrences(of: "(?s)~~~.*?~~~", with: "\n", options: .regularExpression))
            // 원문이 이미 대상 언어로 쓰여 있으면 같은 문장이 남는 것이 정상이다.
            if letterCount(text, language: targetLanguage) * 2 < letterCount(text, language: sourceLanguage) {
                var seen = Set<String>()
                for line in text.split(separator: "\n") {
                    let keptLine = Self.keptVerbatim(String(line))
                    for sentence in sentences(in: String(line)) where Self.isSentence(sentence, language: sourceLanguage) {
                        let candidate = Candidate(text: sentence, scalars: Array(sentence.unicodeScalars),
                                                  letters: letterCount(sentence, language: sourceLanguage))
                        allSentences.append(candidate)
                        if !keptLine, !Self.keptAsIs(sentence, language: sourceLanguage), seen.insert(sentence).inserted {
                            candidates.append(candidate)
                        }
                    }
                }
            }
            self.candidates = candidates
            self.allSentences = allSentences
            letters = candidates.reduce(0) { $0 + $1.letters }
            longest = candidates.map(\.scalars.count).max() ?? 0
        }

        /// `lint()`의 문장 규칙: 결과에 그대로 있는 첫 산문 문장.
        func echoedSentence(in output: String) -> String? {
            let prose = Array(TranslationOutputLint.prose(of: output).unicodeScalars)
            return allSentences.first { Self.occurs($0.scalars, in: prose, from: 0) }?.text
        }

        /// 완료한 결과의 판정. 짝 없는 펜스는 `TranslationMarkup`처럼 스트레이로 본다(`CodeScanner.codeMask(final:)`).
        func measure(_ output: String) -> Echo {
            let prose = Array(TranslationOutputLint.prose(of: output).unicodeScalars)
            return decide(Set(candidates.indices.filter { Self.occurs(candidates[$0].scalars, in: prose, from: 0) }))
        }

        /// 반복 비율이 0.4 이상이거나, 두 문장 이상이 반복되고 비율이 0.3 이상이면 원문 반복이다. 제목·인용처럼 그대로 둔
        /// 한 문장으로는 정하지 않기 위해서다. 후보가 두 개 이하인 짧은 원문은 모든 후보가 그대로 있을 때만 반복이다.
        /// 번역에서 로그·오류 문구 한 줄을 영어 그대로 두는 것은 정상이기 때문이다.
        /// 찾은 문장은 글이 길어져도 사라지지 않으므로 조각에서의 판정은 완료 글에서도 그대로다.
        private func decide(_ found: Set<Int>) -> Echo {
            let covered = found.reduce(0) { $0 + candidates[$1].letters }
            let coverage = letters == 0 ? 0 : Double(covered) / Double(letters)
            let isEcho = candidates.count <= 2 ? !found.isEmpty && found.count == candidates.count
                : coverage >= 0.4 || (found.count >= 2 && coverage >= 0.3)
            return Echo(found: found.count, coverage: coverage, isEcho: isEcho)
        }

        /// 스트리밍 조각용 판정. 인과 모드 산문을 이어 붙이며 새로 늘어난 구간(과 가장 긴 후보만큼 앞)만 찾는다.
        /// 앞 조각을 잇지 않는 조각이 오면 처음부터 다시 읽는다.
        struct Stream: Sendable {
            private let probe: EchoProbe
            private var raw = ""
            private var scanner = CodeScanner(urls: false)
            private var writer = ProseWriter()
            private var searched = 0
            private var found = Set<Int>()

            init(_ probe: EchoProbe) {
                self.probe = probe
            }

            mutating func update(with snapshot: String) -> Echo {
                var start = snapshot.startIndex
                if snapshot.utf8.starts(with: raw.utf8) {
                    start = snapshot.utf8.index(snapshot.utf8.startIndex, offsetBy: raw.utf8.count)
                } else {
                    self = Stream(probe)
                }
                for scalar in snapshot.unicodeScalars[start...] {
                    writer.append(scalar, isCode: scanner.isCode(scalar))
                }
                raw = snapshot
                let from = max(0, searched - probe.longest + 1)
                for index in probe.candidates.indices
                where !found.contains(index) && EchoProbe.occurs(probe.candidates[index].scalars, in: writer.scalars, from: from) {
                    found.insert(index)
                }
                searched = writer.scalars.count
                return probe.decide(found)
            }
        }

        private static func occurs(_ needle: [Unicode.Scalar], in haystack: [Unicode.Scalar], from start: Int) -> Bool {
            guard let first = needle.first, haystack.count - start >= needle.count else { return false }
            for index in start...(haystack.count - needle.count)
            where haystack[index] == first && haystack[index..<(index + needle.count)].elementsEqual(needle) {
                return true
            }
            return false
        }

        /// 산문 문장: 25자·원문 언어 글자 10자 이상이고 코드처럼 보이지 않으며, 영어는 4낱말 이상에 기능어가 있다.
        private static func isSentence(_ sentence: String, language: String) -> Bool {
            guard sentence.count >= 25, letterCount(sentence, language: language) >= 10, !looksLikeCode(sentence) else { return false }
            guard language == "en" else { return true }
            let words = sentence.split(separator: " ")
            return words.count >= 4 && words.contains { functionWords.contains(bare($0)) }
        }

        /// 번역에서도 그대로 둘 수 있는 문장: 따옴표로 감싼 화면 문구·인용과 논문·책·제품 제목(Attention Is All You Need).
        /// 기능어가 아닌 낱말이 모두 대문자로 시작하면 제목으로 본다. 숫자로 시작하는 낱말(16x16)은 보지 않는다.
        private static func keptAsIs(_ sentence: String, language: String) -> Bool {
            if isQuoted(sentence) { return true }
            guard language == "en" else { return false }
            let heads = sentence.split(separator: " ").compactMap { word -> Unicode.Scalar? in
                guard !functionWords.contains(bare(word)),
                      let head = word.unicodeScalars.first(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }),
                      head.properties.isAlphabetic
                else { return nil }
                return head
            }
            return heads.count >= 2 && heads.allSatisfy(\.properties.isUppercase)
        }

        private static func bare(_ word: Substring) -> String {
            String(String.UnicodeScalarView(word.unicodeScalars.filter(\.properties.isAlphabetic))).lowercased()
        }

        /// 그대로 두는 것이 정상인 줄: 링크 태그 밖에 글자가 없는 줄(내비게이션·관련 글 목록)과 참고문헌 항목.
        /// 참고문헌 항목은 줄 머리(`[n]`·`n.`·`-` 같은 목록 표시 뒤)가 저자 이름(Vaswani, A. · Vaswani, Ashish, · Vaswani A, ·
        /// A. Vaswani)이고 연도·et al.·doi·arXiv가 있는 줄이다. ACL·ACM 형식(Jacob Devlin, Ming-Wei Chang, and … 2019. BERT: …)은
        /// 이름이 앞에 오는 저자 뒤에 쉼표나 " and "가 오고, 줄 안에 ". 2019." 같은 연도 문장이 있는 줄이다.
        /// 본문 문단 속 인용(Titanic (1997), Vaswani et al. introduced …, John Smith, the CEO, said in 2019 …)은 번역할 산문이라 후보로 남는다.
        private static func keptVerbatim(_ line: String) -> Bool {
            let outsideLinks = line.replacingOccurrences(of: "<a(\\d{1,3})>.*?</a\\1>", with: "", options: .regularExpression)
            if outsideLinks != line, !outsideLinks.unicodeScalars.contains(where: \.properties.isAlphabetic) { return true }
            if line.range(of: givenNameFirstHead, options: .regularExpression) != nil,
               line.range(of: #"\.\s(?:1[5-9]|20)\d{2}[a-z]?\."#, options: .regularExpression) != nil {
                return true
            }
            return line.range(of: referenceHead, options: .regularExpression) != nil
                && line.range(of: #"\(\d{4}[a-z]?\)|\bet al\.|\b(?:doi|arXiv):|\b(?:1[5-9]|20)\d{2}\b"#, options: .regularExpression) != nil
        }

        private static let listMarker = #"^\s*(?:\[\d{1,3}\]\s*|\d{1,3}\.\s+|[-*•]\s+)?"#

        private static let referenceHead = listMarker
            + #"(?:\p{Lu}[\p{L}'-]+,\s+(?:\p{Lu}\.|\p{Lu}[\p{L}'-]+,)|\p{Lu}[\p{L}'-]+\s\p{Lu}{1,3},|\p{Lu}\.\s?(?:\p{Lu}\.\s?)*\p{Lu}[\p{L}'-]+)"#

        /// 이름이 앞에 오는 저자(Jacob Devlin, · Ming-Wei Chang and · Kenton L. Lee,). 가운데 이름은 하나까지다.
        private static let givenNameFirstHead = listMarker
            + #"\p{Lu}[\p{L}'-]+(?:\s\p{Lu}(?:\.|[\p{L}'-]+))?\s\p{Lu}[\p{L}'-]+(?:,|\sand\s)"#

        /// 따옴표로 감싼 문장은 화면 문구·인용이라 그대로 둘 수 있다.
        private static func isQuoted(_ sentence: String) -> Bool {
            let core = sentence.unicodeScalars.reversed().drop { ".,;:!?".unicodeScalars.contains($0) }
            guard let last = core.first, last == "\"" || last == "'" else { return false }
            return sentence.unicodeScalars.first == last
        }

        private static let codePatterns = [
            "[{}]", ";\\s*$", "[A-Za-z_][A-Za-z0-9_.$]*\\(", "(^|\\s)--?[A-Za-z]", "[=!<>]=|=>|->|::|&&|\\|\\|",
            "(^|\\s)[A-Za-z_][A-Za-z0-9_.]*\\s*=\\s*\\S", "^\\s*(\\$ |#!|//|/\\*|# |>>> )"
        ]

        /// 펜스 없이 놓인 코드·명령·로그 줄.
        private static func looksLikeCode(_ sentence: String) -> Bool {
            if codePatterns.contains(where: { sentence.range(of: $0, options: .regularExpression) != nil }) { return true }
            let punctuation = Set(".,!?'\"’“”()-:".unicodeScalars)
            let symbols = sentence.unicodeScalars.filter {
                !$0.properties.isAlphabetic && !$0.properties.isWhitespace && !punctuation.contains($0)
            }.count
            return Double(symbols) > 0.3 * Double(sentence.unicodeScalars.count)
        }

        private static let functionWords: Set<String> = [
            "a", "an", "the", "to", "of", "in", "on", "at", "by", "for", "from", "with", "and", "or", "but", "if", "when",
            "then", "than", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "you",
            "your", "we", "our", "they", "their", "he", "she", "not", "no", "can", "will", "would", "should", "must", "may",
            "do", "does", "did", "has", "have", "had", "as", "so", "there", "here", "what", "which", "who", "how"
        ]
    }

    // MARK: - 코드와 산문

    /// 원문 반복을 비교할 산문. 코드는 빈칸 하나가 되고(`CodeScanner.codeMask(final:)`), 모든 공백(U+00A0 포함)은
    /// 빈칸 하나로 줄고, 보이지 않는 문자는 빠지고, 둥근 따옴표는 곧은 따옴표가 된다. 줄바꿈은 문장 경계로 남는다.
    static func prose(of text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var writer = ProseWriter()
        for (scalar, code) in zip(scalars, CodeScanner.codeMask(final: scalars)) {
            writer.append(scalar, isCode: code)
        }
        return String(String.UnicodeScalarView(writer.scalars))
    }

    /// `prose(of:)`의 글자 단위 쓰기. 앞에 쓴 글자를 고치지 않으므로 스트리밍 중에도 뒤에만 붙는다.
    struct ProseWriter: Sendable {
        private(set) var scalars: [Unicode.Scalar] = []

        mutating func append(_ scalar: Unicode.Scalar, isCode: Bool) {
            if scalar == "\n" { scalars.append(scalar); return }
            if isCode || scalar.properties.isWhitespace {
                if scalars.last != " " { scalars.append(" ") }
                return
            }
            switch scalar.value {
            case 0x00AD, 0x200B...0x200D, 0x2060, 0xFEFF: return
            case 0x2018...0x201B: scalars.append("'")
            case 0x201C...0x201F: scalars.append("\"")
            default: scalars.append(scalar)
            }
        }
    }

    /// 글자마다 코드인지 산문인지 가른다. 결과 창(`TranslationMarkup`)이 코드로 보여 줄 백틱 펜스 블록과 인라인 코드,
    /// `urls`이면 `http://`·`https://`로 시작하는 낱말이 코드다. 원문 반복은 코드를 비교하지 않고 한자 치환은 코드를 고치지 않는다.
    ///
    /// 인과 모드(`init(urls:)`)는 앞 글자들과 그 글자만 보고 정하므로 스트리밍 조각도 완성된 글과 같은 판정을 받는다.
    /// 왼쪽만 보고 정할 수 없으면 코드 쪽으로 기운다: 짝 없는 맨 펜스도 블록을 열고, 닫히지 않은 인라인 코드는 줄 끝까지
    /// 코드다. 최종 모드(`codeMask(final:)`)는 글 전체를 보고 `TranslationMarkup.roles`처럼 닫는 줄이 없는 맨 펜스를
    /// 스트레이로 본다(코드 안에서 시작한 선택). 빈 줄이 뒤따른 맨 펜스 뒤에 닫는 줄보다 정보 문자열이 있는 펜스가 먼저 오면
    /// 그 맨 펜스도 스트레이다. 인과 모드는 그 펜스 줄에서 이를 알게 되므로, 맨 펜스가 없는 셈 치고 함께 읽어 둔 판정으로
    /// 갈아탄다. 같은 글에서 인과 모드의 코드는 최종 모드의 코드를 포함한다.
    /// 펜스 줄의 정보 문자열은 두 모드 모두 `TranslationMarkup.reading(of:)`처럼 읽는다. 아는 태그·속성이 붙은 정보 문자열은
    /// 닫는 줄까지 가는 블록이고, 아는 명령(```pwd)과 그 밖의 글(```npm install)은 채팅식 블록이라 백틱으로 끝나는 코드 줄에서도
    /// 닫힌다. 모르는 한 낱말(```node)은 펜스 뒤 첫 비어 있지 않은 줄이 끝날 때 정한다. 그 줄이 채팅식으로 닫히면 거기서 닫고,
    /// 아니면 태그다. `TranslationMarkup`도 그 줄에서 정하므로 인과 모드도 그 줄이 끝날 때 같은 판정을 내린다.
    struct CodeScanner: Sendable {
        /// 블록이 닫히는 방식. `undecided`는 아직 읽지 않은 한 낱말 이름 펜스다.
        private enum Closing: Sendable { case fence, chat, undecided }

        private struct Fence: Sendable {
            let length: Int
            let closing: Closing
        }

        private let urls: Bool
        private var open: Fence?
        /// 빈 줄이 뒤따른 맨 펜스가 연 블록 안에서, 그 펜스를 스트레이로 볼 때의 판정(많아야 하나). 블록이 닫히면 버린다.
        private var stray: [CodeScanner] = []
        /// 바로 앞 줄이 맨 펜스로 블록을 열었다. 이 줄이 비어 있으면 `stray`를 시작한다.
        private var afterBareOpener = false
        // 줄 머리: 들여쓰기 공백(3개까지)과 백틱
        private var leadingSpaces = 0
        private var headRun = 0
        private var headDone = false
        // 백틱 3개 이상으로 시작한 줄의 나머지(정보 문자열)
        private var lineIsFence = false
        private var rest: [Unicode.Scalar] = []
        // 줄 끝 백틱 묶음(채팅식 블록 닫기): 공백을 뺀 줄 길이와 그 끝의 백틱 수
        private var lineLength = 0
        private var contentLength = 0
        private var tailRun = 0
        private var blankAfterContent = false
        private var lineIsBlank = true
        // 산문 줄의 인라인 코드: 읽는 중인 백틱 수, 열린 스팬의 길이(`Int.max`면 닫히지 않음)와 내용 길이
        private var run = 0
        private var span: Int?
        private var spanUnits = 0
        // URL: 낱말의 앞 8글자(소문자)
        private var token: [Unicode.Scalar] = []
        private var tokenIsURL = false

        init(urls: Bool) {
            self.urls = urls
        }

        mutating func isCode(_ scalar: Unicode.Scalar) -> Bool {
            if !stray.isEmpty { _ = stray[0].isCode(scalar) }
            if scalar == "\n" {
                endLine()
                return false
            }
            trackTail(scalar)
            if !headDone {
                if scalar == " ", headRun == 0, leadingSpaces < 3 {
                    leadingSpaces += 1
                    return open != nil
                }
                if scalar == "`" {
                    headRun += 1
                    if headRun == 3 { lineIsFence = true }
                    return true
                }
                headDone = true
                if !lineIsFence, open == nil { run = headRun }
            }
            if lineIsFence {
                rest.append(scalar)
                return true
            }
            return open != nil || proseIsCode(scalar)
        }

        private mutating func endLine() {
            let rest = self.rest.last == "\r" ? self.rest.dropLast() : self.rest[...]
            let info = lineIsFence && !rest.contains("`") ? Self.info(rest) : nil
            var bareOpener = false
            if let fence = open {
                // 맨 펜스가 스트레이였다. `stray`는 이 줄까지 읽었다.
                if let info, !info.isEmpty, let resolved = stray.first {
                    self = resolved
                    return
                }
                let closer = lineIsFence && headRun >= fence.length && rest.allSatisfy { $0 == " " || $0 == "\t" }
                open = Self.continued(fence, closer: closer, closesChat: tailRun >= fence.length && tailRun < contentLength, blank: lineIsBlank)
                if open == nil { stray = [] } else if afterBareOpener, lineIsBlank { stray = [CodeScanner(urls: urls)] }
            } else if let info {
                open = Fence(length: headRun, closing: Self.closing(info: info))
                bareOpener = info.isEmpty
            }
            self = CodeScanner(urls: urls, open: open, stray: stray, afterBareOpener: bareOpener)
        }

        private init(urls: Bool, open: Fence?, stray: [CodeScanner], afterBareOpener: Bool) {
            self.urls = urls
            self.open = open
            self.stray = stray
            self.afterBareOpener = afterBareOpener
        }

        private mutating func trackTail(_ scalar: Unicode.Scalar) {
            lineLength += 1
            if !scalar.properties.isWhitespace { lineIsBlank = false }
            if scalar == " " || scalar == "\t" || scalar == "\r" {
                if contentLength > 0 { blankAfterContent = true }
                return
            }
            tailRun = scalar == "`" ? (blankAfterContent ? 1 : tailRun + 1) : 0
            contentLength = lineLength
            blankAfterContent = false
        }

        /// 산문 줄: 같은 길이의 백틱 묶음으로 같은 줄에서 96 UTF-16 단위 안에 닫히는 인라인 코드
        /// (`TranslationMarkup.codeSpanEnd`). 아직 닫히지 않은 스팬은 닫힐 때까지 코드로 본다.
        private mutating func proseIsCode(_ scalar: Unicode.Scalar) -> Bool {
            if scalar == "`" {
                run += 1
                return true
            }
            if run > 0 {
                if span == nil {
                    span = run
                    spanUnits = 0
                } else if span == run {
                    span = nil
                } else if span != .max {
                    spanUnits += run
                    if spanUnits > 96 { span = .max }
                }
                run = 0
            }
            if let length = span {
                if length != .max {
                    spanUnits += scalar.utf16.count
                    if spanUnits > 96 { span = .max }
                }
                return true
            }
            return urls && isURL(scalar)
        }

        private mutating func isURL(_ scalar: Unicode.Scalar) -> Bool {
            if scalar.properties.isWhitespace {
                token.removeAll()
                tokenIsURL = false
                return false
            }
            if tokenIsURL { return true }
            if "(<[\"'".unicodeScalars.contains(scalar) {
                token.removeAll()
                return false
            }
            if token.count < 8 {
                token.append(("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar)
            }
            tokenIsURL = token.elementsEqual("http://".unicodeScalars) || token.elementsEqual("https://".unicodeScalars)
            return false
        }

        /// 최종 모드: 글 전체 글자마다 코드인지. 맨 펜스는 뒤에 닫는 줄이 있을 때만 블록을 열고, 빈 줄 다음에
        /// 정보 문자열이 있는 펜스가 먼저 오면 스트레이다. 인라인 코드는 닫히는 스팬만 코드다. URL은 보지 않는다.
        static func codeMask(final scalars: [Unicode.Scalar]) -> [Bool] {
            let lines = scalars.split(separator: "\n", omittingEmptySubsequences: false)
            var mask: [Bool] = []
            mask.reserveCapacity(scalars.count)
            var open: Fence?
            for (index, line) in lines.enumerated() {
                if index > 0 { mask.append(false) }
                if let fence = open {
                    open = continued(fence, closer: isCloser(line, fence.length), closesChat: closesChat(line, fence.length),
                                blank: line.allSatisfy(\.properties.isWhitespace))
                    mask += repeatElement(true, count: line.count)
                } else if let fence = fenceLine(line) {
                    if !fence.info.isEmpty || pairs(fence.length, after: index, in: lines) {
                        open = Fence(length: fence.length, closing: closing(info: fence.info))
                    }
                    mask += repeatElement(true, count: line.count)
                } else {
                    mask += inlineMask(Array(line))
                }
            }
            return mask
        }

        /// 열린 블록이 줄 하나를 지난 뒤. 닫는 줄이거나, 채팅식 블록에서 백틱 묶음으로 끝나는 코드 줄이면 닫힌다(nil).
        /// 이름 펜스는 첫 비어 있지 않은 줄이 채팅식으로 닫지 않으면 태그 블록이 된다(`TranslationMarkup.namesLanguage`).
        private static func continued(_ fence: Fence, closer: Bool, closesChat: Bool, blank: Bool) -> Fence? {
            if closer || fence.closing != .fence && closesChat { return nil }
            return fence.closing == .undecided && !blank ? Fence(length: fence.length, closing: .fence) : fence
        }

        private static func fenceParts(_ line: ArraySlice<Unicode.Scalar>) -> (run: Int, rest: ArraySlice<Unicode.Scalar>)? {
            let line = line.last == "\r" ? line.dropLast() : line
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3, line.dropFirst(indent).first == "`" else { return nil }
            let run = line.dropFirst(indent).prefix { $0 == "`" }.count
            return (run, line.dropFirst(indent + run))
        }

        private static func fenceLine(_ line: ArraySlice<Unicode.Scalar>) -> (length: Int, info: String)? {
            guard let parts = fenceParts(line), parts.run >= 3, !parts.rest.contains("`") else { return nil }
            return (parts.run, info(parts.rest))
        }

        private static func info(_ rest: ArraySlice<Unicode.Scalar>) -> String {
            String(String.UnicodeScalarView(rest)).trimmingCharacters(in: .whitespaces)
        }

        private static func closing(info: String) -> Closing {
            switch reading(of: info) {
            case .info: .fence
            case .code: .chat
            case .name: .undecided
            }
        }

        /// 펜스 줄 글의 읽기: 정보 문자열, 펜스 줄에 쓴 코드, 뒤따르는 줄로 정할 한 낱말 이름.
        private enum Reading { case info, code, name }

        /// `TranslationMarkup.reading(of:)`와 그 두 목록의 복제다. 이 파일은 혼자 컴파일되므로(벤치마크 도구) 옮겨 두고,
        /// HanjaRepairTests의 판정 일치 테스트가 두 쪽이 같게 읽는지 확인한다. 한쪽 목록을 바꾸면 다른 쪽도 바꾼다.
        static let languageTags: Set<String> = [
            "bash", "sh", "shell", "zsh", "fish", "console", "terminal", "shell-session",
            "powershell", "ps1", "bat", "batch", "cmd",
            "c", "h", "cpp", "c++", "cc", "cxx", "hpp", "cs", "csharp", "c#", "objc", "objective-c",
            "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "py", "python", "python3",
            "rb", "ruby", "go", "golang", "rust", "rs", "java", "kotlin", "kt", "scala", "php",
            "perl", "pl", "lua", "r", "dart", "elixir", "ex", "erlang", "erl", "haskell", "hs",
            "clojure", "clj", "lisp", "julia", "jl", "sql", "html", "htm", "xml", "css", "scss", "sass", "less",
            "json", "jsonc", "yaml", "yml", "toml", "ini", "text", "txt", "plaintext", "plain",
            "md", "markdown", "mdx", "diff", "patch", "dockerfile", "makefile", "cmake",
            "graphql", "gql", "proto", "protobuf", "vue", "svelte", "astro", "mermaid", "regex", "regexp"
        ]

        static let commands: Set<String> = [
            "pwd", "ls", "ll", "cd", "whoami", "clear", "cls", "date", "uptime", "hostname", "history",
            "exit", "top", "htop", "ps", "df", "du", "id", "uname", "printenv", "ifconfig", "ipconfig"
        ]

        private static func reading(of info: String) -> Reading {
            if info.isEmpty { return .info }
            let head = #"(?:[A-Za-z0-9_+#.\-]{1,24}(?::\S+)?|\{[^{}]*\})"#
            let attribute = #"(?:\{[^{}]*\}|[a-z][A-Za-z0-9_\-]*=(?:"[^"]*"|'[^']*'))"#
            let flag = #"[A-Za-z][A-Za-z0-9_\-]*"#
            if info.range(of: "^\(head)$", options: .regularExpression) != nil {
                if info.hasPrefix("{") || languageTags.contains(info.lowercased()) { return .info }
                return commands.contains(info.lowercased()) ? .code : .name
            }
            return info.range(of: "^\(head)(?:\\s+(?:\(attribute)|\(flag)))*$", options: .regularExpression) != nil
                && info.range(of: "\\s\(attribute)", options: .regularExpression) != nil ? .info : .code
        }

        private static func isCloser(_ line: ArraySlice<Unicode.Scalar>, _ length: Int) -> Bool {
            guard let parts = fenceParts(line) else { return false }
            return parts.run >= length && parts.rest.allSatisfy { $0 == " " || $0 == "\t" }
        }

        private static func closesChat(_ line: ArraySlice<Unicode.Scalar>, _ length: Int) -> Bool {
            let content = line.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }
            let run = content.prefix { $0 == "`" }.count
            return run >= length && run < content.count
        }

        private static func pairs(_ length: Int, after index: Int, in lines: [ArraySlice<Unicode.Scalar>]) -> Bool {
            let blankAfter = lines.indices.contains(index + 1) && lines[index + 1].allSatisfy(\.properties.isWhitespace)
            for line in lines[(index + 1)...] {
                guard let next = fenceLine(line) else { continue }
                if isCloser(line, length) { return true }
                if blankAfter, !next.info.isEmpty { return false }
            }
            return false
        }

        private static func inlineMask(_ line: [Unicode.Scalar]) -> [Bool] {
            var mask = [Bool](repeating: false, count: line.count)
            var index = 0
            while index < line.count {
                guard line[index] == "`" else { index += 1; continue }
                let run = line[index...].prefix { $0 == "`" }.count
                guard let end = spanEnd(line, opening: index, run: run) else { index += run; continue }
                for position in index..<(end + run) { mask[position] = true }
                index = end + run
            }
            return mask
        }

        private static func spanEnd(_ line: [Unicode.Scalar], opening: Int, run: Int) -> Int? {
            var index = opening + run
            var units = 0
            while index < line.count, units <= 96 {
                guard line[index] == "`" else {
                    units += line[index].utf16.count
                    index += 1
                    continue
                }
                let closing = line[index...].prefix { $0 == "`" }.count
                if closing == run { return index }
                units += closing
                index += closing
            }
            return nil
        }
    }

    // MARK: - 보조

    /// 원문과 결과의 줄바꿈 방식(CRLF·CR·LF)이 달라도 문단·줄 판정이 같도록 맞춘다.
    private static func normalizingNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// 코드 블록·인라인 코드·URL은 번역 대상이 아니므로 문자·문장 검사에서 뺀다.
    private static func removingLiterals(from text: String) -> String {
        var result = text
        for pattern in ["(?s)```.*?```|~~~.*?~~~", "`[^`\\r\\n]+`", "https?://\\S+"] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    private static func sentences(in text: String) -> [String] {
        text.replacingOccurrences(of: "(?<=[.!?。！？])\\s+", with: "\n", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func paragraphCount(_ text: String) -> Int {
        text.replacingOccurrences(of: "\\n[ \\t]*\\n\\s*", with: "\u{0}", options: .regularExpression)
            .split(separator: "\u{0}")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { nsText.substring(with: $0.range) }
    }

    private static func letterCount(_ text: String, language: String) -> Int {
        text.unicodeScalars.filter { scalar in
            switch language {
            case "ko": isHangul(scalar)
            case "en": ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
            default: false
            }
        }.count
    }

    private static func nonWhitespaceCount(_ text: String) -> Int {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHangul)
    }

    static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value) || (0x3131...0x318E).contains(scalar.value)
    }

    private static func isCompatibilityJamo(_ scalar: Unicode.Scalar) -> Bool {
        (0x3131...0x318E).contains(scalar.value)
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value)
    }
}
