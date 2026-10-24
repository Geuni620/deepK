import Foundation

@main
private enum RichSourceImporterTests {
    static func main() {
        chrome()
        variants()
        urlPolicy()
        fallbacks()
        limits()
        copiedSources()
        reviewFollowUps()
        widgetChrome()
        alignmentBudget()
        selectedTabs()
        capturedFixtures()
        copyButtons()
        copyControls()
        gutters()
        chromeSafety()
        languageLabels()
        codeBlocks()
        structuredFallbacks()
        htmlLists()
        reviewOfPR56()
        liveCaptures()
        print("RichSourceImporterTests passed")
    }

    private static let plain = """
    The core idea is to give the model only four tools. read, write, edit, and bash.
    Check it out: Finding the best harness for DeepSeek v4 Flash.
    """

    /// Shaped like Chrome's `public.html`: a charset meta, inline styles, a query with `&amp;`.
    private static let chromeHTML = """
    <meta charset='utf-8'><p style="color: rgb(36, 41, 47); font-family: -apple-system, sans-serif;">The core idea is to give \
    the model only four tools. <code style="font-family: ui-monospace, monospace;">read</code>, <code>write</code>, \
    <code>edit</code>, and <code>bash</code>.</p><p>Check it out: <a href="https://blog.example.com/harness?x=1&amp;y=2" \
    style="color: rgb(9, 105, 218);">Finding the best harness for DeepSeek v4 Flash</a>.</p>
    """

    private static func capture(_ plain: String, _ html: String, source: String? = nil) -> CapturedSource {
        RichSourceImporter.capture(plain: plain, html: html, sourceURL: source)
    }

    private static func stripped(_ markup: SourceMarkup) -> String {
        markup.text.replacingOccurrences(of: "</?a[0-9]+>", with: "", options: .regularExpression).replacingOccurrences(of: "`", with: "")
    }

    private static func chrome() {
        let captured = capture(plain, chromeHTML)
        guard let markup = captured.markup else { return require(false, "chrome html yields markup") }
        require(captured.plain == plain, "plain stays the identity")
        require(markup.text == """
        The core idea is to give the model only four tools. `read`, `write`, `edit`, and `bash`.
        Check it out: <a1>Finding the best harness for DeepSeek v4 Flash</a1>.
        """, "chrome markup: \(markup.text)")
        require(markup.links == [SourceLink(url: URL(string: "https://blog.example.com/harness?x=1&y=2")!, text: "Finding the best harness for DeepSeek v4 Flash")],
                "links keep the decoded query")
        require(markup.code == ["read", "write", "edit", "bash"], "code set")
        require(stripped(markup) == plain, "markers removed give the plain text")
        // The result parser sees the same spans.
        let parsed = TranslationMarkup(markup.text, inline: markup.inlineOptions)
        require(parsed.displayText == plain && parsed.spans.count == 5, "markup parses back to the plain text")

        // No HTML, unreadable data or no structure: plain only.
        require(RichSourceImporter.capture(plain: plain, html: nil) == CapturedSource(plain: plain), "no html")
        require(RichSourceImporter.capture(plain: plain, html: "") == CapturedSource(plain: plain), "empty html")
        require(capture("그냥 문장", "<p>그냥 문장</p>").markup == nil, "html without links or code")
    }

    private static func variants() {
        // Safari: a full document with a style sheet and NBSP between words.
        let safari = """
        <html><head><style>p { color: red } a < b</style><title>T</title></head><body>
        <p>Run&nbsp;<code>npm i</code> then open <a href="/docs/start">the guide</a>.</p><script>if (a<b) {}</script></body></html>
        """
        let safariPlain = "Run npm i then open the guide."
        let fromSafari = capture(safariPlain, safari, source: "https://example.com/page")
        require(fromSafari.markup?.text == "Run `npm i` then open <a1>the guide</a1>.", "safari: \(String(describing: fromSafari.markup?.text))")
        require(fromSafari.markup?.links.first?.url.absoluteString == "https://example.com/docs/start", "relative link resolves against the page")
        require(capture(safariPlain, safari).markup?.text == "Run `npm i` then open the guide.", "relative link without a page is dropped")

        // Google Docs: monospace styling without code tags.
        let docs = """
        <b style="font-weight:normal;"><span style="font-family:Arial;">Call </span><span style="font-family:'Roboto Mono',monospace;">\
        fetch()</span><span style="font-family:Arial;"> first.</span></b>
        """
        require(capture("Call fetch() first.", docs).markup?.text == "Call `fetch()` first.", "google docs monospace")

        // An editor copy that is mostly monospace gets no chips.
        let editor = "<div style=\"font-family: Menlo, monospace;\"><div>let a = 1</div><div>print(a)</div></div>"
        require(capture("let a = 1\nprint(a)", editor).markup == nil, "editor copy is plain")

        // Code inside `pre` is an app-made fenced block, not a chip; a linked code span nests inside the tag.
        let mixed = "<pre><code>make all</code></pre><p>See <a href=\"https://x.dev/a\"><code>Makefile</code></a>.</p>"
        let fenced = capture("make all\nSee Makefile.", mixed)
        require(fenced.markup?.text == "```\nmake all\n```\nSee <a1>`Makefile`</a1>." && fenced.plain == "make all\nSee Makefile.", "pre and linked code")
        require(fenced.markup?.blocks == [SourceCodeBlock(language: nil, code: "make all")] && fenced.markup?.blocks.first?.fence == 3, "a bare fence")

        // List markers only in the plain text and HTML-only hidden text are tolerated.
        let list = "<ul><li>Use <code>git</code></li><li>Read <a href=\"https://g.dev\">docs</a><span hidden>secret</span></li></ul>"
        require(capture("• Use git\n• Read docs", list).markup?.text == "• Use `git`\n• Read <a1>docs</a1>", "list markers")

        // Uppercase styling changes case in the plain text only.
        require(capture("SEE THE DOCS", "<p style=\"text-transform:uppercase\">see <a href=\"https://d.dev\">the docs</a></p>").markup?.text
                == "SEE <a1>THE DOCS</a1>", "case-insensitive match")

        // Adjacent code elements stay separate spans.
        require(capture("Press a b now", "<p>Press <code>a</code> <code>b</code> now</p>").markup?.text == "Press `a` `b` now", "adjacent code")
    }

    private static func urlPolicy() {
        for href in ["javascript:alert(1)", "java\nscript:alert(1)", "java&#10;script:alert(1)", "data:text/html,x", "file:///etc/passwd",
                     "https://bank.com@evil.com/", "https://user:pw@evil.com/", "#section", "ftp://x.dev/f", "https:///nohost",
                     "https://x.dev/" + String(repeating: "a", count: 2100)] {
            let html = "<p>Go <a href=\"\(href)\">there</a> now</p>"
            require(capture("Go there now", html).markup == nil, "unsafe link dropped: \(href.prefix(40))")
        }
        let mail = capture("Write to us", "<p>Write to <a href=\"mailto:hi@x.dev\">us</a></p>")
        require(mail.markup?.links.first?.url.absoluteString == "mailto:hi@x.dev", "mailto allowed")
        require(SourceLink.isAllowed(URL(string: "https://x.dev/a?b=1")!) && !SourceLink.isAllowed(URL(string: "javascript:x")!), "policy helper")
    }

    private static func fallbacks() {
        // Notion's plain text is already markdown: nothing is layered on top.
        let notion = "<p>Use <code>read</code> and <a href=\"https://n.so\">this</a></p>"
        require(capture("Use `read` and [this](https://n.so)", notion).markup == nil, "markdown plain keeps its own text")
        // Literal tags in the plain text would be ambiguous.
        require(capture("Type <a1> here", "<p>Type &lt;a1&gt; <a href=\"https://x.dev\">here</a></p>").markup == nil, "literal link tags")
        // HTML that does not describe this plain text is ignored.
        require(capture("Completely different text that was copied", chromeHTML).markup == nil, "mismatched html")
        // A link that spans lines or has no words is dropped.
        require(capture("one\ntwo", "<a href=\"https://x.dev\">one<br>two</a>").markup == nil, "multi-line link")
        require(capture("→ next", "<a href=\"https://x.dev\">→</a> next").markup == nil, "icon link")
        // Partially matched spans are not guessed.
        require(capture("Use rd now", "<p>Use <code>read</code> now</p>").markup == nil, "partial code span")
        // Comments and unknown entities do not break the scan.
        require(capture("A & b", "<!-- <a href=\"https://x.dev\"> --><p>A &amp; <code>b</code></p>").markup?.text == "A & `b`", "comments")
    }

    private static func limits() {
        let words = (1...50).map { "w\($0)" }
        let html = words.map { "<a href=\"https://x.dev/\($0)\">\($0)</a>" }.joined(separator: " ")
        let captured = capture(words.joined(separator: " "), html)
        require(captured.markup?.links.count == RichSourceImporter.maxLinks, "link cap")
        let long = String(repeating: "x", count: 97)
        require(capture("run \(long)", "<p>run <code>\(long)</code></p>").markup == nil, "code longer than 96 units")
        let huge = String(repeating: "a", count: RichSourceImporter.maxHTMLBytes + 1)
        require(RichSourceImporter.capture(plain: "a", html: huge).markup == nil, "html over 1 MiB")
    }

    /// A double copy tidies formulas first; only a copy whose text stays as copied gets links and inline code.
    private static func copiedSources() {
        func fixture(_ name: String) -> (plain: String, html: String) {
            let directory = URL(fileURLWithPath: "DeepKTests/Fixtures/MathCopy")
            return (try! String(contentsOf: directory.appendingPathComponent(name + ".txt"), encoding: .utf8),
                    try! String(contentsOf: directory.appendingPathComponent(name + ".html"), encoding: .utf8))
        }
        let math = fixture("katex-article")
        let tidied = CopiedMathNormalizer.normalize(plain: math.plain, html: math.html).text
        let fromMath = RichSourceImporter.copiedSource(plain: math.plain, html: math.html, inputLimit: .max)
        require(tidied != math.plain && fromMath == CapturedSource(plain: tidied), "a copy with formulas keeps the tidied plain text")
        require(RichSourceImporter.copiedSource(plain: plain, html: chromeHTML) == capture(plain, chromeHTML), "a copy without formulas keeps its links")
        let control = fixture("control")
        let fromControl = RichSourceImporter.copiedSource(plain: control.plain, html: control.html, inputLimit: .max)
        let controlList = control.plain.replacingOccurrences(of: "\nn\nx\n+\n2\nApples\nPears\n", with: "\n- n\n- x\n- +\n- 2\n- Apples\n- Pears\n")
        require(fromControl.plain == controlList && fromControl.raw == control.plain && fromControl.markup?.links.count == 1,
                "a real Chrome copy restores its list and keeps its link: \(fromControl.plain.debugDescription) / \(fromControl.markup?.text ?? "nil")")
        require(fromControl.markup?.blocks.map(\.code) == ["let x = 1\nx\n+\n2\n}"], "its <pre> is fenced as copied")
        require(RichSourceImporter.copiedSource(plain: plain, html: nil) == CapturedSource(plain: plain), "no html")
        require(RichSourceImporter.copiedSource(plain: plain, html: chromeHTML, inputLimit: 10).markup == nil, "over the input limit stays plain")
    }

