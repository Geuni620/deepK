import Foundation

@main
private enum TranslationMarkupTests {
    static func main() {
        identity()
        recognition()
        normalization()
        streamingMonotonicity()
        exports()
        inlineRecognition()
        inlineStreaming()
        inlineReview()
        reviewFollowUps()
        secondReview()
        fenceFuzz()
        thirdReview()
        fourthReview()
        singleWordCommands()
        unknownNames()
        lineLayout()
        copiedBlocks()
        listStructure()
        inlineCodeMarkersStayLiteral()
        print("TranslationMarkupTests passed")
    }

    private static func listStructure() {
        let source = "3. 첫째 😀\n  - `child` <a1>링크</a1>\n7. 둘째\n\n문단\n\n```text\n- literal code\n```"
        let link = SourceLink(url: URL(string: "https://example.com/path")!, text: "link")
        let markup = TranslationMarkup(source, inline: InlineOptions(code: .any, links: [link]))
        let items = markup.lists.items
        require(items.count == 3 && items.map(\.depth) == [0, 1, 0] && items[1].parent == 0,
                "literal list structure has parents and UTF-16 ranges, excluding fenced code")
        require(items[0].marker.number == 3 && items[2].marker.number == 7, "actual start and discontinuous values are retained")
        let html = markup.html
        require(html.contains("<ol start=\"3\"><li value=\"3\">첫째 😀<ul><li><code>child</code> <a href=\"https://example.com/path\">링크</a></li></ul></li><li value=\"7\">둘째</li></ol>"),
                "semantic HTML keeps nested items, numbering, chips and links: \(html)")
        require(html.contains("<pre ") && html.contains("<code class=\"language-text\">- literal code</code>"),
                "code that looks like a list stays code")
        let plain = "3. 첫째 😀\n  - child 링크\n7. 둘째\n\n문단\n\n- literal code"
        require(markup.displayText == plain, "visible text keeps every literal marker")
        let all = NSRange(location: 0, length: markup.displayText.utf16.count)
        require(markup.plainText(in: all, fences: .none) == "3. 첫째 😀\n  - `child` 링크\n7. 둘째\n\n문단\n\n- literal code",
                "plain copies keep markers and the source's backtick policy")
        require(markup.markdown(in: all).contains("3. 첫째 😀\n  - `child` [링크](https://example.com/path)\n7. 둘째"),
                "markdown preserves literal nesting and actual numbering")
        let text = markup.displayText as NSString
        let bodyOnly = text.range(of: "첫째 😀")
        require(markup.html(in: bodyOnly) == "<meta charset=\"utf-8\"><p>첫째 😀</p>",
                "a selection without its marker never invents a list")
        let nested = NSRange(location: items[1].markerRange.location, length: NSMaxRange(items[1].contentRange) - items[1].markerRange.location)
        require(markup.html(in: nested).contains("<ul><li><code>child</code> ") && !markup.html(in: nested).contains("<ol"),
                "a selected child without its parent starts a standalone list")
        let tail = NSRange(location: items[2].range.location, length: 5)
        require(markup.html(in: tail) == "<meta charset=\"utf-8\"><ol start=\"7\"><li value=\"7\">둘째</li></ol>",
                "partial-list copy starts at the selected item's actual number")
        let continuation = TranslationMarkup("- First\n  wraps explicitly\n  - Child\n  parent again\n- Next")
        require(continuation.html.contains("<ul><li>First<br>wraps explicitly<ul><li>Child</li></ul><br>parent again</li><li>Next</li></ul>"),
                "continuations attach to their owning item without extra markers: \(continuation.html)")
        let prose = TranslationMarkup("The - character is punctuation.\n\n    - indented code\n\n* * *\n\n~~~text\n- fenced tilde code\n~~~")
        require(!prose.containsLists && !prose.html.contains("<ul>"), "prose, thematic rules and indented/fenced code never become lists")
        let signed = TranslationMarkup("-2. Before zero\n-1. Retry\n0. Zero\n+7) Positive")
        require(signed.lists.items.compactMap { $0.marker.number } == [-2, -1, 0, 7]
                && signed.html.contains("<ol start=\"-2\">") && signed.html.contains("<li value=\"7\">"),
                "signed, zero and reversed HTML counters retain their actual values")
        let empty = TranslationMarkup("- One\n- Two\n-")
        require(empty.lists.items.count == 3 && empty.html.contains("<li></li>"), "an empty trailing item keeps its marker")
    }

    private static func inlineCodeMarkersStayLiteral() {
        for content in ["- literal item", "1. literal item"] {
            for options in [InlineOptions(code: .any), InlineOptions(code: .only([content]))] {
                let markup = TranslationMarkup("`" + content + "`", inline: options)
                require(markup.spans.filter { $0.kind == .code }.count == 1 && !markup.containsLists,
                        "a marker inside inline code stays literal")
                require(markup.html.contains("<code>" + content + "</code>") && !markup.html.contains("<li"),
                        "rich copy keeps the complete inline code, including its apparent list marker: \(markup.html)")
                let range = NSRange(location: 0, length: markup.displayText.utf16.count)
                require(markup.markdown(in: range) == "`" + content + "`", "markdown copy keeps code delimiters and marker")
            }
        }
        let real = TranslationMarkup("- `git`", inline: InlineOptions(code: .any))
        require(real.containsLists && real.html.contains("<ul><li><code>git</code></li></ul>"),
                "inline code in an item's body does not hide a real list marker")
    }

    private static let fixtures = [
        "설명입니다 😀\n\n```swift\nlet a = 1\n```\n\n다음 문단.",
        "번역문 단락\n```",
        "```swift\na\n```\n```",
        "설명\n```js\nconst x = 1;\nconsole.log(x)",
        "````md\n```\ninner\n```\n````\n끝",
        "~~~\ntilde\n~~~\n~~취소선~~",
        "````x`\u{301}\n코드",
        "공지\n~~~~~~~~~~\n내일 회의",
        "첫 줄\r\n```ts\r\nlet a = 1\r\n```\r\n둘째 줄",
        "1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행",
        "공백 줄\n   \n```\n  \n\t\n```\n끝",
        "```a\nx\n```\n```b\ny\n```",
        "```py\nprint(1)\n  ```  \n뒤",
        "``inline`` 과 `code` 그리고 ```한줄```",
        "    ```\n    들여쓴 코드\n    ```",
        "실행:\n```npm install\nnpm run build```\n그다음 앱을 엽니다.",
        "npm install\nnpm run build\n```\n\n그다음 서버를 다시 시작합니다.",
        "명령:\nnpm i\n```\n\n다음 단계는 설정입니다.\n```bash\nls\n```",
        "```js title=\"a.js\"\nx\n```\n```{python}\ny\n```\n```c++\nz\n```",
        "실행:\n```npm install\nnpm run build\n```\n그다음 앱을 엽니다.",
        "예:\n```jsx live\n<Button />\n```\n이 예제는 버튼을 그립니다.\n\n```js\nconst a = 1\n```\n끝.",
        "설치:\n```pip install requests==2.31.0\npython app.py\n```\n\n그다음 서버를 시작합니다.",
        "실행:\n```pwd\n```\n끝",
        "실행:\n```ls\nls -la```\n끝",
        "실행:\r\n  ```project-tool\r\n  ```\r\n끝",
        "```customlang title=\"example\"\nx\n```",
        "설명:\n```console\n$ echo hi\n```\n끝",
        "```nginx\n\nserver {}\n```",
        "실행:\n```node\nnode -v```\n끝",
        "실행:\n```pwd\nls -la\n```\n끝",
        "실행:\n```http://localhost:3000\n```\n끝",
        "번역 결과입니다.\n```console",
    ]

