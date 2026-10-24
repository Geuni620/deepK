import Foundation

@main
private enum CodeBlockGuardTests {
    static func main() {
        keptBlocks()
        translatedComments()
        stringsAndUnknownLanguages()
        apostrophes()
        verbatimBlocks()
        alteredLines()
        unfencedBlocks()
        translatedCommand()
        missingBlocks()
        modelFences()
        commandSentences()
        neighbours()
        wholeAnswerFences()
        modelFenceLines()
        identicalBlocks()
        titles()
        shortenedFence()
        skipped()
        composition()
        print("CodeBlockGuardTests passed")
    }

    /// The impeccable section: a one-line `text` block the model may unfence, translate or drop.
    private static let command = SourceCodeBlock(language: "text", code: "/impeccable document")
    private static let commandInput = "Ask Impeccable to write down the design you have:\n\n```text\n/impeccable document\n```\nIt scans the code."
    private static let commandResult = "Impeccable에게 요청하세요:\n\n```text\n/impeccable document\n```\n코드를 살펴봅니다."

    private static let python = SourceCodeBlock(language: "python", code: "import os\n# Print the working directory\nprint(os.getcwd())")
    private static let pythonInput = "The script prints where it runs:\n\n```python\nimport os\n# Print the working directory\nprint(os.getcwd())\n```\n\nSee the reference."

    private static let shell = SourceCodeBlock(language: "shell", code: "npm install left-pad")
    private static let js = SourceCodeBlock(language: "js", code: "import leftPad from 'left-pad';\nleftPad('7', 3, '0'); // => '007'")
    private static let pairInput = "Add the package with `npm`, then import it:\n\n```shell\nnpm install left-pad\n```\n```js\nimport leftPad from 'left-pad';\n"
        + "leftPad('7', 3, '0'); // => '007'\n```\nSee the <a1>API reference</a1> for every option."
    private static let pairResult = "`npm`으로 패키지를 추가한 뒤 가져옵니다:\n\n```shell\nnpm install left-pad\n```\n```js\nimport leftPad from 'left-pad';\n"
        + "leftPad('7', 3, '0'); // => '007'\n```\n<a1>API 참고 문서</a1>에서 모든 옵션을 보세요."

    /// Every case also checks that restoring again changes nothing, that each block is there intact, that no code line
    /// shows up more often than the model input or the output has it, and that the output's prose stays unless it is a code line.
    private static func restore(_ output: String, _ input: String, _ blocks: [SourceCodeBlock]) -> (text: String, outcome: CodeBlockGuard.Outcome) {
        let once = CodeBlockGuard.restore(output, source: input, blocks: blocks)
        let twice = CodeBlockGuard.restore(once.text, source: input, blocks: blocks)
        require(twice.text == once.text && twice.outcome == CodeBlockGuard.Outcome(kept: blocks.count), "restore is idempotent: \(output.debugDescription)")
        require(blocks.allSatisfy { intact($0, in: once.text) >= 1 }, "every block is intact: \(once.text.debugDescription)")
        let result = once.text.components(separatedBy: "\n")
        let source = input.components(separatedBy: "\n"), model = output.components(separatedBy: "\n")
        for line in Set(blocks.flatMap(\.lines)) where !line.allSatisfy(\.isWhitespace) {
            require(result.filter { $0 == line }.count <= max(source.filter { $0 == line }.count, model.filter { $0 == line }.count),
                    "no code line twice: \(line) in \(once.text.debugDescription)")
        }
        let layout = TranslationMarkup.layout(output)
        for (line, kind) in zip(layout.lines, layout.kinds) where kind == .prose && !result.contains(line) {
            let words = line.split(whereSeparator: \.isWhitespace)
            require(blocks.flatMap(\.lines).contains { code in
                let tokens = code.split(whereSeparator: \.isWhitespace)
                return code.trimmingCharacters(in: .whitespaces) == line.trimmingCharacters(in: .whitespaces) || words.first == tokens.first && words.count <= tokens.count
            } || blocks.contains { $0.title != nil && $0.title == SourceCodeBlock.title(line) }, "only code lines and titles leave the prose: \(line) in \(once.text.debugDescription)")
        }
        return once
    }

    /// Closed blocks in `text` with the fence and info of `block` and as many lines; `exact` also wants its very code.
    private static func intact(_ block: SourceCodeBlock, in text: String, exact: Bool = false) -> Int {
        TranslationMarkup.layout(text).blocks.filter {
            $0.fence.length == block.fence && $0.fence.info == block.info && $0.closer != nil
                && (exact ? $0.code == block.lines : $0.code.count == block.lines.count)
        }.count
    }

    private static func lines(_ prefix: String, in text: String) -> Int {
        text.components(separatedBy: "\n").filter { $0.hasPrefix(prefix) }.count
    }

    private static func keptBlocks() {
        let kept = restore(commandResult, commandInput, [command])
        require(kept.text == commandResult && kept.outcome == CodeBlockGuard.Outcome(kept: 1), "an intact block is kept: \(kept)")
        let pair = restore(pairResult, pairInput, [shell, js])
        require(pair.text == pairResult && pair.outcome.kept == 2, "adjacent blocks are kept")
        // The model's fence becomes the source's: tag, delimiter and indent.
        for fence in ["```", "```TEXT", "````text", "   ```text"] {
            let closer = fence.hasPrefix("   ") ? "   ```" : String(fence.prefix { $0 == "`" })
            let indent = fence.hasPrefix("   ") ? "   " : ""
            let output = "Impeccable에게 요청하세요:\n\n\(fence)\n\(indent)/impeccable document\n\(closer)\n코드를 살펴봅니다."
            let restored = restore(output, commandInput, [command])
            require(restored.text == commandResult && restored.outcome.kept == 1, "the fence language is normalized: \(fence)")
        }
    }