    /// Independent review of PR #53.
    private static func reviewFollowUps() {
        // A `>` inside a quoted attribute does not end the tag, so attribute text never becomes a link.
        let quoted = capture("Please read the Docs before you start the installation.",
                             "<p>Please read the <span title=\"x><a href='https://evil.example/login'><i \">Docs</span> before you start the installation.</p>")
        require(quoted.markup == nil, "attribute text is not a link")
        // Spaces inside an href are percent-encoded, as browsers do; spaces around it go.
        let spaced = capture("Open the report now", "<p>Open <a href=\" https://files.example/q?name=annual report.pdf \">the report</a> now</p>")
        require(spaced.markup?.links.first?.url.absoluteString == "https://files.example/q?name=annual%20report.pdf", "inner space kept")
        let mail = capture("Write to us", "<p>Write to <a href=\"mailto:help@x.dev?subject=Order 1234\">us</a></p>")
        require(mail.markup?.links.first?.url.absoluteString == "mailto:help@x.dev?subject=Order%201234", "mailto subject kept")
        // Text that is already a markdown link keeps its own syntax, also in a long paragraph.
        let filler = String(repeating: "This sentence only makes the paragraph long enough to align. ", count: 10)
        let markdownPlain = filler + "Read [this](https://n.so) first."
        let markdownHTML = "<p>" + filler + "Read [<a href=\"https://n.so\">this</a>](https://n.so) first.</p>"
        require(capture(markdownPlain, markdownHTML).markup == nil, "a markdown link is not wrapped again")
        // A page with semantic code tags gets chips only for them, not for monospace styling.
        let semantic = capture("Run make and see abc123 now.", "<p>Run <code>make</code> and see <span style=\"font-family: monospace\">abc123</span> now.</p>")
        require(semantic.markup?.code == ["make"], "semantic code wins over monospace")
        // Text only in the HTML cannot pull the alignment ahead and drop the real spans.
        let extra = capture("Run git then read docs", "<p>Run <span>d</span> <code>git</code> then read docs</p>")
        require(extra.markup?.text == "Run `git` then read docs", "an HTML-only letter is skipped")
        // HTML that does not describe the text is given up early and stays plain.
        let unrelated = String(repeating: "<div>menu entry that is not in the copied text</div>", count: 4_000)
        require(capture("A short copied sentence with a link.", unrelated + "<p>A short copied sentence with a <a href=\"https://x.dev\">link</a>.</p>").markup == nil,
                "unrelated HTML stays plain")
    }

    // MARK: - Code blocks and page controls

    private static func codeCopy(_ name: String) -> (plain: String, html: String) {
        let directory = URL(fileURLWithPath: "DeepKTests/Fixtures/CodeCopy")
        return (try! String(contentsOf: directory.appendingPathComponent(name + ".txt"), encoding: .utf8),
                try! String(contentsOf: directory.appendingPathComponent(name + ".html"), encoding: .utf8))
    }

    private static func withReport(_ plain: String, _ html: String) -> (source: CapturedSource, report: RichSourceImporter.Report) {
        RichSourceImporter.captureWithReport(plain: plain, html: html)
    }

    /// The cleaned text as its markup shows it: a titled block's opener stands for the title lines right above its code.
    private static func shown(_ captured: CapturedSource) -> String {
        var lines = captured.plain.components(separatedBy: "\n")
        var from = 0
        for block in captured.markup?.blocks ?? [] {
            let code = block.lines
            guard let start = lines.indices.dropFirst(from).first(where: { Array(lines[$0...].prefix(code.count)) == code }) else { continue }
            let titleLines = block.title?.components(separatedBy: " · ").count ?? 0
            lines.removeSubrange((start - titleLines)..<start)
            from = start - titleLines + code.count
        }
        return lines.joined(separator: "\n")
    }

    private static let paragraph = "This paragraph is long enough that the alignment budget is not the thing under test here, and it keeps going a little longer still."

    /// The impeccable docs widget, as Chrome copies a self-written replica of its DOM (scripts/code-copy): tab buttons, a
    /// clipped copy label and a status line around a `text` `<pre>`. Chrome leaves its unselectable prompt out of both texts.
    /// The selected tab says which tools the command is for, so it stays as the block's title; the other tab and the copy
    /// button go.
    private static func widgetChrome() {
        let copy = codeCopy("impeccable-full")
        let (captured, report) = withReport(copy.plain, copy.html)
        let lines = captured.plain.components(separatedBy: "\n")
        require(!lines.contains("Codex") && !lines.contains("Copy") && lines.contains("/impeccable document"),
                "the other tab and the copy button are gone, the command stays: \(captured.plain)")
        require(captured.plain == copy.plain.replacingOccurrences(of: "Most Agents\nCodex\nCopy\n", with: "Most Agents\n"),
                "the selected tab stays right above the command, nothing else changes: \(captured.plain)")
        guard let markup = captured.markup else { return require(false, "the widget copy keeps its structure") }
        require(markup.text.contains("you have:\n\n```text title=\"Most Agents\"\n/impeccable document\n```\nIt scans the code"),
                "an app fence with the page's language and the tab as its title, in place of the tab's line: \(markup.text)")
        require(markup.blocks == [SourceCodeBlock(language: "text", code: "/impeccable document", title: "Most Agents")], "one titled block")
        require(markup.links.map(\.text) == ["init", "Context files"] && markup.code == ["DESIGN.md", ".impeccable/design.json", "PRODUCT.md"],
                "2 links and 3 chips")
        require(captured.removed.count == 2 && report.removedLines == 2 && report.chromeMatched == 3 && report.chromeSkipped == 0,
                "two control lines removed; the title is no removal")
        require(captured.raw == copy.plain && captured.removed.map { (copy.plain as NSString).substring(with: $0) } == ["\nCodex", "\nCopy"],
                "the raw copy and what was removed stay for diagnostics")
        let parsed = TranslationMarkup(markup.text, inline: markup.inlineOptions)
        require(parsed.displayText == shown(captured) && parsed.blocks.compactMap(\.fence).map(\.info) == ["text title=\"Most Agents\""],
                "the markup displays the cleaned text, with the title in the opener")

        // Copying again after the button was used ("Copied", "Copied to clipboard.") is the same source.
        let two = codeCopy("impeccable-two"), copied = codeCopy("impeccable-copied")
        let before = capture(two.plain, two.html), after = capture(copied.plain, copied.html)
        require(before == after && before.plain == after.plain && before.markup == after.markup && before.raw != after.raw,
                "Copy and Copied! give one cleaned source")
    }

    /// Widget controls no longer count against the alignment budget, so smaller selections around them keep their
    /// links and chips. Before, their 19 control letters exceeded the budget of these two selections.
    private static func alignmentBudget() {
        for (name, links) in [("impeccable-full", 2), ("impeccable-two", 2), ("impeccable-one", 0)] {
            let copy = codeCopy(name)
            let (captured, report) = withReport(copy.plain, copy.html)
            require(report.misses == 0 && captured.markup?.code.contains("DESIGN.md") == true && captured.markup?.links.count == links
                    && captured.markup?.blocks == [SourceCodeBlock(language: "text", code: "/impeccable document", title: "Most Agents")],
                    "\(name): misses \(report.misses), markup \(String(describing: captured.markup?.text))")
            require(captured.plain.contains("Most Agents\n/impeccable document\nIt scans") && captured.markup?.text.contains("```text title=\"Most Agents\"\n/impeccable document\n```\nIt scans") == true,
                    "\(name): the title above the command, in the opener for the model")
            if name != "impeccable-full" { require(report.budget < 19, "\(name) used to fail: budget \(report.budget)") }
        }
        // The widget alone with a paragraph: the selected tab and the command, then the paragraph.
        let one = codeCopy("impeccable-one"), scans = String(one.plain[one.plain.range(of: "It scans")!.lowerBound...])
        let alone = capture(one.plain, one.html)
        require(alone.plain == "Most Agents\n/impeccable document\n" + scans
                && alone.markup?.text == "```text title=\"Most Agents\"\n/impeccable document\n```\n"
                    + scans.replacingOccurrences(of: "DESIGN.md", with: "`DESIGN.md`").replacingOccurrences(of: ".impeccable/design.json", with: "`.impeccable/design.json`"),
                "impeccable-one: \(alone.plain.debugDescription) / \(alone.markup?.text.debugDescription ?? "nil")")
        // The budget still holds for text the HTML does not have.
        let bare = "<pre class=\"astro-code\" data-language=\"text\"><code>/impeccable document</code></pre>"
            + one.html[one.html.range(of: "<p ")!.lowerBound...]
        let (captured, report) = withReport(one.plain, bare)
        require(captured == CapturedSource(plain: one.plain) && report.fallback == "html does not match" && report.misses > report.budget,
                "controls missing from the HTML still cost misses")
        // Option buttons right above code, none marked selected, are the page's own text (a quiz): they stay, as prose of the
        // model input too, and the code is still fenced.
        let question = "Which keyword declares a constant? Pick one, then check the code below."
        let options = { (attributes: String) in
            "<p>\(question)</p><div class=\"quiz\"><button \(attributes)>let</button><button \(attributes)>const</button><button \(attributes)>var</button></div>"
                + "<pre><code class=\"language-js\">const a = 1;</code></pre>"
        }
        let quiz = withReport("\(question)\nlet\nconst\nvar\nconst a = 1;", options("class=\"option\""))
        require(quiz.report.misses == 0 && quiz.report.chromeMatched == 0 && quiz.source.plain == "\(question)\nlet\nconst\nvar\nconst a = 1;"
                && quiz.source.markup?.text == "\(question)\nlet\nconst\nvar\n```js\nconst a = 1;\n```"
                && quiz.source.markup?.blocks == [SourceCodeBlock(language: "js", code: "const a = 1;")], "quiz options stay: \(quiz.report)")
        // A screen-reader label inside an option is still a control of its own: it goes, the options stay.
        let clip = "clip: rect(0px, 0px, 0px, 0px); height: 1px; overflow: hidden; position: absolute; width: 1px;"
        let labelled = withReport("\(question)\nlet\n(selected answer)\nconst\nvar\nconst a = 1;",
                                  options("class=\"option\"").replacingOccurrences(of: ">let<", with: ">let<div class=\"sr-only\" style=\"\(clip)\">(selected answer)</div><"))
        require(labelled.report.removedLines == 1 && labelled.report.chromeMatched == 1 && labelled.source.plain == quiz.source.plain && labelled.source.markup == quiz.source.markup,
                "a hidden label in an option goes: \(labelled.source.plain.debugDescription)")
        // Tabs with none selected: one starts like the code, but the code still fits after all of them. They all go, and title nothing.
        let tabs = withReport("\(question)\nlet\nconst\nvar\nconst a = 1;", options("role=\"tab\""))
        require(tabs.report.misses == 0 && tabs.report.chromeMatched == 3 && tabs.source.plain == "\(question)\nconst a = 1;"
                && tabs.source.markup?.blocks == [SourceCodeBlock(language: "js", code: "const a = 1;")],
                "a tab that starts like the code after it is matched: \(tabs.report) \(tabs.source.plain.debugDescription)")
    }