    private static func identity() {
        for text in ["", "산문만 있는 번역입니다.", "`inline` 코드", "```code``` 한 줄", "    ```\n    네 칸", "~~취소선~~",
                     "첫 문단.\n\n둘째 문단.", "```swift\nlet a = 1\n```"] {
            require(TranslationMarkup.normalized(text) == text, "balanced text is unchanged: \(text)")
        }
        let prose = TranslationMarkup("첫 문단.\n\n둘째 문단.\n\n")
        require(prose.displayText == "첫 문단.\n\n둘째 문단." && !prose.containsCode, "prose display only trims the end")
        require(prose.blocks == [.init(kind: .prose, range: NSRange(location: 0, length: prose.displayText.utf16.count))], "prose is one block")
        require(TranslationMarkup("```code``` 한 줄").displayText == "```code``` 한 줄", "backtick info is not a fence")
        require(!TranslationMarkup("    ```\n    네 칸\n    ```").containsCode, "four-space indent is prose")
        require(!TranslationMarkup("\t```\nx\n```").containsCode, "tab before marker is prose")
        require(!TranslationMarkup("> ```\n> x").containsCode && !TranslationMarkup("- ```\nx").containsCode, "containers stay prose")
    }

    private static func recognition() {
        let text = "설명 😀\n\n```swift\nlet a = 1\n```\n\n다음"
        let markup = TranslationMarkup(text)
        require(markup.displayText == "설명 😀\n\nlet a = 1\n\n다음", "fence lines are not displayed")
        let code = markup.blocks.first { $0.fence != nil }
        require(code?.fence?.language == "swift", "language comes from the info string")
        require((markup.displayText as NSString).substring(with: code!.range) == "let a = 1\n", "UTF-16 range after Korean and emoji")
        require(markup.blocks.count == 3 && markup.blocks.first?.kind == .prose && markup.blocks.last?.kind == .prose, "prose, code, prose")

        let crlf = TranslationMarkup("첫 줄\r\n```ts\r\nlet a = 1\r\n```\r\n둘째")
        require(crlf.displayText == "첫 줄\r\nlet a = 1\r\n둘째" && crlf.blocks.count == 3, "CRLF fences")
        let tilde = TranslationMarkup("공지\n~~~~~~~~~~\n내일 회의")
        require(!tilde.containsCode && tilde.displayText == "공지\n~~~~~~~~~~\n내일 회의", "tilde lines stay prose")
        require(!TranslationMarkup("```js`\u{FE0F}\ncode\n```").blocks.contains { $0.fence?.info == "js`\u{FE0F}" }, "a backtick with a combining mark is still a backtick")
        let nested = TranslationMarkup("````md\n```\ninner\n```\n````\n끝")
        require(nested.displayText == "```\ninner\n```\n끝", "a shorter run is content")
        let longer = TranslationMarkup("```\nx\n`````\n끝")
        require(longer.displayText == "x\n끝", "a longer closer closes")
        let content = TranslationMarkup("```\n```js\n```")
        require(content.displayText == "```js", "an opener-looking line inside a block is content")
        let indentedCloser = TranslationMarkup("```\nx\n  ```\n뒤")
        require(indentedCloser.displayText == "x\n뒤", "a closer indented two spaces closes")
        let deepCloser = TranslationMarkup("```\nx\n    ```\n뒤")
        require(deepCloser.displayText == "x\n    ```\n뒤", "a closer indented four spaces is content")
        require(TranslationMarkup("```js {1,3}\nx\n```").blocks[0].fence?.language == "js", "language is the first word")
        require(TranslationMarkup("```\nx\n```").blocks[0].fence?.language == nil, "untagged fence has no label")
        let list = TranslationMarkup("1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행")
        require(list.displayText == "1. 설치:\nnpm i\n2. 실행", "content is dedented by the opener indent")
        let adjacent = TranslationMarkup("```a\nx\n```\n```b\ny\n```")
        require(adjacent.blocks.count == 2 && adjacent.blocks.allSatisfy { $0.fence != nil }, "adjacent blocks stay separate")
        require(TranslationMarkup("```\n```").displayText.isEmpty, "an empty block displays nothing")
    }

    private static func normalization() {
        require(TranslationMarkup.normalized("번역입니다.\n```") == "번역입니다.", "stray trailing fence is removed")
        require(TranslationMarkup.normalized("```swift\na\n```\n```") == "```swift\na\n```", "double close is trimmed")
        require(TranslationMarkup.normalized("```") == "", "a lone fence becomes empty")
        require(TranslationMarkup.normalized("번역\n```\n  \n") == "번역", "whitespace-only open block is removed")
        require(TranslationMarkup.normalized("설명\n```js\nx") == "설명\n```js\nx\n```", "unclosed block is closed")
        require(TranslationMarkup.normalized("설명\n````md\nx\n") == "설명\n````md\nx\n````", "closer matches the opener length")
        // A bare fence nothing closes is a stray, not a block to close: it may close code that began before the text.
        require(TranslationMarkup.normalized("설명\n```\nx") == "설명\nx" && !TranslationMarkup("설명\n```\nx").containsCode, "an unclosed bare fence opens nothing")
        require(TranslationMarkup.normalized("~~~\nx") == "~~~\nx", "tilde lines are not fences")
        require(TranslationMarkup.normalized("먼저 실행하세요:\n```bash\nnpm install", source: "Run this first:\n```bash\nnpm install")
                == "먼저 실행하세요:\n```bash\nnpm install", "a source ending inside a fence keeps the result as written")
        require(TranslationMarkup.normalized("설치하세요.\n\n```", source: "Install it.\n\n```") == "설치하세요.\n\n```", "a selected opening fence is kept")
        require(TranslationMarkup.normalized("번역\n```", source: "Translate") == "번역", "a balanced source still drops the stray fence")
        require(TranslationMarkup.normalized("설명입니다.\n```js\n```", source: "Explain.") == "설명입니다.", "an empty fence pair is removed")
        let middle = "앞 문단.\n\n```\n```\n\n뒤 문단."
        require(TranslationMarkup.normalized(middle) == "앞 문단.\n\n\n뒤 문단."
                && TranslationMarkup(TranslationMarkup.normalized(middle)).displayText == TranslationMarkup(middle).displayText,
                "removing an empty pair keeps the display")
        require(TranslationMarkup.normalized("예시\n```\n```", source: "Example\n```\n```") == "예시\n```\n```", "source fences are kept as written")
        require(TranslationMarkup.normalized("```\n```\ncode\n```") == "code", "pairs are read in order")
        for text in fixtures {
            let once = TranslationMarkup.normalized(text)
            require(TranslationMarkup.normalized(once) == once, "normalized is idempotent: \(text)")
        }
        require(TranslationMarkup(TranslationMarkup.normalized("```\n```")).displayText.isEmpty, "empty fences normalize to empty display")
    }