    /// Translated comments survive in every family that has them; the code around them does not change.
    private static func translatedComments() {
        let translated = "The script prints where it runs:\n\n```python\nimport os\n# 작업 디렉터리를 출력합니다\nprint(os.getcwd())\n```\n\n참고 문서를 보세요."
            .replacingOccurrences(of: "The script prints where it runs:", with: "스크립트는 실행 위치를 출력합니다:")
        let hash = restore(translated, pythonInput, [python])
        require(hash.text == translated && hash.outcome.kept == 1, "a hash comment may be translated")
        let trailing = restore(pairResult.replacingOccurrences(of: "// => '007'", with: "// => '007' 이 됩니다"), pairInput, [shell, js])
        require(trailing.text.contains("leftPad('7', 3, '0'); // => '007' 이 됩니다") && trailing.outcome.kept == 2, "a slash comment after code may be translated")

        func check(_ language: String, _ code: String, _ result: String, _ name: String) {
            let block = SourceCodeBlock(language: language, code: code)
            let input = "Example:\n```\(language)\n\(code)\n```\nDone."
            let output = "예:\n```\(language)\n\(result)\n```\n끝."
            let restored = restore(output, input, [block])
            require(restored.text == output && restored.outcome == CodeBlockGuard.Outcome(kept: 1), "\(name): \(restored.text)")
        }
        check("js", "// Add two numbers\nconst sum = a + b;", "// 두 수를 더합니다\nconst sum = a + b;", "a slash comment line")
        check("css", "a { color: red; /* brand red */ }", "a { color: red; /* 브랜드 빨강 */ }", "a CSS block comment keeps its closer and the code after it")
        check("html", "<nav>\n  <!-- main links -->\n</nav>", "<nav>\n  <!-- 주요 링크 -->\n</nav>", "an HTML comment")
        check("ts", "/*\n * Adds two numbers.\n */\nfunction add(a: number, b: number) { return a + b }",
              "/*\n * 두 수를 더합니다.\n */\nfunction add(a: number, b: number) { return a + b }", "a multi-line block comment")
        check("sql", "SELECT 1; -- one row", "SELECT 1; -- 한 행", "a dash comment")

        // Code changed next to a translated comment goes back to the page's bytes.
        let block = SourceCodeBlock(language: "css", code: "a { color: red; /* brand red */ }")
        let restored = restore("예:\n```css\na { color: blue; /* 브랜드 빨강 */ }\n```\n끝.", "Example:\n```css\na { color: red; /* brand red */ }\n```\nDone.", [block])
        require(restored.text == "예:\n```css\na { color: red; /* brand red */ }\n```\n끝." && restored.outcome.restored == 1, "code beside a comment is restored")
        let unclosed = restore("예:\n```css\na { color: red; /* 브랜드 빨강\n```\n끝.", "Example:\n```css\na { color: red; /* brand red */ }\n```\nDone.", [block])
        require(unclosed.text.contains("a { color: red; /* brand red */ }"), "a comment must keep its closer and what follows it")
        let multi = SourceCodeBlock(language: "ts", code: "/*\n * Adds two numbers.\n */\nexport {}")
        let shifted = restore("예:\n```ts\n/*\n* 두 수를 더합니다.\n */\nexport {}\n```\n끝.", "Example:\n```ts\n\(multi.code)\n```\nDone.", [multi])
        require(shifted.text.contains("\n * Adds two numbers.\n"), "an interior comment line keeps its indent and gutter")
        let gutter = restore("예:\n```ts\n/*\n 두 수를 더합니다.\n */\nexport {}\n```\n끝.", "Example:\n```ts\n\(multi.code)\n```\nDone.", [multi])
        require(gutter.text.contains("\n * Adds two numbers.\n") && gutter.outcome == CodeBlockGuard.Outcome(restored: 1), "an interior line without its `*` gutter is restored: \(gutter.text)")
        // Trailing spaces and tabs are no change.
        let padded = "스크립트:\n```python\nimport os   \nprint(os.getcwd())\t\n```\n끝."
        let spaces = restore(padded, "Script:\n```python\nimport os\nprint(os.getcwd())\n```\nDone.", [SourceCodeBlock(language: "python", code: "import os\nprint(os.getcwd())")])
        require(spaces.text == padded && spaces.outcome == CodeBlockGuard.Outcome(kept: 1), "trailing spaces are kept as the model wrote them: \(spaces.text)")
    }

