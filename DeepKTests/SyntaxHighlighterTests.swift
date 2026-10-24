import Foundation

@main
private enum SyntaxHighlighterTests {
    static func main() {
        languageFamilies()
        multilineState()
        utf16Offsets()
        aliases()
        textCommands()
        cacheRepaintsFromTheFirstChangedLine()
        lineByLineEqualsStreamed()
        print("SyntaxHighlighterTests passed")
    }

    /// Every family in one sample each: the colored runs in order, by their text and kind.
    static let samples: [(tag: String, text: String, expected: [[String]])] = [
        ("ts", "// wire\nimport { getModel } from 'ai';\nconst ctx = await loadContext(repo);\nexport class Foo<T> extends Bar { x: number = 0x1F }", [
            ["comment // wire"],
            ["keyword import", "keyword from", "string 'ai'"],
            ["keyword const", "keyword await", "function loadContext"],
            ["keyword export", "keyword class", "type Foo", "type T", "keyword extends", "type Bar", "type number", "number 0x1F"]
        ]),
        ("js", "const s = `a\n${b}` + $el; // c", [
            ["keyword const", "string `a"],
            ["string ${b}`", "comment // c"]
        ]),
        ("py", "@dataclass\ndef greet(name: str) -> None:\n    print(f\"hi {name}\", 1.5e-3)  # 주석", [
            ["function @dataclass"],
            ["keyword def", "function greet", "type str", "keyword None"],
            ["function print", "string f\"hi {name}\"", "number 1.5e-3", "comment # 주석"]
        ]),
        ("swift", "@MainActor func f() -> Int { return nil }\n#if DEBUG", [
            ["function @MainActor", "keyword func", "function f", "type Int", "keyword return", "keyword nil"],
            ["keyword #if", "type DEBUG"]
        ]),
        ("go", "func main() { s := `raw\\n` }", [["keyword func", "function main", "string `raw\\n`"]]),
        ("rust", "fn main<'a>(x: &'a str) { println!(\"{}\", 'c'); /* a /* b */ c */ }", [
            ["keyword fn", "function main", "type 'a", "type 'a", "type str", "function println!", "string \"{}\"", "string 'c'",
             "comment /* a /* b */ c */"]
        ]),
        ("java", "@Override public String name() { return \"x\"; }", [
            ["function @Override", "keyword public", "type String", "function name", "keyword return", "string \"x\""]
        ]),
        ("kotlin", "fun greet(): Unit = println(\"hi\")", [["keyword fun", "function greet", "type Unit", "function println", "string \"hi\""]]),
        ("c", "#include <stdio.h>\nint main(void) { return 0; }", [
            ["keyword #include", "string <stdio.h>"],
            ["keyword int", "function main", "keyword void", "keyword return", "number 0"]
        ]),
        ("rb", "class Foo\n  def bar = @baz # c", [["keyword class", "type Foo"], ["keyword def", "function bar", "property @baz", "comment # c"]]),
        ("sh", "# install\nNODE_ENV=production npm run build -- --watch && echo \"$HOME\" | grep -i ${USER}\nsudo apt-get install -y curl \\\n  --no-install-recommends", [
            ["comment # install"],
            ["property NODE_ENV", "command npm", "flag --", "flag --watch", "command echo", "string \"$HOME\"", "command grep", "flag -i",
             "property ${USER}"],
            ["command sudo", "command apt-get", "flag -y"],
            ["flag --no-install-recommends"]
        ]),
        ("json", "{\"a\": 1, \"b\": [true, null, -2]} // c", [
            ["property \"a\"", "number 1", "property \"b\"", "keyword true", "keyword null", "number -2", "comment // c"]
        ]),
        ("yaml", "name: deepk # c\n- key: \"v\"\n  on: true\nanchor: &a 12", [
            ["property name", "comment # c"], ["property key", "string \"v\""], ["property on", "keyword true"],
            ["property anchor", "type &a", "number 12"]
        ]),
        ("toml", "[tool.x]\nname = \"deepk\" # c\nversion = 1.2", [
            ["type [tool.x]"], ["property name", "string \"deepk\"", "comment # c"], ["property version", "number 1.2"]
        ]),
        ("html", "<!DOCTYPE html>\n<div class=\"a\" id=x>&amp;</div>", [
            ["keyword <!DOCTYPE html>"],
            ["tag <div", "property class", "string \"a\"", "property id", "string x", "tag >", "number &amp;", "tag </div", "tag >"]
        ]),
        ("css", ".a, #b:hover {\n  color: #fff !important;\n  margin: 0 10px;\n}\n@media (max-width: 600px) { a { b: 1 } }", [
            ["tag .a", "tag #b", "tag :hover"], ["property color", "number #fff", "keyword !important"],
            ["property margin", "number 0", "number 10px"], [],
            ["keyword @media", "number 600px", "tag a", "property b", "number 1"]
        ]),
        ("sql", "SELECT COUNT(*) FROM users WHERE name = 'a' -- c", [
            ["keyword SELECT", "function COUNT", "keyword FROM", "keyword WHERE", "string 'a'", "comment -- c"]
        ]),
        // Escapes, raw strings and lines that go on in a construct the line before opened.
        ("ts", "const s = \"say \\\"hi\\\"\";", [["keyword const", "string \"say \\\"hi\\\"\""]]),
        ("py", "x = \"\"\"a \\\"\"\" b\"\"\" + f(x)", [["string \"\"\"a \\\"\"\" b\"\"\"", "function f"]]),
        ("go", "s := `C:\\`; f(x)", [["string `C:\\`", "function f"]]),
        ("jsonc", "{\n/* a\nb */ \"k\": 1\n}", [[], ["comment /* a"], ["comment b */", "property \"k\"", "number 1"], []]),
        ("toml", "s = \"\"\"\nbody = x\n\"\"\"", [["property s", "string \"\"\""], ["string body = x"], ["string \"\"\""]]),
        ("ts", "x = 0x1e+5", [["number 0x1e", "number 5"]]),
        ("sh", "FOO=\"a b\" npm test", [["property FOO", "string \"a b\"", "command npm"]]),
        ("rust", "let s = \"first\n// not a comment\nfn x\";\nfn main() {}", [
            ["keyword let", "string \"first"], ["string // not a comment"], ["string fn x\""], ["keyword fn", "function main"]
        ]),
        ("rust", "let r = r#\"a \"quoted\"\nb\"#; let c = br\"\\\";", [
            ["keyword let", "string r#\"a \"quoted\""], ["string b\"#", "keyword let", "string br\"\\\""]
        ]),
        ("cpp", "auto s = R\"x(first\nint x; )\" return\n)x\"; int y;", [
            ["keyword auto", "string R\"x(first"], ["string int x; )\" return"], ["string )x\"", "keyword int"]
        ]),
        ("sh", "echo 'first\nrm -rf second'\nls -la", [["command echo", "string 'first"], ["string rm -rf second'"], ["command ls", "flag -la"]]),
        ("sh", "curl -d \"{\n  \\\"a\\\": 1\n}\" https://x", [["command curl", "flag -d", "string \"{"], ["string   \\\"a\\\": 1"], ["string }\""]]),
        ("sh", "echo It's here\necho don\\'t\nls", [["command echo", "string 's here"], ["command echo"], ["command ls"]]),
        ("html", "<script>\nfor (let i = 0; i<items.length; i++) {\n</script>\n<p>", [
            ["tag <script", "tag >"], [], ["tag </script", "tag >"], ["tag <p", "tag >"]
        ]),
        ("vue", "<script setup>\nif (count.value<limit) go()\n</SCRIPT><style>a<b</style>", [
            ["tag <script", "property setup", "tag >"], [], ["tag </SCRIPT", "tag >", "tag <style", "tag >", "tag </style", "tag >"]
        ]),
        ("svelte", "{#if count<max}\n  <p>ok</p>\n{/if}", [[], ["tag <p", "tag >", "tag </p", "tag >"], []]),
        ("js", "app.get('/', h); x.set(1); obj.from; f(...this)", [["function get", "string '/'", "function set", "number 1", "function f", "keyword this"]]),
        ("kotlin", "val value = entry.value", [["keyword val", "keyword value"]]),
        ("java", "range.to(); this.with", [["function to", "keyword this"]]),
        ("swift", "let a = Foo.self; b = .init()", [["keyword let", "type Foo", "keyword self", "keyword init"]]),
        ("scss", "$primary: #333;\na { color: $primary; }", [["property $primary", "number #333"], ["tag a", "property color"]]),
        ("less", "@primary: #333;\n@media (max-width: 600px) {}", [["property @primary", "number #333"], ["keyword @media", "number 600px"]]),
        // One search for the next `{`, `;` or `}` serves the line until it is passed.
        ("css", "a { x: 1; p:hover { y: 2 } }", [["tag a", "property x", "number 1", "tag p", "tag :hover", "property y", "number 2"]])
    ]