    /// The selected tab of a tab bar right above a block names its code: it stays as a line of its own in the plain text and
    /// travels untranslated in the opener. Buttons are a tab bar only when they are tabs or exactly one is marked selected.
    private static func selectedTabs() {
        let plain = "\(paragraph)\nnpm\nyarn\nnpm install foo"
        let code = "<pre><code class=\"language-bash\">npm install foo</code></pre>"
        func tabs(_ npm: String, _ yarn: String = "") -> String {
            "<p>\(paragraph)</p><div class=\"tabs\"><button \(npm)>npm</button><button \(yarn)>yarn</button></div>" + code
        }
        // A toggle pressed among toggles is marked too.
        let toggles = [("aria-pressed=\"true\"", "aria-pressed=\"false\""), ("data-state=\"on\"", "data-state=\"off\"")]
        for (npm, yarn) in ["aria-selected=\"true\"", "aria-current=\"true\"", "aria-current=\"page\"", "data-state=\"active\"", "data-selected=\"true\"",
                            "class=\"active\"", "class=\"tab is-active\"", "class=\"selected\"", "class=\"is-selected\"", "class=\"current\"", "class=\"tab--active\"",
                            "class=\"tab-active\"", "class=\"tab_active\"", "class=\"tab--selected\"", "class=\"tab-selected\""].map({ ($0, "") }) + toggles {
            let captured = capture(plain, tabs(npm, yarn))
            require(captured.plain == "\(paragraph)\nnpm\nnpm install foo" && captured.markup?.text == "\(paragraph)\n```bash title=\"npm\"\nnpm install foo\n```"
                    && captured.markup?.blocks == [SourceCodeBlock(language: "bash", code: "npm install foo", title: "npm")], "selected by \(npm): \(captured.plain.debugDescription)")
        }
        // Without a mark, or with two, plain buttons are the page's own text. So is a pressed toggle beside a plain button:
        // a setting (Wrap beside Run), not the tab on show.
        for (npm, yarn) in [("class=\"inactive\"", ""), ("class=\"tab-inactive\"", ""), ("class=\"unselected\"", ""), ("class=\"is-unselected\"", ""),
                            ("aria-selected=\"false\"", ""), ("data-state=\"inactive\"", ""), ("class=\"active\"", "class=\"active\""),
                            ("aria-pressed=\"true\"", ""), ("data-state=\"on\"", ""), ("aria-pressed=\"true\"", "aria-pressed=\"true\"")] {
            let captured = capture(plain, tabs(npm, yarn))
            require(captured.plain == plain && captured.markup?.text == "\(paragraph)\nnpm\nyarn\n```bash\nnpm install foo\n```", "not one selected: \(npm) \(yarn)")
        }
        // Tabs are a tab bar with any number selected, but only one selected titles the block.
        let both = capture(plain, tabs("role=\"tab\" aria-selected=\"true\"", "role=\"tab\" aria-selected=\"true\""))
        require(both.plain == "\(paragraph)\nnpm install foo" && both.markup?.blocks == [SourceCodeBlock(language: "bash", code: "npm install foo")], "two selected tabs")

        // A lone copy button beside the tab bar goes; the line they shared becomes exactly the title.
        let shared = withReport("\(paragraph)\nnpmyarnCopy\nnpm install foo", "<p>\(paragraph)</p><div class=\"header\"><div class=\"tabs\"><button class=\"active\">npm</button>"
                                + "<button>yarn</button></div><button class=\"copy\">Copy</button></div>" + code)
        require(shared.source.plain == "\(paragraph)\nnpm\nnpm install foo" && shared.source.markup?.blocks.first?.title == "npm" && shared.report.removedLines == 0
                && shared.source.removed.map { (shared.source.raw as NSString).substring(with: $0) } == ["yarnCopy"], "a shared line: \(shared.source.plain.debugDescription)")
        // Text of a control inside the tab is no part of its label.
        let clip = "clip: rect(0px, 0px, 0px, 0px); height: 1px; overflow: hidden; position: absolute; width: 1px;"
        let nested = capture("\(paragraph)\nindex.js(selected)\nutil.js\nexport {}", "<p>\(paragraph)</p><div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\">index.js"
                             + "<span class=\"sr-only\" style=\"\(clip)\">(selected)</span></button><button role=\"tab\">util.js</button></div><pre><code class=\"language-js\">export {}</code></pre>")
        require(nested.plain == "\(paragraph)\nindex.js\nexport {}" && nested.markup?.text == "\(paragraph)\n```js title=\"index.js\"\nexport {}\n```", "a nested label: \(nested.plain.debugDescription)")

        // Two tab bars over one block: their labels stay in order, and the opener joins them.
        let twoBars = "<p>\(paragraph)</p><div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\">macOS</button><button role=\"tab\">Linux</button></div>"
            + "<div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\">npm</button><button role=\"tab\">yarn</button></div>" + code
        for (raw, removed) in [("\(paragraph)\nmacOS\nLinux\nnpm\nyarn\nnpm install foo", ["\nLinux", "\nyarn"]), ("\(paragraph)\nmacOSLinux\nnpmyarn\nnpm install foo", ["Linux", "yarn"])] {
            let captured = capture(raw, twoBars)
            require(captured.plain == "\(paragraph)\nmacOS\nnpm\nnpm install foo" && captured.markup?.text == "\(paragraph)\n```bash title=\"macOS · npm\"\nnpm install foo\n```"
                    && captured.removed.map { (raw as NSString).substring(with: $0) } == removed
                    && TranslationMarkup(captured.markup?.text ?? "").displayText == shown(captured), "two tab bars: \(captured.plain.debugDescription)")
        }

        // A title with one kind of quote is quoted with the other; a block without a language is tagged text for it.
        func titled(_ label: String) -> CapturedSource {
            capture("\(paragraph)\n\(label.replacingOccurrences(of: "<br>", with: "\n"))\nOther\nmake",
                    "<p>\(paragraph)</p><div class=\"tabs\"><button class=\"active\">\(label)</button><button>Other</button></div><pre><code>make</code></pre>")
        }
        for (label, opener) in [("Say \"hi\"", "```text title='Say \"hi\"'"), ("It's", "```text title=\"It's\""),
                                ("Production build with source map enabled", "```text title=\"Production build with source map enabled\"")] {
            let captured = titled(label)
            require(captured.plain == "\(paragraph)\n\(label)\nmake" && captured.markup?.text == "\(paragraph)\n\(opener)\nmake\n```"
                    && captured.markup?.blocks == [SourceCodeBlock(language: nil, code: "make", title: label)], "titled \(label): \(captured.markup?.text ?? "nil")")
        }
        // A title the opener cannot carry goes with the other tabs: both quotes, 41 characters, a label on two lines.
        for label in ["\"a\" or 'b'", "Production build with source maps enabled", "Most<br>Agents"] {
            let captured = titled(label)
            require(captured.plain == "\(paragraph)\nmake" && captured.markup?.text == "\(paragraph)\n```\nmake\n```", "no title from \(label): \(captured.plain.debugDescription)")
        }
        // Tabs below a block title nothing: tabs sit above the code they name.
        let below = capture("\(paragraph)\nnpm install foo\nnpm\nyarn\nDone.", "<p>\(paragraph)</p>" + code + "<div class=\"tabs\"><button class=\"active\">npm</button>"
                            + "<button>yarn</button></div><p>Done.</p>")
        require(below.plain == "\(paragraph)\nnpm install foo\nDone." && below.markup?.blocks.first?.title == nil, "tabs below: \(below.plain.debugDescription)")
        // Between two blocks, the farther tab bar may be the first block's below it: only the bar nearest the second titles it.
        let between = capture("\(paragraph)\necho one\nA\nB\nnpm\nyarn\nnpm install foo", "<p>\(paragraph)</p><pre><code class=\"language-bash\">echo one</code></pre>"
                              + "<div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\">A</button><button role=\"tab\">B</button></div>"
                              + "<div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\">npm</button><button role=\"tab\">yarn</button></div>" + code)
        require(between.plain == "\(paragraph)\necho one\nnpm\nnpm install foo"
                && between.markup?.text == "\(paragraph)\n```bash\necho one\n```\n```bash title=\"npm\"\nnpm install foo\n```", "tabs between blocks: \(between.plain.debugDescription)")
    }