    private static func stringsAndUnknownLanguages() {
        // `//` in a string literal is no comment, so text after it is code.
        let url = SourceCodeBlock(language: "js", code: "const home = \"http://example.com\"; // home page")
        let input = "Set it:\n```js\n\(url.code)\n```\nDone."
        let comment = restore("설정:\n```js\nconst home = \"http://example.com\"; // 홈 페이지\n```\n끝.", input, [url])
        require(comment.outcome.kept == 1 && comment.text.contains("// 홈 페이지"), "the comment after the string may be translated")
        let string = restore("설정:\n```js\nconst home = \"http://예제.com\"; // home page\n```\n끝.", input, [url])
        require(string.text.contains(url.code) && string.outcome.restored == 1, "a changed string is restored: \(string.text)")
        let quoted = SourceCodeBlock(language: "js", code: "const s = \"a // b\";")
        let inString = restore("예:\n```js\nconst s = \"a // 비\";\n```\n끝.", "Example:\n```js\n\(quoted.code)\n```\nDone.", [quoted])
        require(inString.text.contains(quoted.code), "`//` inside a string starts no comment")

        // Without a language, `#include` and a root prompt are code; a comment after code may change.
        let include = SourceCodeBlock(language: nil, code: "#include <stdio.h>\nint main(void) { return 0; } // entry point")
        let includeInput = "Build it:\n```\n\(include.code)\n```\nDone."
        let translated = restore("빌드:\n```\n#include <표준입출력.h>\nint main(void) { return 0; } // 진입점\n```\n끝.", includeInput, [include])
        require(translated.text.contains("#include <stdio.h>\n") && translated.text.contains("// 진입점"), "#include is no comment: \(translated.text)")
        let prompt = SourceCodeBlock(language: nil, code: "# apt install nginx\nnginx -t")
        let root = restore("설치:\n```\n# apt 로 nginx 설치\nnginx -t\n```\n끝.", "Install:\n```\n\(prompt.code)\n```\nDone.", [prompt])
        require(root.text.contains("# apt install nginx\n") && root.outcome.restored == 1, "a root prompt in an unlabelled block is code")
        let notes = SourceCodeBlock(language: nil, code: "// Step one\n// Step two")
        let onlyComments = restore("예:\n```\n// 첫 단계\n// 둘째 단계\n```\n끝.", "Example:\n```\n\(notes.code)\n```\nDone.", [notes])
        require(onlyComments.outcome.kept == 1 && onlyComments.text.contains("// 첫 단계"), "a block of nothing but comments may be translated")

        // A line marker needs a space or the line start before it: a URL fragment and an operator next to code are code.
        for (language, code, changed) in [("bash", "open https://docs.example.com/guide#install", "open https://docs.example.com/guide#설치"),
                                          ("js", "const total = price*qty//discount", "const total = price*qty//할인")] {
            let restored = restore("예:\n```\(language)\n\(changed)\n```\n끝.", "Example:\n```\(language)\n\(code)\n```\nDone.", [SourceCodeBlock(language: language, code: code)])
            require(restored.text == "예:\n```\(language)\n\(code)\n```\n끝." && restored.outcome == CodeBlockGuard.Outcome(restored: 1), "no comment without a space: \(restored.text)")
        }
    }

    /// `'` quotes a character in Rust and Haskell and nothing in Lisp; a lifetime or a prime hides no comment after it.
    private static func apostrophes() {
        for (language, code, translated) in [("rust", "fn first<'a>(s: &'a str) -> &'a str { s } // returns the input", "fn first<'a>(s: &'a str) -> &'a str { s } // 입력을 그대로 반환"),
                                             ("haskell", "total = foldl' (+) 0 xs -- strict sum", "total = foldl' (+) 0 xs -- 엄격한 합"),
                                             ("rust", "let q = '\"'; // a quote", "let q = '\"'; // 따옴표"),
                                             ("clojure", "(def xs '(1 2)) ; a list", "(def xs '(1 2)) ; 목록")] {
            let output = "예:\n```\(language)\n\(translated)\n```\n끝."
            let restored = restore(output, "Example:\n```\(language)\n\(code)\n```\nDone.", [SourceCodeBlock(language: language, code: code)])
            require(restored.text == output && restored.outcome == CodeBlockGuard.Outcome(kept: 1), "the comment may be translated: \(restored.text)")
        }
        // A string still hides `//`.
        let string = SourceCodeBlock(language: "rust", code: "let s = \"a // b\";")
        let restored = restore("예:\n```rust\nlet s = \"a // 비\";\n```\n끝.", "Example:\n```rust\n\(string.code)\n```\nDone.", [string])
        require(restored.text.contains(string.code) && restored.outcome == CodeBlockGuard.Outcome(restored: 1), "`//` inside a Rust string starts no comment: \(restored.text)")
    }

    /// Text, output and data blocks stay byte for byte (decision B6).
    private static func verbatimBlocks() {
        for language in ["text", "json", "console", "diff"] {
            let block = SourceCodeBlock(language: language, code: "# Server started on port 8080")
            let restored = restore("예:\n```\(language)\n# 서버가 8080 포트에서 시작됨\n```\n끝.", "Example:\n```\(language)\n\(block.code)\n```\nDone.", [block])
            require(restored.text == "예:\n```\(language)\n# Server started on port 8080\n```\n끝." && restored.outcome.restored == 1, "\(language) is verbatim")
        }
    }

    private static func alteredLines() {
        let output = "스크립트는 실행 위치를 출력합니다:\n\n```python\nimport os\n# 작업 디렉터리를 출력합니다\nprint(os.getcwdd())\n```\n\n참고 문서를 보세요."
        let restored = restore(output, pythonInput, [python])
        require(restored.text == output.replacingOccurrences(of: "getcwdd", with: "getcwd") && restored.outcome == CodeBlockGuard.Outcome(restored: 1),
                "only the altered line reverts; the translated comment stays: \(restored.text)")
        let shorter = restore("스크립트:\n\n```python\nimport os\n```\n\n참고.", pythonInput, [python])
        require(shorter.text == "스크립트:\n\n```python\n\(python.code)\n```\n\n참고." && shorter.outcome.restored == 1, "a block missing lines comes back whole")
    }

    private static func unfencedBlocks() {
        let output = "스크립트는 실행 위치를 출력합니다:\n\nimport os\n# 작업 디렉터리를 출력합니다\nprint(os.getcwd())\n\n참고 문서를 보세요."
        let restored = restore(output, pythonInput, [python])
        require(restored.text == "스크립트는 실행 위치를 출력합니다:\n\n```python\nimport os\n# 작업 디렉터리를 출력합니다\nprint(os.getcwd())\n```\n\n참고 문서를 보세요."
                && restored.outcome == CodeBlockGuard.Outcome(refenced: 1), "dropped fences come back around intact code: \(restored.text)")
        let command = restore("Impeccable에게 요청하세요:\n\n/impeccable document\n코드를 살펴봅니다.", commandInput, [Self.command])
        require(command.text == commandResult && command.outcome.refenced == 1, "an unfenced command is fenced again")
    }