    private static func described(_ line: String, _ tokens: [SyntaxToken]) -> [String] {
        tokens.map { "\($0.kind) \((line as NSString).substring(with: $0.range))" }
    }

    private static func languageFamilies() {
        for sample in samples {
            let highlighter = SyntaxHighlighter(tag: sample.tag)!
            let lines = sample.text.components(separatedBy: "\n")
            let tokens = highlighter.tokenize(sample.text)
            require(tokens.count == lines.count, "\(sample.tag): one token list per line")
            for (index, line) in lines.enumerated() {
                require(described(line, tokens[index]) == sample.expected[index],
                        "\(sample.tag) line \(index + 1): \(described(line, tokens[index]))")
                // Ranges are in order and never overlap.
                require(zip(tokens[index], tokens[index].dropFirst()).allSatisfy { NSMaxRange($0.range) <= $1.range.location },
                        "\(sample.tag) line \(index + 1): ordered, separate runs")
            }
        }
    }

    /// Comments, strings and tags that span lines carry their state to the next line.
    private static func multilineState() {
        func states(_ tag: String, _ text: String) -> [SyntaxLineState] {
            let highlighter = SyntaxHighlighter(tag: tag)!
            var state = SyntaxLineState.normal
            return text.components(separatedBy: "\n").map { line in
                state = highlighter.tokenize(line.utf16, from: state).end
                return state
            }
        }
        require(states("ts", "a /* one\ntwo\nthree */ b") == [.blockComment(depth: 1), .blockComment(depth: 1), .normal], "block comment")
        require(states("rust", "/* a /* b\n*/ still\n*/ done") == [.blockComment(depth: 2), .blockComment(depth: 1), .normal],
                "nested block comment")
        require(states("py", "s = \"\"\"doc\nmore\n\"\"\" + x") == [.string(0), .string(0), .normal], "Python triple quotes")
        require(states("js", "const t = `a\n${b}\nc`;") == [.string(0), .string(0), .normal], "template literal")
        require(states("html", "<!-- a\nb\n--> <p>") == [.markupComment, .markupComment, .normal], "markup comment")
        require(states("html", "<a\n  href=\"/\"\n>x</a>") == [.markupTag, .markupTag, .normal], "a tag over lines")
        require(states("css", "a {\n  b { c: 1;\n  }\n}") == [.css(depth: 1), .css(depth: 2), .css(depth: 1), .normal], "CSS braces")
        require(states("css", "a { /* x\ny */ }") == [.cssComment(depth: 1), .normal], "CSS comment inside braces")
        require(states("sh", "docker run \\\n  --rm image\nls") == [.continued, .normal, .normal], "shell continuation")
        require(states("rust", "\"a\nb\" c") == [.string(0), .normal], "Rust string")
        require(states("rust", "r##\"a\"#\nb\"##") == [.rawString(close: "\"##"), .normal], "Rust raw string with hashes")
        require(states("cpp", "R\"(a\nb)\"") == [.rawString(close: ")\""), .normal], "C++ raw string")
        require(states("sh", "echo \"a\nb\\\"\nc\"") == [.string(0), .string(0), .normal], "shell double quotes with an escaped quote")
        require(states("sh", "echo 'a\\\nb'") == [.string(1), .normal], "a backslash in single quotes is plain")
        require(states("html", "<script\n  src=x>\nlet a = b<c;\n</script>") == [.markupRawTag(0), .markupRaw(0), .markupRaw(0), .normal],
                "script text is not markup until its closing tag")
        require(states("html", "<script src=x />\n<p>") == [.normal, .normal], "a self-closed script has no text")

        // A continued line goes on scanning the same construct.
        let python = SyntaxHighlighter(tag: "py")!
        let doc = python.tokenize("more \"\"\" + x".utf16, from: .string(0))
        require(described("more \"\"\" + x", doc.tokens) == ["string more \"\"\""] && doc.end == .normal, "a string closes on a later line")
        let css = SyntaxHighlighter(tag: "css")!
        require(described("  color: red;", css.tokenize("  color: red;".utf16, from: .css(depth: 1)).tokens) == ["property color"],
                "inside braces a name before a colon is a property")
        require(described("  color: red;", css.tokenize("  color: red;".utf16, from: .normal).tokens) == ["tag color", "tag red"],
                "outside braces it is a selector")
        let shell = SyntaxHighlighter(tag: "sh")!
        require(described("  image --rm", shell.tokenize("  image --rm".utf16, from: .continued).tokens) == ["flag --rm"],
                "a continued command has no command word")
    }

