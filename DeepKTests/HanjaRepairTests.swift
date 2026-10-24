import Foundation

/// 한국어 결과에 섞인 한자 치환(HanjaReading·HanjaRepair)과 코드 판정(TranslationOutputLint.CodeScanner).
@main
private enum HanjaRepairTests {
    static func main() {
        readingTable()
        substitution()
        soundRules()
        protectedSourceHan()
        codeIsNeverTouched()
        scopeGuard()
        unreadableHanIsKept()
        parenthesizedGlossesAreKept()
        chineseAndJapaneseAfterKoreanAreKept()
        streamWithholdsUndecidedTails()
        prefixAndLengthProperties()
        scannerAgreesWithTranslationMarkup()
        scannerAgreesOnShuffledLines()
        print("HanjaRepairTests passed")
    }

    private static let repair = HanjaRepair(protecting: [])

    private static func repaired(_ text: String, protecting sources: [String] = []) -> String {
        HanjaRepair(protecting: sources).apply(to: text).text
    }

    private static func readingTable() {
        require(HanjaReading.parse(HanjaReadingData.rows).count == HanjaReading.entryCount, "the generated table covers U+3400–4DBF and U+4E00–9FFF")
        require(HanjaReadingData.unicodeVersion == "18.0.0", "the table records its Unicode version")
        let expected: [(Character, Character)] = [
            ("确", "확"), ("確", "확"), ("保", "보"), ("点", "점"), ("量", "량"), ("李", "리"), ("不", "불"), ("樂", "락"), ("率", "률"), ("金", "금"),
            // 번체 여러 글자를 합친 간체는 중국어에서 흔한 쪽의 독음(scripts/generate-hanja-readings.py MERGED)
            ("征", "징"), ("于", "어"), ("么", "마"), ("净", "정")
        ]
        for (han, reading) in expected {
            let actual = HanjaReading.reading(of: han.unicodeScalars.first!).map { Character($0) }
            require(actual == reading, "\(han) reads \(reading), got \(String(describing: actual))")
        }
        require(HanjaReading.reading(of: "A") == nil && HanjaReading.reading(of: "가") == nil, "only Han has a reading")
    }

    private static func substitution() {
        let cases = [
            ("보안이 确保된 연결", "보안이 확보된 연결"),
            ("궁금한 点이 있으면", "궁금한 점이 있으면"),
            ("보안이 <a1>确保</a1>된 연결", "보안이 <a1>확보</a1>된 연결"),
            ("```\nx\n```\n确保하세요", "```\nx\n```\n확보하세요"),
            ("确保 방법", "확보 방법"),
            ("제품의 特征을 설명", "제품의 특징을 설명"), ("이 문제에 关于", "이 문제에 관어"), ("什么가 문제인가", "십마가 문제인가"), ("방이 干净하다", "방이 간정하다")
        ]
        for (input, output) in cases {
            require(repaired(input) == output, "\(input) → \(output), got \(repaired(input))")
        }
        let counts = repair.apply(to: "보안이 确保된 연결").counts
        require(counts == HanjaRepair.Counts(replaced: 2), "two characters were replaced: \(counts)")
    }

    /// 두음법칙, 모음·ㄴ 받침 뒤의 렬·률, 不의 부·불.
    private static func soundRules() {
        let cases = [
            ("量이 많다", "양이 많다"), ("사용量", "사용량"), ("사용량(量이 많음)", "사용량(양이 많음)"), ("2015年에", "2015년에"), ("年末에", "연말에"),
            ("비率", "비율"), ("선律", "선율"), ("확率", "확률"),
            ("자원이 不足", "자원이 부족"), ("마음이 不安하다", "마음이 불안하다"), ("不正한", "부정한"), ("자원이 不", "자원이 불"), ("不당한", "부당한")
        ]
        for (input, output) in cases {
            require(repaired(input) == output, "\(input) → \(output), got \(repaired(input))")
        }
        require(HanjaReading.wordInitial("량") == "양" && HanjaReading.wordInitial("력") == "역" && HanjaReading.wordInitial("락") == "낙"
                && HanjaReading.wordInitial("로") == "노" && HanjaReading.wordInitial("녀") == "여" && HanjaReading.wordInitial("말") == "말",
                "word-initial sound rules")
        require(HanjaReading.afterSyllable(previous: "규", "률") == "율" && HanjaReading.afterSyllable(previous: "확", "률") == "률"
                && HanjaReading.afterSyllable(previous: "분", "렬") == "열", "렬·률 after a vowel or ㄴ")
    }