    /// "/impeccable 문서" is the command with a word translated: it becomes the block, never sits beside it.
    private static func translatedCommand() {
        let prose = restore("Impeccable에게 요청하세요:\n\n/impeccable 문서\n코드를 살펴봅니다.", commandInput, [command])
        require(prose.text == commandResult && prose.outcome.refenced == 1 && lines("/impeccable", in: prose.text) == 1,
                "the translated command is replaced: \(prose.text)")
        let fenced = restore("Impeccable에게 요청하세요:\n\n```text\n/impeccable 문서\n```\n코드를 살펴봅니다.", commandInput, [command])
        require(fenced.text == commandResult && fenced.outcome.restored == 1 && lines("/impeccable", in: fenced.text) == 1,
                "the same inside a fence, found where the block was")
        // A longer block whose other lines are gone: the translated first line still becomes the block, once.
        let commands = SourceCodeBlock(language: "text", code: "/impeccable document\n/impeccable audit\n/impeccable polish")
        let input = "Run these:\n\n```text\n\(commands.code)\n```\nThen review."
        let partial = restore("다음을 실행하세요:\n\n/impeccable 문서\n그다음 검토합니다.", input, [commands])
        require(intact(commands, in: partial.text, exact: true) == 1 && lines("/impeccable document", in: partial.text) == 1 && !partial.text.contains("/impeccable 문서"),
                "no block twice: \(partial.text)")
    }

    private static func missingBlocks() {
        let dropped = restore("Impeccable에게 요청하세요:\n\n코드를 살펴봅니다.", commandInput, [command])
        require(dropped.text == commandResult && dropped.outcome == CodeBlockGuard.Outcome(inserted: 1), "a dropped block returns to its slot: \(dropped.text)")
        // ko→en: prose that mentions the command's words is translation, not the block.
        let ko = SourceCodeBlock(language: "bash", code: "npm install express")
        let english = restore("Install express with npm:\nThen start the server.", "다음 명령으로 설치합니다:\n```bash\nnpm install express\n```\n그다음 서버를 시작합니다.", [ko])
        require(english.text == "Install express with npm:\n```bash\nnpm install express\n```\nThen start the server." && english.outcome.inserted == 1,
                "the sentence is not eaten: \(english.text)")
        // A translated command two lines from where the block was is the model's prose.
        let far = restore("테스트를 실행합니다.\n결과를 봅니다.\n또 봅니다.\nnpm 테스트\n끝.", "Run the tests.\n```bash\nnpm test\n```\nSee the result.\nAgain.\nDone.",
                          [SourceCodeBlock(language: "bash", code: "npm test")])
        require(far.text == "테스트를 실행합니다.\n```bash\nnpm test\n```\n결과를 봅니다.\n또 봅니다.\nnpm 테스트\n끝." && far.outcome == CodeBlockGuard.Outcome(inserted: 1),
                "only a line of drift: \(far.text)")
        // A line of more foreign letters than ASCII is a sentence, even one that starts with the command.
        let sentence = restore("파일 목록:\nls 디렉터리의모든파일\n끝.", "List files:\n```bash\nls -la\n```\nDone.", [SourceCodeBlock(language: "bash", code: "ls -la")])
        require(sentence.text == "파일 목록:\n```bash\nls -la\n```\nls 디렉터리의모든파일\n끝." && sentence.outcome == CodeBlockGuard.Outcome(inserted: 1),
                "the sentence stays: \(sentence.text)")
        let second = restore(pairResult.replacingOccurrences(of: "```js\nimport leftPad from 'left-pad';\nleftPad('7', 3, '0'); // => '007'\n```\n", with: ""),
                             pairInput, [shell, js])
        require(second.text == pairResult && second.outcome == CodeBlockGuard.Outcome(kept: 1, inserted: 1), "the second block is inserted after the first: \(second.text)")
        let first = restore("Run:\n\nDone.", "Run:\n\n```\nmake\n```\nDone.", [SourceCodeBlock(language: nil, code: "make")])
        require(first.text == "Run:\n\n```\nmake\n```\nDone.", "blank lines before the block stay before it")
        let atStart = restore("설명입니다.", "```\nmake\n```\nExplained.", [SourceCodeBlock(language: nil, code: "make")])
        require(atStart.text == "```\nmake\n```\n설명입니다.", "a block that opened the source opens the result")
        let atEnd = restore("설명입니다.\n", "Explained.\n```\nmake\n```\n", [SourceCodeBlock(language: nil, code: "make")])
        require(atEnd.text == "설명입니다.\n```\nmake\n```\n", "the output's final line break is kept")
    }

    private static func modelFences() {
        // A whole answer fenced at once: the lines around the block leave the fence as prose.
        let whole = restore("```\nImpeccable에게 요청하세요:\n/impeccable document\n코드를 살펴봅니다.\n```", commandInput, [command])
        require(whole.text == "Impeccable에게 요청하세요:\n```text\n/impeccable document\n```\n코드를 살펴봅니다." && whole.outcome.kept == 1,
                "a whole-answer fence is split: \(whole.text)")
        let both = restore("`npm`으로 패키지를 추가한 뒤 가져옵니다:\n\n```\nnpm install left-pad\nimport leftPad from 'left-pad';\nleftPad('7', 3, '0'); // => '007'\n```\n"
                           + "<a1>API 참고 문서</a1>에서 모든 옵션을 보세요.", pairInput, [shell, js])
        require(both.text == pairResult && both.outcome.kept == 2, "two blocks in one model fence are split: \(both.text)")
        // Fences the model added around other text stay as written.
        let extra = commandResult + " 예:\n```\nDESIGN.md\n```"
        let restored = restore(extra, commandInput, [command])
        require(restored.text == extra && restored.outcome.kept == 1, "extra model fences are untouched")
    }