    /// Ranges are UTF-16 offsets: Korean and emoji keep every run exact, and a surrogate pair is never split.
    private static func utf16Offsets() {
        let python = SyntaxHighlighter(tag: "py")!
        let line = "s = \"😀한\"  # 한글 주석 🎉"
        let tokens = python.tokenize(line.utf16, from: .normal).tokens
        require(tokens == [SyntaxToken(kind: .string, range: NSRange(location: 4, length: 5)),
                           SyntaxToken(kind: .comment, range: NSRange(location: 11, length: 10))], "string and comment ranges: \(tokens)")
        let ts = SyntaxHighlighter(tag: "ts")!
        let named = "const 값😀 = 42;"
        require(described(named, ts.tokenize(named.utf16, from: .normal).tokens) == ["keyword const", "number 42"],
                "a non-ASCII name stays one plain run and the number after it keeps its place")
        for (tag, text) in [("ts", "/* 🎉\n주석 */ x"), ("sh", "echo \"😀\" # 🎉"), ("html", "<p title=\"😀\">한</p>")] {
            let ns = text as NSString
            var offset = 0
            for (line, lineTokens) in zip(text.components(separatedBy: "\n"), SyntaxHighlighter(tag: tag)!.tokenize(text)) {
                for token in lineTokens {
                    let start = offset + token.range.location, end = offset + NSMaxRange(token.range)
                    require(ns.rangeOfComposedCharacterSequence(at: start).location == start
                            && (end == ns.length || ns.rangeOfComposedCharacterSequence(at: end).location == end),
                            "\(tag): runs start and end on character boundaries")
                }
                offset += line.utf16.count + 1
            }
        }
    }