    /// Chrome's copies of self-written replicas (scripts/code-copy) of GitHub, MDN, Docusaurus (tabs) and Sphinx, whose
    /// table gutter Chrome writes as lines of their own.
    private static func capturedFixtures() {
        let expected: [(name: String, blocks: [SourceCodeBlock], links: [String], code: Set<String>, removed: [String])] = [
            ("github-readme", [SourceCodeBlock(language: "shell", code: "npm install left-pad"),
                               SourceCodeBlock(language: "js", code: "import leftPad from 'left-pad';\nleftPad('7', 3, '0'); // => '007'")],
             ["API reference"], ["npm"], []),
            ("mdn", [SourceCodeBlock(language: "js", code: "const doubled = numbers.map(n => n * 2);")],
             ["Array.prototype.map()"], ["Array.prototype.map()", "forEach()"], ["\nCopy to Clipboard"]),
            ("docusaurus-tabs", [SourceCodeBlock(language: "bash", code: "npm install @docusaurus/core", title: "npm")], [], ["npm run start"], ["\nYarn", "\npnpm"]),
            ("sphinx-linenos", [SourceCodeBlock(language: "python", code: "import os\n# Print the working directory\nprint(os.getcwd())")],
             ["os.getcwd()"], ["os.getcwd()"], ["\n1", "\n2", "\n3"]),
        ]
        for fixture in expected {
            let copy = codeCopy(fixture.name)
            let captured = capture(copy.plain, copy.html)
            guard let markup = captured.markup else { return require(false, "\(fixture.name) keeps its structure") }
            require(markup.blocks == fixture.blocks, "\(fixture.name) blocks: \(markup.blocks)")
            require(markup.links.map(\.text) == fixture.links && markup.code == fixture.code, "\(fixture.name) links and chips: \(markup.text)")
            require(captured.removed.map { (copy.plain as NSString).substring(with: $0) } == fixture.removed, "\(fixture.name) removed: \(captured.removed)")
            let raw = copy.plain.components(separatedBy: "\n")
            require(captured.plain.components(separatedBy: "\n").allSatisfy { line in line.isEmpty || raw.contains { $0.contains(line) } },
                    "\(fixture.name): cleaning only drops")
            require(TranslationMarkup(markup.text, inline: markup.inlineOptions).displayText == shown(captured), "\(fixture.name) parses back")
        }
        // MDN's label sits beside the <pre>, not in it: v1 keeps it as text.
        require(capture(codeCopy("mdn").plain, codeCopy("mdn").html).plain.hasPrefix("Use Array.prototype.map() to build a new array:\n\njs\nconst doubled"),
                "a sibling language label stays")
        // Docusaurus: the selected tab stays above its code as the block's title, the others go; Chrome leaves the hidden panels out.
        let tabs = capture(codeCopy("docusaurus-tabs").plain, codeCopy("docusaurus-tabs").html)
        require(tabs.plain == "Install the package:\n\nnpm\nnpm install @docusaurus/core\n\nThen restart the dev server with npm run start."
                && tabs.markup?.text == "Install the package:\n\n```bash title=\"npm\"\nnpm install @docusaurus/core\n```\n\nThen restart the dev server with `npm run start`.",
                "tabs: \(tabs.plain) / \(tabs.markup?.text ?? "nil")")
    }

    private static func copyButtons() {
        let html = "<div class=\"highlight\"><pre><button class=\"copy\">Copy</button><code class=\"language-sh\">ls -la\npwd</code></pre></div><p>\(paragraph)</p>"
        for plain in ["Copyls -la\npwd\n\(paragraph)", "Copy\nls -la\npwd\n\(paragraph)"] {
            let captured = capture(plain, html)
            require(captured.plain == "ls -la\npwd\n\(paragraph)" && captured.markup?.text == "```sh\nls -la\npwd\n```\n\(paragraph)",
                    "a copy button inside a pre, inline or on its own line: \(captured.plain.debugDescription)")
        }
    }

    /// A copy button is a control wherever it sits, and the buttons beside it are judged without it: one left is a lone
    /// button and goes next to code too, options stay, and a tab bar keeps its title.
    private static func copyControls() {
        let code = "<pre><code class=\"language-bash\">npm install foo</code></pre>"
        let fenced = "\(paragraph)\n```bash\nnpm install foo\n```"
        func toolbar(_ raw: String, _ buttons: String) -> CapturedSource {
            capture("\(paragraph)\n\(raw)\nnpm install foo", "<p>\(paragraph)</p><div class=\"toolbar\">\(buttons)</div>" + code)
        }
        // Copy and Run, or a Wrap toggle and Copy, on lines of their own or on one: both go. A Korean verb form of copy is the same.
        for (raw, buttons) in [("Copy\nRun", "<button>Copy</button><button>Run</button>"), ("CopyRun", "<button>Copy</button><button>Run</button>"),
                               ("Wrap\nCopy", "<button aria-pressed=\"true\">Wrap</button><button>Copy</button>"),
                               ("복사하기\n실행", "<button>복사하기</button><button>실행</button>")] {
            let captured = toolbar(raw, buttons)
            require(captured.plain == "\(paragraph)\nnpm install foo" && captured.markup?.text == fenced, "\(raw.debugDescription) goes: \(captured.plain.debugDescription)")
        }
        // A chat's Copy code and Edit beside its language label, inside the <pre>: all three go.
        let chat = "<p>\(paragraph)</p><pre><div class=\"header\"><span>python</span><div class=\"actions\"><button>Copy code</button><button>Edit</button></div></div>"
            + "<div><code class=\"hljs language-python\">print(1)</code></div></pre>"
        for raw in ["python\nCopy code\nEdit", "pythonCopy codeEdit"] {
            let captured = capture("\(paragraph)\n\(raw)\nprint(1)", chat)
            require(captured.plain == "\(paragraph)\nprint(1)" && captured.markup?.text == "\(paragraph)\n```python\nprint(1)\n```", "chat \(raw.debugDescription): \(captured.plain.debugDescription)")
        }
        // What says copy: the button's text, label, title, data-* names and tooltips, and classes, or an icon-only button's icon.
        // Run beside any of them is lone, so it goes.
        for (text, button) in [("Copied!", "<button>Copied!</button>"), ("Copied.", "<button>Copied.</button>"), ("COPY", "<button>COPY</button>"),
                               ("Copy to clipboard", "<button>Copy to clipboard</button>"), ("Copy command", "<button>Copy command</button>"),
                               ("복사", "<button>복사</button>"), ("복사됨", "<button>복사됨</button>"), ("코드 복사", "<button>코드 복사</button>"),
                               ("コピー", "<button>コピー</button>"), ("コードをコピー", "<button>コードをコピー</button>"),
                               ("복사하기", "<button>복사하기</button>"), ("코드 복사하기", "<button>코드 복사하기</button>"),
                               ("복사되었습니다", "<button>복사되었습니다</button>"), ("복사됐습니다!", "<button>복사됐습니다!</button>"),
                               ("복사했습니다", "<button>복사했습니다</button>"), ("복사 완료", "<button>복사 완료</button>"),
                               ("コピーする", "<button>コピーする</button>"), ("コピーしました", "<button>コピーしました</button>"),
                               ("コードをコピーしました", "<button>コードをコピーしました</button>"), ("コピー済み", "<button>コピー済み</button>"),
                               ("コピー完了", "<button>コピー完了</button>"),
                               (nil, "<button aria-label=\"코드 복사하기\"></button>"), (nil, "<button title=\"コピーする\"></button>"),
                               ("content_copy", "<button><span class=\"material-icons\">content_copy</span></button>"),
                               (nil, "<button aria-label=\"Copy\"></button>"), (nil, "<button title=\"Copy to clipboard\"></button>"),
                               (nil, "<button data-tooltip=\"Copy\"></button>"), (nil, "<button data-bs-original-title=\"Copy\"></button>"),
                               (nil, "<button data-clipboard-text=\"npm install foo\"></button>"),
                               (nil, "<button class=\"copyButton\"></button>"), (nil, "<button class=\"btn js-clipboard-copy\"></button>"),
                               (nil, "<button><svg aria-label=\"Copy\"><path d=\"M0 0\"></path></svg></button>"), (nil, "<button><img alt=\"Copy\"></button>"),
                               (nil, "<button><svg><title>Copy to clipboard</title><path d=\"M0 0\"></path></svg></button>"),
                               (nil, "<button><svg><use href=\"#icon-copy\"></use></svg></button>"),
                               (nil, "<button><i class=\"fa fa-copy\"></i></button>"), (nil, "<button><span class=\"copyButtonIcons_eSgA\"></span></button>")] {
            let captured = toolbar((text.map { $0 + "\n" } ?? "") + "Run", button + "<button>Run</button>")
            require(captured.plain == "\(paragraph)\nnpm install foo" && captured.markup?.text == fenced, "\(button) says copy: \(captured.plain.debugDescription)")
        }
        // Copyright and copycat are other words, in text and in names: those two are options, and only Copy goes.
        let words = toolbar("Copyright\ncopycat\nCopy", "<button class=\"copyright\">Copyright</button><button title=\"copycat\">copycat</button><button>Copy</button>")
        require(words.plain == "\(paragraph)\nCopyright\ncopycat\nnpm install foo" && words.markup?.text == "\(paragraph)\nCopyright\ncopycat\n```bash\nnpm install foo\n```",
                "not copy: \(words.plain.debugDescription)")
        // Options that only mention a copy are options: an article or an adjective before it, an identifier, a sentence, a tooltip
        // that does not start with it, or a data-* value that is no tooltip.
        for (raw, buttons) in [("A view\nA copy", "<button>A view</button><button>A copy</button>"),
                               ("Shallow copy\nDeep copy", "<button>Shallow copy</button><button>Deep copy</button>"),
                               ("copyWithin()\nfill()", "<button>copyWithin()</button><button>fill()</button>"),
                               ("Create a shallow copy of the list using slicing\nMutate it in place",
                                "<button>Create a shallow copy of the list using slicing</button><button>Mutate it in place</button>"),
                               ("Yes\nNo", "<button title=\"Yes, it makes a copy\">Yes</button><button>No</button>"),
                               ("Reference\nValue", "<button data-feedback=\"Copy semantics would clone it\">Reference</button><button>Value</button>"),
                               ("복사본\n원본", "<button>복사본</button><button>원본</button>"),
                               ("복사하기 전에 저장\n저장하지 않음", "<button>복사하기 전에 저장</button><button>저장하지 않음</button>"),
                               ("완료\n복사 중", "<button>완료</button><button>복사 중</button>"),
                               ("コピーを作る\n元のまま", "<button>コピーを作る</button><button>元のまま</button>")] {
            let captured = toolbar(raw, buttons)
            require(captured.plain == "\(paragraph)\n\(raw)\nnpm install foo" && captured.markup?.text == "\(paragraph)\n\(raw)\n```bash\nnpm install foo\n```",
                    "\(raw.debugDescription) stay: \(captured.plain.debugDescription)")
        }
        // A tab may name a file or a tool that says copy, or say it in its tooltip: the selected one still titles the code, a tab by
        // its role whatever its label. A copy button counts among the buttons side by side, so the one selected beside it is a tab.
        let titled = { (raw: String, buttons: String, title: String) in
            let captured = toolbar(raw, buttons)
            require(captured.plain == "\(paragraph)\n\(title)\nnpm install foo" && captured.markup?.text == "\(paragraph)\n```bash title=\"\(title)\"\nnpm install foo\n```",
                    "\(raw.debugDescription) titled \(title): \(captured.plain.debugDescription)")
        }
        for (label, other) in [("copy.js", "paste.js"), ("CopyButton.tsx", "index.ts"), ("copy-files.sh", "move-files.sh"), ("deep_copy.py", "main.py"), ("npm", "Copy files")] {
            for (selected, plain) in [("role=\"tab\" aria-selected=\"true\"", "role=\"tab\""), ("class=\"tab active\"", "class=\"tab\""),
                                      ("class=\"tab active\" title=\"Commands to copy into \(label)\"", "class=\"tab\" title=\"Commands to copy into \(other)\"")] {
                titled("\(label)\n\(other)", "<button \(selected)>\(label)</button><button \(plain)>\(other)</button>", label)
            }
        }
        titled("Copy object\nDelete object", "<button role=\"tab\" aria-selected=\"true\">Copy object</button><button role=\"tab\">Delete object</button>", "Copy object")
        titled("복사하기\n붙여넣기", "<button role=\"tab\" aria-selected=\"true\">복사하기</button><button role=\"tab\">붙여넣기</button>", "복사하기")
        titled("npm\nCopy", "<button class=\"active\">npm</button><button>Copy</button>", "npm")
        // Known limits. An option or a tab without a role that starts with Copy, or ends with a Korean copy form, is a copy button,
        // as Copy beside Run is: with one button left, that one is lone and goes too, and nothing titles the code; with more left,
        // only it goes; with none left, every option goes. A form not in the list says nothing, so both buttons stay.
        for (raw, buttons, kept) in [("Reference\nCopy", "<button>Reference</button><button>Copy</button>", ""),
                                     ("Copy object\nDelete object", "<button class=\"tab active\">Copy object</button><button class=\"tab\">Delete object</button>", ""),
                                     ("move\ndel\ncopy", "<button>move</button><button>del</button><button>copy</button>", "move\ndel\n"),
                                     ("참조\n값\n깊은 복사하기", "<button>참조</button><button>값</button><button>깊은 복사하기</button>", "참조\n값\n"),
                                     ("얕은 복사\n깊은 복사하기", "<button>얕은 복사</button><button>깊은 복사하기</button>", ""),
                                     ("복사완료\n실행", "<button>복사완료</button><button>실행</button>", "복사완료\n실행\n")] {
            let captured = toolbar(raw, buttons)
            require(captured.plain == "\(paragraph)\n\(kept)npm install foo" && captured.markup?.text == "\(paragraph)\n\(kept)```bash\nnpm install foo\n```",
                    "limit \(raw.debugDescription): \(captured.plain.debugDescription)")
        }
        // Quiz options with a copy button: the options stay, the copy button goes.
        let quiz = capture("\(paragraph)\nlet\nconst\nvar\nCopy\nconst a = 1;", "<p>\(paragraph)</p><div class=\"quiz\"><button class=\"option\">let</button><button class=\"option\">const</button>"
                           + "<button class=\"option\">var</button><button class=\"copy\">Copy</button></div><pre><code class=\"language-js\">const a = 1;</code></pre>")
        require(quiz.plain == "\(paragraph)\nlet\nconst\nvar\nconst a = 1;" && quiz.markup?.text == "\(paragraph)\nlet\nconst\nvar\n```js\nconst a = 1;\n```",
                "quiz with copy: \(quiz.plain.debugDescription)")
        // Known limit: nothing tells three plain buttons beside Copy from options, so they stay as text; only Copy goes.
        let three = toolbar("Run\nReset\nFormat\nCopy", "<button>Run</button><button>Reset</button><button>Format</button><button>Copy</button>")
        require(three.plain == "\(paragraph)\nRun\nReset\nFormat\nnpm install foo" && three.markup?.text == "\(paragraph)\nRun\nReset\nFormat\n```bash\nnpm install foo\n```",
                "three buttons stay: \(three.plain.debugDescription)")
        // The impeccable widget with its copy button among the tabs, marked active after use: the tabs are still a tab bar,
        // so the selected tab titles the command and Codex and Copy go.
        let one = codeCopy("impeccable-one"), scans = String(one.plain[one.plain.range(of: "It scans")!.lowerBound...])
        let inside = one.html.replacingOccurrences(of: "</div><button class=\"site-code-copy\"", with: "<button class=\"site-code-copy is-active\"")
            .replacingOccurrences(of: "</span></button></div><pre", with: "</span></button></div></div><pre")
        let tabs = capture(one.plain, inside)
        require(inside != one.html && tabs.plain == "Most Agents\n/impeccable document\n" + scans
                && tabs.markup?.blocks == [SourceCodeBlock(language: "text", code: "/impeccable document", title: "Most Agents")],
                "a used copy button among the tabs: \(tabs.plain.debugDescription)")
    }