    /// A sentence that starts with the command stays a sentence; the code line next to it is the block.
    private static func commandSentences() {
        let status = SourceCodeBlock(language: "bash", code: "git status")
        let ko = "git status로 변경 사항을 봅니다:\n```bash\ngit status\n```\n그다음 커밋합니다."
        let unfenced = restore("git status shows your changes:\ngit status\nThen commit.", ko, [status])
        require(unfenced.text == "git status shows your changes:\n```bash\ngit status\n```\nThen commit." && unfenced.outcome == CodeBlockGuard.Outcome(refenced: 1),
                "ko→en: the code line is fenced, the sentence stays: \(unfenced.text)")
        let dropped = restore("Check the status:\ngit status shows the state of the working tree.",
                              "상태를 확인합니다:\n```bash\ngit status\n```\ngit status는 작업 트리 상태를 보여 줍니다.", [status])
        require(dropped.text == "Check the status:\n```bash\ngit status\n```\ngit status shows the state of the working tree." && dropped.outcome.inserted == 1,
                "ko→en: a dropped block does not eat the sentence after it: \(dropped.text)")
        let install = SourceCodeBlock(language: "bash", code: "npm install")
        let english = restore("npm install을 먼저 실행하세요:\nnpm install\n그다음 서버를 시작합니다.", "Run npm install first:\n```bash\nnpm install\n```\nThen start the server.", [install])
        require(english.text == "npm install을 먼저 실행하세요:\n```bash\nnpm install\n```\n그다음 서버를 시작합니다." && english.outcome.refenced == 1,
                "en→ko: the same: \(english.text)")
        // Several translated commands in a row all become the block, even a line away from where it was.
        let commands = SourceCodeBlock(language: "text", code: "/impeccable document\n/impeccable audit\n/impeccable polish")
        let shifted = restore("먼저 다음을 확인하세요.\n다음을 실행하세요:\n\n/impeccable 문서\n/impeccable 감사\n/impeccable 다듬기\n그다음 검토합니다.",
                              "Run these:\n\n```text\n\(commands.code)\n```\nThen review.", [commands])
        require(shifted.text == "먼저 다음을 확인하세요.\n다음을 실행하세요:\n\n```text\n\(commands.code)\n```\n그다음 검토합니다." && shifted.outcome.refenced == 1,
                "every translated command is replaced: \(shifted.text)")
        // Unlabelled shell lines end options with `--`; what follows is code, not a comment.
        for (code, changed) in [("git checkout -- README.md", "git checkout -- 리드미.md"), ("npm test -- --watch", "npm test -- --감시")] {
            let block = SourceCodeBlock(language: nil, code: code)
            let restored = restore("예:\n```\n\(changed)\n```\n끝.", "Example:\n```\n\(code)\n```\nDone.", [block])
            require(restored.text == "예:\n```\n\(code)\n```\n끝." && restored.outcome.restored == 1, "`--` starts no comment: \(restored.text)")
        }
    }

    /// A block looks for itself only between the blocks around it that stand intact, so it never takes their fences.
    private static func neighbours() {
        // GitHub README shape: the first block unfenced, the second with its string translated.
        let install = SourceCodeBlock(language: "bash", code: "npm install greet"), greet = SourceCodeBlock(language: "js", code: "greet(\"Hello\");")
        let readme = "Add it:\n\n```bash\nnpm install greet\n```\n```js\ngreet(\"Hello\");\n```\nDone."
        let pair = restore("추가합니다:\n\nnpm install greet\n```js\ngreet(\"안녕하세요\");\n```\n끝.", readme, [install, greet])
        require(pair.text == "추가합니다:\n\n```bash\nnpm install greet\n```\n```js\ngreet(\"Hello\");\n```\n끝."
                && pair.outcome == CodeBlockGuard.Outcome(restored: 1, refenced: 1), "each block in its own place: \(pair.text)")
        // A dropped first block does not take a later fence that has its line.
        let blocks = [SourceCodeBlock(language: "bash", code: "npm test"), SourceCodeBlock(language: "bash", code: "npm run build"),
                      SourceCodeBlock(language: "bash", code: "npm run build\nnpm test")]
        let input = "Run the tests:\n```bash\nnpm test\n```\nBuild it:\n```bash\nnpm run build\n```\nOr both:\n```bash\nnpm run build\nnpm test\n```\nDone."
        let dropped = restore("테스트를 실행합니다:\n빌드합니다:\n```bash\nnpm run build\n```\n둘 다:\n```bash\nnpm run build\nnpm test\n```\n끝.", input, blocks)
        require(dropped.text == "테스트를 실행합니다:\n```bash\nnpm test\n```\n빌드합니다:\n```bash\nnpm run build\n```\n둘 다:\n```bash\nnpm run build\nnpm test\n```\n끝."
                && dropped.outcome == CodeBlockGuard.Outcome(kept: 2, inserted: 1), "the dropped block goes back to its slot: \(dropped.text)")
        // A fence where a dropped block was that is mostly the next block is the next block's, translated comment and all.
        let ci = SourceCodeBlock(language: "bash", code: "npm ci\nnpm test"), build = SourceCodeBlock(language: "bash", code: "npm run build # bundle\nnpm run lint")
        let next = restore("테스트하고 빌드합니다:\n```bash\nnpm run build # 번들\nnpm run 린트\n```\n끝.",
                           "Test and build it:\n```bash\nnpm ci\nnpm test\n```\n```bash\n\(build.code)\n```\nDone.", [ci, build])
        require(next.text == "테스트하고 빌드합니다:\n```bash\nnpm ci\nnpm test\n```\n```bash\nnpm run build # 번들\nnpm run lint\n```\n끝."
                && next.outcome == CodeBlockGuard.Outcome(restored: 1, inserted: 1), "the next block's fence is not taken: \(next.text)")
        // A translated command a line away from a missing block is the next one's when it is right at its place.
        let audit = SourceCodeBlock(language: "text", code: "/impeccable audit")
        let claimed = restore("디자인을 문서로 남깁니다: /impeccable document\n감사합니다:\n/impeccable 감사\n끝.",
                              "Document the design:\n```text\n/impeccable document\n```\nAudit it:\n```text\n/impeccable audit\n```\nDone.", [command, audit])
        require(claimed.text == "디자인을 문서로 남깁니다: /impeccable document\n```text\n/impeccable document\n```\n감사합니다:\n```text\n/impeccable audit\n```\n끝."
                && claimed.outcome == CodeBlockGuard.Outcome(refenced: 1, inserted: 1), "each block under its own line: \(claimed.text)")
        let fenced = restore("디자인을 문서로 남깁니다: /impeccable document\n감사합니다:\n```text\n/impeccable 감사\n```\n끝.",
                             "Document the design:\n```text\n/impeccable document\n```\nAudit it:\n```text\n/impeccable audit\n```\nDone.", [command, audit])
        require(fenced.text == claimed.text && fenced.outcome == CodeBlockGuard.Outcome(restored: 1, inserted: 1), "and its fence: \(fenced.text)")
        // A whole answer fenced without the block is no altered block: the translation stays.
        let whole = restore("```\nImpeccable에게 요청하세요:\n코드를 살펴봅니다.\n```", commandInput, [command])
        require(whole.text.hasPrefix("```\nImpeccable에게 요청하세요:\n코드를 살펴봅니다.\n```") && whole.outcome.inserted == 1, "the fenced translation stays: \(whole.text)")
        // Two blocks found in one fenced answer with one between them missing: it goes in between.
        let middle = restore("`npm`으로 패키지를 추가한 뒤 가져옵니다:\n\n```\nnpm install left-pad\n그리고\nimport leftPad from 'left-pad';\nleftPad('7', 3, '0'); // => '007'\n```",
                             pairInput.replacingOccurrences(of: "```\n```js", with: "```\nAnd:\n```text\nnpm ls\n```\n```js"),
                             [shell, SourceCodeBlock(language: "text", code: "npm ls"), js])
        require(middle.text.contains("```shell\nnpm install left-pad\n```\n```text\nnpm ls\n```\n그리고\n```js\n") && middle.outcome == CodeBlockGuard.Outcome(kept: 2, inserted: 1),
                "inserted inside the split answer: \(middle.text)")
    }