    private static func aliases() {
        let families: [String: String] = [
            "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript", "TypeScript": "typescript",
            "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript", "javascript": "javascript",
            "py": "python", "python": "python", "python3": "python", "swift": "swift", "go": "go", "golang": "go", "rs": "rust",
            "rust": "rust", "java": "java", "kt": "kotlin", "kts": "kotlin", "kotlin": "kotlin", "c": "c", "h": "c", "cpp": "cpp",
            "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "rb": "ruby", "ruby": "ruby",
            "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "json": "json", "jsonc": "json", "json5": "json",
            "yaml": "yaml", "yml": "yaml", "toml": "toml", "html": "html", "htm": "html", "vue": "html", "svelte": "html",
            "astro": "html", "xml": "xml", "svg": "xml", "plist": "xml", "css": "css", "scss": "css", "sass": "css", "less": "css",
            "sql": "sql", "text": "text", "txt": "text", "plaintext": "text", "plain": "text", "console": "text",
            "terminal": "text", "shell-session": "text"
        ]
        for (tag, family) in families {
            require(SyntaxLanguages.grammar(for: tag)?.name == family, "\(tag) uses \(family)")
        }
        require(SyntaxLanguages.tags.count == Set(families.keys.map { $0.lowercased() }).count, "every alias is listed here")
        for tag in [nil, "", "brainfuck", "diff", "mermaid", "powershell"] as [String?] {
            require(SyntaxHighlighter(tag: tag) == nil, "\(tag ?? "nil") gets no color")
        }
    }

