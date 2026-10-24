import Foundation

/// Chrome에서 KaTeX 수식을 복사하면 text/plain에 숨긴 MathML 토큰이 한 줄에 하나씩 들어오고,
/// 화면용 글자가 공백 없이 한 번 더 붙는다. √와 분수 구조는 같은 복사의 public.html에 남은 MathML에만 있다.
/// HTML의 수식마다 토큰 목록이 text/plain의 연속된 줄과 같고 바로 뒤에 같은 글자 묶음이 올 때만
/// 그 구간을 한 줄짜리 유니코드 수식으로 바꾼다. 맞지 않는 수식과 그 밖의 글자는 그대로 둔다.
/// 상태가 없고 결정적이어서 같은 복사는 늘 같은 문자열이 된다. 원문과 HTML은 기록하지 않는다.
enum CopiedMathNormalizer {
    /// 이보다 큰 HTML은 없는 것으로 본다. 512KB 근처의 KaTeX 복사도 수십 ms 안에 정리된다.
    static let maximumHTMLBytes = 512 * 1024
    /// 토큰 줄 뒤에서 화면 글자를 찾는 범위다. KaTeX의 세로 배치(분수·첨자·행렬)는 줄을 여럿 쓴다.
    static let echoLineLimit = 16

    /// KaTeX 수식이 없거나 맞는 수식이 없으면 `plain`을 그대로 돌려준다.
    static func normalize(plain: String, html: String?) -> (text: String, formulas: Int) {
        guard let html, html.utf8.count <= maximumHTMLBytes,
              html.range(of: "katex-mathml", options: .literal) != nil
        else { return (plain, 0) }
        let formulas = katexFormulas(in: html)
        guard !formulas.isEmpty else { return (plain, 0) }

        let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
        let keys = lines.map(lineKey)
        // 토큰 목록이 같은 수식은 맞는 자리도 같다. 토큰 목록마다 첫 토큰과 같은 줄만 한 번씩 맞춰 보므로,
        // 맞지 않는 수식이 많아도 같은 줄을 수식마다 다시 맞춰 보지 않는다.
        var groupOf: [[String]: Int] = [:]
        var members: [[Int]] = []
        for (index, formula) in formulas.enumerated() {
            if let group = groupOf[formula.tokens] {
                members[group].append(index)
            } else {
                groupOf[formula.tokens] = members.count
                members.append([index])
            }
        }
        let linesByKey = Dictionary(grouping: keys.indices) { keys[$0] }
        var anchorLines = Array(repeating: [Int](), count: members.count)
        var anchorsAt: [Int: [(group: Int, span: Span)]] = [:]
        for (group, indices) in members.enumerated() {
            let formula = formulas[indices[0]]
            for line in linesByKey[formula.tokens[0]] ?? [] {
                guard let span = match(formula, at: line, in: lines, keys: keys) else { continue }
                anchorLines[group].append(line)
                anchorsAt[line, default: []].append((group, span))
            }
        }

        // 코드 블록·목록·제목의 짧은 줄("1\n1", "x\nx-axis")도 한 글자 수식과 똑같이 맞는다. 바꾼 구간 밖에
        // 같은 토큰 목록이 맞는 자리가 남아 HTML의 그 수식보다 많으면 어느 자리가 수식인지 알 수 없으므로,
        // 그 토큰 목록은 맞추지 않고 처음부터 다시 맞춘다. 정해진 횟수 안에 끝나지 않으면 정리하지 않는다.
        var refused = Set<Int>()
        var placements: [Placement] = []
        for round in 0...maximumRefusalRounds {
            placements = place(formulas, members: members, anchorsAt: anchorsAt, refused: refused, lines: lines, plain: plain)
            var covered = Array(repeating: false, count: lines.count)
            var placedCount = Array(repeating: 0, count: members.count)
            for placement in placements {
                placedCount[placement.group] += 1
                for line in placement.lines { covered[line] = true }
            }
            let ambiguous = members.indices.filter { group in
                placedCount[group] > 0
                    && placedCount[group] + anchorLines[group].filter({ !covered[$0] }).count > members[group].count
            }
            if ambiguous.isEmpty { break }
            guard round < maximumRefusalRounds else { return (plain, 0) }
            refused.formUnion(ambiguous)
        }
        let replacements = placements.map { (range: $0.range, text: $0.text) }
        guard !replacements.isEmpty else { return (plain, 0) }

        var text = ""
        var kept: [Substring] = []
        var position = plain.startIndex
        for replacement in replacements {
            kept.append(plain[position..<replacement.range.lowerBound])
            text += plain[position..<replacement.range.lowerBound]
            text += replacement.text
            position = replacement.range.upperBound
        }
        kept.append(plain[position...])
        text += plain[position...]

        // 바꾼 구간 밖의 단어가 하나라도 사라지면 정리하지 않는다.
        let remaining = wordCounts(text)
        let lost = kept.reduce(into: [String: Int]()) { counts, segment in
            counts.merge(wordCounts(segment), uniquingKeysWith: +)
        }.contains { remaining[$0.key, default: 0] < $0.value }
        guard !lost, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (plain, 0) }
        return (text, replacements.count)
    }

    /// 모호한 토큰 목록을 빼고 다시 맞추는 최대 횟수다.
    private static let maximumRefusalRounds = 3

    private struct Placement {
        let group: Int
        /// 토큰 첫 줄부터 바꾼 구간의 마지막 줄까지다.
        let lines: ClosedRange<Int>
        let range: Range<String.Index>
        let text: String
    }

    /// text/plain을 앞에서부터 훑으며 줄마다 그 줄에서 맞는 수식 중 아직 쓰지 않았고 HTML 순서가 가장 앞선 것을 맞춘다.
    /// 맞춘 수식보다 앞선 수식은 다시 보지 않아, 제자리에서 맞지 않은 수식이 뒤쪽 다른 수식 자리를 가져가지 않는다.
    private static func place(
        _ formulas: [Formula], members: [[Int]], anchorsAt: [Int: [(group: Int, span: Span)]],
        refused: Set<Int>, lines: [Substring], plain: String
    ) -> [Placement] {
        var placements: [Placement] = []
        var unused = Array(repeating: 0, count: members.count)
        var nextFormula = 0
        var line = 0
        var consumedLine = -1
        while line < lines.count {
            var best: (index: Int, group: Int, span: Span)?
            for (group, span) in anchorsAt[line] ?? [] where !refused.contains(group) {
                while unused[group] < members[group].count, members[group][unused[group]] < nextFormula { unused[group] += 1 }
                guard unused[group] < members[group].count else { continue }
                let index = members[group][unused[group]]
                if best.map({ index < $0.index }) ?? true { best = (index, group, span) }
            }
            guard let (index, group, span) = best else {
                line += 1
                continue
            }
            let formula = formulas[index]
            let joinsPrevious = !formula.isDisplay && !formula.breakBefore && line > 0 && line - 1 != consumedLine
                && lines[line - 1].last.map(precedesInlineMath) == true
            // 인라인 수식 앞 줄바꿈은 MathML 배치가 넣은 것이다. 앞 줄 끝 공백이 구분자로 남는다.
            // HTML에서 수식 바로 앞이 줄바꿈이면 Chrome이 두 줄바꿈을 하나로 썼으므로 남긴다.
            let lower = joinsPrevious ? plain.index(before: lines[line].startIndex) : lines[line].startIndex
            var upper = span.echoEnd
            var nextLine = span.lastLine + 1
            consumedLine = -1
            if lines[span.lastLine][span.echoEnd...].unicodeScalars.allSatisfy({ $0 == " " || isInvisible($0) }) {
                // 세로 배치가 남기는 U+200B 줄과 공백 줄은 수식에 속한다.
                while nextLine < lines.count, !lines[nextLine].isEmpty,
                      lines[nextLine].allSatisfy({ $0 == " " || $0 == "\u{200B}" }) {
                    nextLine += 1
                }
                if !formula.isDisplay, !formula.breakAfter, nextLine < lines.count, lines[nextLine].first == " " {
                    // 세로 배치 뒤 공백 하나로 시작하는 줄은 같은 문장의 나머지다.
                    // HTML에서 수식 뒤가 줄바꿈이면 그 줄은 원래 글의 줄이다(들여 쓴 코드 줄 등).
                    upper = lines[nextLine].index(after: lines[nextLine].startIndex)
                    nextLine += 1
                } else {
                    upper = lines[nextLine - 1].endIndex
                    consumedLine = nextLine - 1
                }
            }
            placements.append(Placement(group: group, lines: line...(nextLine - 1), range: lower..<upper, text: formula.linear))
            nextFormula = index + 1
            line = nextLine
        }
        return placements
    }

    struct Formula {
        /// mi·mn·mo·mtext 글자를 `lineKey`로 맞춘 값이다. Chrome은 토큰마다 한 줄을 쓴다.
        let tokens: [String]
        /// 화면 글자와 비교할 글자 묶음이다(공백·U+200B·U+2061–2064 제외, 정렬).
        let glyphs: [UInt32]
        let linear: String
        let isDisplay: Bool
        /// HTML에서 수식 바로 앞이나 뒤가 원래 글의 줄바꿈이다.
        let breakBefore: Bool
        let breakAfter: Bool
    }

    /// `.katex-mathml` 안의 `<math>`를 순서대로 잘라 읽는다. XML로 읽지 못한 수식은 건너뛴다.
    static func katexFormulas(in html: String) -> [Formula] {
        var formulas: [Formula] = []
        var cursor = html.startIndex
        while let marker = html.range(of: "katex-mathml", options: .literal, range: cursor..<html.endIndex),
              let open = html.range(of: "<math", options: .literal, range: marker.upperBound..<html.endIndex),
              let close = html.range(of: "</math>", options: .literal, range: open.upperBound..<html.endIndex) {
            cursor = close.upperBound
            let source = html[open.lowerBound..<close.upperBound].replacingOccurrences(of: "&nbsp;", with: "&#160;")
            guard let math = (try? XMLDocument(xmlString: source))?.rootElement() else { continue }
            var tokens: [String] = []
            collectTokens(math, into: &tokens)
            let glyphs = tokens.joined().unicodeScalars.filter { !isSpaceOrInvisible($0) }.map(\.value).sorted()
            let linear = finish(lin(math).text)
            // 선택이 숨은 MathML 안에서 시작하면 <math>만 잘리고, SVG로 그린 악센트·화살표(\widehat, \vec)는
            // 화면 글자에 없다. 그러면 text/plain의 화면 글자 끝을 알 수 없으므로, 화면 글자가 토큰과 같은 수식만 맞춘다.
            guard !tokens.isEmpty, !glyphs.isEmpty, !linear.isEmpty,
                  let screen = screen(in: html, after: close.upperBound), screen.glyphs.sorted() == glyphs
            else { continue }
            let start = html[..<marker.lowerBound].lastIndex(of: "<") ?? marker.lowerBound
            formulas.append(Formula(
                tokens: tokens.map(lineKey),
                glyphs: glyphs,
                linear: linear,
                isDisplay: math.attribute(forName: "display")?.stringValue == "block",
                breakBefore: breaksLine(before: start, in: html),
                breakAfter: breaksLine(after: screen.end, in: html)
            ))
        }
        return formulas
    }

    /// `</math>` 바로 뒤 `.katex-html`의 화면 글자(공백·U+200B·U+2061–2064 제외)와 그 요소가 끝나는 자리다.
    /// Chrome이 글자에 쓰는 개체(&amp; &lt; &gt; &nbsp;) 밖의 개체가 있거나 요소가 닫히지 않으면 nil이다.
    private static func screen(in html: String, after mathEnd: String.Index) -> (glyphs: [UInt32], end: String.Index)? {
        let bytes = html.utf8
        guard bytes[mathEnd...].starts(with: #"</span><span class="katex-html""#.utf8) else { return nil }
        var index = bytes.index(mathEnd, offsetBy: "</span>".utf8.count)
        var depth = 0
        var glyphs: [UInt32] = []
        while index < bytes.endIndex {
            guard bytes[index] == UInt8(ascii: "<") else {
                let next = bytes[index...].firstIndex(of: UInt8(ascii: "<")) ?? bytes.endIndex
                guard appendGlyphs(of: html[index..<next], to: &glyphs) else { return nil }
                index = next
                continue
            }
            guard let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) else { return nil }
            // Chrome이 style을 붙인 태그가 수식마다 수십 개라 이름을 바이트로 바로 견준다.
            let closing = bytes[bytes.index(after: index)] == UInt8(ascii: "/")
            let name = bytes.index(index, offsetBy: closing ? 2 : 1)
            if bytes.distance(from: name, to: close) >= 4, bytes[name] == UInt8(ascii: "s"),
               bytes[bytes.index(name, offsetBy: 1)] == UInt8(ascii: "p"), bytes[bytes.index(name, offsetBy: 2)] == UInt8(ascii: "a"),
               bytes[bytes.index(name, offsetBy: 3)] == UInt8(ascii: "n") {
                depth += closing ? -1 : 1
            }
            index = bytes.index(after: close)
            if depth == 0 { return (glyphs, index) }
        }
        return nil
    }

    /// 태그 사이 글자를 화면 글자에 더한다. 위 네 개체 밖의 개체가 있으면 false다.
    private static func appendGlyphs(of text: Substring, to glyphs: inout [UInt32]) -> Bool {
        guard text.utf8.contains(UInt8(ascii: "&")) else {
            for scalar in text.unicodeScalars where !isSpaceOrInvisible(scalar) { glyphs.append(scalar.value) }
            return true
        }
        for (offset, part) in text.split(separator: "&", omittingEmptySubsequences: false).enumerated() {
            var part = part
            if offset > 0 {
                guard let semicolon = part.prefix(8).firstIndex(of: ";") else { return false }
                switch part[..<semicolon] {
                case "amp": glyphs.append(0x26)
                case "lt": glyphs.append(0x3C)
                case "gt": glyphs.append(0x3E)
                case "nbsp": break
                default: return false
                }
                part = part[part.index(after: semicolon)...]
            }
            glyphs += part.unicodeScalars.filter { !isSpaceOrInvisible($0) }.map(\.value)
        }
        return true
    }

    /// 줄을 나누지 않는 태그다. 인라인 요소, 표 칸(Chrome은 칸 사이에 탭을 쓴다), 복사본 맨 앞의 meta.
    private static let inlineTags: Set<String> = [
        "span", "a", "em", "strong", "b", "i", "u", "s", "code", "mark", "small", "sub", "sup", "q", "cite", "abbr", "font", "td", "th", "meta",
        "kbd", "var", "samp", "dfn", "time", "data", "del", "ins", "label", "button", "img", "wbr", "bdi", "bdo",
    ]

    /// Chrome은 수식 앞뒤의 원래 줄바꿈과 MathML 배치의 줄바꿈을 text/plain에 하나로 쓴다. HTML에서
    /// 수식 바로 앞이 `<br>`, 블록 경계, 줄바꿈 글자(pre·pre-wrap)인지 본다. Chrome은 접히는 공백 속
    /// 줄바꿈을 HTML에 공백으로 쓰므로 남은 줄바꿈 글자는 실제 줄바꿈이다. 줄을 나누지 않는 태그는 건너뛴다.
    private static func breaksLine(before end: String.Index, in html: String) -> Bool {
        let bytes = html.utf8
        var index = end
        while index > bytes.startIndex {
            let previous = bytes.index(before: index)
            switch bytes[previous] {
            case UInt8(ascii: ">"):
                guard let open = bytes[..<previous].lastIndex(of: UInt8(ascii: "<")), isInlineTag(html[open...previous]) else { return true }
                index = open
            case let byte:
                return byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
            }
        }
        return false
    }

    /// 수식 바로 뒤가 원래 글의 줄바꿈인지 본다. 줄바꿈 앞의 공백은 건너뛴다.
    private static func breaksLine(after start: String.Index, in html: String) -> Bool {
        let bytes = html.utf8
        var index = start
        while index < bytes.endIndex {
            switch bytes[index] {
            case UInt8(ascii: "<"):
                guard let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")), isInlineTag(html[index...close]) else { return true }
                index = bytes.index(after: close)
            case UInt8(ascii: " "):
                index = bytes.index(after: index)
            case let byte:
                return byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
            }
        }
        return false
    }

    private static func isInlineTag(_ tag: Substring) -> Bool {
        inlineTags.contains(tag.dropFirst().drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased())
    }

    // MARK: text/plain 맞추기

    private struct Span {
        let lastLine: Int
        /// 화면 글자의 마지막 글자 뒤(뒤따르는 U+200B·U+2061–2064 포함)다.
        let echoEnd: String.Index
    }

    /// 토큰 목록이 `first`부터의 연속된 줄과 같고 바로 뒤에 화면 글자가 올 때만 맞춘다.
    private static func match(_ formula: Formula, at first: Int, in lines: [Substring], keys: [String]) -> Span? {
        let end = first + formula.tokens.count
        guard end < lines.count, keys[first..<end].elementsEqual(formula.tokens),
              let echo = echo(of: formula.glyphs, in: lines, from: end)
        else { return nil }
        return Span(lastLine: echo.line, echoEnd: echo.end)
    }

    /// 토큰 줄 바로 뒤의 글자가 같은 글자 묶음이면 그 끝을 돌려준다. 빈 줄(문단 경계)은 넘지 않는다.
    private static func echo(of glyphs: [UInt32], in lines: [Substring], from start: Int) -> (line: Int, end: String.Index)? {
        var found: [UInt32] = []
        var line = start
        while line < lines.count, line < start + echoLineLimit, !lines[line].isEmpty {
            let scalars = lines[line].unicodeScalars
            var index = scalars.startIndex
            while index < scalars.endIndex {
                let scalar = scalars[index]
                index = scalars.index(after: index)
                guard !isSpaceOrInvisible(scalar) else { continue }
                found.append(scalar.value)
                if found.count == glyphs.count {
                    guard found.sorted() == glyphs else { return nil }
                    while index < scalars.endIndex, isInvisible(scalars[index]) {
                        index = scalars.index(after: index)
                    }
                    return (line, index)
                }
            }
            line += 1
        }
        return nil
    }

    /// Chrome은 토큰 줄의 앞뒤 공백을 접고 U+00A0을 공백으로 쓴다.
    private static func lineKey<S: StringProtocol>(_ text: S) -> String {
        let characters = text.map { $0 == "\u{00A0}" ? " " : $0 }
        guard let first = characters.firstIndex(where: { $0 != " " && $0 != "\t" }),
              let last = characters.lastIndex(where: { $0 != " " && $0 != "\t" })
        else { return "" }
        return String(characters[first...last])
    }

    /// 인라인 수식이 앞 줄에 이어지는 자리: 앞 글자 뒤 공백, 여는 괄호·따옴표.
    private static func precedesInlineMath(_ character: Character) -> Bool {
        character == " " || character == "\u{00A0}" || character.unicodeScalars.allSatisfy {
            $0.properties.generalCategory == .openPunctuation || $0.properties.generalCategory == .initialPunctuation
        }
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200B}" || (0x2061...0x2064).contains(scalar.value)
    }

    private static func isSpaceOrInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || isInvisible(scalar)
    }

    private static func wordCounts<S: StringProtocol>(_ text: S) -> [String: Int] {
        text.split { !$0.isLetter }.reduce(into: [:]) { counts, word in
            if word.count >= 3 { counts[String(word), default: 0] += 1 }
        }
    }

    // MARK: MathML → 유니코드 선형식 ("T ∝ √(L/g)", "3 m + 2 s", "∑_(i=1)^n i = (n(n + 1))/2")

    private static let tokenNames: Set<String> = ["mi", "mn", "mo", "mtext"]
    private static let hiddenNames: Set<String> = ["annotation", "annotation-xml", "mphantom", "none", "mprescripts"]

    private static func elements(_ node: XMLNode) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }
    }

    /// 화면에 그려지는 토큰만 순서대로 모은다. 공백만 있는 토큰은 Chrome이 줄을 만들지 않는다.
    private static func collectTokens(_ element: XMLElement, into tokens: inout [String]) {
        let name = element.localName ?? ""
        guard !hiddenNames.contains(name) else { return }
        if tokenNames.contains(name) {
            let text = element.stringValue ?? ""
            if !text.allSatisfy({ " \t\n\r".contains($0) }) { tokens.append(text) }
            return
        }
        for child in elements(element) { collectTokens(child, into: &tokens) }
    }

    private struct Piece {
        var text: String
        var op: String?
        var isLargeOperator = false
        var isFraction = false
        /// 첨자가 붙은 항(x², a_i)은 분수의 한쪽으로 괄호 없이 쓴다.
        var isScripted = false
    }

    private static let infixOperators: Set<String> = [
        "=", "≠", "<", ">", "≤", "≥", "≦", "≧", "≪", "≫", "≈", "≡", "≢", "∝", "∼", "≃", "≅", "≐", "≺", "≻", "⪯", "⪰",
        "→", "←", "↔", "⇒", "⇐", "⇔", "⟶", "⟹", "⟺", "↦", "⟼", "↪", "∈", "∉", "∋", "⊂", "⊆", "⊃", "⊇", "⊊", "⊋", "⊄",
        "+", "−", "-", "×", "·", "⋅", "÷", "±", "∓", "∘", "⊕", "⊗", "⊙", "∧", "∨", "∩", "∪", "∖", "⊢", "⊨", "⊥", "∣",
        ":=", "≔", "≝", "≜", "⋯", "…", "∗", "⋆", "⊔", "⊓", "⇝", "∥", "⊏", "⊑", "⊐", "⊒", "⨯",
    ]
    private static let relations: Set<String> = [
        "=", "≠", "<", ">", "≤", "≥", "≈", "≡", "∝", "∼", "≃", "≅", "→", "⇒", "⇔", "↦", "∈", "∉", "⊂", "⊆", "⊃", "⊇", ":=", "≔", "⟹", "⟺",
    ]
    private static let openFences: Set<String> = ["(", "[", "{", "⟨", "⌊", "⌈", "⟦", "‖", "|"]
    private static let closeFences: Set<String> = [")", "]", "}", "⟩", "⌋", "⌉", "⟧"]

    private static func closesGroup(_ character: Character) -> Bool {
        closeFences.contains(String(character)) || "|‖∥∣".contains(character)
    }
    private static let largeOperators: Set<String> = ["∑", "∏", "∐", "∫", "∬", "∭", "∮", "⋃", "⋂", "⨁", "⨂", "⋁", "⋀", "lim", "max", "min", "sup", "inf"]
    private static let functionNames: Set<String> = [
        "sin", "cos", "tan", "log", "ln", "exp", "det", "dim", "ker", "deg", "gcd", "arg", "sec", "csc", "cot", "sinh", "cosh", "tanh", "Pr", "lg", "hom", "mod",
    ]
    private static let accents: [String: String] = [
        "^": "\u{0302}", "ˆ": "\u{0302}", "~": "\u{0303}", "˜": "\u{0303}", "¯": "\u{0304}", "‾": "\u{0305}", "−": "\u{0304}",
        "→": "\u{20D7}", "⃗": "\u{20D7}", "˙": "\u{0307}", ".": "\u{0307}", "¨": "\u{0308}", "´": "\u{0301}", "`": "\u{0300}",
        "˘": "\u{0306}", "ˇ": "\u{030C}", "˚": "\u{030A}", "ˊ": "\u{0301}", "ˋ": "\u{0300}", "ˉ": "\u{0304}",
    ]
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "−": "⁻", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
    ]

    private static func lin(_ element: XMLElement) -> Piece {
        let children = elements(element)
        switch element.localName ?? "" {
        case let name where hiddenNames.contains(name):
            return Piece(text: "")
        case "mi", "mn", "mtext":
            return Piece(text: tokenText(element))
        case "mo":
            let text = tokenText(element)
            return Piece(text: text, op: text, isLargeOperator: largeOperators.contains(text))
        case "mspace":
            return Piece(text: " ", op: " ")
        case "msqrt":
            return Piece(text: "√" + parenthesized(row(children).text))
        case "mroot" where children.count >= 2:
            let index = lin(children[1]).text
            let sign = index == "3" ? "∛" : index == "4" ? "∜" : "√[\(index)]"
            return Piece(text: sign + parenthesized(lin(children[0]).text))
        case "mfrac" where children.count >= 2:
            let numerator = lin(children[0]), denominator = lin(children[1])
            let thickness = (element.attribute(forName: "linethickness")?.stringValue ?? "").filter { $0 != " " }
            if ["0", "0px", "0em", "0.0em"].contains(thickness) {   // \binom
                return Piece(text: "binom(\(numerator.text), \(denominator.text))")
            }
            return Piece(text: fractionPart(numerator) + "/" + fractionPart(denominator), isFraction: true)
        case "msup" where children.count >= 2:
            let base = lin(children[0])
            return Piece(text: baseText(base) + superscriptText(lin(children[1]).text), isLargeOperator: base.isLargeOperator, isScripted: true)
        case "msub" where children.count >= 2:
            let base = lin(children[0])
            return Piece(text: baseText(base) + subscriptText(lin(children[1]).text), isLargeOperator: base.isLargeOperator, isScripted: true)
        case "msubsup" where children.count >= 3, "munderover" where children.count >= 3:
            let base = lin(children[0])
            let scripts = subscriptText(lin(children[1]).text) + superscriptText(lin(children[2]).text)
            return Piece(text: baseText(base) + scripts, isLargeOperator: base.isLargeOperator, isScripted: true)
        case "munder" where children.count >= 2:
            let base = lin(children[0]), under = lin(children[1]).text
            if ["_", "̲", "⏟", "‾", "¯"].contains(under) { return base }
            return Piece(text: baseText(base) + subscriptText(under), isLargeOperator: base.isLargeOperator || largeOperators.contains(base.text))
        case "mover" where children.count >= 2:
            let base = lin(children[0]), over = lin(children[1]).text
            if let mark = accents[over] {
                return Piece(text: (base.text.count == 1 ? base.text : parenthesized(base.text)) + mark)
            }
            if over == "⏞" { return base }
            return Piece(text: baseText(base) + "^" + parenthesized(compact(over)), isLargeOperator: base.isLargeOperator)
        case "mtable":
            // aligned 같은 정렬 표는 한 식을 &로 나눈 것이라 칸을 공백으로 잇는다. 행렬은 칸을 쉼표로 나눈다.
            let align = element.attribute(forName: "columnalign")?.stringValue ?? ""
            let aligned = align.hasPrefix("right left") || align.hasPrefix("right center left")
            let rows = children.filter { $0.localName == "mtr" || $0.localName == "mlabeledtr" }.map { tableRow in
                elements(tableRow).enumerated().compactMap { column, cell -> String? in
                    guard cell.localName == "mtd", !(tableRow.localName == "mlabeledtr" && column == 0) else { return nil }
                    let text = row(elements(cell)).text
                    return text.isEmpty ? nil : text
                }.joined(separator: aligned ? " " : ", ")
            }
            return Piece(text: rows.joined(separator: "; "))
        default:   // math, semantics, mrow, mstyle, mpadded, menclose 등
            return row(children)
        }
    }

    /// 형제 요소를 잇는다. 이항 연산자·관계 앞뒤와 쉼표 뒤에 공백을 둔다.
    private static func row(_ children: [XMLElement]) -> Piece {
        var pieces = children.map { ($0, lin($0)) }.filter {
            !$0.1.text.isEmpty && !["\u{2062}", "\u{2063}", "\u{2064}"].contains($0.1.op ?? "")
        }
        // 첨자의 밑(\log_2, \sin^2)에 든 함수 적용 기호는 뒤에 인자가 없다. 남기면 밑이 "(log )"가 된다.
        if pieces.count > 1, pieces.last?.1.op == "\u{2061}" { pieces.removeLast() }
        if pieces.count == 1 { return pieces[0].1 }
        // 다른 항과 붙은 분수는 괄호로 묶는다("(1/2)mv²").
        for index in pieces.indices where pieces[index].1.isFraction {
            let previous = index > 0 && pieces[index - 1].1.op == nil
            let next = index + 1 < pieces.count && pieces[index + 1].1.op == nil
            if previous || next {
                pieces[index].1.text = "(" + pieces[index].1.text + ")"
                pieces[index].1.isFraction = false
            }
        }
        var text = ""
        var afterOperand = false
        var afterLargeOperator = false
        var afterFunctionName = false
        var afterScript = false
        func trimTrailingSpaces() { while text.hasSuffix(" ") { text.removeLast() } }
        for (index, (element, piece)) in pieces.enumerated() {
            let isLast = index + 1 == pieces.count
            guard let op = piece.op else {
                let isFunctionName = element.localName == "mi" && functionNames.contains(piece.text)
                // 첨자 뒤 항은 띄운다("A^T A", "u_n v_n", "sin² x"). 붙이면 첨자가 이어지는 것처럼 읽힌다.
                // 첨자가 붙은 닫는 괄호는 항이 아니라 앞 항에 붙인다("(x − x_0)²", "∥w − w*∥²").
                let needsSpace = (afterLargeOperator || afterFunctionName) && !piece.text.hasPrefix("(")
                    || (isFunctionName || piece.isLargeOperator) && afterOperand
                    || afterScript && !(piece.text.first.map(closesGroup) ?? false)
                if needsSpace && !text.isEmpty && !text.hasSuffix(" ") { text += " " }
                text += piece.text
                afterOperand = true
                afterLargeOperator = piece.isLargeOperator
                afterFunctionName = isFunctionName
                afterScript = piece.isScripted && !piece.isLargeOperator
                continue
            }
            afterScript = false
            switch op {
            case "\u{2061}":   // 함수 적용: "sin x", "f(x)"
                let next = isLast ? "" : pieces[index + 1].1.text
                if !next.hasPrefix("(") && !next.hasPrefix("[") && !text.hasSuffix(" ") { text += " " }
                afterOperand = false
                afterFunctionName = false
                continue
            case " ":
                if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
                continue
            case ",", ";":
                trimTrailingSpaces()
                text += op + " "
                afterOperand = false
                continue
            default:
                break
            }
            afterFunctionName = false
            if piece.isLargeOperator {
                if afterOperand && !text.isEmpty && !text.hasSuffix(" ") { text += " " }
                text += op
                afterLargeOperator = true
                afterOperand = false
            } else if openFences.contains(op) && !(op == "|" && afterOperand) {
                if afterLargeOperator && !text.hasSuffix(" ") { text += " " }
                text += op
                afterOperand = false
                afterLargeOperator = false
            } else if closeFences.contains(op) || op == "|" {
                trimTrailingSpaces()
                text += op
                afterOperand = true
            } else if infixOperators.contains(op) || op.count > 1 {
                if !isLast && (afterOperand || relations.contains(op)) {
                    // 이항 연산자와 관계, 정렬 칸 맨 앞의 관계("= −mg")
                    if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
                    text += op + " "
                } else {
                    if afterLargeOperator && !text.hasSuffix(" ") { text += " " }
                    text += op   // 단항(−x)이나 연산자 하나
                }
                afterOperand = false
                afterLargeOperator = false
            } else {
                text += op   // "/", "!", "′" 등
                afterOperand = ["!", "′", "″", "'"].contains(op)
            }
        }
        return Piece(text: text, isLargeOperator: pieces.last?.1.isLargeOperator ?? false)
    }

    private static func tokenText(_ element: XMLElement) -> String {
        let text = String(foldingMathAlphanumerics(element.stringValue ?? "").compactMap { character -> Character? in
            switch character {
            case "\u{200B}": return nil
            case "\u{2009}", "\u{2005}", "\u{2004}", "\u{2006}", "\u{2002}", "\u{2003}", "\u{00A0}", "\u{205F}", "\u{200A}", "\n", "\t": return " "
            default: return character
            }
        })
        return element.localName == "mtext" ? text : text.trimmingCharacters(in: .whitespaces)
    }

    private static func parenthesized(_ text: String) -> String {
        if isAtomic(text) || text.hasPrefix("(") && text.hasSuffix(")") && closesAtEnd(text) { return text }
        return "(" + text + ")"
    }

    private static func fractionPart(_ piece: Piece) -> String {
        piece.isScripted && !piece.isLargeOperator ? piece.text : parenthesized(piece.text)
    }

    private static func baseText(_ piece: Piece) -> String {
        if piece.isLargeOperator || isAtomic(piece.text) || piece.text.last.map(")]|}".contains) == true { return piece.text }
        return "(" + piece.text + ")"
    }

    /// 첨자는 공백 없이 쓴다("∑_(i=1)^n").
    private static func compact(_ text: String) -> String {
        text.filter { $0 != " " }
    }

    private static func superscriptText(_ script: String) -> String {
        let text = compact(script)
        if !text.isEmpty, text.allSatisfy({ superscripts[$0] != nil }) { return String(text.compactMap { superscripts[$0] }) }
        if text.allSatisfy({ "′″‴'".contains($0) }) { return text }
        if text == "∗" || text == "*" { return "*" }
        // 글자 둘 이상의 위첨자는 곱이라 묶는다(e^(iπ), x^(ab)).
        return "^" + (text.count > 1 && text.allSatisfy(\.isLetter) ? "(" + text + ")" : parenthesized(text))
    }

    private static func subscriptText(_ script: String) -> String {
        "_" + parenthesized(compact(script))
    }

    private static func isAtomic(_ text: String) -> Bool {
        text.count <= 1 || text.allSatisfy { $0.isNumber || $0 == "." } || text.allSatisfy(\.isLetter)
            || text.hasPrefix("√") && isAtomic(String(text.dropFirst()))
    }

    /// 맨 앞 여는 괄호가 맨 끝에서 닫히는지 본다("(a)(b)"는 아니다).
    private static func closesAtEnd(_ text: String) -> Bool {
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 && offset < text.count - 1 { return false }
            }
        }
        return depth == 0
    }

    private static func finish(_ text: String) -> String {
        var text = String(String.UnicodeScalarView(text.unicodeScalars.filter { !isInvisible($0) }))
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// 수학 이탤릭·굵은 글자(𝑇 𝐿 𝜋)를 일반 글자로 바꾼다. 뜻이 있는 필기체·프락투어·겹선 글자(ℝ 𝔽 𝒜)는 둔다.
    private static func foldingMathAlphanumerics(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x1D400...0x1D7FF).contains($0.value) }) else { return text }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let meaningful = (0x1D49C...0x1D59F).contains(value) || (0x1D7D8...0x1D7E1).contains(value)
            if (0x1D400...0x1D7FF).contains(value) && !meaningful {
                scalars.append(contentsOf: String(scalar).precomposedStringWithCompatibilityMapping.unicodeScalars)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