    /// A whole answer fenced at once is prose around the blocks: translated commands in it become blocks, and the
    /// translation around them stays.
    private static func wholeAnswerFences() {
        let alone = restore("```\nImpeccable에게 요청하세요:\n/impeccable 문서\n코드를 살펴봅니다.\n```", commandInput, [command])
        require(alone.text == "Impeccable에게 요청하세요:\n```text\n/impeccable document\n```\n코드를 살펴봅니다." && alone.outcome.restored == 1,
                "the fence gives up only the command: \(alone.text)")
        let install = SourceCodeBlock(language: "shell", code: "npm install left-pad")
        let input = "Ask for it:\n```text\n/impeccable document\n```\nInstall:\n```shell\nnpm install left-pad\n```\nDone."
        let before = restore("```\n요청하세요:\n/impeccable 문서\n설치:\nnpm install left-pad\n```\n끝.", input, [command, install])
        require(before.text == "요청하세요:\n```text\n/impeccable document\n```\n설치:\n```shell\nnpm install left-pad\n```\n끝."
                && before.outcome == CodeBlockGuard.Outcome(kept: 1, refenced: 1), "a command before an intact block in the fence: \(before.text)")
        let after = restore("```\n설치:\nnpm install left-pad\n요청하세요:\n/impeccable 문서\n```\n끝.",
                            "Install:\n```shell\nnpm install left-pad\n```\nAsk for it:\n```text\n/impeccable document\n```\nDone.", [install, command])
        require(after.text == "설치:\n```shell\nnpm install left-pad\n```\n요청하세요:\n```text\n/impeccable document\n```\n끝."
                && after.outcome == CodeBlockGuard.Outcome(kept: 1, refenced: 1), "and after it: \(after.text)")
    }

    /// Fence lines the model wrote inside a fence it opened around an opener of the app's leave with that fence: none
    /// becomes prose that fences what follows, nor a code line of a block.
    private static func modelFenceLines() {
        let script = SourceCodeBlock(language: "python", code: "import os\nprint(os.getcwd())"), run = SourceCodeBlock(language: "bash", code: "python main.py")
        let input = "Write the script:\n```python\nimport os\nprint(os.getcwd())\n```\nThen run it:\n```bash\npython main.py\n```\nDone."
        let result = "스크립트를 작성합니다:\n```python\nimport os\nprint(os.getcwd())\n```\n그다음 실행합니다:\n```bash\npython main.py\n```\n끝."
        let missingCloser = restore("스크립트를 작성합니다:\n```python\nimport os\nprint(os.getcwd())\n그다음 실행합니다:\n```bash\npython main.py\n```\n끝.", input, [script, run])
        require(missingCloser.text == result && missingCloser.outcome == CodeBlockGuard.Outcome(kept: 2), "the first closer missing: \(missingCloser.text)")
        // ```markdown around the whole answer ends at the first closer; the bare fence left at the end shows nothing.
        let wrapped = restore("```markdown\n" + result + "\n```", input, [script, run])
        require(wrapped.text == result + "\n```" && wrapped.outcome == CodeBlockGuard.Outcome(kept: 2)
                && TranslationMarkup(wrapped.text).displayText == TranslationMarkup(result).displayText, "the whole answer wrapped: \(wrapped.text)")
        let install = SourceCodeBlock(language: "bash", code: "npm install left-pad"), test = SourceCodeBlock(language: "bash", code: "npm test")
        let closedWithTag = restore("설치합니다:\n```bash\nnpm install left-pad\n```bash\n테스트합니다:\n```bash\nnpm test\n```\n끝.",
                                    "Install it:\n```bash\nnpm install left-pad\n```\nTest it:\n```bash\nnpm test\n```\nDone.", [install, test])
        require(closedWithTag.text == "설치합니다:\n```bash\nnpm install left-pad\n```\n테스트합니다:\n```bash\nnpm test\n```\n끝." && closedWithTag.outcome == CodeBlockGuard.Outcome(kept: 2),
                "```bash as the first block's closer: \(closedWithTag.text)")
        // The same around a block the model changed.
        let changed = restore("```markdown\n스크립트:\n```python\nimport os\nprint(os.getcwdd())\n```\n끝.\n```", "Script:\n```python\nimport os\nprint(os.getcwd())\n```\nDone.", [script])
        require(changed.text.hasPrefix("스크립트:\n```python\nimport os\nprint(os.getcwd())\n```\n") && lines("```python", in: changed.text) == 1
                && changed.outcome == CodeBlockGuard.Outcome(restored: 1), "a changed block in a wrapped answer: \(changed.text)")
        // A repair that would not read back leaves the output as the model wrote it.
        let make = SourceCodeBlock(language: nil, code: "make"), unreadable = "실행합니다:\n```\nmake\n```bash\n끝."
        require(CodeBlockGuard.restore(unreadable, source: "Run it:\n```\nmake\n```\nDone.", blocks: [make]) == (unreadable, CodeBlockGuard.Outcome(skipped: true)),
                "an unlabelled block closed with ```bash is left alone")
    }