    /// A text block colors only command lines: a prompt and its command, or a slash command. Everything else stays plain.
    private static func textCommands() {
        let text = SyntaxHighlighter(tag: "text")!
        let cases: [(String, [String])] = [
            ("/impeccable document", ["command /impeccable"]),
            ("  /impeccable teach --deep \"x\"", ["command /impeccable", "flag --deep", "string \"x\""]),
            ("$ npm install -D deepk", ["comment $", "command npm", "flag -D"]),
            ("% ls -la", ["comment %", "command ls", "flag -la"]),
            ("> node -v", ["comment >", "command node", "flag -v"]),
            ("› claude --version", ["comment ›", "command claude", "flag --version"]),
            ("❯ git status | grep x", ["comment ❯", "command git", "command grep"]),
            ("# apt update", ["comment #", "command apt"]),
            ("Hello world, run it now.", []),
            ("/usr/local/bin/node", []),
            ("$5 is the price", []),
            ("Error: path / name", []),
            ("--flag at the start", []),
            ("/ 5 is half", []),
            ("", [])
        ]
        for (line, expected) in cases {
            require(described(line, text.tokenize(line.utf16, from: .normal).tokens) == expected,
                    "text \"\(line)\": \(described(line, text.tokenize(line.utf16, from: .normal).tokens))")
        }
        let continued = text.tokenize("$ docker run \\".utf16, from: .normal)
        require(continued.end == .continued, "a command line can continue")
        require(described("  --rm image", text.tokenize("  --rm image".utf16, from: .continued).tokens) == ["flag --rm"],
                "its next line has flags and no command")
    }

    /// The cache scans a block again from its first changed line, and from the start when its tag or start changes.
    private static func cacheRepaintsFromTheFirstChangedLine() {
        let ts = SyntaxHighlighter(tag: "ts")!
        var cache = SyntaxHighlightCache()
        var text = (1...10).map { "const value\($0) = \($0);" }.joined(separator: "\n")
        func block() -> NSRange { NSRange(location: 0, length: (text as NSString).length) }
        func lineStart(_ line: Int) -> Int {
            (text as NSString).range(of: "const value\(line) ").location
        }
        _ = cache.tokens(in: text as NSString, block: block(), tag: "ts", highlighter: ts, from: 0)
        require(cache.linesScanned == 10, "the first pass scans every line")
        text += " // 끝"
        let tail = cache.tokens(in: text as NSString, block: block(), tag: "ts", highlighter: ts, from: lineStart(10))
        require(cache.linesScanned == 11 && tail.map(\.kind) == [.keyword, .number, .comment], "an append rescans the last line only")
        text += "\nconst more = `open"
        _ = cache.tokens(in: text as NSString, block: block(), tag: "ts", highlighter: ts, from: lineStart(10))
        require(cache.linesScanned == 13, "a new line rescans the old last line and the new one")
        text += "\nstill string`;"
        let closing = cache.tokens(in: text as NSString, block: block(), tag: "ts", highlighter: ts, from: (text as NSString).range(of: "const more").location)
        require(closing.first { $0.range.location > (text as NSString).range(of: "still").location - 1 }?.kind == .string,
                "the next line starts in the string the line before left open")
        let scanned = cache.linesScanned
        _ = cache.tokens(in: text as NSString, block: block(), tag: "ts", highlighter: ts, from: lineStart(3))
        require(cache.linesScanned == scanned + 10, "a change in line 3 rescans from line 3: \(cache.linesScanned - scanned)")
        _ = cache.tokens(in: text as NSString, block: block(), tag: "js", highlighter: SyntaxHighlighter(tag: "js")!, from: lineStart(12))
        require(cache.linesScanned == scanned + 22, "a new tag rescans from the block's start")
        let shifted = NSRange(location: 1, length: (text as NSString).length - 1)
        _ = cache.tokens(in: text as NSString, block: shifted, tag: "js", highlighter: SyntaxHighlighter(tag: "js")!, from: lineStart(12))
        require(cache.linesScanned == scanned + 34, "a block at a new start has no memory")
        cache.keep(blockStarts: [])
        _ = cache.tokens(in: text as NSString, block: block(), tag: "js", highlighter: SyntaxHighlighter(tag: "js")!, from: lineStart(12))
        require(cache.linesScanned == scanned + 46, "forgotten blocks start over")

        // Restyled from line 3 with the first change in line 9: lines 3 to 8 give back their runs without a rescan.
        let js = SyntaxHighlighter(tag: "js")!
        let fresh = cache.tokens(in: text as NSString, block: block(), tag: "js", highlighter: js, from: lineStart(3))
        let before = cache.linesScanned
        let reused = cache.tokens(in: text as NSString, block: block(), tag: "js", highlighter: js, from: lineStart(3), changedFrom: lineStart(9) + 2)
        require(reused == fresh && cache.linesScanned == before + 4, "lines before the change are reused: \(cache.linesScanned - before)")
        let untouched = cache.tokens(in: text as NSString, block: block(), tag: "js", highlighter: js, from: 0, changedFrom: (text as NSString).length)
        require(cache.linesScanned == before + 5 && untouched.count > reused.count, "a change at the end rescans the last line only")
    }