    /// 원문(모델 입력)에 있는 한자는 그대로 둔다. 묶음에 하나라도 있으면 묶음 전체를 둔다.
    private static func protectedSourceHan() {
        require(repaired("제목에 漢字를 쓰세요.", protecting: ["Write 漢字 in the title."]) == "제목에 漢字를 쓰세요.", "source Han is kept")
        let partly = HanjaRepair(protecting: ["保"]).apply(to: "보안이 确保된 연결")
        require(partly.text == "보안이 确保된 연결" && partly.counts == HanjaRepair.Counts(kept: 1), "a run with a source Han stays whole: \(partly)")
        require(repaired("보안이 确保된 연결", protecting: ["```\nprint('确保')\n```"]) == "보안이 确保된 연결", "Han in source code is protected too")
        // 원문 한자가 혼자이거나 묶음 첫 글자여도 둔다.
        let alone = HanjaRepair(protecting: ["Write 漢 in the title."]).apply(to: "제목에 漢을 쓰세요.")
        require(alone.text == "제목에 漢을 쓰세요." && alone.counts == HanjaRepair.Counts(), "a lone source Han is kept: \(alone)")
        let leading = HanjaRepair(protecting: ["The 人 radical."]).apply(to: "보안이 人口가 많다")
        require(leading.text == "보안이 人口가 많다" && leading.counts == HanjaRepair.Counts(kept: 1), "a run that starts with a source Han is kept: \(leading)")
    }

    /// 코드 블록, 인라인 코드, URL 안의 한자는 고치지 않고 센다. 코드 안에서 시작한 선택의 코드 줄도 그대로다.
    private static func codeIsNeverTouched() {
        for input in ["`确保` 확인", "```\n确保\n```", "```python 确保", "https://x.dev/确保 확인", "보안이 `确保`된 설정"] {
            let result = repair.apply(to: input)
            require(result.text == input && result.counts.inCode == 2 && result.counts.replaced == 0, "code is untouched: \(input) → \(result)")
        }
        let source = "  label = '保存'  # 저장 버튼\n}\n```\n\nThen save the file."
        let output = "  label = '保存'  # 저장 버튼\n}\n```\n\n그런 다음 파일을 저장하세요."
        require(repaired(output, protecting: [source]) == output, "code lines before a stray closer keep their Han")
        // 채팅식 블록(```pwd, 첫 줄이 채팅식으로 닫히는 ```node)은 그 줄에서 닫히므로 뒤의 맨 펜스 블록도 결과 창처럼 코드다.
        for chat in ["```pwd\n/home/user```", "```node\nnode -v```", "```npm install\nnpm run build```"] {
            let text = "현재 위치를 확인하세요.\n\(chat)\n아래 코드를 실행하세요.\n```\n# 确保 연결 확인\ncheck()\n```\n끝"
            let result = repair.apply(to: text)
            require(result.text == text && result.counts == HanjaRepair.Counts(inCode: 2), "Han in the block after a chat fence is code: \(chat) → \(result)")
        }
    }