    /// Where intact blocks go, prose lines that may be an unfenced block count as no prose, in the model input and the
    /// output alike: identical blocks each keep their place.
    private static func identicalBlocks() {
        let one = SourceCodeBlock(language: "python", code: "x = 1")
        let input = "가.\n```python\nx = 1\n```\n나.\n```python\nx = 1\n```\n다.\n```python\nx = 1\n```\n라."
        let restored = restore("가.\nx = 1\n나.\n```python\nx = 1\n```\n다.\n라.", input, [one, one, one])
        require(restored.text == input && restored.outcome == CodeBlockGuard.Outcome(kept: 1, refenced: 1, inserted: 1), "one block under each line: \(restored.text)")
        // A code line the model input also has as prose stays prose; the block stays the fence where it was.
        let test = SourceCodeBlock(language: "bash", code: "npm test")
        let output = "이 명령을 쓰세요.\n\nnpm test\n\n실행하세요:\n```bash\nnpm test\n```\n끝."
        let echo = restore(output, "Use this command.\n\nnpm test\n\nRun it:\n```bash\nnpm test\n```\nDone.", [test])
        require(echo.text == output && echo.outcome == CodeBlockGuard.Outcome(kept: 1) && intact(test, in: echo.text) == 1, "the fence where the block was wins: \(echo.text)")
    }