    private static func gutters() {
        // Padded inline numbers go with their own spaces; the code's indentation stays.
        let padded = capture(" 1 def f():\n 2     return 1\n",
                             "<div class=\"highlight\"><pre><span class=\"lineno\"> 1 </span>def f():\n<span class=\"lineno\"> 2 </span>    return 1\n</pre></div>")
        require(padded.plain == "def f():\n    return 1\n" && padded.markup?.blocks.first?.code == "def f():\n    return 1", "padded numbers: \(padded.plain.debugDescription)")
        // Unselectable numbers are not in the copy and cost nothing.
        let unselectable = withReport("def f():\n    return 1", "<div class=\"highlight\"><pre><span class=\"linenos\" style=\"user-select: none;\">1</span>def f():\n"
                                  + "<span class=\"linenos\" style=\"user-select: none;\">2</span>    return 1</pre></div>")
        require(unselectable.source.markup?.blocks.first?.code == "def f():\n    return 1" && unselectable.report.chromeSkipped == 2, "unselectable numbers")
        // Rouge puts its gutter table inside the block; VitePress puts the numbers after it.
        let rouge = capture("1\n2\ndef f\nend\n", "<div class=\"language-ruby highlighter-rouge\"><div class=\"highlight\"><pre class=\"highlight\"><code><table class=\"rouge-table\">"
                            + "<tbody><tr><td class=\"rouge-gutter gl\"><pre class=\"lineno\">1\n2\n</pre></td><td class=\"rouge-code\"><pre>def f\nend\n</pre></td></tr></tbody></table></code></pre></div></div>")
        require(rouge.plain == "def f\nend\n" && rouge.markup?.blocks == [SourceCodeBlock(language: "ruby", code: "def f\nend")], "rouge: \(rouge.plain.debugDescription)")
        let vitepress = capture("ts\nconst a = 1\nconst b = 2\n1\n2", "<div class=\"language-ts vp-adaptive-theme line-numbers-mode\"><button title=\"Copy Code\" class=\"copy\"></button>"
                                + "<span class=\"lang\">ts</span><pre class=\"shiki vp-code\"><code><span class=\"line\">const a = 1</span>\n<span class=\"line\">const b = 2</span></code></pre>"
                                + "<div class=\"line-numbers-wrapper\" aria-hidden=\"true\"><span class=\"line-number\">1</span><br><span class=\"line-number\">2</span><br></div></div>")
        require(vitepress.plain == "ts\nconst a = 1\nconst b = 2" && vitepress.markup?.blocks.first?.language == "ts", "vitepress: \(vitepress.plain.debugDescription)")
        // Line numbers grow with the code, so a long listing is not held to the fixed cap.
        let code = (1...40).map { "value_\($0) = compute(\($0))" }
        let long = capture(code.enumerated().map { "\($0.offset + 1)\($0.element)" }.joined(separator: "\n"),
                           "<div class=\"highlight\"><pre>" + code.enumerated().map { "<span class=\"linenos\">\($0.offset + 1)</span>\($0.element)" }.joined(separator: "\n") + "</pre></div>")
        require(long.plain == code.joined(separator: "\n") && long.removed.count == 40, "40 numbered lines")
        // Numbers longer than the code they number (a run of closing braces) go too: they count against no cap.
        let braces = Array(repeating: "}", count: 12), numbers = (1...12).map(String.init)
        let table = withReport(numbers.joined(separator: "\n") + "\t" + braces.joined(separator: "\n") + "\n",
                               "<div class=\"highlight-js notranslate\"><table class=\"highlighttable\"><tbody><tr><td class=\"linenos\"><div class=\"linenodiv\"><pre>"
                               + numbers.joined(separator: "\n") + "</pre></div></td><td class=\"code\"><div class=\"highlight\"><pre>" + braces.joined(separator: "\n")
                               + "\n</pre></div></td></tr></tbody></table></div>")
        require(table.source.plain == braces.joined(separator: "\n") + "\n" && !table.report.cleaningAbandoned
                && table.source.markup?.blocks == [SourceCodeBlock(language: "js", code: braces.joined(separator: "\n"))], "short numbered lines: \(table.source.plain.debugDescription)")
    }