    /// 4자 이하 묶음이고 결과의 앞쪽 어디든(앞 줄 포함) 한글이 있었거나 바로 뒤(공백 3개까지)가 한글이어야 고친다.
    private static func scopeGuard() {
        let chinese = repair.apply(to: "我们确保安全。")
        require(chinese.text == "我们确保安全。" && chinese.counts == HanjaRepair.Counts(kept: 6), "a Chinese sentence is kept: \(chinese)")
        require(repaired("确保。") == "确保。", "a run with no Hangul around is kept")
        require(repaired("确保    방법") == "确保    방법", "more than three spaces before the Hangul do not count")
        require(repaired("确保   방법") == "확보   방법", "up to three spaces before the Hangul count")
        require(repaired("설명\n确保.") == "설명\n확보.", "Hangul on an earlier line counts")
        let layouts = [
            ("보안 설정을 확인하세요.\n- 确保\n- 연결", "보안 설정을 확인하세요.\n- 확보\n- 연결"),
            ("다음 항목을 점검합니다.\n确保, 그리고 검증", "다음 항목을 점검합니다.\n확보, 그리고 검증"),
            ("| 항목 | 설명 |\n| 确保 | 연결 보장 |", "| 항목 | 설명 |\n| 확보 | 연결 보장 |"),
            ("## 보안\n\n### 确保\n", "## 보안\n\n### 확보\n")
        ]
        for (input, output) in layouts {
            require(repaired(input) == output, "a word alone in a list item, table cell or heading is repaired: \(input) → \(repaired(input))")
        }
        require(repaired("```\n설명\n```\n确保。") == "```\n설명\n```\n确保。", "Hangul inside code does not count")
        require(repaired("설명\n我们确保安全。") == "설명\n我们确保安全。", "a Chinese sentence after Korean is still kept")
        require(repaired("보안을 确保安全稳定하게") == "보안을 确保安全稳定하게", "a run longer than four characters is kept")
    }

    /// 괄호 안에 꼭 맞게 놓인 묶음은 한글 낱말에 붙인 한자 병기다. 독음으로 바꾸면 "예(예)"가 된다.
    private static func parenthesizedGlossesAreKept() {
        for input in ["예(禮)와 정명(正名)", "예（禮）와 정명（正名）을 함께 배운다", "사용량(量)"] {
            let result = repair.apply(to: input)
            let glosses = input.unicodeScalars.filter(TranslationOutputLint.isHan).count
            require(result.text == input && result.counts == HanjaRepair.Counts(kept: glosses), "a gloss in parentheses is kept: \(input) → \(result)")
            requireStreamMatches(input)
        }
        // 괄호에 꼭 맞지 않으면 산문이다.
        let cases = [("정명(正名이라고도 함)", "정명(정명이라고도 함)"), ("정명 正名) 끝", "정명 정명) 끝"), ("설명(确保 )", "설명(확보 )")]
        for (input, output) in cases {
            require(repaired(input) == output, "\(input) → \(output), got \(repaired(input))")
            requireStreamMatches(input)
        }
    }

    /// 한국어 뒤에 온 중국어·일본어 문장: 묶음 뒤가 가나나 전각 문장 부호, 또는 앞이 가나면 둔다.
    /// 한국어 문장은 ASCII 문장 부호를 쓰므로 "보안이 确保된", "确保."는 그대로 고친다.
    private static func chineseAndJapaneseAfterKoreanAreKept() {
        for input in ["보안 설정을 확인하세요.\n\n首先，确保安全。然后，检查日志。", "보안 설정을 확인하세요.\n\nまず、安全を確認します。",
                      "설명\n确保。", "보안 설정: 「确保」", "설명 カタカナ確保 끝", "설명 确保ー", "설명 确保　끝", "설명 确保！", "설명 确保？", "설명 确保；", "설명 确保：끝"] {
            let result = repair.apply(to: input)
            let han = input.unicodeScalars.filter(TranslationOutputLint.isHan).count
            require(result.text == input && result.counts == HanjaRepair.Counts(kept: han), "Chinese or Japanese after Korean is kept: \(input) → \(result)")
            requireStreamMatches(input)
        }
        let cases = [("보안이 确保된 연결", "보안이 확보된 연결"), ("설명\n确保.", "설명\n확보."), ("설명 确保, 그리고", "설명 확보, 그리고"),
                     ("설명 确保   。", "설명 确保   。"), ("설명 确保    。", "설명 확보    。")]
        for (input, output) in cases {
            require(repaired(input) == output, "\(input) → \(output), got \(repaired(input))")
            requireStreamMatches(input)
        }
    }