    /// Streaming a block chunk by chunk, scanning from the line the last chunk ended in, gives the same runs as scanning
    /// the finished block at once: over every sample and 500 random split points.
    private static func lineByLineEqualsStreamed() {
        var seed: UInt64 = 0x5EED
        func random(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }
        var splits = 0
        while splits < 500 {
            for sample in samples where splits < 500 {
                let highlighter = SyntaxHighlighter(tag: sample.tag)!
                let full = sample.text as NSString
                var whole = SyntaxHighlightCache()
                let expected = whole.tokens(in: full, block: NSRange(location: 0, length: full.length), tag: sample.tag,
                                            highlighter: highlighter, from: 0)
                // The same runs as tokenizing line by line with carried state.
                var offset = 0
                var lineByLine: [SyntaxToken] = []
                for (line, tokens) in zip(sample.text.components(separatedBy: "\n"), highlighter.tokenize(sample.text)) {
                    lineByLine += tokens.map { SyntaxToken(kind: $0.kind, range: NSRange(location: offset + $0.range.location, length: $0.range.length)) }
                    offset += line.utf16.count + 1
                }
                require(lineByLine == expected, "\(sample.tag): the cache's first pass is the line-by-line scan")

                var cache = SyntaxHighlightCache()
                var byLine: [Int: [SyntaxToken]] = [:]
                var length = 0
                while length < full.length {
                    let next = min(full.length, length + 1 + random(12))
                    splits += 1
                    let text = full.substring(to: next) as NSString
                    // As the renderer does: restyled from the line before the one the previous text ended in, rescanned from the
                    // first new character's line.
                    let last = length == 0 ? 0 : text.paragraphRange(for: NSRange(location: length - 1, length: 0)).location
                    let from = last == 0 ? 0 : text.paragraphRange(for: NSRange(location: last - 1, length: 0)).location
                    let scanned = cache.linesScanned
                    let tokens = cache.tokens(in: text, block: NSRange(location: 0, length: text.length), tag: sample.tag,
                                              highlighter: highlighter, from: from, changedFrom: length)
                    let newLines = text.substring(from: length).filter { $0 == "\n" || $0 == "\r\n" }.count
                    require(cache.linesScanned - scanned <= newLines + 1, "\(sample.tag): a chunk rescans its own lines only")
                    for key in byLine.keys where key >= from { byLine[key] = nil }
                    for token in tokens {
                        let start = text.paragraphRange(for: NSRange(location: token.range.location, length: 0)).location
                        byLine[start, default: []].append(token)
                    }
                    length = next
                }
                let streamed = byLine.keys.sorted().flatMap { byLine[$0]! }
                require(streamed == expected, "\(sample.tag): streamed runs equal the finished block's")
            }
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "SyntaxHighlighterTests: \(message)")
    }
}