    /// Classes and roles that look like controls but carry the page's text stay.
    private static func chromeSafety() {
        let clip = "clip: rect(0px, 0px, 0px, 0px); height: 1px; overflow: hidden; position: absolute; width: 1px;"
        let layout = capture("Step 1\n2\nOpen Settings.", "<div class=\"row no-gutters\"><div class=\"col\">Step 1</div><div class=\"col gutter\">2</div>"
                             + "<div class=\"col\">Open <a href=\"https://x.dev/settings\">Settings</a>.</div></div>")
        require(layout.plain == "Step 1\n2\nOpen Settings." && layout.markup?.text == "Step 1\n2\nOpen <a1>Settings</a1>.", "layout gutters are text")
        let responsive = capture("Plans start at $9.\nper month", "<p>Plans start at $9.</p><span class=\"sr-only md:not-sr-only\" style=\"\(clip)\">per month</span>")
        require(responsive.plain == "Plans start at $9.\nper month", "md:not-sr-only shows the text")
        let skip = capture("Skip to main content\nWelcome to the docs.", "<a class=\"visually-hidden-focusable\" href=\"#main\" style=\"\(clip)\">Skip to main content</a><p>Welcome to the docs.</p>")
        require(skip.plain == "Skip to main content\nWelcome to the docs.", "a focusable skip link stays")
        let unstyled = capture("\(paragraph)\nper month", "<p>\(paragraph)</p><span class=\"sr-only\">per month</span>")
        require(unstyled.plain == "\(paragraph)\nper month", "a class name alone is no evidence")
        let action = capture("Ready? Get started now.", "<p>Ready? <a role=\"button\" class=\"btn\" href=\"https://x.dev/start\">Get started</a> now.</p>")
        require(action.markup?.text == "Ready? <a1>Get started</a1> now.", "a call to action stays a link")
        let quiz = capture("Which keyword declares a constant?\nlet\nconst\nPick one to see the answer.\nconst a = 1;",
                           "<p>Which keyword declares a constant?</p><div class=\"quiz\"><button class=\"option\">let</button><button class=\"option\">const</button></div>"
                           + "<p>Pick one to see the answer.</p><pre><code class=\"language-js\">const a = 1;</code></pre>")
        require(quiz.plain.hasPrefix("Which keyword declares a constant?\nlet\nconst\n"), "option buttons away from code stay")
        let faq = capture("\(paragraph)\nHow do I install it?\nnpm install foo",
                          "<p>\(paragraph)</p><h3><button aria-expanded=\"false\">How do I install it?</button></h3><pre><code>npm install foo</code></pre>")
        require(faq.plain == "\(paragraph)\nHow do I install it?\nnpm install foo", "a heading's disclosure button stays next to code")
        let long = "Show the full configuration file with every option explained"
        let longButton = capture("\(paragraph)\n\(long)\nnpm install foo", "<p>\(paragraph)</p><button>\(long)</button><pre><code>npm install foo</code></pre>")
        require(longButton.plain.contains(long), "a long button is content")
        let prose = capture("\(paragraph)\nCopy\nThe end.", "<p>\(paragraph)</p><button>Copy</button><p>The end.</p>")
        require(prose.plain.contains("\nCopy\n"), "a button away from code stays")
        let duplicate = withReport("Area is πr2 here.", "<p>Area is <span aria-hidden=\"true\">πr2</span> here.</p>")
        require(duplicate.source.plain == "Area is πr2 here." && duplicate.report.chromeMatched == 1, "visible aria-hidden text is matched, never removed")
        // Clipped text is removable anywhere, unless a screen-reader text is long; so is a status that reports a copy. Any other
        // visible status may be the page's own message: it goes only where a button would, right next to code.
        let status = capture("\(paragraph)\nSaved\nper month", "<p>\(paragraph)</p><span role=\"status\">Saved</span><span class=\"sr-only\" style=\"\(clip)\">per month</span>")
        require(status.plain == "\(paragraph)\nSaved", "clipped text goes anywhere, a visible status stays: \(status.plain.debugDescription)")
        let release = "Version 2.4 is the current stable release."
        let message = capture("\(paragraph)\n\(release)\nRead the notes below.", "<p>\(paragraph)</p><p role=\"status\">\(release)</p><p>Read the notes below.</p>")
        require(message.plain == "\(paragraph)\n\(release)\nRead the notes below.", "a status message in prose stays: \(message.plain.debugDescription)")
        let feedback = capture("\(paragraph)\nCopied!\nRead the notes below.", "<p>\(paragraph)</p><span role=\"status\">Copied!</span><p>Read the notes below.</p>")
        require(feedback.plain == "\(paragraph)\nRead the notes below.", "copy feedback goes anywhere: \(feedback.plain.debugDescription)")
        let announced = capture("\(paragraph)\n3 results found\nRead the notes below.",
                                "<p>\(paragraph)</p><span role=\"status\" style=\"\(clip)\">3 results found</span><p>Read the notes below.</p>")
        require(announced.plain == "\(paragraph)\nRead the notes below.", "a clipped status is hidden text: \(announced.plain.debugDescription)")
        let code = "<pre><code class=\"language-sh\">npm install foo</code></pre>"
        for word in ["Copied!", "Saved"] {
            let beside = capture("\(paragraph)\nnpm install foo\n\(word)\nDone.", "<p>\(paragraph)</p>\(code)<span role=\"status\">\(word)</span><p>Done.</p>")
            require(beside.plain == "\(paragraph)\nnpm install foo\nDone." && beside.markup?.blocks.count == 1, "a status next to code goes: \(beside.plain.debugDescription)")
        }
        let note = "This sentence is only for screen readers and explains the chart above in more words than a label would."
        let longHidden = capture("\(paragraph) \(paragraph)\n\(note)", "<p>\(paragraph) \(paragraph)</p><span class=\"visually-hidden\" style=\"\(clip)\">\(note)</span>")
        require(longHidden.plain.hasSuffix(note), "long screen-reader text is content")
        // Only a clip to nothing hides text; a crop shows it.
        let crop = capture("\(paragraph)\nFigure 2: visible caption", "<p>\(paragraph)</p><span style=\"position: absolute; clip: rect(0px, 240px, 30px, 0px);\">Figure 2: visible caption</span>")
        require(crop.plain == "\(paragraph)\nFigure 2: visible caption", "a cropped caption stays")
        let spaced = capture("\(paragraph)\nper month", "<p>\(paragraph)</p><span style=\"position: absolute; clip: rect(0 0 0 0);\">per month</span>")
        require(spaced.plain == paragraph, "rect(0 0 0 0) clips to nothing")
    }

    private static func languageLabels() {
        let html = "<p>\(paragraph)</p><pre><div class=\"header\"><span>python</span><button>Copy code</button></div><div><code class=\"hljs language-python\">print(1)</code></div></pre>"
        for plain in ["\(paragraph)\npython\nCopy code\nprint(1)", "\(paragraph)\npythonCopy code\nprint(1)"] {
            let (captured, report) = withReport(plain, html)
            require(captured.plain == "\(paragraph)\nprint(1)" && captured.markup?.text == "\(paragraph)\n```python\nprint(1)\n```" && report.labelLines == 1,
                    "a chat-style label inside the pre goes: \(captured.plain.debugDescription)")
        }
        let mismatch = capture("\(paragraph)\nPython 3\nprint(1)", "<p>\(paragraph)</p><pre><div>Python 3</div><code class=\"language-python\">print(1)</code></pre>")
        require(mismatch.plain == "\(paragraph)\nPython 3\nprint(1)", "a label that is not the language stays")
        let paragraphLabel = capture("Python\nprint(1)", "<p>Python</p><pre><code class=\"language-python\">print(1)</code></pre>")
        require(paragraphLabel.plain == "Python\nprint(1)" && paragraphLabel.markup?.text == "Python\n```python\nprint(1)\n```", "a paragraph is no label")
    }

    private static func codeBlocks() {
        func fence(_ html: String, _ plain: String = "x\nDone.") -> String? { capture(plain, html + "<p>Done.</p>").markup?.text }
        for (html, language) in [("<pre data-language=\"TS\"><code>x</code></pre>", "ts"), ("<pre><code class=\"language-go\">x</code></pre>", "go"),
                                 ("<pre class=\"lang-rb\"><code>x</code></pre>", "rb"), ("<pre class=\"brush: php; toolbar: false\">x</pre>", "php"),
                                 ("<pre class=\"sourceCode python\"><code class=\"sourceCode python\">x</code></pre>", "python"),
                                 ("<div class=\"highlight highlight-source-rust\"><pre>x</pre></div>", "rust"), ("<pre><code class=\"hljs kotlin\">x</code></pre>", "kotlin"),
                                 ("<pre lang=\"swift\"><code>x</code></pre>", "swift"), ("<div class=\"highlight-console\"><div class=\"highlight\"><pre>x</pre></div></div>", "console"),
                                 ("<pre class=\"chroma\"><code class=\"x\" data-lang=\"yaml\">x</code></pre>", "yaml")] {
            require(fence(html) == "```\(language)\nx\n```\nDone.", "language \(language): \(String(describing: fence(html)))")
        }
        // A tag that would not read as one at once (a file suffix, a command, a human language) gives a bare fence.
        for html in ["<pre><code class=\"language-js:file\">x</code></pre>", "<pre><code class=\"language-ls\">x</code></pre>",
                     "<pre><code class=\"language-none\">x</code></pre>", "<pre lang=\"cs\"><code>x</code></pre>", "<pre><code class=\"language-nginx\">x</code></pre>"] {
            require(fence(html) == "```\nx\n```\nDone.", "bare fence: \(html)")
        }
        require(fence("<pre class=\"chroma\"><code class=\"language-py\">a = 1<br>b = 2</code></pre>", "a = 1\nb = 2\nDone.") == "```py\na = 1\nb = 2\n```\nDone.", "<br> lines")
        require(fence("<pre><code>a</code></pre><pre><code>b</code></pre>", "a\nb\nDone.") == "```\na\n```\n```\nb\n```\nDone.", "two pres")
        let nested = capture("Example:\n```js\nx\n```", "<p>Example:</p><pre><code class=\"language-md\">```js\nx\n```</code></pre>")
        require(nested.markup?.text == "Example:\n````md\n```js\nx\n```\n````" && nested.markup?.blocks.first?.fence == 4, "code with a fence gets four backticks")
        let linked = capture("See docs/api.md\nThe docs live in docs.", "<pre><code>See <a href=\"https://x.dev/api\">docs/api.md</a></code></pre><p>The <a href=\"https://x.dev/docs\">docs</a> live in docs.</p>")
        require(linked.markup?.text == "```\nSee docs/api.md\n```\nThe <a1>docs</a1> live in docs.", "no link tags inside code")
        let template = capture("const s = `${a}`;\nRun build to bundle.", "<pre><code class=\"language-js\">const s = `${a}`;</code></pre><p>Run <code>build</code> to bundle.</p>")
        require(template.markup?.text == "```js\nconst s = `${a}`;\n```\nRun `build` to bundle." && template.markup?.hasInlineStructure == true,
                "backticks in code do not stop chips in prose")
        let only = capture("npm install", "<pre><code>npm install</code></pre>")
        require(only.plain == "npm install" && only.markup?.text == "```\nnpm install\n```" && only.markup?.hasInlineStructure == false, "a code-only selection")
        let partial = capture("pwd\nls\nThen run the build.", "<pre><code>pwd\nls</code></pre><p>Then run the build.</p>")
        require(partial.markup?.text == "```\npwd\nls\n```\nThen run the build.", "a selection that starts inside code")
        require(capture("Network Working Group\n   Request for Comments: 2616", "<pre class=\"newpage\">Network Working Group\n   Request for Comments: 2616</pre>").markup == nil,
                "a <pre> without a code signal stays text")
        require(fence("<div class=\"highlight\"><pre>x</pre></div>") == "```\nx\n```\nDone.", "a highlighter's <pre> without <code>")
        let many = (0...RichSourceImporter.maxCodeBlocks).map { "c\($0)" }
        let limited = withReport(many.joined(separator: "\n"), many.map { "<pre><code>\($0)</code></pre>" }.joined())
        require(limited.source.markup?.blocks.count == RichSourceImporter.maxCodeBlocks && limited.report.blocks.last?.reason == "over the block limit", "block limit")
    }