    /// A block titled by the page's selected tab: its opener comes back byte for byte whatever the model did to it, and the
    /// title the model also wrote as a line of its own right above the block goes, so it shows once.
    private static func titles() {
        let block = SourceCodeBlock(language: "text", code: "/impeccable document", title: "Most Agents")
        let input = "Ask Impeccable to write down the design you have:\n\n```text title=\"Most Agents\"\n/impeccable document\n```\nIt scans the code."
        let result = "Impeccable에게 요청하세요:\n\n```text title=\"Most Agents\"\n/impeccable document\n```\n코드를 살펴봅니다."
        let kept = restore(result, input, [block])
        require(kept.text == result && kept.outcome == CodeBlockGuard.Outcome(kept: 1), "a titled block is kept: \(kept.text)")
        for (opener, closer) in [("```text title=\"대부분의 에이전트\"", "```"), ("```text title='Most Agents'", "```"), ("```text", "```"), ("```", "```"),
                                 ("````TEXT title=\"Most Agents\"", "````"), ("```text title=Most Agents", "```"), ("```text title=\"Most Agents", "```")] {
            let restored = restore("Impeccable에게 요청하세요:\n\n\(opener)\n/impeccable document\n\(closer)\n코드를 살펴봅니다.", input, [block])
            require(restored.text == result && restored.outcome == CodeBlockGuard.Outcome(kept: 1), "a translated, changed or dropped title comes back: \(opener)")
        }
        // Unfenced, translated, rewritten under the block's tag, or missing: the whole opener goes back in.
        for (body, outcome) in [("/impeccable document", CodeBlockGuard.Outcome(refenced: 1)), ("/impeccable 문서", CodeBlockGuard.Outcome(refenced: 1)),
                                ("```text title=\"Most Agents\"\n/impeccable 문서\n```", CodeBlockGuard.Outcome(restored: 1)),
                                ("```text title=\"Most Agents\"\n완전히 다른 내용\n```", CodeBlockGuard.Outcome(restored: 1)),
                                ("```text title=Most Agents\n/impeccable 문서\n```", CodeBlockGuard.Outcome(restored: 1)), ("", CodeBlockGuard.Outcome(inserted: 1))] {
            let restored = restore("Impeccable에게 요청하세요:\n\n\(body.isEmpty ? "" : body + "\n")코드를 살펴봅니다.", input, [block])
            require(restored.text == result && restored.outcome == outcome, "re-fenced or inserted with its title: \(body) → \(restored.text)")
        }
        // The title also written as a line right above the block, verbatim or as all of that line, goes.
        for title in ["Most Agents", "  Most   Agents "] {
            for body in ["```text title=\"Most Agents\"\n/impeccable document\n```", "```\n/impeccable document\n```", "/impeccable document", "/impeccable 문서", ""] {
                let restored = restore("Impeccable에게 요청하세요:\n\n\(title)\n\(body.isEmpty ? "" : body + "\n")코드를 살펴봅니다.", input, [block])
                require(restored.text == result, "the title shows once: \(title.debugDescription) \(body) → \(restored.text)")
            }
        }
        // A translated title is the model's own prose, and a title line the model input has above the block too stays.
        let translated = "Impeccable에게 요청하세요:\n\n대부분의 에이전트\n```text title=\"Most Agents\"\n/impeccable document\n```\n코드를 살펴봅니다."
        require(restore(translated, input, [block]).text == translated, "a translated title line stays")
        let heading = restore("설치\n\nnpm\n```bash title=\"npm\"\nnpm i foo\n```\n끝.", "Install\n\nnpm\n\n```bash title=\"npm\"\nnpm i foo\n```\nDone.",
                              [SourceCodeBlock(language: "bash", code: "npm i foo", title: "npm")])
        require(heading.text == "설치\n\nnpm\n```bash title=\"npm\"\nnpm i foo\n```\n끝.", "the input's line a blank line above stays: \(heading.text)")
        let own = "Most Agents\n```text title=\"Most Agents\"\n/impeccable document\n```\n"
        require(restore(own + "끝.", own + "Done.", [block]).text == own + "끝.", "the input's own line stays")
        require(restore("Most Agents\n끝.", own + "Done.", [block]).text == own + "끝.", "a dropped block goes back under the input's own line")
        // Title lines the model writes are no prose of the model input, which has the opener there: they move no block.
        let npm = SourceCodeBlock(language: "bash", code: "npm install foo\nnpm run build", title: "npm")
        let pair = "Ask Impeccable to write down the design you have:\n\n\(block.opener)\n/impeccable document\n```\nIt scans the code.\n\nInstall it:\n\(npm.opener)\n\(npm.code)\n```\nDone."
        let both = restore("Impeccable에게 요청하세요:\n\nMost Agents\n/impeccable 문서\n코드를 살펴봅니다.\n\n설치하세요:\nnpm\nnpm install foo\nnpm run 빌드\n끝.", pair, [block, npm])
        require(both.text == "Impeccable에게 요청하세요:\n\n\(block.opener)\n/impeccable document\n```\n코드를 살펴봅니다.\n\n설치하세요:\n\(npm.opener)\n\(npm.code)\n```\n끝."
                && both.outcome == CodeBlockGuard.Outcome(refenced: 2), "two unfenced titled blocks are fenced in place: \(both.text)")
        let longer = restore("소개.\n\n설치는 간단합니다.\n이렇게 하세요:\nnpm\nnpm install foo\nnpm run 빌드\n끝.", "Intro.\n\nInstall it:\n\(npm.opener)\n\(npm.code)\n```\nDone.", [npm])
        require(longer.text == "소개.\n\n설치는 간단합니다.\n이렇게 하세요:\n\(npm.opener)\n\(npm.code)\n```\n끝." && longer.outcome == CodeBlockGuard.Outcome(refenced: 1),
                "a title line and a sentence split in two are one line of drift: \(longer.text)")
        // A title with a double quote is single-quoted, and a block without a language is tagged text for it.
        let quoted = SourceCodeBlock(language: nil, code: "make", title: "Say \"hi\"")
        let back = restore("실행:\n```\nmake\n```\n끝.", "Run:\n```text title='Say \"hi\"'\nmake\n```\nDone.", [quoted])
        require(back.text == "실행:\n```text title='Say \"hi\"'\nmake\n```\n끝.", "a single-quoted title comes back: \(back.text)")
    }

    /// A model that shortens a four-backtick fence still leaves exactly one intact block.
    private static func shortenedFence() {
        let block = SourceCodeBlock(language: "md", code: "```js\nx\n```")
        let input = "예시:\n````md\n```js\nx\n```\n````\n끝."
        for output in ["Example:\n```md\n```js\nx\n```\n```\nEnd.", TranslationMarkup.normalized("Example:\n```md\n```js\nx\n```\n```\nEnd.", source: input)] {
            let restored = restore(output, input, [block])
            require(intact(block, in: restored.text, exact: true) == 1 && TranslationMarkup(restored.text).displayText.hasPrefix("Example:\n```js\nx\n```\n"),
                    "one intact block: \(restored.text)")
        }
    }

    private static func skipped() {
        let output = "번역입니다."
        require(CodeBlockGuard.restore(output, source: "Translated.", blocks: [command]) == (output, CodeBlockGuard.Outcome(skipped: true)),
                "a model input without the blocks changes nothing")
        require(CodeBlockGuard.restore(output, source: commandInput, blocks: []) == (output, CodeBlockGuard.Outcome()), "no blocks, no work")
        let other = SourceCodeBlock(language: "text", code: "/impeccable audit")
        require(CodeBlockGuard.restore(output, source: commandInput, blocks: [other]).outcome.skipped, "blocks that differ from the input are not trusted")
    }

    /// A–B contract: checks run against the model input, whose fences take the restored code out of the echo check.
    private static func composition() {
        let block = SourceCodeBlock(language: "python", code: "result = compute_everything(arguments, verbose=True)")
        let input = "Run the helper to compute every value in one call.\n\n```python\n\(block.code)\n```\n\nThe result holds one entry per argument."
        let output = "도우미를 실행해 모든 값을 한 번에 계산합니다.\n\n\(block.code)\n\n결과에는 인자마다 항목이 하나씩 들어 있습니다."
        let restored = restore(output, input, [block])
        require(restored.outcome.refenced == 1, "the code is fenced again")
        let rules = TranslationOutputLint.lint(source: input, output: restored.text, sourceLanguage: "en", targetLanguage: "ko").map(\.rule)
        require(!rules.contains(.sourceEcho), "restored code is no source echo: \(rules)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "CodeBlockGuardTests: \(message)")
    }
}