    /// 글자 단위 조각마다 보이는 글은 앞 글에 덧붙기만 하고 완료 결과의 앞부분이며, 판정할 글자가 이미 있으면 완료 결과와 같다.
    private static func requireStreamMatches(_ text: String) {
        let final = repair.apply(to: text).text
        var stream = HanjaRepair.Stream(repair)
        var previous = ""
        var prefix = ""
        for scalar in text.unicodeScalars {
            prefix.unicodeScalars.append(scalar)
            let shown = stream.repairedPrefix(of: prefix)
            require(shown.unicodeScalars.starts(with: previous.unicodeScalars) && final.unicodeScalars.starts(with: shown.unicodeScalars),
                    "the stream only grows and stays a prefix of the final repair: \(prefix) → \(shown)")
            previous = shown
        }
        var whole = HanjaRepair.Stream(repair)
        require(whole.repairedPrefix(of: text + "\n") == final + "\n", "a decided stream equals the final repair: \(text)")
    }

    private static func unreadableHanIsKept() {
        let unreadable = (0x4E00...0x9FFF).lazy.compactMap { Unicode.Scalar(UInt32($0)) }.first { HanjaReading.reading(of: $0) == nil }!
        let input = "보안이 " + String(Character(unreadable)) + "된 연결"
        let result = repair.apply(to: input)
        require(result.text == input && result.counts == HanjaRepair.Counts(unreadable: 1), "a Han without a reading is kept and counted: \(result)")
    }

    /// 판정이 남은 끝 묶음은 다음 조각까지 보이지 않는다. 한자가 없으면 늦추지 않는다.
    private static func streamWithholdsUndecidedTails() {
        var stream = HanjaRepair.Stream(repair)
        let steps = [
            ("보안이 ", "보안이 "), ("보안이 确", "보안이 "), ("보안이 确保", "보안이 "), ("보안이 确保된", "보안이 확보된"), ("보안이 确保된 연결", "보안이 확보된 연결")
        ]
        for (snapshot, shown) in steps {
            let actual = stream.repairedPrefix(of: snapshot)
            require(actual == shown, "\(snapshot) shows \(shown), got \(actual)")
        }
        var tail = HanjaRepair.Stream(repair)
        require(tail.repairedPrefix(of: "자원이 不") == "자원이 ", "a trailing 不 waits for its next syllable")
        require(repaired("자원이 不") == "자원이 불", "a final trailing 不 reads 불")
        var waiting = HanjaRepair.Stream(repair)
        require(waiting.repairedPrefix(of: "确保  ") == "", "a run waiting for the next Hangul is withheld with its spaces")
        require(waiting.repairedPrefix(of: "确保  방법") == "확보  방법", "the next Hangul decides the run")
        var plain = HanjaRepair.Stream(repair)
        require(plain.repairedPrefix(of: "한자가 없는 글") == "한자가 없는 글", "text without Han is never delayed")
        require(plain.repairedPrefix(of: "다른 글") == "다른 글", "a snapshot that does not extend the last one starts over")
    }

    private static let corpus = [
        "보안이 确保된 연결이 필요합니다. 궁금한 点이 있으면 문의하세요.",
        "年末에 사용量을 확인하고 비率과 확率을 비교합니다.",
        "자원이 不足하고 마음이 不安합니다. 不",
        "```python\nprint('确保')\n```\n确保하세요 `点` https://x.dev/确保 보안이 <a1>确保</a1>된",
        "我们确保安全。\n确保    방법\n确保 방법\r\n보안을 确保安全稳定하게",
        "  label = '保存'\n}\n```\n\n그런 다음 保存하세요.",
        "2015年 😀 사용量 (量) 不足",
        "````md\n```\n确保\n```\n````\n끝에 确保",
        "설명\n```pwd\n/home/确保```\n确保하세요\n```\n确保\n```\n- 确保",
        "설명\n```\n\n````md\n```\n确保 산문\n````\n确保",
        "예(禮)와 정명(正名) (量 ) （量）\n\n首先，确保安全。まず、安全を確認します。确保 . 确保  ？"
    ]