    private static func structuredFallbacks() {
        require(capture("Copy", "<button>Copy</button>") == CapturedSource(plain: "Copy"), "a copy of controls only stays as copied")
        // At most half the letters, and at most 64 of them, may go; anything more keeps the copy as it was.
        let clip = "clip: rect(0px, 0px, 0px, 0px); height: 1px; overflow: hidden; position: absolute; width: 1px;"
        func status(_ text: String, removing count: Int) -> RichSourceImporter.Report {
            withReport("\(text)\n\(String(repeating: "b", count: count))", "<p>\(text)</p><span class=\"sr-only\" style=\"\(clip)\">\(String(repeating: "b", count: count))</span>").report
        }
        let ten = String(repeating: "a", count: 10)
        require(status(ten, removing: 10).removedLines == 1 && status(ten, removing: 11).cleaningAbandoned, "the half cap")
        require(status(paragraph + " " + paragraph, removing: 64).removedLines == 1 && status(paragraph + " " + paragraph, removing: 65).cleaningAbandoned, "the fixed cap")
        require(capture("Hi\nCopied to clipboard.", "<p>Hi</p><span role=\"status\">Copied to clipboard.</span>").plain == "Hi\nCopied to clipboard.", "mostly controls")
        // Keys the HTML lacks on a code line (Slack's backticks) leave the block unfenced.
        let long = [paragraph, paragraph, paragraph].joined(separator: " ")
        let slack = withReport("\(long)\n```npm i```", "<p>\(long)</p><pre><code>npm i</code></pre>")
        require(slack.source.markup == nil && slack.report.blocks.first?.reason == "shares its lines", "unmatched keys on a code line")
        // A copy that already writes fences (Notion, chat apps) gets none from the app.
        let markdown = withReport("\(long)\n```\nls -la\n```", "<p>\(long)</p><pre><code>ls -la</code></pre>")
        require(markdown.source.markup == nil && markdown.report.blocks.first?.accepted == true && !markdown.report.fences, "fences off")
        // Given up, cleaning leaves a copy button on its code line: that block is not fenced, the clean one still is.
        let noisy = String(repeating: "b", count: 65)
        let abandoned = withReport("\(paragraph)\n\(noisy)\nCopyls -la\npwd\nmake",
                                   "<p>\(paragraph)</p><span class=\"sr-only\" style=\"\(clip)\">\(noisy)</span><div class=\"highlight\"><pre><button class=\"copy\">Copy</button>"
                                   + "<code class=\"language-sh\">ls -la\npwd</code></pre></div><pre><code class=\"language-sh\">make</code></pre>")
        require(abandoned.report.cleaningAbandoned && abandoned.source.plain == "\(paragraph)\n\(noisy)\nCopyls -la\npwd\nmake"
                && abandoned.source.markup?.text == "\(paragraph)\n\(noisy)\nCopyls -la\npwd\n```sh\nmake\n```"
                && abandoned.report.blocks.map(\.reason) == ["keeps page controls", "fenced"], "no controls inside a fence: \(abandoned.source.markup?.text ?? "nil")")
    }

    /// Independent review of PR #56.
    private static func reviewOfPR56() {
        // Code that shows fences of its own is fenced with four backticks; the store reads the source's fence style without it
        // (CodeBlockStoreTests).
        let readme = capture("Add this to your README:\n```js\nconsole.log(1)\n```\nThen commit the file to your repository today.",
                             "<p>Add this to your README:</p><pre><code class=\"language-markdown\">```js\nconsole.log(1)\n```</code></pre><p>Then commit the file to your repository today.</p>")
        require(readme.markup?.text == "Add this to your README:\n````markdown\n```js\nconsole.log(1)\n```\n````\nThen commit the file to your repository today.",
                "a block with fences inside: \(readme.markup?.text ?? "nil")")

        // Hacker News sets indented prose (a quote) in a bare <pre><code>: it stays prose, as before app fences.
        let quote = "  This is the first line of a quote from the article that I want to answer.\n  And the second line of that quote, which is also a sentence."
        let hn = withReport("I disagree with the premise here.\n\(quote)\nSee the thread for more.",
                            "<div class=\"commtext c00\">I disagree with the premise here.<p></p><pre><code>\(quote)</code></pre><p>See <a href=\"https://news.ycombinator.com/item?id=1\">the thread</a> for more.</p></div>")
        require(hn.source.markup?.text == "I disagree with the premise here.\n\(quote)\nSee <a1>the thread</a1> for more." && hn.source.markup?.blocks == [] && hn.report.blocks.isEmpty,
                "a quote in a bare pre is prose: \(hn.source.markup?.text ?? "nil")")
        // Commands, flags and data in a bare <pre><code> are still code.
        for code in ["npm install foo", "ls -la", "{\n  \"name\": \"demo\",\n  \"private\": true\n}", "git commit -m \"Fix the parser for the empty input case\""] {
            let bare = capture("\(code)\nDone.", "<pre><code>\(code)</code></pre><p>Done.</p>")
            require(bare.markup?.text == "```\n\(code)\n```\nDone.", "a bare pre of code: \(bare.markup?.text ?? "nil")")
        }

        // Starlight's tabs are links to their panels, which Chrome writes out in full: still tabs, so the selected one titles the code.
        let starlight = "<p>Install Astro with your package manager:</p><starlight-tabs><div class=\"tablist-wrapper not-content\"><ul role=\"tablist\">"
            + "<li role=\"presentation\" class=\"tab\"><a role=\"tab\" href=\"https://docs.example.com/install/#tab-panel-0\" id=\"tab-0\" aria-selected=\"true\" tabindex=\"0\">npm</a></li>"
            + "<li role=\"presentation\" class=\"tab\"><a role=\"tab\" href=\"https://docs.example.com/install/#tab-panel-1\" id=\"tab-1\" aria-selected=\"false\" tabindex=\"-1\">pnpm</a></li>"
            + "</ul></div><div id=\"tab-panel-0\" aria-labelledby=\"tab-0\" role=\"tabpanel\"><pre><code class=\"language-sh\">npm create astro@latest</code></pre></div></starlight-tabs>"
        for page in [nil, "https://docs.example.com/install/"] {
            let tabs = RichSourceImporter.capture(plain: "Install Astro with your package manager:\nnpm\npnpm\nnpm create astro@latest", html: starlight, sourceURL: page)
            require(tabs.plain == "Install Astro with your package manager:\nnpm\nnpm create astro@latest"
                    && tabs.markup?.text == "Install Astro with your package manager:\n```sh title=\"npm\"\nnpm create astro@latest\n```" && tabs.markup?.links == [],
                    "link tabs title the code: \(tabs.plain.debugDescription) / \(tabs.markup?.text ?? "nil")")
        }
        // Left unfenced (a prose line of only backticks), the selected tab stays as text and links nowhere.
        let unfenced = capture("Install Astro with your package manager:\nnpm\npnpm\nnpm create astro@latest\n```", starlight + "<p>```</p>")
        require(unfenced.plain == "Install Astro with your package manager:\nnpm\nnpm create astro@latest\n```" && unfenced.markup == nil,
                "an unfenced tab is no link: \(unfenced.markup?.text ?? "nil")")
        // A tab labelled in code titles the block without a chip on its line, and the prose keeps its chip and link.
        let coded = capture("\(paragraph) Run npm ci or see the guide.\nnpm\nyarn\nnpm install foo",
                            "<p>\(paragraph) Run <code>npm ci</code> or see <a href=\"https://x.dev/guide\">the guide</a>.</p><div role=\"tablist\"><button role=\"tab\" aria-selected=\"true\"><code>npm</code></button>"
                            + "<button role=\"tab\"><code>yarn</code></button></div><pre><code class=\"language-bash\">npm install foo</code></pre>")
        require(coded.markup?.text == "\(paragraph) Run `npm ci` or see <a1>the guide</a1>.\n```bash title=\"npm\"\nnpm install foo\n```", "a tab in code: \(coded.markup?.text ?? "nil")")
        // A button that only points into its own page is a control too; one that leaves it is a call to action.
        let toggle = "<p>\(paragraph)</p><a role=\"button\" href=\"https://docs.example.com/install/#code\">Expand</a><pre><code class=\"language-sh\">npm i</code></pre>"
        require(RichSourceImporter.capture(plain: "\(paragraph)\nExpand\nnpm i", html: toggle, sourceURL: "https://docs.example.com/install/").plain == "\(paragraph)\nnpm i",
                "an in-page button link next to code goes")
        require(RichSourceImporter.capture(plain: "\(paragraph)\nExpand\nnpm i", html: toggle).markup?.text == "\(paragraph)\n<a1>Expand</a1>\n```sh\nnpm i\n```",
                "without the page, a button link stays a link")

        // Controls that stay (a clickable card, a toolbar of prose: over 40 letters) keep their links and chips.
        let card = capture("\(paragraph)\nAcme SDK\nInstall with npm install acme and read the quick start before your first integration.",
                           "<p>\(paragraph)</p><div role=\"button\" tabindex=\"0\" class=\"card\"><h3>Acme SDK</h3><p>Install with <code>npm install acme</code> and read the "
                           + "<a href=\"https://acme.dev/start\">quick start</a> before your first integration.</p></div>")
        require(card.markup?.text == "\(paragraph)\nAcme SDK\nInstall with `npm install acme` and read the <a1>quick start</a1> before your first integration.",
                "a card keeps its chip and link: \(card.markup?.text ?? "nil")")
        let toolbar = capture("\(paragraph)\nSelect text, then press Ctrl+B to make it bold or open the shortcut list.",
                              "<p>\(paragraph)</p><div role=\"toolbar\" aria-label=\"Formatting\"><p>Select text, then press <kbd>Ctrl</kbd>+<kbd>B</kbd> to make it bold or open the "
                              + "<a href=\"https://acme.dev/keys\">shortcut list</a>.</p></div>")
        require(toolbar.markup?.text == "\(paragraph)\nSelect text, then press `Ctrl`+`B` to make it bold or open the <a1>shortcut list</a1>.",
                "a toolbar of prose keeps its chips and link: \(toolbar.markup?.text ?? "nil")")
        // A copy button that goes takes its link with it.
        let removed = capture("\(paragraph)\nnpm install acme\nCopy", "<p>\(paragraph)</p><pre><code class=\"language-sh\">npm install acme</code></pre>"
                              + "<button class=\"copy\"><a href=\"https://acme.dev/copy\">Copy</a></button>")
        require(removed.plain == "\(paragraph)\nnpm install acme" && removed.markup?.text == "\(paragraph)\n```sh\nnpm install acme\n```" && removed.markup?.links == [],
                "a removed copy button contributes nothing: \(removed.markup?.text ?? "nil")")

        // A block left unfenced (a prose line of only backticks) is prose: its links stay.
        let rustdoc = capture("pub fn parse(input: &str) -> Doc\nParses the input. A fence in prose looks like this:\n```",
                              "<pre class=\"rust item-decl\"><code class=\"language-rust\">pub fn parse(input: &amp;<a class=\"primitive\" href=\"https://doc.rust-lang.org/std/primitive.str.html\">str</a>) -&gt; "
                              + "<a class=\"struct\" href=\"https://docs.rs/demo/latest/demo/struct.Doc.html\">Doc</a></code></pre><p>Parses the input. A fence in prose looks like this:</p><p>```</p>")
        require(rustdoc.markup?.blocks == [] && rustdoc.markup?.links.map(\.text) == ["str", "Doc"]
                && rustdoc.markup?.text.hasPrefix("pub fn parse(input: &<a1>str</a1>) -> <a2>Doc</a2>\n") == true,
                "an unfenced block keeps its links: \(rustdoc.markup?.text ?? "nil")")
    }