    /// Every streamed snapshot must extend the previous display, and the final display.
    private static func streamingMonotonicity() {
        for text in fixtures {
            let scalars = Array(text.unicodeScalars)
            let final = TranslationMarkup(TranslationMarkup.normalized(text)).displayText
            var previous = ""
            for end in 0...scalars.count {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[0..<end])
                let display = TranslationMarkup(String(view), streaming: true).displayText
                require(display.utf16.starts(with: previous.utf16), "display only appends: \(text.debugDescription) at \(end)")
                require(final.utf16.starts(with: display.utf16), "streamed display is a prefix of the final: \(text.debugDescription) at \(end)")
                previous = display
            }
            if text.hasSuffix("```") {
                require(TranslationMarkup(text, streaming: true).displayText == final, "a stream ending in a fence matches the final")
            }
        }
        require(!TranslationMarkup("```py\nprint(1)\n``", streaming: true).displayText.contains("`"), "partial closer is held")
        require(TranslationMarkup("설명\n``", streaming: true).displayText == "설명", "partial opener is held")
        require(TranslationMarkup("설명\n``x", streaming: true).displayText == "설명\n``x", "non-fence line is shown")
        require(TranslationMarkup("설명\n```swift", streaming: true).displayText == "설명", "an opener shows nothing until code")
        let started = TranslationMarkup("설명\n```swift\nlet", streaming: true)
        require(started.displayText == "설명\nlet" && started.blocks.last?.fence?.language == "swift", "box appears with the first code character")
    }

    private static func exports() {
        let markup = TranslationMarkup("앞 문단\n```swift\nlet a = 1\nlet b = 2\n```\n뒤 & <끝>")
        let text = markup.displayText as NSString
        let inside = text.range(of: "a = 1")
        require(markup.markdown(in: inside) == "```swift\na = 1\n```", "a code slice is fenced")
        let all = NSRange(location: 0, length: text.length)
        require(markup.markdown(in: all) == "앞 문단\n```swift\nlet a = 1\nlet b = 2\n```\n뒤 & <끝>", "full selection rebuilds the markdown")
        let tail = NSRange(location: text.range(of: "let b").location, length: text.length - text.range(of: "let b").location)
        require(markup.markdown(in: tail) == "```swift\nlet b = 2\n```\n뒤 & <끝>", "partial code slice is fenced")
        require(!markup.needsMarkdown(for: inside) && markup.needsMarkdown(for: tail) && !markup.needsMarkdown(for: text.range(of: "뒤")),
                "only selections mixing code and prose copy as markdown")
        let listed = TranslationMarkup("1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행")
        let listedText = listed.displayText as NSString
        require(listed.markdown(in: NSRange(location: 0, length: listedText.length)) == "1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행", "rebuilt fences keep the list indent")
        let nested = TranslationMarkup("````md\n```\ninner\n```\n````\n끝")
        let nestedText = nested.displayText as NSString
        require(TranslationMarkup(nested.markdown(in: NSRange(location: 0, length: nestedText.length))).displayText == nested.displayText,
                "rebuilt fences are longer than any backtick run inside")
        let html = markup.html
        require(html.hasPrefix("<meta charset=\"utf-8\">") && html.contains("<code class=\"language-swift\">let a = 1\nlet b = 2</code>"), "html code")
        require(html.contains("<p>뒤 &amp; &lt;끝&gt;</p>") && html.contains("<p>앞 문단</p>"), "html prose is escaped")
        require(TranslationMarkup("한 줄\n둘째 줄\n\n새 문단").html.contains("<p>한 줄<br>둘째 줄</p><p>새 문단</p>"), "html paragraphs")

        let result = "설명\n\n```bash\nnpm i\n```"
        require(TranslationMarkup.insertionText(result: result, source: "Explain\n\nnpm i") == "설명\n\nnpm i", "model-added fences are dropped")
        let list = "1. CLI를 설치합니다:\n   ```bash\n   npm install -g deepk\n   ```\n2. 실행합니다."
        require(TranslationMarkup.insertionText(result: list, source: "1. Install the CLI:\n   npm install -g deepk\n2. Run it.")
                == "1. CLI를 설치합니다:\n   npm install -g deepk\n2. 실행합니다.", "inserted code keeps its indentation")
        require(TranslationMarkup.insertionText(result: "실행:\n\n```bash\nnpm i\n```\n", source: "Run:\n\nnpm i\n") == "실행:\n\nnpm i\n", "inserted text keeps its line end")
        require(TranslationMarkup.insertionText(result: "설명\r\n```\r\nx\r\n```\r\n", source: "Explain\r\nx\r\n") == "설명\r\nx\r\n", "CRLF line ends are kept")
        require(TranslationMarkup.insertionText(result: result, source: "Explain\n\n```bash\nnpm i\n```") == result, "source fences are kept")
        require(TranslationMarkup.insertionText(result: "산문", source: "prose") == "산문", "prose is inserted unchanged")
    }

    private static let links = [SourceLink(url: URL(string: "https://blog.example.com/harness")!, text: "Finding the best harness"),
                                SourceLink(url: URL(string: "https://example.com/two")!, text: "Two")]

    private static func inlineRecognition() {
        let any = InlineOptions(code: .any)
        let both = InlineOptions(code: .only(["read", "bash"]), links: links)
        let plain = TranslationMarkup("도구는 `read`, `bash`입니다.")
        require(plain.displayText == "도구는 `read`, `bash`입니다." && plain.spans.isEmpty, "inline parsing is off by default")

        let chips = TranslationMarkup("도구는 `read`, `bash`입니다.", inline: any)
        require(chips.displayText == "도구는 read, bash입니다.", "backticks are hidden")
        require(chips.spans.map { (chips.displayText as NSString).substring(with: $0.range) } == ["read", "bash"]
                && chips.spans.allSatisfy { $0.kind == .code }, "each span is a chip")
        require(TranslationMarkup("``a`b`` 와 ` x ` 그리고 `열린", inline: any).displayText == "a`b 와 x 그리고 `열린", "CommonMark span rules")
        require(TranslationMarkup("`" + String(repeating: "x", count: 97) + "`", inline: any).spans.isEmpty, "a span longer than 96 is literal")

        let only = TranslationMarkup("`read`, `읽기` 그리고 `bash`", inline: both)
        require(only.displayText == "read, 읽기 그리고 bash" && only.spans.count == 2, "only captured code gets a chip; other backticks are hidden")

        let linked = TranslationMarkup("확인해 보세요: <a1>하네스 찾기</a1>. <a3>모름</a3> <a2>둘째 `read`</a2> a < b", inline: both)
        require(linked.displayText == "확인해 보세요: 하네스 찾기. 모름 둘째 read a < b", "tags are removed and other text stays")
        let text = linked.displayText as NSString
        require(linked.spans.contains(InlineSpan(kind: .link(0), range: text.range(of: "하네스 찾기")))
                && linked.spans.contains(InlineSpan(kind: .link(1), range: text.range(of: "둘째 read")))
                && linked.spans.contains(InlineSpan(kind: .code, range: text.range(of: "read"))), "links, unknown ids and nested code")
        let broken = TranslationMarkup("<a1>열림 <a2>안쪽</a2> 닫힘</a1> </a2> <a1>끝없음", inline: both)
        require(broken.displayText == "열림 안쪽 닫힘  끝없음" && broken.spans == [InlineSpan(kind: .link(0), range: NSRange(location: 0, length: 8))],
                "a second opener, stray closers and an unclosed link")
        require(TranslationMarkup("코드 <a1>x</a1>", inline: InlineOptions(code: .any)).displayText == "코드 <a1>x</a1>", "without links tags are text")
        let fenced = TranslationMarkup("앞 `read`\n```\n`read` <a1>x</a1>\n```", inline: both)
        require(fenced.displayText == "앞 read\n`read` <a1>x</a1>" && fenced.spans.count == 1, "inline markup is not parsed inside fences")
    }

    private static func inlineStreaming() {
        let both = InlineOptions(code: .any, links: links)
        let fixtures = [
            "확인: <a1>하네스 찾기</a1>. `read`, `bash` 끝",
            "``a`b`` 그리고 `열림 <a2>둘째</a2>",
            "< a <a <a1 <a1x> </a1> </a12> <a1234>",
            "`x``y` `` ` 끝",
            "설명\n```py\nprint(`x`)\n```\n`read` <a1>링크</a1>",
        ]
        var generator = SplitMix(seed: 0x5EED)
        let alphabet: [String] = ["`", "`", "<", "a", "1", "2", "/", ">", " ", "\n", "한", "x"]
        let random = (0..<300).map { _ in (0..<generator.next(upTo: 24)).map { _ in alphabet[generator.next(upTo: alphabet.count)] }.joined() }
        for text in fixtures + random {
            let scalars = Array(text.unicodeScalars)
            let final = TranslationMarkup(TranslationMarkup.normalized(text), inline: both).displayText
            var previous = ""
            for end in 0...scalars.count {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[0..<end])
                let display = TranslationMarkup(String(view), streaming: true, inline: both).displayText
                require(display.utf16.starts(with: previous.utf16), "inline display only appends: \(text.debugDescription) at \(end)")
                require(final.utf16.starts(with: display.utf16), "inline stream is a prefix of the final: \(text.debugDescription) at \(end)")
                previous = display
            }
        }
        require(TranslationMarkup("확인: <a", streaming: true, inline: both).displayText == "확인:", "a partial tag is held")
        require(TranslationMarkup("확인: <a1>하네", streaming: true, inline: both).displayText == "확인: 하네", "link text is not held")
        require(TranslationMarkup("도구 `re", streaming: true, inline: both).displayText == "도구", "an open code span is held")
        require(TranslationMarkup("도구 `read`", streaming: true, inline: both).displayText == "도구", "a closing run at the end may still grow")
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(upTo bound: Int) -> Int {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Int((z ^ (z >> 31)) % UInt64(bound))
        }
    }

    /// Review of PR #49: fence lines that are not openers never hide text or turn prose into code.
    private static func reviewFollowUps() {
        let slack = TranslationMarkup("실행:\n```npm install\nnpm run build```\n그다음 앱을 엽니다.")
        require(slack.displayText == "실행:\nnpm install\nnpm run build\n그다음 앱을 엽니다."
                && slack.blocks.map { $0.fence != nil } == [false, true, false] && slack.blocks[1].fence?.language == nil,
                "code on a fence line is the block's first line, and a chat-style closer ends it")
        let tagged = TranslationMarkup("```js title=\"a.js\"\nx\n```\n```{python}\ny\n```\n```c++\nz\n```")
        require(tagged.blocks.compactMap { $0.fence?.language } == ["js", "python", "c++"], "language tags with attributes open blocks")

        // A selection that starts inside a code block: its closer is not an opener.
        let source = "npm install\nnpm run build\n```\n\nThen restart the server."
        let result = "npm install\nnpm run build\n```\n\n그다음 서버를 다시 시작합니다."
        require(TranslationMarkup.normalized(result, source: source) == result, "the source's lone closer is kept as written")
        let inside = TranslationMarkup(result)
        require(!inside.containsCode && inside.displayText == "npm install\nnpm run build\n\n그다음 서버를 다시 시작합니다.", "prose stays prose")

        // A stray bare fence in the middle is dropped, not closed at the end.
        let stray = "명령:\nnpm i\n```\n\n다음 단계는 설정입니다."
        require(TranslationMarkup.normalized(stray) == "명령:\nnpm i\n\n다음 단계는 설정입니다.", "a stray fence is removed")
        require(!TranslationMarkup(stray).containsCode, "a stray fence opens nothing")
        require(TranslationMarkup("명령:\n```\n", streaming: true).displayText == "명령:", "a bare fence waits for its next line")
        require(TranslationMarkup("명령:\n```\nls", streaming: true).containsCode, "code right after a bare fence opens a block")

        // The completed side of a streaming unit keeps its separator.
        require(TranslationMarkup.displayOffset(of: ("첫 문단입니다.\n\n" as NSString).length, in: "첫 문단입니다.\n\n둘째", limit: 100)
                == ("첫 문단입니다.\n\n" as NSString).length, "the tail offset keeps the separator")
        let code = "설명\n\n```py\nprint(1)\n```\n\n"
        require(TranslationMarkup.displayOffset(of: (code as NSString).length, in: code + "다음", limit: 100)
                == ("설명\n\nprint(1)\n\n" as NSString).length, "after a block too")

        // Plain text of a selection matches the copy button.
        let listed = TranslationMarkup("1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행")
        let all = NSRange(location: 0, length: (listed.displayText as NSString).length)
        require(listed.plainText(in: all, fences: .none) == "1. 설치:\n   npm i\n2. 실행", "code keeps its list indent")
        require(listed.plainText(in: all, fences: .fenced) == listed.markdown(in: all), "a fenced source keeps fences")
        let button = TranslationMarkup.insertionText(result: "1. 설치:\n   ```bash\n   npm i\n   ```\n2. 실행", source: "1. Install:\n   npm i\n2. Run")
        require(listed.plainText(in: all, fences: .none) == button, "same as the copy button")
    }

    /// Second review of PR #49.
    private static func secondReview() {
        // Code on a fence line pairs with its closer like any opener, so the prose after the closer stays prose.
        let slack = TranslationMarkup("실행:\n```npm install\nnpm run build\n```\n그다음 앱을 엽니다.")
        let codeOf = { (markup: TranslationMarkup) in markup.blocks.filter { $0.fence != nil }.map { (markup.displayText as NSString).substring(with: $0.range) } }
        require(codeOf(slack) == ["npm install\nnpm run build\n"] && slack.displayText.hasSuffix("\n그다음 앱을 엽니다."), "the closer of a code fence line closes it")
        require(TranslationMarkup.normalized("예:\n```ts twoslash\nconst a = 1\n```\n다음 문단입니다.").hasSuffix("다음 문단입니다."), "no closer is added")
        let chained = TranslationMarkup("예:\n```jsx live\n<Button />\n```\n이 예제는 버튼을 그립니다.\n\n```js\nconst a = 1\n```\n끝.")
        require(codeOf(chained) == ["jsx live\n<Button />\n", "const a = 1\n"], "every block pairs on its own")
        // A chat-style block that closes on a code line leaves later blocks alone.
        let later = TranslationMarkup("설치:\n```npm install\nnpm run build```\n그다음:\n```js\nmodule.exports = {}\n```\n\n```\nnpm start\n```")
        require(codeOf(later) == ["npm install\nnpm run build\n", "module.exports = {}\n", "npm start"], "later blocks still pair")
        let fromSlack = "Install:\n```npm install\nnpm run build```\nThen restart."
        let answer = "설치:\n```npm install\nnpm run build```\n다시 시작합니다.\n\n```\nnpm start\n```"
        require(TranslationMarkup.normalized(answer, source: fromSlack) == answer, "the model's closer is kept")
        // Commands on the fence line are never hidden, `=` or not.
        for info in ["pip install requests==2.31.0", "export NODE_ENV=production", "npm --registry=https://r.example install", "ls -la",
                     "const a=1", "make debug=1", "python title=app.py"] {
            let markup = TranslationMarkup("설치:\n```\(info)\npython app.py\n```\n\n다음.")
            require(codeOf(markup) == ["\(info)\npython app.py\n"], "fence-line code is the first code line: \(info)")
            require(TranslationMarkup("```\(info)\n```").displayText == info, "a lone command fence shows the command: \(info)")
        }
        let attributed = TranslationMarkup("```js title=\"a b.js\" {1,3}\nx\n```\n```{r, echo=FALSE}\ny\n```\n```jsx title=\"src/App.js\" showLineNumbers\nz\n```"
                                           + "\n```js {1,3} showLineNumbers\nw\n```\n```{.python}\nv\n```\n```{ r }\nu\n```")
        require(attributed.blocks.compactMap { $0.fence?.language } == ["js", "r", "jsx", "js", "python", "r"], "attributes, flags and brace groups open blocks")
        // While a chat-style block streams, a trailing backtick run is held, so the display only grows.
        require(TranslationMarkup("```npm i\nnpm run b``", streaming: true).displayText == "npm i\nnpm run b", "a possible closer is not shown")

        // A selection starting at a code line's end copies no empty or turned-over code.
        let bare = TranslationMarkup("설명입니다.\n```\nfirst()\nsecond()\n```\n다음 문단입니다.")
        let text = bare.displayText as NSString
        let start = text.range(of: "first()").location + 7
        let fromLineEnd = NSRange(location: start, length: text.length - start)
        require(bare.markdown(in: fromLineEnd) == "```\nsecond()\n```\n다음 문단입니다.", "the line break before the first selected code line is not code")
        require(TranslationMarkup(bare.markdown(in: fromLineEnd)).blocks.map { $0.fence != nil } == [true, false], "copied markdown reads back the same way")
        require(bare.html(in: fromLineEnd).contains("<code>second()</code></pre><p>다음 문단입니다.</p>"), "html keeps code and prose apart")
        let tail = TranslationMarkup("설치합니다.\n\n```bash\nnpm i\n```\n\n다음 문단입니다.")
        let tailText = tail.displayText as NSString
        let afterCode = NSRange(location: tailText.range(of: "npm i").location + 5, length: tailText.length - tailText.range(of: "npm i").location - 5)
        require(!tail.needsMarkdown(for: afterCode) && !tail.markdown(in: afterCode).contains("```") && !tail.html(in: afterCode).contains("<pre"),
                "a code block's line break alone is not code")

        // A block's empty first line is code; so is an empty line a selection starts at.
        let blankFirst = TranslationMarkup("설명\n\n```py\n\nprint(1)\n```")
        let all = NSRange(location: 0, length: (blankFirst.displayText as NSString).length)
        require(blankFirst.markdown(in: all) == "설명\n\n```py\n\nprint(1)\n```" && blankFirst.html.contains("<code class=\"language-py\">\nprint(1)</code>"),
                "an empty first code line is kept")
        // Plain text puts back exactly the spaces each line lost, so a heredoc terminator still matches.
        let heredoc = "- 예:\n  ```sh\n  cat <<EOF\nhello\n\nEOF\n  ```\n뒤"
        let heredocMarkup = TranslationMarkup(heredoc)
        let heredocAll = NSRange(location: 0, length: (heredocMarkup.displayText as NSString).length)
        require(heredocMarkup.plainText(in: heredocAll, fences: .none) == TranslationMarkup.insertionText(result: heredoc, source: "- e.g.:\n  cat"),
                "plain text matches the copy button line by line")
        require(TranslationMarkup(heredocMarkup.markdown(in: heredocAll)).displayText == heredocMarkup.displayText, "rebuilt markdown reads back the same")
        // Insertion keeps a chat-style block's code without its backticks.
        require(TranslationMarkup.insertionText(result: "설치:\n```npm install\nnpm run build```\n끝", source: "Install: npm install") == "설치:\nnpm install\nnpm run build\n끝",
                "chat-style fences are dropped, code kept")

        // CRLF result whose last line is a closing fence.
        require(TranslationMarkup.insertionText(result: "설명\r\n```\r\nx\r\n```", source: "Explain\r\nx") == "설명\r\nx", "no CR is left at the end")
    }

    /// Random fence-heavy text: every streamed display is a prefix of the next and of the final display,
    /// normalizing twice changes nothing, and rebuilt markdown reads back to the same display.
    private static func fenceFuzz() {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let pieces = ["```", "`", "``", "\n", "\n\n", " ", "  ", "js", "npm i", "a=1", "title=\"x\"", "{1}", "flag", "코드", "x", "\r\n", "~~~"]
        for case_ in 0..<400 {
            let text = (0..<Int(next() % 24 + 1)).map { _ in pieces[Int(next() % UInt64(pieces.count))] }.joined()
            let normalized = TranslationMarkup.normalized(text)
            require(TranslationMarkup.normalized(normalized) == normalized, "normalized is idempotent: \(text.debugDescription)")
            let final = TranslationMarkup(normalized).displayText
            let scalars = Array(text.unicodeScalars)
            var previous = ""
            for end in 0...scalars.count {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[0..<end])
                let display = TranslationMarkup(String(view), streaming: true).displayText
                require(display.utf16.starts(with: previous.utf16), "fuzz \(case_): display only appends: \(text.debugDescription) at \(end)")
                previous = display
            }
            require(final.utf16.starts(with: previous.utf16), "fuzz \(case_): the stream is a prefix of the final display: \(text.debugDescription)")
            let markup = TranslationMarkup(normalized)
            let all = NSRange(location: 0, length: (markup.displayText as NSString).length)
            let rebuilt = TranslationMarkup(markup.markdown(in: all))
            require(rebuilt.displayText == final, "fuzz \(case_): rebuilt markdown reads back: \(text.debugDescription)")
        }
    }

    /// Third review of PR #49.
    private static func thirdReview() {
        let whole = { (markup: TranslationMarkup) in NSRange(location: 0, length: (markup.displayText as NSString).length) }
        // An indented chat-style fence keeps its first code line's indent in every copy.
        let listed = "- 설치:\n  ```npm install\n  npm run build\n  ```\n- 끝"
        let listedMarkup = TranslationMarkup(listed)
        require(listedMarkup.plainText(in: whole(listedMarkup), fences: .none) == TranslationMarkup.insertionText(result: listed, source: "- Install")
                && TranslationMarkup.insertionText(result: listed, source: "- Install") == "- 설치:\n  npm install\n  npm run build\n- 끝",
                "plain text matches the copy button")
        require(listedMarkup.markdown(in: whole(listedMarkup)) == "- 설치:\n  ```\n  npm install\n  npm run build\n  ```\n- 끝", "rebuilt markdown keeps the list")

        // CRLF results keep CRLF through chat-style fences.
        for result in ["설명\r\n```npm i\r\nnpm run build\r\n```\r\n끝", "설명\r\n```npm i\r\nnpm run build```\r\n끝"] {
            require(TranslationMarkup(result).displayText == "설명\r\nnpm i\r\nnpm run build\r\n끝", "display keeps CRLF: \(result.debugDescription)")
            require(TranslationMarkup.insertionText(result: result, source: "Explain") == "설명\r\nnpm i\r\nnpm run build\r\n끝", "insertion keeps CRLF: \(result.debugDescription)")
        }

        // Qiita and Zenn put a file name after the tag.
        let named = TranslationMarkup("설정 파일:\n```ruby:config/app.rb\nputs 1\n```\n끝")
        require(named.displayText == "설정 파일:\nputs 1\n끝" && named.blocks.compactMap { $0.fence?.language } == ["ruby"], "a file name is not code")

        // Normalizing twice changes nothing, also when the source has fences.
        let fenced = "T\n```js\nx\n```"
        let once = TranslationMarkup.normalized("번역\n```js\nx\n```\n```\n\n```", source: fenced)
        require(once == "번역\n```js\nx\n```" && TranslationMarkup.normalized(once, source: fenced) == once, "no fence is left at the end")

        // A source with untagged fences, as chat apps write them, gets untagged fences back.
        let slackSource = "Install:\n```npm install\nnpm run build```\nThen restart the server."
        let tagged = "설치:\n```bash\nnpm install\nnpm run build\n```\n그다음 서버를 다시 시작합니다."
        require(TranslationMarkup.FenceStyle(source: slackSource) == .untagged && TranslationMarkup.FenceStyle(source: "a\n```py\nb\n```") == .fenced
                && TranslationMarkup.FenceStyle(source: "그냥 문장") == .none, "fence style of the source")
        require(TranslationMarkup.insertionText(result: tagged, source: slackSource) == "설치:\n```\nnpm install\nnpm run build\n```\n그다음 서버를 다시 시작합니다.",
                "insertion drops the tag a chat app would show as code")
        let taggedMarkup = TranslationMarkup(tagged)
        require(taggedMarkup.plainText(in: whole(taggedMarkup), fences: .untagged) == TranslationMarkup.insertionText(result: tagged, source: slackSource),
                "plain text matches the copy button for untagged sources")

        // Partial selections: an empty code line a selection starts at stays; a line started mid-way gets no indent.
        let gap = TranslationMarkup("설명\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n다음 문단")
        let gapText = gap.displayText as NSString
        let blank = gapText.range(of: "1\n").location + 2
        require(gap.markdown(in: NSRange(location: blank, length: gapText.length - blank)) == "```swift\n\nlet b = 2\n```\n다음 문단", "the empty line stays")
        let shell = TranslationMarkup("- 예:\n  ```sh\n  echo hello world\n  ls\n  ```\n뒤")
        let shellText = shell.displayText as NSString
        let middle = shellText.range(of: "hello").location
        require(shell.plainText(in: NSRange(location: middle, length: shellText.length - middle), fences: .none) == "hello world\n  ls\n뒤",
                "a line started mid-way gets no indent")
    }

    /// Fourth review of PR #49.
    private static func fourthReview() {
        let codeOf = { (markup: TranslationMarkup) in markup.blocks.filter { $0.fence != nil }.map { (markup.displayText as NSString).substring(with: $0.range) } }
        // A stray the model adds to a fenced source is removed from what is stored, copied and inserted.
        let source = "Run:\n```bash\nnpm i\n```\n\nThen restart the server."
        let stray = TranslationMarkup.normalized("실행:\n```bash\nnpm i\n```\n```\n\n그다음 서버를 다시 시작합니다.", source: source)
        require(stray == "실행:\n```bash\nnpm i\n```\n\n그다음 서버를 다시 시작합니다.", "a stray is removed even when the source has fences")
        require(TranslationMarkup.normalized("앞\n```js\nx\n```\n```\n```\n뒤", source: source) == "앞\n```js\nx\n```\n뒤", "so is an empty pair")
        // A bare fence followed by a blank line still opens a block when a closer follows: code may start with a blank line.
        let blankFirst = TranslationMarkup("예:\n\n```\n\nfoo()\n```\n다음 문단입니다.")
        require(codeOf(blankFirst) == ["\nfoo()\n"] && blankFirst.displayText.hasSuffix("\n다음 문단입니다."), "a closed bare block keeps its blank first line")
        require(TranslationMarkup.normalized("예:\n\n```\n\nfoo()\n```\n다음 문단입니다.", source: "Example:\n\nfoo()\nNext.") == "예:\n\n```\n\nfoo()\n```\n다음 문단입니다.",
                "and is stored as written")
        // A selection that starts inside code: a closer followed directly by prose opens nothing.
        let inside = TranslationMarkup("  return x\n}\n```\n다음으로 함수를 호출하세요.\nx를 반환합니다.")
        require(!inside.containsCode && inside.displayText == "  return x\n}\n다음으로 함수를 호출하세요.\nx를 반환합니다.", "prose after a lone closer stays prose")
        // Whitespace-only blocks show nothing and are removed, tagged or not.
        require(TranslationMarkup.normalized("설명\n```js\n   ") == "설명" && TranslationMarkup.normalized("번역\n```js\n  \n") == "번역", "an open block of spaces is removed")
        require(TranslationMarkup.normalized("앞\n```\n\n```\n뒤") == "앞\n뒤" && TranslationMarkup("앞\n```py\n  \n```\n뒤").displayText == "앞\n뒤",
                "a closed block of blank lines is removed")

        // CRLF prose becomes paragraphs in HTML.
        let crlf = TranslationMarkup("첫 문단\r\n\r\n둘째 문단\r\n```py\nx\n```")
        require(crlf.html.contains("<p>첫 문단</p><p>둘째 문단</p>"), "CRLF paragraphs")
        // A source with tagged and untagged fences keeps tags.
        require(TranslationMarkup.FenceStyle(source: "```\na\n```\n```py\nb\n```") == .fenced, "any tag in the source keeps tags")
        // Spaces before a chat-style closing run are not code.
        require(TranslationMarkup("```npm i\nnpm run build ```\n끝").displayText == "npm i\nnpm run build\n끝", "no trailing space before the closer")
    }

    private static func singleWordCommands() {
        for command in ["pwd", "ls", "whoami", "make", "project-tool"] {
            let text = "실행:\n```\(command)\n```\n끝"
            let markup = TranslationMarkup(text)
            let all = NSRange(location: 0, length: markup.displayText.utf16.count)
            require(markup.displayText == "실행:\n\(command)\n끝", "a bare command on the fence line is code, not a language: \(command)")
            require(markup.blocks.compactMap { $0.fence?.language }.isEmpty && markup.containsCode, "an ambiguous command has no language label")
            require(TranslationMarkup.normalized(text) == text, "normalization never removes a fence-line command")
            require(TranslationMarkup.FenceStyle(source: text) == .untagged, "chat-style commands are untagged fences")
            require(markup.plainText(in: all, fences: .none) == "실행:\n\(command)\n끝", "plain selection keeps the command")
            require(TranslationMarkup.insertionText(result: text, source: "Run the command.") == markup.displayText, "plain insertion and selection agree")
            require(TranslationMarkup(markup.markdown(in: all)).displayText == markup.displayText, "rebuilt markdown keeps the command")
            require(markup.html.contains("<code>\(command)</code>"), "rich copy keeps the command")
        }
        let inlineCloser = TranslationMarkup("실행:\n```pwd\nls -la```\n끝")
        require(inlineCloser.displayText == "실행:\npwd\nls -la\n끝" && inlineCloser.blocks.last?.kind == .prose, "a single-word chat opener also accepts an inline closer")
        let crlf = "실행:\r\n  ```pwd\r\n  ```\r\n끝"
        require(TranslationMarkup(crlf).displayText == "실행:\r\npwd\r\n끝"
                && TranslationMarkup.insertionText(result: crlf, source: "Run.") == "실행:\r\n  pwd\r\n끝", "command lines keep their CRLF and indentation")

        // Explicit metadata still supports custom languages; an unknown bare name is a tag when code follows it.
        for info in ["swift", "Python", "c++", "ruby:config/app.rb", "{customlang}", "customlang:example.src", "customlang title=\"example\""] {
            let markup = TranslationMarkup("```\(info)\nx\n```")
            require(markup.displayText == "x" && markup.blocks.first?.fence?.language != nil, "known tags and explicit metadata remain tags: \(info)")
        }
        let custom = TranslationMarkup("```customlang\nx\n```")
        require(custom.displayText == "x" && custom.blocks.first?.fence?.language == "customlang", "an unknown name with code after it is a tag")
        require(TranslationMarkup("```customlang\n```").displayText == "customlang", "an unknown name alone in its block is not silently discarded")
        require(TranslationMarkup.normalized("```python\n```").isEmpty, "a recognized empty language block is still removed")
    }

    /// Review of 8035b70: a single name no list knows is read from what follows it, not hidden or shown by a list.
    private static func unknownNames() {
        for tag in ["nginx", "hcl", "http", "env", "suggestion", "output", "make"] {
            let text = "설명:\n```\(tag)\n$ echo hi\n```\n끝"
            let markup = TranslationMarkup(text)
            let all = NSRange(location: 0, length: markup.displayText.utf16.count)
            require(markup.displayText == "설명:\n$ echo hi\n끝" && markup.blocks.compactMap { $0.fence?.language } == [tag],
                    "a name with code after it is a tag: \(tag)")
            require(markup.html.contains("<code class=\"language-\(tag)\">"), "rich copy keeps the label: \(tag)")
            require(TranslationMarkup.FenceStyle(source: text) == .fenced && markup.plainText(in: all, fences: .fenced) == text,
                    "a source fenced with the tag keeps it in selection copies: \(tag)")
            require(TranslationMarkup.insertionText(result: text, source: "Explain:\n$ echo hi\nEnd") == "설명:\n$ echo hi\n끝",
                    "the tag is never inserted as code: \(tag)")
        }
        require(TranslationMarkup("```nginx\n\nserver {}\n```").blocks.first?.fence?.language == "nginx", "blank lines decide nothing")
        require(TranslationMarkup("실행:\n```node\nnode -v```\n끝").displayText == "실행:\nnode\nnode -v\n끝",
                "a first code line that closes chat-style makes the name code")
        require(TranslationMarkup("실행:\n```pwd\nls -la\n```\n끝").displayText == "실행:\npwd\nls -la\n끝",
                "a known command stays code with more code after it")
        // A single token with a colon is a name too: alone in its block it is code; a file name before code is not.
        for token in ["http://localhost:3000", "nginx:latest", "redis:7", "C:\\Users\\me\\run.bat", "std::cout", "deploy:prod"] {
            let text = "실행:\n```\(token)\n```\n끝"
            require(TranslationMarkup(text).displayText == "실행:\n\(token)\n끝" && TranslationMarkup.normalized(text) == text,
                    "a colon token alone in its block is code: \(token)")
        }
        // A name fence with nothing after it is a stray, as before.
        require(TranslationMarkup.normalized("번역 결과입니다.\n```nginx") == "번역 결과입니다.", "a stray name fence is cut")
        // While streaming, nothing from a name's fence on shows until its first code line is complete.
        require(TranslationMarkup("설명:\n```nginx\n", streaming: true).displayText == "설명:"
                && TranslationMarkup("설명:\n```nginx\n$ ech", streaming: true).displayText == "설명:"
                && TranslationMarkup("설명:\n```nginx\n$ echo hi\n", streaming: true).displayText == "설명:\n$ echo hi",
                "a name waits for its first code line")
        // Shell transcript tags are recognized, so a copied block's fence opens at once.
        for tag in ["console", "terminal", "shell-session"] {
            require(TranslationMarkup.isFenceLanguage(tag) && TranslationMarkup("설명:\n```\(tag)\n$ ech", streaming: true).displayText == "설명:\n$ ech",
                    "a transcript tag is a tag at once: \(tag)")
            require(TranslationMarkup.normalized("번역 결과입니다.\n```\(tag)") == "번역 결과입니다.", "a stray transcript fence is cut: \(tag)")
        }
        require(TranslationMarkup("```pwd\n", streaming: true).displayText == "pwd", "a known command shows at once")
    }

    /// Repairs that rewrite whole lines read blocks, strays and prose exactly as the display does.
    private static func lineLayout() {
        let text = "설명 😀\n\n```swift\nlet a = 1\n```\n다음\n  ```py\n  print(1)\n  ```\n```npm i\nnpm run build```\n```\n끝"
        let layout = TranslationMarkup.layout(text)
        require(layout.lines.joined(separator: "\n") == text && !layout.terminated, "lines rebuild the text")
        require(layout.kinds == [.prose, .blank, .opener(0), .code(0), .closer(0), .prose, .opener(1), .code(1), .closer(1),
                                 .opener(2), .code(2), .stray, .prose], "kinds: \(layout.kinds)")
        require(layout.blocks.map(\.code) == [["let a = 1"], ["print(1)"], ["npm i", "npm run build"]], "code is dedented, chat code included")
        require(layout.blocks.map(\.closer) == [4, 8, nil] && layout.blocks.map(\.end) == [4, 8, 10], "block extents")
        require(layout.blocks[0].fence.language == "swift" && layout.blocks[2].fence.inlineCode == "npm i", "fences as parsed")
        require(layout.proseOrdinals() == [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3] && layout.proseOrdinals(skipping: [5]).last == 2,
                "prose ordinals count non-blank prose lines, but for skipped ones")
        let display = TranslationMarkup(text).blocks.compactMap { $0.fence }
        require(display == layout.blocks.map(\.fence), "the layout finds the display's blocks")
        let crlf = TranslationMarkup.layout("가\r\n```ts\r\nlet a = 1\r\n```\r\n")
        require(crlf.terminated && crlf.blocks.first?.code == ["let a = 1\r"], "CRLF code keeps its CR as display does")
        require(TranslationMarkup.layout("").lines.isEmpty && TranslationMarkup.layout("").blocks.isEmpty, "empty text")

        for tag in ["text", "js", "python", "c++", "c#", "objective-c", "console"] {
            require(TranslationMarkup.isFenceLanguage(tag), "a recognized tag is a fence language: \(tag)")
        }
        for tag in ["", "ls", "pwd", "nginx", "js:file", "npm install", "{python}x"] {
            require(!TranslationMarkup.isFenceLanguage(tag), "not a tag at once: \(tag)")
        }
    }

    /// App-made blocks from a copied page: their fence never closes inside the code, and their backticks are not the source's chips.
    private static func copiedBlocks() {
        require(SourceCodeBlock(language: "js", code: "const a = `x`").fence == 3, "a short run keeps three backticks")
        let nested = SourceCodeBlock(language: "md", code: "```js\nx\n```")
        require(nested.fence == 4 && nested.opener == "````md" && nested.closer == "````", "code with a fence gets a longer one")
        require(SourceCodeBlock(language: nil, code: "make all").opener == "```", "a bare fence")
        let block = SourceCodeBlock(language: "js", code: "const s = `${a}`")
        let markup = SourceMarkup(text: "Run it:\n```js\nconst s = `${a}`\n```", links: [], code: [], blocks: [block])
        require(!markup.hasInlineStructure && SourceMarkup(text: "a", links: [], code: ["a"]).hasInlineStructure, "only links and chips are inline")
        require(InlineOptions(source: "Run it:\nconst s = `${a}`", markup: markup).code == .off, "fenced code backticks are not chips")
        require(InlineOptions(source: "Run it:\nconst s = `${a}`\nThen `npm i`", markup: markup).code == .any,
                "backticks typed after the copy still pair")
        require(InlineOptions(source: "Run it:\nconst s = `${a}`", markup: nil).code == .any, "without blocks the source decides as before")
        let captured = CapturedSource(plain: "a", raw: "a\nCopy", removed: [NSRange(location: 1, length: 5)])
        require(captured == CapturedSource(plain: "a") && captured.raw == "a\nCopy" && CapturedSource(plain: "a").raw == "a",
                "diagnostics take no part in equality")

        // A selected tab's label travels in the opener: `title="…"` after the tag, or after `text` when the page named no language.
        let titled = SourceCodeBlock(language: nil, code: "/impeccable document", title: "  Most   Agents ")
        require(titled.title == "Most Agents" && titled.language == nil && titled.opener == "```text title=\"Most Agents\"", "a trimmed title: \(titled.opener)")
        require(SourceCodeBlock(language: "bash", code: "npm i", title: "npm").opener == "```bash title=\"npm\"", "a title after the language")
        require(SourceCodeBlock(language: nil, code: "x", title: "Say \"hi\"").opener == "```text title='Say \"hi\"'"
                && SourceCodeBlock(language: nil, code: "x", title: "It's").opener == "```text title=\"It's\"", "quoted with the other quote")
        require(SourceCodeBlock(language: nil, code: "x", title: " Production  build with source map enabled").title?.count == 40
                && SourceCodeBlock(language: nil, code: "x", title: "Production build with source maps enabled").title == nil, "at most 40 characters")
        for label in ["\"a\" or 'b'", "`npm`", "Most\nAgents", "Most\tAgents", "a\u{0007}b", "Most\u{2028}Agents", "   "] {
            let block = SourceCodeBlock(language: nil, code: "make", title: label)
            require(block.title == nil && block.opener == "```", "no title: \(label.debugDescription)")
        }
        for block in [titled, SourceCodeBlock(language: "c++", code: "int a;", title: "main.cpp"), SourceCodeBlock(language: nil, code: "x", title: "Say \"hi\"")] {
            let fence = TranslationMarkup("예:\n\(block.opener)\n\(block.code)\n\(block.closer)").blocks.compactMap(\.fence).first
            require(TranslationMarkup.isFenceLanguage(block.info) && fence?.info == block.info && fence?.language == block.tag, "the opener reads as an info string: \(block.opener)")
        }
        require(TranslationMarkup("설명:\n```text title=\"Most Agents\"\n/imp", streaming: true).displayText == "설명:\n/imp", "a titled opener opens at once")
    }

    /// Independent review of PR #53.
    private static func inlineReview() {
        let guide = SourceLink(url: URL(string: "https://good.example/login")!, text: "guide")
        // Brackets in link words are escaped in markdown, so page text cannot make another link.
        let bracketed = TranslationMarkup("<a1>x](https://evil.example/login) [여기</a1>에서 로그인하세요.", inline: InlineOptions(links: [guide]))
        require(bracketed.markdown(in: NSRange(location: 0, length: (bracketed.displayText as NSString).length))
                == "[x\\](https://evil.example/login) \\[여기](https://good.example/login)에서 로그인하세요.", "link words are escaped")
        // With inline markup, a bare fence waits for its closer while streaming, so the shown text only grows.
        let options = InlineOptions(code: .any, links: [guide])
        let pieces = ["```", "\n", "\n\n", "<a1>", "</a1>", "`", "x", " ", "가", "npm"]
        var state: UInt64 = 0x2545F4914F6CDD1D
        func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        for case_ in 0..<2_000 {
            let text = (0..<Int(next() % 16 + 1)).map { _ in pieces[Int(next() % UInt64(pieces.count))] }.joined()
            let final = TranslationMarkup(TranslationMarkup.normalized(text), inline: options).displayText
            let scalars = Array(text.unicodeScalars)
            var previous = ""
            for end in 0...scalars.count {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[0..<end])
                let display = TranslationMarkup(String(view), streaming: true, inline: options).displayText
                require(display.utf16.starts(with: previous.utf16), "inline fence fuzz \(case_): display only appends: \(text.debugDescription)")
                previous = display
            }
            require(final.utf16.starts(with: previous.utf16), "inline fence fuzz \(case_): stream is a prefix of the final: \(text.debugDescription)")
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "TranslationMarkupTests: \(message)")
    }
}