    /// (a) 조각마다 보이는 글은 앞 글에 덧붙기만 하고 완료 결과의 앞부분이다. (b) UTF-16 길이가 같다. (c) ASCII는 그대로다.
    private static func prefixAndLengthProperties() {
        for text in corpus {
            let final = repair.apply(to: text).text
            require(final.utf16.count == text.utf16.count, "repair keeps the UTF-16 length: \(text)")
            for (before, after) in zip(text.unicodeScalars, final.unicodeScalars) where before.isASCII {
                require(before == after, "repair never changes ASCII: \(text)")
            }
            var stream = HanjaRepair.Stream(repair)
            var previous = ""
            var prefix = ""
            for scalar in text.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                let shown = stream.repairedPrefix(of: prefix)
                require(shown.unicodeScalars.starts(with: previous.unicodeScalars), "streamed text only grows: \(prefix)")
                require(final.unicodeScalars.starts(with: shown.unicodeScalars), "streamed text is a prefix of the final repair: \(prefix)")
                previous = shown
            }
        }
    }

    /// 최종 모드는 펜스 짝을 `TranslationMarkup`처럼 읽고, 인과 모드는 그보다 넓게 코드로 본다.
    private static func scannerAgreesWithTranslationMarkup() {
        let fixtures = [
            "설명\n```swift\nlet a = 1\n```\n다음 문단",
            "번역문 단락\n```",
            "  return x\n```\n\n그 다음 설명입니다.\n",
            "  return x\n```\n그 다음 설명\n```bash\nnpm test\n```\n끝",
            "````md\n```js\ninner\n```\n````\n끝",
            "```\n\n산문\n```js\ncode\n```\n산문2",
            "```npm install\nnpm run build```\n다음 산문",
            "산문\n```\n코드\n```\n```\n",
            "```python\nprint(1)\n",
            "```\n\n```\n산문",
            "   ```\n들여쓴 코드\n   ```\n산문",
            "```js title=\"a.js\"\nconst a = 1;\n```\n산문",
            "~~~\n틸드\n~~~\n산문",
            "산문\r\n```\r\ncode\r\n```\r\n끝\r\n",
            "앞\n```\n가\n```\n중간\n```\n나\n```\n뒤",
            "    들여쓴 네 칸 ```\n산문",
            // 아는 명령, 첫 코드 줄이 채팅식으로 닫히는 모르는 이름, 닫는 줄이 먼저 오는 이름, 코드가 이어지는 이름
            "현재 위치\n```pwd\n/home/user```\n아래 코드\n```\n# 확인\ncheck()\n```\n끝",
            "버전\n```node\nnode -v```\n아래 코드\n```\nconnect()\n```\n끝",
            "배포\n```deploy\n```\n산문\n```\n코드\n```\n끝",
            "설정\n```nginx\n\nserver {}\n```\n산문",
            "설정\n```console\n$ ls```\n산문\n```\n코드\n```\n끝",
            // 따옴표 없는 속성은 정보 문자열이 아니라 코드다. 낱말 안의 기호(/impeccable)도 코드다.
            "```js title=a.js\nconst a = 1;```\n산문\n```\n코드\n```\n끝",
            "```/impeccable document\n```\n산문",
            "```/impeccable\n/impeccable document```\n산문",
            // 빈 줄 뒤 정보 문자열 펜스가 먼저 오면 앞의 맨 펜스는 스트레이다(더 긴 펜스 안의 짧은 닫는 줄은 코드).
            "```\n \n````md\n```\n산문 하나",
            "```\n\n````text\n```bash\nnpm i\n```\n설명 줄\n````\n끝"
        ]
        fixtures.forEach(requireAgreement)
        // 복제한 태그 목록은 `TranslationMarkup`의 목록과 같다.
        let missing = TranslationMarkup.knownLanguageTags.symmetricDifference(TranslationOutputLint.CodeScanner.languageTags)
        require(missing.isEmpty, "the tag lists differ: \(missing.sorted())")
        // 복제한 목록의 낱말마다: 태그면 채팅식 줄에서 닫히지 않고, 명령이면 코드가 이어진 뒤에도 채팅식 줄에서 닫힌다.
        for tag in TranslationOutputLint.CodeScanner.languageTags { requireAgreement("```\(tag)\nx```\n산문") }
        for command in TranslationOutputLint.CodeScanner.commands { requireAgreement("```\(command)\nls -la\nfoo```\n산문") }
    }

    /// 펜스·코드·산문 줄 조각을 무작위로(고정 씨앗) 이어 붙인 글에서도 같다. 가져오기가 펜스에 쓰는 태그(console, terminal,
    /// shell-session)도 넣어 두어 한쪽 태그 목록만 바뀌면 여기서 드러난다.
    private static func scannerAgreesOnShuffledLines() {
        let pieces = [
            "```", "````", "`````", "   ```", "  ````md", "```js", "```JS", "```C#", "```text", "```js\r", "```\t",
            "```console", "```terminal", "```shell-session", "```pwd", "  ```pwd", "```node", "```node\r", "```deploy",
            "```npm install", "```ls -la", "```python main.py", "```ts {1,3}", "```js {1}", "```js title=\"a.js\"",
            "```js title=a.js", "```js showLineNumbers", "````md", "```{.py}", "```/impeccable", "```lang:file.js", "~~~",
            "x = 1", "foo```", "x```\r", "node -v```", "ls -la```", "npm run build```", "a ````", "", "", " ", "\u{00A0}",
            "산문 하나", "确保 방법", "다른 산문", "끝 줄\r"
        ]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Int(state % UInt64(bound))
        }
        for _ in 0..<20_000 {
            requireAgreement((0...next(12)).map { _ in pieces[next(pieces.count)] }.joined(separator: "\n"))
        }
    }

    private static func requireAgreement(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        let final = TranslationOutputLint.CodeScanner.codeMask(final: scalars)
        var scanner = TranslationOutputLint.CodeScanner(urls: false)
        let causal = scalars.map { scanner.isCode($0) }
        require(final.count == scalars.count, "one decision per scalar: \(text.debugDescription)")
        // 공백은 어느 쪽이든 빈칸 하나라 비교하지 않는다(펜스 줄의 들여쓰기는 백틱이 오기 전에 정해진다).
        for (index, code) in final.enumerated() where code && !scalars[index].properties.isWhitespace {
            require(causal[index], "causal mode marks at least the final mode's code: \(text.debugDescription) at \(index)")
        }
        var lines: [String] = []
        var line = String.UnicodeScalarView()
        var lineIsProse = true
        for (scalar, code) in zip(scalars, final) {
            if scalar == "\n" {
                if lineIsProse { lines.append(String(line)) }
                line = String.UnicodeScalarView()
                lineIsProse = true
            } else {
                line.append(scalar)
                if code { lineIsProse = false }
            }
        }
        if lineIsProse { lines.append(String(line)) }
        let markup = TranslationMarkup(text)
        let display = markup.displayText as NSString
        let markupProse = markup.blocks.filter { $0.fence == nil }.map { display.substring(with: $0.range) }.joined()
        require(nonBlankLines(lines.joined(separator: "\n")) == nonBlankLines(markupProse),
                "final mode prose matches TranslationMarkup: \(text.debugDescription)\n\(lines) vs \(markupProse.debugDescription)")
    }

    private static func nonBlankLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("HanjaRepairTests failed: \(message)") }
    }
}