    /// Real Chrome copies, not committed (`swift scripts/dump-pasteboard.swift <dir> <name>`): with
    /// `DEEPK_CODE_COPY_LIVE=<dir>` every `.txt`/`.html` pair there must keep the invariants, and its report is printed.
    private static func liveCaptures() {
        guard let path = ProcessInfo.processInfo.environment["DEEPK_CODE_COPY_LIVE"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        require(!names.isEmpty, "no captures in \(path)")
        for name in names {
            let plain = try! String(contentsOf: directory.appendingPathComponent(name + ".txt"), encoding: .utf8)
            let html = try? String(contentsOf: directory.appendingPathComponent(name + ".html"), encoding: .utf8)
            let (captured, report) = withReport(plain, html ?? "")
            print("live \(name): \(report)")
            let raw = plain.components(separatedBy: "\n")
            require(captured.plain.components(separatedBy: "\n").allSatisfy { line in line.isEmpty || raw.contains { $0.contains(line) } }, "\(name): cleaning only drops")
            guard let markup = captured.markup else { continue }
            let display = TranslationMarkup(markup.text, inline: markup.inlineOptions).displayText
            require(TranslationMarkup.trimmingTrailingWhitespace(display) == TranslationMarkup.trimmingTrailingWhitespace(shown(captured)), "\(name): the markup shows the cleaned text")
            let fenced = TranslationMarkup.layout(markup.text).blocks.filter { $0.closer != nil }.map(\.code)
            require(markup.blocks.allSatisfy { fenced.contains($0.lines) }, "\(name): every block reads back")
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "RichSourceImporterTests: \(message)")
    }

    private static func htmlLists() {
        let raw = "Describe the outcome: ordinary language is enough.\nAsk for a review: choose where to start."
        let html = "<ul><li><strong>Describe the outcome:</strong> ordinary language is enough.</li>"
            + "<li><strong>Ask for a review:</strong> choose where to start.</li></ul>"
        let bullet = capture(raw, html)
        require(bullet.plain == "- Describe the outcome: ordinary language is enough.\n- Ask for a review: choose where to start.",
                "HTML-only bullet markers are visible in the source: \(bullet.plain)")
        require(bullet.raw == raw && bullet.markup == nil, "list-only captures preserve raw identity without inventing inline markup")

        let ordered = capture("Keep the window.\nRetry.\nFinish.",
                              "<ol start='3'><li>Keep the window.</li><li value='7'>Retry.</li><li>Finish.</li></ol>")
        require(ordered.plain == "3. Keep the window.\n7. Retry.\n8. Finish.", "ordered start, value and the following counter")
        let reversed = capture("Keep.\nRetry.\nFinish.", "<ol reversed><li>Keep.</li><li value='7'>Retry.</li><li>Finish.</li></ol>")
        require(reversed.plain == "3. Keep.\n7. Retry.\n6. Finish.", "reversed list counts direct items, then follows value")
        let negative = capture("Keep.\nRetry.", "<ol start='-2'><li>Keep.</li><li>Retry.</li></ol>")
        require(negative.plain == "-2. Keep.\n-1. Retry.", "signed HTML counters stay literal numbered text")

        let nested = capture("Keep the source.\nPreserve links.\nPreserve code.\nCopy the result.",
                             "<ul><li>Keep the source.<ol start='4'><li>Preserve links.</li><li>Preserve code.</li></ol></li>"
                                + "<li>Copy the result.</li></ul>")
        require(nested.plain == "- Keep the source.\n  4. Preserve links.\n  5. Preserve code.\n- Copy the result.", "mixed nested item order and depth")
        let fragment = capture("Preserve links.\nPreserve code.", "<ul><li><ul><li>Preserve links.</li><li>Preserve code.</li></ul></li></ul>")
        require(fragment.plain == "- Preserve links.\n- Preserve code.", "a selected nested fragment does not invent an unselected parent")

        for marker in ["- ", "* ", "• ", "1. ", "3) "] {
            let text = marker + "Keep the source.\n" + marker + "Copy the result."
            require(capture(text, "<ul><li>Keep the source.</li><li>Copy the result.</li></ul>").plain == text,
                    "existing plain markers are never doubled: \(marker)")
        }
        let wraps = capture("  Keep the source\nwhen a line wraps.\n\nA second paragraph.\nCopy.",
                            "<ul><li><p>Keep the source<br>when a line wraps.</p><p>A second paragraph.</p></li><li>Copy.</li></ul>")
        require(wraps.plain == "- Keep the source\n  when a line wraps.\n\n  A second paragraph.\n- Copy.",
                "one marker per item, with body indentation across lines and paragraphs: \(wraps.plain)")
        require(wraps.raw.hasPrefix("  Keep"), "normalization never rewrites the diagnostic copy")
        let markedWrap = capture("• Keep the source\nwhen a line wraps.", "<ul><li>Keep the source<br>when a line wraps.</li></ul>")
        require(markedWrap.plain == "• Keep the source\n  when a line wraps.", "an existing marker also supplies continuation indentation")

        let inline = capture("Use git and read docs.\nKeep going.",
                             "<ul><li>Use <code>git</code> and read <a href='https://d.dev'>docs</a>.</li><li>Keep going.</li></ul>")
        require(inline.plain == "- Use git and read docs.\n- Keep going."
                && inline.markup?.text == "- Use `git` and read <a1>docs</a1>.\n- Keep going."
                && inline.markup?.links.map(\.url.absoluteString) == ["https://d.dev"] && inline.markup?.code == ["git"],
                "list insertion updates chip and link offsets together: \(inline.markup?.text ?? "nil")")
        if let markup = inline.markup {
            require(TranslationMarkup(markup.text, inline: markup.inlineOptions).displayText == inline.plain,
                    "the model markup and source show the same list text")
        }

        let widgetPlain = "Install it.\nnpm\npnpm\nnpm install deepk\nCopy\nRead docs."
        let widget = capture(widgetPlain, "<ul><li>Install it.<div role='tablist'><button role='tab' aria-selected='true'>npm</button>"
                             + "<button role='tab'>pnpm</button></div><pre><code class='language-sh'>npm install deepk</code></pre>"
                             + "<button>Copy</button></li><li>Read docs.</li></ul>")
        require(widget.plain == "- Install it.\nnpm\nnpm install deepk\n- Read docs."
                && widget.markup?.text == "- Install it.\n```sh title=\"npm\"\nnpm install deepk\n```\n- Read docs."
                && widget.markup?.blocks.first?.code == "npm install deepk", "list markers stay away from code and selected tab titles")

        require(capture("Completely different copied prose.", html).plain == "Completely different copied prose.", "mismatched HTML adds no items")
        let partial = capture("pha item.\nBeta item.", "<ul><li>Alpha item.</li><li>Beta item.</li></ul>")
        require(!partial.plain.contains("Alpha") && !partial.plain.hasPrefix("- pha"), "a clipped first item is not reconstructed from outside the copy")
        let combined = capture("AlphaBeta", "<ul><li>Alpha</li><li>Beta</li></ul>")
        require(combined.plain == "AlphaBeta", "ambiguous items sharing one plain line are left unchanged")
        require(capture("Keep the source.\nCopy the result.", "<p>Keep the source.</p><p>Copy the result.</p>").plain
                == "Keep the source.\nCopy the result.", "plain paragraphs do not acquire bullets")
    }
}
