import Foundation

/// Projects links, code and lists from the clipboard HTML onto the selected plain text, and removes
/// the page's own controls from it: tab labels, copy buttons, line numbers and screen-reader labels around
/// code. The selected tab above a block stays as its title. Any doubt keeps less: fences go first, then chips,
/// then links, and HTML that does not describe the text leaves the plain text alone, which is what DeepK
/// translated before.
enum RichSourceImporter {
    static let maxHTMLBytes = 1 << 20
    static let maxLinks = 40
    static let maxCodeSpans = 80
    static let maxCodeBlocks = 32
    /// Cleaning is given up when it would remove more letters than this, or more than half the rest of the copy;
    /// line numbers count against neither.
    static let maxRemovedKeys = 64

    /// How a capture went, for tests and diagnostics. Counts and reasons only, never the text.
    struct Report {
        struct Block: Equatable {
            var language: String?
            var accepted: Bool
            var reason: String
        }

        /// Plain letters the alignment skipped, and how many it allows.
        var misses = 0
        var budget = 0
        /// Page controls the plain text has as a whole, and those it lacks.
        var chromeMatched = 0
        var chromeSkipped = 0
        /// Lines cleaning removed, language labels included, and the labels alone.
        var removedLines = 0
        var labelLines = 0
        /// Cleaning would have removed too much, so the text stays as copied, and blocks whose lines kept controls
        /// are not fenced.
        var cleaningAbandoned = false
        var blocks: [Block] = []
        /// App fences made it into the markup, and which inline layer did: "chips+links", "links" or "".
        var fences = false
        var inline = ""
        /// Why the copy stayed exactly as copied, if it did.
        var fallback: String?
    }

    /// `html` is the clipboard's `public.html`, read with the plain text in one clipboard change.
    static func capture(plain: String, html: String?, sourceURL: String? = nil) -> CapturedSource {
        captureWithReport(plain: plain, html: html, sourceURL: sourceURL).source
    }

    static func captureWithReport(plain: String, html: String?, sourceURL: String? = nil) -> (source: CapturedSource, report: Report) {
        var report = Report()
        guard let markup = html, markup.utf8.count <= maxHTMLBytes else {
            report.fallback = "no html"
            return (CapturedSource(plain: plain), report)
        }
        let base = sourceURL.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        guard let rich = scan(markup, base: base) else {
            report.fallback = "unreadable html"
            return (CapturedSource(plain: plain), report)
        }
        return (project(rich, onto: plain, report: &report) ?? CapturedSource(plain: plain), report)
    }

    /// What a double copy translates. Formulas are tidied first; a copy whose text that changed stays plain,
    /// because links and inline code are matched against the copied text. A source over `inputLimit`
    /// characters is not parsed: it is not translated anyway, and parsing runs on the main thread.
    static func copiedSource(plain: String, html: String?, inputLimit: Int = 4_000) -> CapturedSource {
        let text = CopiedMathNormalizer.normalize(plain: plain, html: html).text
        guard let html, text == plain, text.count <= inputLimit else { return CapturedSource(plain: text) }
        return capture(plain: text, html: html)
    }

    // MARK: - HTML scan

    private struct Style: Equatable {
        var skip = false
        /// Number of the outermost code element, so adjacent elements stay separate spans.
        var code: Int?
        var mono = false
        var pre = false
        var link: Int?
        /// Nearest list container and item. Their text is still aligned with the clipboard before markers are added.
        var list: Int?
        var listItem: Int?
        /// The outermost `<pre>` around the text, as an index into `Rich.blocks`.
        var block: Int?
        /// Inside that block's `<code>` or `<samp>`, as opposed to a label beside it.
        var blockCode = false
        /// The outermost page control around the text (`Rich.chrome`); its text matches as a whole or not at all.
        var chrome: Int?
        /// The outermost control around the text that cleaning may remove.
        var removable: Int?
        /// The innermost control around the text; `Chrome.outer` leads to the ones around it.
        var inner: Int?
        /// The button or tab around the text, one of the controls side by side in a widget.
        var member: Int?
        /// The nearest tablist or toolbar around the text, as an element id.
        var bar: Int?
        /// Inside a heading, summary, label or table header, where a button is the heading itself.
        var heading = false
    }

    private enum ChromeKind {
        /// Buttons and tabs: removable next to a code block or inside one.
        case interactive
        /// A live status: removable anywhere when it is copy feedback ("Copied!"), else only where a button would be.
        case status
        /// Text clipped to nothing for screen readers: removable anywhere.
        case hidden
        /// Line numbers: removable around the block they number.
        case gutter
        /// `aria-hidden` or unselectable text, which may be the visible copy: matched, never removed.
        case decorative
    }

    private struct Chrome {
        let kind: ChromeKind
        var removable: Bool
        /// Ids of a gutter's parent and grandparent; it numbers a block whose `<pre>` shares one of them.
        let scope: [Int]
        /// The block a gutter numbers.
        var block: Int?
        /// Spaces and tabs after its last letter inside it, which go with it when it is cut from a code line.
        var trailingSpaces = 0
        /// The control directly around it.
        let outer: Int?
        /// For a button or tab: the controls it stands beside, as the element id of their tablist or toolbar, else
        /// of their parent; whether it is marked selected; as a toggle, whether it is pressed; and whether it is a tab.
        let group: Int?
        let selected: Bool
        let pressed: Bool?
        let tab: Bool
        /// A button that says copy: a control in any group, never the tab on show or an option. Nil for a tab by its own role,
        /// which never is one: its label names a file or a tool (`copy.js`).
        var copy: Bool?
        /// The one selected tab of its tab bar, whose label may title the block below it.
        var title = false
        /// A status that reports a copy ("Copied!", "Copied to clipboard."); any other status may be the page's own message.
        var feedback = false
    }

    private struct Block {
        /// Named on the `<pre>`, or failing that on its `<code>`.
        var language: String?
        /// Named on a highlighter's wrapper above the `<pre>`.
        let hint: String?
        var hasCode = false
        /// A highlighter's class on the `<pre>` or close above it.
        let signal: Bool
        /// Inside a page control, such as a gutter's own `<pre>`.
        let inChrome: Bool
        /// Ids of its nearest ancestors.
        let ancestors: [Int]
        /// A bare `<pre><code>` whose lines read as sentences: Hacker News sets indented prose (a quote) that way.
        var prose = false
        var tag: String? { language ?? hint }
        var isCandidate: Bool { signal || tag != nil || hasCode && !prose }
    }

    private struct Rich {
        var scalars: [(scalar: Unicode.Scalar, style: Style)] = []
        var links: [URL] = []
        var blocks: [Block] = []
        var chrome: [Chrome] = []
        var lists: [List] = []
        var listItems: [ListItem] = []
    }

    private struct List {
        let ordered: Bool
        let depth: Int
        let start: Int?
        let reversed: Bool
        var items: [Int] = []
    }

    private struct ListItem {
        let list: Int
        let value: Int?
        var number: Int?
    }

    private static let skipped: Set<String> = ["head", "style", "script", "title", "template", "noscript", "svg", "math", "iframe", "textarea", "select"]
    private static let rawText: Set<String> = ["script", "style", "textarea", "title"]
    private static let void: Set<String> = ["br", "img", "hr", "meta", "link", "input", "wbr", "area", "base", "col", "embed", "source", "track", "param"]
    private static let codeTags: Set<String> = ["code", "kbd", "samp", "tt"]
    private static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "summary", "legend", "label", "caption", "dt", "th"]
    private static let interactiveRoles: Set<String> = ["button", "tab", "tablist", "toolbar", "switch"]
    /// Line-number columns of Pygments, Rouge, GitHub, highlight.js, VitePress and Expressive Code.
    private static let gutterClasses: Set<String> = ["lineno", "linenos", "linenodiv", "line-number", "linenumber", "linenumbers",
                                                     "gutter", "rouge-gutter", "blob-num", "hljs-ln-n", "hljs-ln-numbers"]
    /// Classes code highlighters put on a `<pre>` or its wrapper.
    private static let codeWidgetClasses: Set<String> = ["highlight", "codehilite", "chroma", "shiki", "prism-code", "astro-code", "sourcecode",
                                                         "hljs", "highlighter-rouge", "code-block", "codeblock", "expressive-code"]

    /// A lenient scanner: only text, the elements above and a few of their attributes matter. Page controls
    /// are recorded, not dropped: the plain text may or may not have their text.
    private static func scan(_ html: String, base: URL?) -> Rich? {
        let s = Array(html.unicodeScalars)
        var rich = Rich()
        var stack: [(name: String, style: Style, id: Int, classes: [String])] = []
        var codeElements = 0
        var elements = 0
        var i = 0
        while i < s.count {
            guard s[i] == "<" else {
                let end = s[i...].firstIndex(of: "<") ?? s.count
                let style = stack.last?.style ?? Style()
                if !style.skip {
                    for scalar in decodeEntities(s[i..<end]) { rich.scalars.append((scalar, style)) }
                }
                i = end
                continue
            }
            if s[i...].starts(with: "<!--".unicodeScalars) {
                i = (find("-->", in: s, from: i + 4).map { $0 + 3 }) ?? s.count
                continue
            }
            guard let close = tagEnd(in: s, from: i + 1) else { break }
            let tag = s[(i + 1)..<close]
            i = close + 1
            if tag.first == "!" || tag.first == "?" { continue }
            if tag.first == "/" {
                let name = tagName(tag.dropFirst())
                if let at = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(at...) }
                continue
            }
            let name = tagName(tag)
            guard !name.isEmpty else { continue }
            let parent = stack.last?.style ?? Style()
            if name == "br" {
                if !parent.skip { rich.scalars.append(("\n", Style())) }
                continue
            }
            if rawText.contains(name) {
                // Script and style bodies may contain `<`; skip to the end tag without parsing them. An icon's title names it
                // (`<svg><title>Copy</title></svg>`).
                let end = find("</" + name, in: s, from: i) ?? s.count
                if name == "title", let member = parent.member, rich.chrome[member].copy == false,
                   saysCopy(String(String.UnicodeScalarView(decodeEntities(s[i..<end])))) { rich.chrome[member].copy = true }
                i = s[end...].firstIndex(of: ">").map { $0 + 1 } ?? s.count
                continue
            }
            let attributes = attributes(of: tag)
            // An icon-only button says copy with its icon (`<svg aria-label="Copy">`, `<img alt="Copy">`, `<i class="fa-copy">`,
            // `<use href="#icon-copy">`).
            if let member = parent.member, rich.chrome[member].copy == false, saysCopy(attributes) { rich.chrome[member].copy = true }
            if void.contains(name) || tag.last == "/" { continue }
            guard stack.count < 512 else { return nil }
            var style = parent
            let classes = (attributes["class"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            let css = declarations(attributes["style"] ?? "")
            elements += 1
            if skipped.contains(name) || attributes["hidden"] != nil || css["display"] == "none" || css["visibility"] == "hidden" { style.skip = true }
            if !style.skip, name == "ul" || name == "ol" {
                let depth = parent.list.map { rich.lists[$0].depth + 1 } ?? 0
                style.list = rich.lists.count
                rich.lists.append(List(ordered: name == "ol", depth: depth, start: listNumber(attributes["start"]),
                                       reversed: attributes["reversed"] != nil))
            }
            if !style.skip, name == "li", let list = style.list {
                let item = rich.listItems.count
                rich.listItems.append(ListItem(list: list, value: listNumber(attributes["value"])))
                rich.lists[list].items.append(item)
                style.listItem = item
            }
            if headings.contains(name) { style.heading = true }
            let role = attributes["role"]?.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init)
            if !style.skip, let kind = chromeKind(name, role, attributes, classes, css, base: base) {
                let removable = switch kind {
                case .interactive: !parent.heading && attributes["aria-expanded"] == nil
                case .status, .hidden, .gutter: true
                case .decorative: false
                }
                let index = rich.chrome.count
                if style.chrome == nil { style.chrome = index }
                if removable, style.removable == nil { style.removable = index }
                // A button or tab not inside another one stands beside those of its tablist or toolbar, else of its parent.
                let bar = role == "tablist" || role == "toolbar"
                let member = kind == .interactive && !bar && parent.member == nil
                rich.chrome.append(Chrome(kind: kind, removable: removable, scope: stack.suffix(2).map(\.id), block: style.block, outer: parent.inner,
                                          group: member ? parent.bar ?? stack.last?.id ?? 0 : nil, selected: member && isSelected(attributes, classes),
                                          pressed: member ? pressed(attributes) : nil, tab: role == "tab" || parent.bar != nil,
                                          copy: role == "tab" ? nil : member && saysCopy(attributes)))
                style.inner = index
                if member { style.member = index }
                if bar { style.bar = elements }
            }
            if codeTags.contains(name), style.code == nil { codeElements += 1; style.code = codeElements }
            if name == "pre" {
                style.pre = true
                if style.block == nil, !style.skip {
                    let near = [classes] + stack.suffix(3).map(\.classes)
                    style.block = rich.blocks.count
                    rich.blocks.append(Block(language: language(attributes, classes), hint: hint(stack.suffix(6).map(\.classes)),
                                             signal: near.contains { !codeWidgetClasses.isDisjoint(with: $0) },
                                             inChrome: style.chrome != nil, ancestors: stack.suffix(4).map(\.id)))
                }
            }
            if name == "code" || name == "samp", let block = style.block, !style.blockCode {
                rich.blocks[block].hasCode = true
                rich.blocks[block].language = rich.blocks[block].language ?? language(attributes, classes)
                style.blockCode = true
            }
            if let css = attributes["style"], isMonospace(css) { style.mono = true }
            // A tab's href only shows its panel (`#tab-panel-0`, written out in full by Chrome): it is no link.
            if name == "a", role != "tab", style.link == nil, let href = attributes["href"], let url = safeURL(href, base: base) {
                style.link = rich.links.count
                rich.links.append(url)
            }
            stack.append((name, style, elements, classes))
        }
        for list in rich.lists where list.ordered {
            var number = list.start ?? (list.reversed ? list.items.count : 1)
            for item in list.items {
                number = rich.listItems[item].value ?? number
                rich.listItems[item].number = number
                number += list.reversed ? -1 : 1
            }
        }
        settle(&rich)
        return rich
    }

    /// Bound HTML counters before arithmetic and keep markers short enough to be ordinary text.
    private static func listNumber(_ value: String?) -> Int? {
        guard let value, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-999_999...999_999).contains(number) else { return nil }
        return number
    }

    /// What only the whole scan knows: which buttons side by side are a tab bar, caps on removable controls, and the
    /// block each gutter numbers. A copy button is a control wherever it is, never the tab on show or an option, though it
    /// counts among the buttons side by side. Tabs, or buttons of which exactly one is marked selected (`npm` beside `Copy`),
    /// are a tab bar; plain buttons side by side are the page's own options (a quiz), so text; a lone button stays a control,
    /// also one left beside a copy button (Run beside Copy). A gutter that is not digits beside a code block is ordinary
    /// text (`.no-gutters` layouts), so it is no control at all.
    private static func settle(_ rich: inout Rich) {
        // A bare `<pre><code>`, without a language or a highlighter, is code only when its lines look like code.
        var code = [String.UnicodeScalarView](repeating: String.UnicodeScalarView(), count: rich.blocks.count)
        var lastBlock: Int?
        for (scalar, style) in rich.scalars where style.chrome == nil {
            if let block = style.block, style.blockCode { code[block].append(scalar); lastBlock = block } else if scalar == "\n", let block = lastBlock { code[block].append(scalar) }
            if style.block == nil, scalar != "\n" { lastBlock = nil }
        }
        for index in rich.blocks.indices where rich.blocks[index].hasCode && !rich.blocks[index].signal && rich.blocks[index].tag == nil {
            rich.blocks[index].prose = !looksLikeCode(String(code[index]))
        }

        var texts = [String.UnicodeScalarView](repeating: String.UnicodeScalarView(), count: rich.chrome.count)
        var statuses = [String.UnicodeScalarView](repeating: String.UnicodeScalarView(), count: rich.chrome.count)
        for (scalar, style) in rich.scalars {
            if let member = style.member { texts[member].append(scalar) }
            var next = style.inner
            while let control = next {
                if rich.chrome[control].kind == .status { statuses[control].append(scalar) }
                next = rich.chrome[control].outer
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in rich.chrome.indices {
            if rich.chrome[index].copy == false, saysCopy(String(texts[index])) { rich.chrome[index].copy = true }
            if rich.chrome[index].kind == .status { rich.chrome[index].feedback = saysCopy(String(statuses[index])) }
            if let group = rich.chrome[index].group { groups[group, default: []].append(index) }
        }
        var options: Set<Int> = []
        for members in groups.values {
            let buttons = members.filter { rich.chrome[$0].copy != true }
            // A pressed toggle is the one on show only among toggles; beside a plain button (Wrap beside Run) it is a setting.
            let toggles = buttons.filter { rich.chrome[$0].pressed != nil }.count
            let selected = buttons.filter { rich.chrome[$0].selected || rich.chrome[$0].pressed == true && toggles > 1 }
            if buttons.contains(where: { rich.chrome[$0].tab }) || members.count > 1 && selected.count == 1 {
                if selected.count == 1 { rich.chrome[selected[0]].title = true }
            } else if buttons.count > 1 {
                options.formUnion(buttons)
            }
        }
        demote(options, in: &rich)

        var letters = [Int](repeating: 0, count: rich.chrome.count)
        var digits = [Bool](repeating: true, count: rich.chrome.count)
        for (scalar, style) in rich.scalars {
            guard let index = style.removable else { continue }
            if scalar == " " || scalar == "\t" { rich.chrome[index].trailingSpaces += 1; continue }
            rich.chrome[index].trailingSpaces = 0
            guard !ignorable(scalar) else { continue }
            letters[index] += 1
            if !("0"..."9").contains(scalar) { digits[index] = false }
        }
        var demoted: Set<Int> = []
        for index in rich.chrome.indices {
            let chrome = rich.chrome[index]
            switch chrome.kind {
            // A long button is content (a FAQ question); so is a long screen-reader paragraph.
            case .interactive where letters[index] > 40, .status where letters[index] > 80, .hidden where letters[index] > 80:
                rich.chrome[index].removable = false
            case .gutter:
                let block = chrome.block ?? rich.blocks.firstIndex { !$0.inChrome && $0.isCandidate && !Set($0.ancestors).isDisjoint(with: chrome.scope) }
                if letters[index] > 0, digits[index], let block { rich.chrome[index].block = block } else { demoted.insert(index) }
            default: break
            }
        }
        demote(demoted, in: &rich)
    }

    /// Text that reads as code rather than prose: a line with code punctuation or a command's shape (`{`, `ls -la`, `a = 1`,
    /// `f(x)`, `->`, a prompt or comment), or mostly lines that are no sentence (`npm install foo`, `make all`). A sentence has
    /// four words and one of them a function word, or is in a script without spaces between words.
    private static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return true }
        let punctuation = Set(".,!?'\"’“”()-:;".unicodeScalars)
        for line in lines {
            if codeShapes.contains(where: { line.range(of: $0, options: .regularExpression) != nil }) { return true }
            let symbols = line.unicodeScalars.filter { !$0.properties.isAlphabetic && !$0.properties.isWhitespace && !("0"..."9").contains($0) && !punctuation.contains($0) }.count
            if symbols * 10 > line.unicodeScalars.count * 3 { return true }
        }
        let sentences = lines.filter { line in
            let words = line.split(separator: " ").map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            return words.count >= 4 && words.contains(where: functionWords.contains)
                || line.unicodeScalars.filter({ $0.properties.isAlphabetic && !$0.isASCII }).count >= 10
        }.count
        return sentences * 2 < lines.count
    }

    private static let codeShapes = [
        "[{}]", ";$", "[A-Za-z_][A-Za-z0-9_.$]*\\((?!s\\))", "(^|\\s)--?[A-Za-z]", "[=!<>]=|=>|->|::|&&|\\|\\|",
        "(^|\\s)[A-Za-z_][A-Za-z0-9_.]*\\s*=\\s*\\S", "^(\\$ |#!|//|/\\*|# |>>> |<[A-Za-z/!])"
    ]

    private static let functionWords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "by", "for", "from", "with", "and", "or", "but", "if", "when", "then", "than",
        "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "you", "your", "we", "our", "they", "their", "i", "my",
        "he", "she", "not", "no", "can", "will", "would", "should", "do", "does", "did", "has", "have", "had", "as", "so", "what", "which"
    ]

    /// Controls that turned out to be text leave their letters to the controls inside and around them, if any.
    private static func demote(_ demoted: Set<Int>, in rich: inout Rich) {
        guard !demoted.isEmpty else { return }
        for index in rich.scalars.indices {
            var controls: [Int] = []
            var next = rich.scalars[index].style.inner
            while let control = next {
                controls.append(control)
                next = rich.chrome[control].outer
            }
            guard controls.contains(where: demoted.contains) else { continue }
            let kept = controls.filter { !demoted.contains($0) }
            rich.scalars[index].style.chrome = kept.last
            rich.scalars[index].style.removable = kept.last { rich.chrome[$0].removable }
        }
    }

    /// Marked as the tab or option on show: `aria-selected`, `aria-current`, `data-state=active`, `data-selected`, or a class
    /// `active`, `selected`, `current` or one ending in `-active`, `_active` or `-selected` (`is-active`, `tabs__item--active`),
    /// never `inactive` or `unselected`.
    private static func isSelected(_ attributes: [String: String], _ classes: [String]) -> Bool {
        func value(_ name: String, in values: Set<String>) -> Bool { attributes[name].map { values.contains($0.lowercased()) } == true }
        return value("aria-selected", in: ["true"]) || value("aria-current", in: ["true", "page"])
            || value("data-state", in: ["active"]) || value("data-selected", in: ["true"])
            || classes.contains { ["active", "selected", "current"].contains($0) || ["-active", "_active", "-selected"].contains(where: $0.hasSuffix) }
    }

    /// Says copy as a copy button's label does, case-insensitively: Latin that starts with copy or copied (`Copied!`, `Copy to
    /// clipboard`), Korean or Japanese that ends with one of `copyEndings` (`코드 복사`, `복사하기`, `복사 완료`, `コードをコピー`,
    /// `コピーしました`), or Material's copy icon, whose name is its text (`content_copy`). An option that mentions a copy
    /// (`A copy`, `Deep copy`, `복사본`), a file name (`copy.js`), an identifier (`copyWithin()`), `Copyright` and `copycat` do not.
    private static func saysCopy(_ label: String) -> Bool {
        let parts = words(label, name: false)
        return ["copy", "copied", "content_copy"].contains(parts.first ?? "") || copyEndings.contains { parts.suffix($0.count).elementsEqual($0) }
    }

    /// The last words of a Korean or Japanese copy label: the noun, and the forms a button takes before and after it copied.
    /// Words split where katakana meets other letters, so a Japanese verb ending after コピー is a word of its own.
    private static let copyEndings: [[String]] = [
        ["복사"], ["복사됨"], ["복사하기"], ["복사되었습니다"], ["복사됐습니다"], ["복사했습니다"], ["복사", "완료"],
        ["コピー"], ["コピー", "する"], ["コピー", "しました"], ["コピー", "済み"], ["コピー", "完了"]
    ]

    /// An element's attributes say copy, the button's own or its icon's: by a word of its class, a `data-*` name or an icon sprite's
    /// fragment (`js-clipboard-copy`, `copyButton`, `fa-copy`, `data-clipboard-text`, `#icon-copy`), or by its `aria-label`, `title`,
    /// `alt` or `data-*` tooltip (`data-tooltip`, `data-bs-original-title`) as a label. Other `data-*` values are the page's own
    /// data (`data-code`).
    private static func saysCopy(_ attributes: [String: String]) -> Bool {
        let sprite = String((attributes["href"] ?? attributes["xlink:href"] ?? "").drop { $0 != "#" })
        let names = attributes.keys.filter { $0.hasPrefix("data-") } + [attributes["class"] ?? "", sprite]
        let labels = attributes.filter { key, _ in
            ["aria-label", "title", "alt"].contains(key) || key.hasPrefix("data-") && words(key, name: true).contains { ["tooltip", "title", "tippy"].contains($0) }
        }.values
        return names.contains { words($0, name: true).contains { ["copy", "copied", "clipboard"].contains($0) } } || labels.contains(where: saysCopy)
    }

    /// Lowercased words, split where katakana meets other letters (`コードをコピー`). A name splits at anything but letters and
    /// where a lowercase letter meets an uppercase one (`copyButton`); a label only at spaces and punctuation, so a file name or an
    /// identifier stays one word (`copy.js`, `deep_copy.py`, `CopyButton.tsx`), and `Copied.` is `copied`.
    private static func words(_ text: String, name: Bool) -> [String] {
        func katakana(_ scalar: Unicode.Scalar) -> Bool { (0x30A0...0x30FF).contains(scalar.value) }
        var spaced = String.UnicodeScalarView()
        var last: Unicode.Scalar = " "
        for scalar in text.unicodeScalars {
            if name && last.properties.isLowercase && scalar.properties.isUppercase || katakana(last) != katakana(scalar) { spaced.append(" ") }
            let joins = !name && (("0"..."9").contains(scalar) || "._-".unicodeScalars.contains(scalar))
            spaced.append(scalar.properties.isAlphabetic || joins ? scalar : " ")
            last = scalar
        }
        return String(spaced).lowercased().split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "._-")) }.filter { !$0.isEmpty }
    }

    /// A toggle's state, by `aria-pressed` or by `data-state` on or off; nil for no toggle.
    private static func pressed(_ attributes: [String: String]) -> Bool? {
        if let pressed = attributes["aria-pressed"] { return pressed.lowercased() == "true" }
        return switch attributes["data-state"]?.lowercased() {
        case "on": true
        case "off": false
        default: nil
        }
    }

    private static func chromeKind(_ name: String, _ role: String?, _ attributes: [String: String], _ classes: [String], _ css: [String: String], base: URL?) -> ChromeKind? {
        // A link styled as a button, such as a call to action in prose, is still a link. A tab is a control even as a link:
        // Chrome writes its in-page href out in full (Starlight, Bootstrap's nav tabs), and so is a button or switch whose href
        // only points into the page it is on.
        let href = name == "a" ? attributes["href"].flatMap { safeURL($0, base: base) } : nil
        let inPage = href.map { url in base.map { sameDocument(url, $0) } == true } == true
        if name == "button" || role == "tab" || role.map({ interactiveRoles.contains($0) }) == true && (href == nil || inPage) { return .interactive }
        // A clipped status is hidden text; a visible one may be the page's own message.
        if isVisuallyHidden(classes, css) { return .hidden }
        if role == "status" { return .status }
        if classes.contains(where: { gutterClasses.contains($0) }) { return .gutter }
        if attributes["aria-hidden"] == "true" || css["user-select"] == "none" || css["-webkit-user-select"] == "none" { return .decorative }
        return nil
    }

    /// A fragment of the page itself (`https://docs.example.com/install/#tab-panel-0` on `https://docs.example.com/install/`).
    private static func sameDocument(_ url: URL, _ page: URL) -> Bool {
        func document(_ url: URL) -> String { url.absoluteString.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
        return url.fragment != nil && document(url) == document(page)
    }

    /// Clipped to nothing, as `sr-only` and `visually-hidden` utilities do. Chrome writes the computed clip into the
    /// copied HTML, so a class name alone never counts, and utilities that show the text again (`md:not-sr-only`,
    /// `visually-hidden-focusable`) never do.
    private static func isVisuallyHidden(_ classes: [String], _ css: [String: String]) -> Bool {
        guard !classes.contains(where: { $0.contains("not-sr-only") || $0.hasSuffix("-focusable") }) else { return false }
        let clipPath = css["clip-path"] ?? ""
        return clipPath.hasPrefix("inset(50%)") || clipPath.hasPrefix("inset(100%)") || clipsToNothing(css["clip"] ?? "")
            || css["width"] == "1px" && css["height"] == "1px" && css["overflow"] == "hidden"
    }

    /// `rect()` whose four edges are each 0 or 1px, as screen-reader utilities write it. Any other rectangle is a
    /// crop that shows text (`rect(0px, 240px, 30px, 0px)`).
    private static func clipsToNothing(_ clip: String) -> Bool {
        guard clip.hasPrefix("rect("), clip.hasSuffix(")") else { return false }
        let edges = clip.dropFirst(5).dropLast().split { $0 == "," || $0 == " " }
        return edges.count == 4 && edges.allSatisfy { ["0", "0px", "1px"].contains($0) }
    }

    /// Inline style declarations, lowercased, each run of whitespace one space: `clip: rect(1px,  1px)` reads `clip` → `rect(1px, 1px)`.
    private static func declarations(_ css: String) -> [String: String] {
        var result: [String: String] = [:]
        for declaration in css.lowercased().split(separator: ";") {
            guard let colon = declaration.firstIndex(of: ":") else { continue }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            result[property] = declaration[declaration.index(after: colon)...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return result
    }

    /// The language a highlighter named on one element: `data-language`, `language-x`, `lang-x`, `brush: x`,
    /// pandoc's `sourceCode x`, `highlight-source-x`, `hljs x`, or a `lang` attribute that is no human language.
    private static func language(_ attributes: [String: String], _ classes: [String]) -> String? {
        var names = [attributes["data-language"], attributes["data-lang"]].compactMap { $0 }
        for (index, token) in classes.enumerated() {
            if let prefix = ["language-", "lang-", "highlight-source-"].first(where: { token.hasPrefix($0) }) {
                names.append(String(token.dropFirst(prefix.count)))
            } else if token == "brush:" || token == "sourcecode", index + 1 < classes.count {
                names.append(classes[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: ";")))
            } else if token.hasPrefix("brush:") {
                names.append(String(token.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: ";")))
            }
        }
        if classes.contains("hljs") { names += classes.filter { TranslationMarkup.knownLanguageTags.contains($0) } }
        // cs, pl, ts and sh are also ISO 639-1 codes.
        if let lang = attributes["lang"]?.lowercased(), !["cs", "pl", "ts", "sh"].contains(lang), TranslationMarkup.knownLanguageTags.contains(lang) {
            names.append(lang)
        }
        return names.lazy.compactMap(fenceTag).first
    }

    /// A language a highlighter's wrapper names (`language-x`, `lang-x`, GitHub's `highlight-source-x`, Sphinx's
    /// `highlight-x`), nearest first. Wrappers carry other words too, so only recognized tags count.
    private static func hint(_ ancestors: [[String]]) -> String? {
        for classes in ancestors.reversed() {
            for token in classes {
                guard let prefix = ["language-", "lang-", "highlight-source-", "highlight-"].first(where: { token.hasPrefix($0) }) else { continue }
                let name = String(token.dropFirst(prefix.count))
                if TranslationMarkup.knownLanguageTags.contains(name), let tag = fenceTag(name) { return tag }
            }
        }
        return nil
    }

    /// The fence tag for a language name: lowercase, at most 24 of `[a-z0-9_+#.-]`, and read as a tag at once
    /// (`TranslationMarkup.isFenceLanguage`). Anything else, a command like `ls` included, gives a bare fence.
    private static func fenceTag(_ name: String) -> String? {
        let tag = name.lowercased()
        guard (1...24).contains(tag.unicodeScalars.count),
              tag.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || "_+#.-".unicodeScalars.contains($0) }),
              TranslationMarkup.isFenceLanguage(tag) else { return nil }
        return tag
    }

    /// The `>` that ends a tag. A `>` inside a quoted attribute value belongs to the value, as in browsers.
    private static func tagEnd(in s: [Unicode.Scalar], from start: Int) -> Int? {
        var quote: Unicode.Scalar?
        for index in start..<s.count {
            let scalar = s[index]
            if let open = quote {
                if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                // Only a quote that starts an attribute value opens one (`title="…"`), not one inside a name.
                if index > start, s[index - 1] == "=" || CharacterSet.whitespaces.contains(s[index - 1]) { quote = scalar }
            } else if scalar == ">" {
                return index
            }
        }
        return nil
    }

    private static func tagName(_ tag: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(tag.prefix { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "/" })).lowercased()
    }

    /// ASCII case-insensitive search.
    private static func find(_ needle: String, in s: [Unicode.Scalar], from start: Int) -> Int? {
        let n = Array(needle.lowercased().unicodeScalars)
        guard !n.isEmpty, start >= 0, start <= s.count - n.count else { return nil }
        return (start...(s.count - n.count)).first { at in
            n.indices.allSatisfy { lowercased(s[at + $0]) == n[$0] }
        }
    }

    private static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar
    }

    /// Attribute names lowercased; values entity-decoded. Later duplicates are ignored, as in browsers.
    private static func attributes(of tag: ArraySlice<Unicode.Scalar>) -> [String: String] {
        var result: [String: String] = [:]
        let isSpace = { (scalar: Unicode.Scalar) in CharacterSet.whitespacesAndNewlines.contains(scalar) }
        var i = tag.startIndex
        while i < tag.endIndex, !isSpace(tag[i]) { i += 1 }
        while i < tag.endIndex {
            while i < tag.endIndex, isSpace(tag[i]) || tag[i] == "/" { i += 1 }
            let nameStart = i
            while i < tag.endIndex, !isSpace(tag[i]), tag[i] != "=", tag[i] != "/" { i += 1 }
            let name = String(String.UnicodeScalarView(tag[nameStart..<i])).lowercased()
            while i < tag.endIndex, isSpace(tag[i]) { i += 1 }
            var value = ""
            if i < tag.endIndex, tag[i] == "=" {
                i += 1
                while i < tag.endIndex, isSpace(tag[i]) { i += 1 }
                if i < tag.endIndex, tag[i] == "\"" || tag[i] == "'" {
                    let quote = tag[i]
                    let end = tag[(i + 1)...].firstIndex(of: quote) ?? tag.endIndex
                    value = String(String.UnicodeScalarView(decodeEntities(tag[(i + 1)..<end])))
                    i = min(end + 1, tag.endIndex)
                } else {
                    let start = i
                    while i < tag.endIndex, !isSpace(tag[i]) { i += 1 }
                    value = String(String.UnicodeScalarView(decodeEntities(tag[start..<i])))
                }
            }
            if !name.isEmpty, result[name] == nil { result[name] = value }
        }
        return result
    }

    private static func isMonospace(_ css: String) -> Bool {
        guard let range = css.range(of: "font-family", options: .caseInsensitive) else { return false }
        let value = css[range.upperBound...].drop { $0 == ":" || $0.isWhitespace }.prefix { $0 != ";" }
        let first = value.split(separator: ",").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).lowercased() } ?? ""
        return ["monospace", "mono", "courier", "consolas", "inconsolata", "menlo", "monaco", "source code"].contains { first.contains($0) }
    }

    /// Cleaned as browsers do before the policy check: spaces and controls around it go, controls inside it
    /// go (so `java\nscript:` cannot slip through), and a space inside it is percent-encoded, not dropped.
    private static func safeURL(_ href: String, base: URL?) -> URL? {
        let trimmed = href.unicodeScalars.drop { $0.value <= 0x20 }.reversed().drop { $0.value <= 0x20 }.reversed()
        let cleaned = String(String.UnicodeScalarView(trimmed.filter { $0.value >= 0x20 && $0.value != 0x7F }))
            .replacingOccurrences(of: " ", with: "%20")
        guard !cleaned.isEmpty, !cleaned.hasPrefix("#"), let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
              SourceLink.isAllowed(url) else { return nil }
        return url
    }

    private static let entities: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]

    private static func decodeEntities(_ s: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i..<min(s.endIndex, i + 12)].firstIndex(of: ";") {
                let name = String(String.UnicodeScalarView(s[(i + 1)..<semi]))
                var decoded: [Unicode.Scalar]?
                if let named = entities[name] { decoded = Array(named.unicodeScalars) }
                else if name.hasPrefix("#x") || name.hasPrefix("#X") { decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { [$0] } }
                else if name.hasPrefix("#") { decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { [$0] } }
                if let decoded { out += decoded; i = semi + 1; continue }
            }
            out.append(s[i])
            i += 1
        }
        return out
    }

    // MARK: - Alignment

    private static func ignorable(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar) || [0x00A0, 0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF].contains(scalar.value)
    }

    private static func folded(_ scalar: Unicode.Scalar) -> String { scalar.properties.lowercaseMapping }

    private typealias Item = (scalar: Unicode.Scalar, style: Style)

    private enum Owner: Equatable { case unmatched, content(Int), chrome(Int) }

    private struct Alignment {
        /// For each plain key, the rich item it matched.
        var owner: [Owner]
        /// For each rich item, the plain key it matched.
        var mapped: [Int?]
    }

    /// Greedy alignment of the rich items' letters with the plain keys. A content match after skipped plain keys
    /// (list markers) must be confirmed by the next few content letters, so text that exists only in the HTML
    /// cannot pull the alignment forward; HTML that does not describe this text stops as soon as it is clearly off.
    /// A page control's text matches as a whole where the plain text has it and costs nothing where it does not
    /// (an unselectable prompt, an icon button's label).
    private static func align(_ items: [Item], _ pk: [String], report: inout Report) -> Alignment? {
        let rk = items.map { folded($0.scalar) }
        // The last item of each control's run of letters.
        var runEnd = Array(items.indices)
        for r in items.indices.reversed() where r + 1 < items.count {
            if let chrome = items[r].style.chrome, items[r + 1].style.chrome == chrome { runEnd[r] = runEnd[r + 1] }
        }
        func runMatches(_ r: Int, at k: Int) -> Bool {
            let length = runEnd[r] - r + 1
            return k + length <= pk.count && (0..<length).allSatisfy { rk[r + $0] == pk[k + $0] }
        }
        // The next three content letters follow plain key `k`, past controls the plain text has or lacks.
        func confirms(_ r: Int, at k: Int) -> Bool {
            var x = r + 1, y = k + 1, compared = 0
            while compared < 3, x < items.count, y < pk.count {
                if items[x].style.chrome != nil {
                    if runMatches(x, at: y) { y += runEnd[x] - x + 1 }
                    x = runEnd[x] + 1
                    continue
                }
                guard rk[x] == pk[y] else { return false }
                x += 1
                y += 1
                compared += 1
            }
            return true
        }
        func matches(_ r: Int, at k: Int) -> Bool { k < pk.count && rk[r] == pk[k] && confirms(r, at: k) }
        // The first content item at or after each index, so a run of controls finds what follows it at once.
        var nextContent = [Int?](repeating: nil, count: items.count + 1)
        for r in items.indices.reversed() { nextContent[r] = items[r].style.chrome == nil ? r : nextContent[r + 1] }

        let budget = max(4, (items.filter { $0.style.chrome == nil }.count + pk.count) * 3 / 200)
        var alignment = Alignment(owner: Array(repeating: .unmatched, count: pk.count), mapped: Array(repeating: nil, count: items.count))
        var misses = 0
        var j = 0
        var r = 0
        while r < items.count {
            guard items[r].style.chrome == nil else {
                let end = runEnd[r], length = end - r + 1
                // Text that starts like the control is content when only the content fits there, and not after the
                // control and the controls between them that the plain text has (a tab named like the code below it).
                // Only a control the plain text has here needs the look ahead.
                func startsContent() -> Bool {
                    guard let next = nextContent[end + 1] else { return false }
                    var x = end + 1, y = j + length
                    while x < next {
                        if runMatches(x, at: y) { y += runEnd[x] - x + 1 }
                        x = runEnd[x] + 1
                    }
                    return matches(next, at: j) && !matches(next, at: y)
                }
                if runMatches(r, at: j), !startsContent() {
                    for offset in 0..<length {
                        alignment.mapped[r + offset] = j + offset
                        alignment.owner[j + offset] = .chrome(r + offset)
                    }
                    j += length
                    report.chromeMatched += 1
                } else {
                    report.chromeSkipped += 1
                }
                r = end + 1
                continue
            }
            var found: Int?
            for k in j..<min(pk.count, j + 65) where pk[k] == rk[r] {
                if k == j || confirms(r, at: k) { found = k; break }
            }
            if let k = found {
                misses += k - j
                alignment.mapped[r] = k
                alignment.owner[k] = .content(r)
                j = k + 1
            } else {
                misses += 1
            }
            if misses > budget { break }
            r += 1
        }
        misses += pk.count - j
        report.misses = misses
        report.budget = budget
        return misses <= budget ? alignment : nil
    }

    // MARK: - Lines, cleaning and code blocks

    /// The plain text line by line, with what each key matched.
    private struct Projection {
        let rich: Rich
        let items: [Item]
        let p: [Unicode.Scalar]
        /// Scalar index of each key: each scalar that is not ignorable.
        let keys: [Int]
        let owner: [Owner]
        /// Each line's scalars without its "\n", and the keys on it.
        let lines: [Range<Int>]
        let lineKeys: [Range<Int>]

        /// The block whose code a key is: content of its `<pre>`, inside `<code>` when the `<pre>` has one.
        func block(of key: Int) -> Int? {
            guard case .content(let r) = owner[key], let block = items[r].style.block, rich.blocks[block].isCandidate,
                  !rich.blocks[block].hasCode || items[r].style.blockCode else { return nil }
            return block
        }

        func isChrome(_ key: Int) -> Bool {
            if case .chrome = owner[key] { true } else { false }
        }

        /// The removable control a key belongs to; buttons and tabs only `nearCode`, gutters only beside their block.
        func removable(_ key: Int, nearCode: Bool, accepted: Set<Int>) -> Int? {
            guard case .chrome(let r) = owner[key], let index = items[r].style.removable, rich.chrome[index].removable else { return nil }
            switch rich.chrome[index].kind {
            case .hidden: return index
            case .status: return nearCode || rich.chrome[index].feedback ? index : nil
            case .interactive: return nearCode ? index : nil
            case .gutter: return rich.chrome[index].block.map { accepted.contains($0) } == true ? index : nil
            case .decorative: return nil
            }
        }

        func holdsOnlyControls(_ line: Int, nearCode: Bool, accepted: Set<Int>) -> Bool {
            !lineKeys[line].isEmpty && lineKeys[line].allSatisfy { removable($0, nearCode: nearCode, accepted: accepted) != nil }
        }

        /// The selected tab whose label a key is, when its tab bar may title a block; text of controls inside the tab is no label.
        func title(of key: Int) -> Int? {
            guard key >= 0, key < owner.count, case .chrome(let r) = owner[key], let member = items[r].style.member,
                  items[r].style.inner == member, rich.chrome[member].title else { return nil }
            return member
        }

        /// The language a chat or docs page writes above its code inside the same `<pre>`, possibly beside a copy button.
        func isLabel(_ line: Int, of block: Int, accepted: Set<Int>) -> Bool {
            guard let language = rich.blocks[block].tag, rich.blocks[block].hasCode else { return false }
            var label = ""
            for key in lineKeys[line] {
                if case .content(let r) = owner[key], items[r].style.block == block, !items[r].style.blockCode {
                    label.unicodeScalars.append(p[keys[key]])
                } else if removable(key, nearCode: true, accepted: accepted) == nil {
                    return false
                }
            }
            let names = RichSourceImporter.languageAliases.first { $0.contains(language) } ?? [language]
            return names.contains(label.lowercased())
        }
    }

    private static let languageAliases: [Set<String>] = [["js", "javascript"], ["ts", "typescript"], ["py", "python"], ["sh", "bash", "shell", "console"]]

    /// List markers are added only to lines whose letters all belong to one selected HTML item. The first
    /// letter of that item must be present: a copy starting halfway through it stays a partial paragraph.
    /// Existing plain-text markers remain untouched, including the page's choice of bullet and delimiter.
    private static func listPrefixes(_ copy: Projection, alignment: Alignment, cleaning: inout Cleaning,
                                     accepted: [(block: Int, lines: ClosedRange<Int>)]) -> [Int: String] {
        guard !copy.rich.listItems.isEmpty else { return [:] }
        let codeLines = Set(accepted.flatMap { Array($0.lines) })
        var firstContent: [Int: Int] = [:]
        for r in copy.items.indices where copy.items[r].style.chrome == nil {
            if let item = copy.items[r].style.listItem { firstContent[item] = firstContent[item] ?? r }
        }
        var firstLine: [Int: Int] = [:]
        var candidates: [(line: Int, item: Int, content: Int)] = []
        for line in copy.lines.indices where !cleaning.removed[line] && !codeLines.contains(line) {
            let range = cleaning.cuts[line] ?? copy.lines[line]
            let keys = copy.lineKeys[line].filter { range.contains(copy.keys[$0]) }
            let content = keys.compactMap { key -> (key: Int, rich: Int, item: Int)? in
                guard case .content(let r) = copy.owner[key], let item = copy.items[r].style.listItem,
                      !copy.items[r].style.pre else { return nil }
                return (key, r, item)
            }
            guard let first = content.first, content.allSatisfy({ $0.item == first.item }),
                  keys.allSatisfy({ key in
                      if copy.keys[key] < copy.keys[first.key] { return true }
                      if case .content(let r) = copy.owner[key] { return copy.items[r].style.listItem == first.item }
                      return false
                  }),
                  let start = firstContent[first.item], alignment.mapped[start] != nil else { continue }
            let leading = copy.p[range.lowerBound..<copy.keys[first.key]]
            // An unmatched prefix may only be the marker already supplied by the browser. Never decorate a
            // line that begins with unrelated copied text, controls, or content from another item.
            let prefix = String(String.UnicodeScalarView(leading))
            guard leading.allSatisfy({ $0 == " " || $0 == "\t" }) || listMarker(prefix) != nil else { continue }
            firstLine[first.item] = firstLine[first.item] ?? line
            candidates.append((line, first.item, copy.keys[first.key]))
        }
        let marked = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate -> (Int, String)? in
            guard firstLine[candidate.item] == candidate.line else { return nil }
            let range = cleaning.cuts[candidate.line] ?? copy.lines[candidate.line]
            return listMarker(String(String.UnicodeScalarView(copy.p[range]))).map { (candidate.item, $0) }
        })
        let minimumDepth = candidates.map { copy.rich.lists[copy.rich.listItems[$0.item].list].depth }.min() ?? 0
        var prefixes: [Int: String] = [:]
        for (line, item, content) in candidates {
            let range = cleaning.cuts[line] ?? copy.lines[line]
            let original = String(String.UnicodeScalarView(copy.p[range]))
            // A marker already on this line stays verbatim. In particular a literal list-looking continuation
            // must never receive a second bullet just because it sits inside an HTML item.
            if listMarker(original) != nil { continue }
            let entry = copy.rich.listItems[item]
            let list = copy.rich.lists[entry.list]
            let marker = entry.number.map { "\($0). " } ?? "- "
            let indent = String(repeating: " ", count: min(list.depth - minimumDepth, 32) * 2)
            let first = firstLine[item] == line && firstContent[item].flatMap { alignment.mapped[$0] }.map { copy.keys[$0] == content } == true
            if let existing = marked[item] {
                prefixes[line] = String(repeating: " ", count: existing.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) })
            } else {
                prefixes[line] = indent + (first ? marker : String(repeating: " ", count: marker.count))
            }
            // HTML owns the indentation here. Whitespace copied before a missing marker must precede the
            // marker, rather than becoming extra spaces between the marker and the item's first word.
            cleaning.cuts[line] = content..<range.upperBound
        }
        return prefixes
    }

    private static func listMarker(_ text: String) -> String? {
        let pattern = #"^[ \t]*(?:[-+*•◦▪][ \t]+|[+-]?[0-9]+[.)][ \t]+)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    /// `<pre>` blocks whose code fills whole plain lines with nothing else but controls on them, in order.
    /// Keys the HTML does not have (Slack's backticks) or other text on those lines leave a block unfenced.
    private static func acceptedBlocks(_ copy: Projection, report: inout Report) -> [(block: Int, lines: ClosedRange<Int>)] {
        var first: [Int: Int] = [:], last: [Int: Int] = [:]
        for (line, keys) in copy.lineKeys.enumerated() {
            for key in keys {
                guard let block = copy.block(of: key) else { continue }
                first[block] = first[block] ?? line
                last[block] = line
            }
        }
        var accepted: [(block: Int, lines: ClosedRange<Int>)] = []
        for block in copy.rich.blocks.indices where copy.rich.blocks[block].isCandidate {
            let reason: String
            if let lo = first[block], let hi = last[block] {
                if (lo...hi).contains(where: { copy.lineKeys[$0].contains { copy.block(of: $0) != block && !copy.isChrome($0) } }) {
                    reason = "shares its lines"
                } else if accepted.count >= maxCodeBlocks {
                    reason = "over the block limit"
                } else {
                    accepted.append((block, lo...hi))
                    reason = "fenced"
                }
            } else {
                reason = "not in the copy"
            }
            report.blocks.append(Report.Block(language: copy.rich.blocks[block].tag, accepted: reason == "fenced", reason: reason))
        }
        return accepted
    }

    private struct Cleaning {
        var removed: [Bool]
        /// The scalars a code line keeps once controls at its edges are cut.
        var cuts: [Int: Range<Int>] = [:]
        /// Blocks whose lines keep a copy button or line numbers because cleaning was given up; their text is not the page's code.
        var unclean: Set<Int> = []
        /// Blocks the selected tabs right above them title: the lines that keep the tabs' labels, in order, and the title.
        var titles: [Int: (lines: [Int], title: String)] = [:]
    }

    /// Removes lines that hold only page controls: buttons, tabs and statuses next to an accepted block, a block's gutter
    /// lines, and screen-reader text or copy feedback anywhere; a language label inside the block's `<pre>` goes too.
    /// Code lines lose controls at their edges (an inline copy button, line numbers). Too much removal keeps the
    /// text as copied.
    private static func clean(_ copy: Projection, accepted: [(block: Int, lines: ClosedRange<Int>)], report: inout Report) -> Cleaning {
        let lines = copy.lines, p = copy.p
        let blocks = Set(accepted.map(\.block))
        var inBlock = [Bool](repeating: false, count: lines.count)
        for (_, range) in accepted { for line in range { inBlock[line] = true } }
        var cleaning = Cleaning(removed: Array(repeating: false, count: lines.count))
        var labels = 0
        for (block, range) in accepted {
            for step in [-1, 1] {
                var line = step < 0 ? range.lowerBound - 1 : range.upperBound + 1
                while lines.indices.contains(line), !inBlock[line] {
                    if !copy.lineKeys[line].isEmpty, !cleaning.removed[line] {
                        if copy.holdsOnlyControls(line, nearCode: true, accepted: blocks) {
                            cleaning.removed[line] = true
                        } else if step < 0, copy.isLabel(line, of: block, accepted: blocks) {
                            cleaning.removed[line] = true
                            labels += 1
                        } else {
                            break
                        }
                    }
                    line += step
                }
            }
            for line in range {
                let keys = copy.lineKeys[line]
                var lead = keys.lowerBound, trail = keys.upperBound
                while lead < trail, copy.removable(lead, nearCode: true, accepted: blocks) != nil { lead += 1 }
                while trail > lead, copy.removable(trail - 1, nearCode: true, accepted: blocks) != nil { trail -= 1 }
                var start = lines[line].lowerBound, end = lines[line].upperBound
                if lead > keys.lowerBound {
                    // Through the control's own trailing spaces (a padded line number) and a table cell's tab.
                    start = copy.keys[lead - 1] + 1
                    var spaces = copy.removable(lead - 1, nearCode: true, accepted: blocks).map { copy.rich.chrome[$0].trailingSpaces } ?? 0
                    while spaces > 0, start < end, p[start] == " " || p[start] == "\t" { start += 1; spaces -= 1 }
                    if start < end, p[start] == "\t" { start += 1 }
                }
                if trail < keys.upperBound {
                    end = copy.keys[trail]
                    while end > start, p[end - 1] == " " || p[end - 1] == "\t" { end -= 1 }
                }
                if start != lines[line].lowerBound || end != lines[line].upperBound { cleaning.cuts[line] = start..<end }
            }
        }
        for line in lines.indices where !inBlock[line] && !cleaning.removed[line] && copy.holdsOnlyControls(line, nearCode: false, accepted: blocks) {
            cleaning.removed[line] = true
        }

        // The selected tab of each tab bar right above a block names its code, as on the page: its label stays, alone on
        // its line, and the block's opener carries the labels joined. A label on several lines, or a title the opener cannot
        // carry, goes with the other tabs.
        for (block, range) in accepted {
            var labels: [(line: Int, keys: ClosedRange<Int>)] = []
            var line = range.lowerBound - 1
            while line >= 0, cleaning.removed[line] {
                let found = copy.lineKeys[line].filter { copy.title(of: $0) != nil }
                if let first = found.first, let last = found.last {
                    let tab = copy.title(of: first)
                    guard found.count == last - first + 1, found.allSatisfy({ copy.title(of: $0) == tab }),
                          copy.title(of: first - 1) != tab, copy.title(of: last + 1) != tab else { labels = []; break }
                    labels.insert((line, first...last), at: 0)
                }
                line -= 1
            }
            // Right below another block, the farther tab bars may be that block's own below it: only the nearest is surely this one's.
            if line >= 0, inBlock[line] { labels = Array(labels.suffix(1)) }
            let label = { (keys: ClosedRange<Int>) in String(String.UnicodeScalarView(p[copy.keys[keys.lowerBound]...copy.keys[keys.upperBound]])) }
            guard !labels.isEmpty, let title = SourceCodeBlock.title(labels.map { label($0.keys) }.joined(separator: " · ")) else { continue }
            for (line, keys) in labels {
                cleaning.removed[line] = false
                let kept = copy.keys[keys.lowerBound]..<(copy.keys[keys.upperBound] + 1)
                if kept != lines[line] { cleaning.cuts[line] = kept }
            }
            cleaning.titles[block] = (labels.map(\.line), title)
        }
        let removedLines = cleaning.removed.filter { $0 }.count

        // A removed run between blank lines takes one of them; at either end of the text it takes the blank lines there.
        func blank(_ line: Int) -> Bool { copy.lineKeys[line].isEmpty && !inBlock[line] && !cleaning.removed[line] }
        var line = 0
        while line < lines.count {
            guard cleaning.removed[line] else { line += 1; continue }
            var end = line
            while end + 1 < lines.count, cleaning.removed[end + 1] { end += 1 }
            if line == 0 {
                while end + 1 < lines.count, blank(end + 1) { end += 1; cleaning.removed[end] = true }
            } else if end == lines.count - 1 {
                var previous = line - 1
                while previous >= 0, blank(previous) { cleaning.removed[previous] = true; previous -= 1 }
            } else if blank(line - 1), blank(end + 1) {
                end += 1
                cleaning.removed[end] = true
            }
            line = end + 1
        }

        // Line numbers grow with the code and only ever number an accepted block, so they count against neither cap.
        func isGutter(_ key: Int) -> Bool {
            guard case .chrome(let r) = copy.owner[key], let index = copy.items[r].style.removable else { return false }
            return copy.rich.chrome[index].kind == .gutter
        }
        var removedGutters = 0, removedOthers = 0
        for (line, keys) in copy.lineKeys.enumerated() {
            let kept = cleaning.removed[line] ? 0..<0 : cleaning.cuts[line] ?? lines[line]
            for key in keys where !kept.contains(copy.keys[key]) {
                if isGutter(key) { removedGutters += 1 } else { removedOthers += 1 }
            }
        }
        let keepsText = lines.indices.contains { line in
            !cleaning.removed[line] && (cleaning.cuts[line] ?? lines[line]).contains { !ignorable(p[$0]) }
        }
        if removedOthers * 2 > copy.keys.count - removedGutters || removedOthers > maxRemovedKeys || !keepsText {
            report.cleaningAbandoned = removedGutters + removedOthers > 0
            let unclean = accepted.filter { $0.lines.contains { cleaning.cuts[$0] != nil } }.map(\.block)
            return Cleaning(removed: Array(repeating: false, count: lines.count), unclean: Set(unclean))
        }
        report.removedLines = removedLines
        report.labelLines = labels
        return cleaning
    }

    // MARK: - Projection onto the plain text

    private struct Span {
        enum Kind: Equatable { case code, link(URL) }
        let kind: Kind
        /// Indices into the cleaned scalars, inclusive.
        let first: Int
        let last: Int
    }

    private static func project(_ rich: Rich, onto plain: String, report: inout Report) -> CapturedSource? {
        let p = Array(plain.unicodeScalars)
        let keys = p.indices.filter { !ignorable(p[$0]) }
        let items = rich.scalars.filter { !ignorable($0.scalar) }
        guard items.contains(where: { $0.style.chrome == nil }), !keys.isEmpty else {
            report.fallback = "no text to match"
            return nil
        }
        guard let alignment = align(items, keys.map { folded(p[$0]) }, report: &report) else {
            report.fallback = "html does not match"
            return nil
        }
        var lines: [Range<Int>] = [], lineKeys: [Range<Int>] = []
        var lineStart = 0, nextKey = 0
        for index in 0...p.count where index == p.count || p[index] == "\n" {
            let firstKey = nextKey
            while nextKey < keys.count, keys[nextKey] < index { nextKey += 1 }
            lines.append(lineStart..<index)
            lineKeys.append(firstKey..<nextKey)
            lineStart = index + 1
        }
        let copy = Projection(rich: rich, items: items, p: p, keys: keys, owner: alignment.owner, lines: lines, lineKeys: lineKeys)
        let accepted = acceptedBlocks(copy, report: &report)
        var cleaning = clean(copy, accepted: accepted, report: &report)
        let prefixes = listPrefixes(copy, alignment: alignment, cleaning: &cleaning, accepted: accepted)

        // The cleaned text: kept lines, cut at their edges, joined again.
        var c: [Unicode.Scalar] = []
        var toCleaned = [Int?](repeating: nil, count: p.count)
        var cleanedLines: [Range<Int>] = []
        var cleanedLine = [Int?](repeating: nil, count: lines.count)
        for (line, range) in lines.enumerated() where !cleaning.removed[line] {
            if !cleanedLines.isEmpty { c.append("\n") }
            let start = c.count
            c.append(contentsOf: (prefixes[line] ?? "").unicodeScalars)
            for index in cleaning.cuts[line] ?? range {
                toCleaned[index] = c.count
                c.append(p[index])
            }
            cleanedLine[line] = cleanedLines.count
            cleanedLines.append(start..<c.count)
        }
        let cleaned = String(String.UnicodeScalarView(c))
        let removed = removedRanges(p, lines: lines, cleaning: cleaning)

        // Code blocks, unless the text already writes its own fences (Notion, Slack and chat copies).
        let text = { (range: Range<Int>) in String(String.UnicodeScalarView(c[range])) }
        for block in cleaning.unclean {
            let entry = rich.blocks[..<block].filter(\.isCandidate).count
            report.blocks[entry].accepted = false
            report.blocks[entry].reason = "keeps page controls"
        }
        // A block's title lines are right above its code: every line between them was removed.
        var fencing = accepted.filter { block, range in
            !cleaning.unclean.contains(block) && cleanedLine[range.lowerBound] != nil && cleanedLine[range.upperBound] != nil
        }
        var blocks: [(lines: ClosedRange<Int>, title: Range<Int>, block: SourceCodeBlock)] = fencing.map { block, range in
            let lo = cleanedLine[range.lowerBound]!, hi = cleanedLine[range.upperBound]!, title = cleaning.titles[block]
            return (lo...hi, (lo - (title?.lines.count ?? 0))..<lo,
                    SourceCodeBlock(language: rich.blocks[block].tag, code: text(cleanedLines[lo].lowerBound..<cleanedLines[hi].upperBound), title: title?.title))
        }
        let candidateLines = Set(blocks.flatMap { Array($0.lines) })
        if cleanedLines.indices.contains(where: { !candidateLines.contains($0) && (TranslationMarkup.fenceParts(text(cleanedLines[$0]))?.run ?? 0) >= 3 }) {
            blocks = []
            fencing = []
        }

        // Fences must give back exactly the cleaned text and each block's code; any doubt drops them. An opener with a
        // title stands for its title lines as well: they must say the title, and the rest must show as cleaned.
        let writer = Writer(c: c, lines: cleanedLines, blocks: blocks)
        var fenced = false
        if !blocks.isEmpty {
            let fencesOnly = writer.text(fences: true)
            let parsed = TranslationMarkup.layout(fencesOnly.text)
            let titleLines = Set(blocks.flatMap { Array($0.title) })
            let shown = cleanedLines.indices.filter { !titleLines.contains($0) }.map { text(cleanedLines[$0]) }.joined(separator: "\n")
            fenced = TranslationMarkup(fencesOnly.text).displayText == TranslationMarkup.trimmingTrailingWhitespace(shown)
                && parsed.blocks.count == blocks.count
                && zip(parsed.blocks, blocks).allSatisfy { parsed, app in
                    parsed.closer != nil && parsed.fence.indent == 0 && parsed.fence.inlineCode == nil
                        && parsed.fence.info == app.block.info && parsed.fence.length == app.block.fence && parsed.code == app.block.lines
                        && app.block.title == SourceCodeBlock.title(app.title.map { text(cleanedLines[$0]) }.joined(separator: " · "))
                }
        }
        report.fences = fenced
        // Lines of the blocks that end up fenced, and of the titles their openers stand for, in the copied text and the cleaned one.
        // A block left unfenced is prose, links and all.
        if !fenced { fencing = [] }
        let blockLines = Set(fencing.flatMap { block, range in Array(range) + (cleaning.titles[block]?.lines ?? []) })
        let fencedLines = fenced ? candidateLines : []
        let codeBlocks = Set(accepted.map(\.block))

        // Links and chips of prose, over letters that stay in the cleaned text: content, and controls that are not removed (a
        // clickable card, a toolbar of prose). Text of controls inside a link that the plain text lacks does not break it.
        var lineOfKey = [Int](repeating: 0, count: keys.count)
        for (line, range) in lineKeys.enumerated() { for key in range { lineOfKey[key] = line } }
        let content = items.indices.filter { items[$0].style.chrome == nil }
        let spanned = items.indices.filter { r in
            items[r].style.chrome == nil || alignment.mapped[r].map { toCleaned[keys[$0]] != nil } == true
        }
        func runs(_ key: (Style) -> Int?, _ kind: (Int) -> Span.Kind) -> [Span] {
            var spans: [Span] = []
            var i = 0
            while i < spanned.count {
                guard let value = key(items[spanned[i]].style) else { i += 1; continue }
                var end = i
                while end + 1 < spanned.count, key(items[spanned[end + 1]].style) == value { end += 1 }
                // Every letter matched consecutive plain keys, nothing in between was cut, and it is not code.
                if (i...end).allSatisfy({ alignment.mapped[spanned[$0]] != nil }),
                   let a = alignment.mapped[spanned[i]], let b = alignment.mapped[spanned[end]], b - a == end - i,
                   let first = toCleaned[keys[a]], let last = toCleaned[keys[b]], last - first == keys[b] - keys[a],
                   !blockLines.contains(lineOfKey[a]), !blockLines.contains(lineOfKey[b]) {
                    spans.append(Span(kind: kind(value), first: first, last: last))
                }
                i = end + 1
            }
            return spans
        }
        let spanText = { (span: Span) in String(String.UnicodeScalarView(c[span.first...span.last])) }
        let singleLine = { (span: Span) in !c[span.first...span.last].contains { $0 == "\n" || $0 == "\r" } }

        // Pages that already write markdown (Notion's plain text) or `<aN>` keep their own text.
        let hasLinkTags = cleaned.range(of: "</?a[0-9]+>", options: .regularExpression) != nil
        let links = hasLinkTags ? [] : runs({ $0.link }, { .link(rich.links[$0]) }).filter { span in
            let markdownLink = span.first > 0 && c[span.first - 1] == "[" && span.last + 2 < c.count && c[span.last + 1] == "]" && c[span.last + 2] == "("
            return singleLine(span) && !markdownLink && spanText(span).contains { $0.isLetter || $0.isNumber }
        }.prefix(maxLinks).map { $0 }

        // Semantic code tags win; monospace styling counts only where the page has none (Google Docs).
        // Prose that is mostly code (an editor, a terminal) gets no chips at all; fenced blocks are not prose.
        let prose = content.filter { items[$0].style.block.map { !codeBlocks.contains($0) } ?? true }
        let semantic = prose.contains { items[$0].style.code != nil && !items[$0].style.pre }
        let codeLike = prose.filter { items[$0].style.code != nil || items[$0].style.pre || items[$0].style.mono }.count
        let proseBackticks = cleanedLines.indices.contains { !fencedLines.contains($0) && c[cleanedLines[$0]].contains("`") }
        let allowCode = !proseBackticks && codeLike * 10 < prose.count * 9
        let code = !allowCode ? [] : runs({ style in
            guard !style.pre else { return nil }
            if let code = style.code { return code }
            return !semantic && style.mono ? 0 : nil
        }, { _ in .code }).filter { span in
            singleLine(span) && spanText(span).utf16.count <= 96
                && !links.contains { $0.first <= span.last && span.first <= $0.last && !($0.first <= span.first && span.last <= $0.last) }
        }.prefix(maxCodeSpans).map { $0 }

        let base = writer.text(fences: fenced).text
        let display = TranslationMarkup(base)
        let fences = display.blocks.filter { $0.fence != nil }
        for candidate in [code, []] where !links.isEmpty || !candidate.isEmpty {
            let (markup, sourceLinks) = writer.text(fences: fenced, links: links, code: candidate, text: spanText)
            let source = SourceMarkup(text: markup, links: sourceLinks, code: Set(candidate.map(spanText)), blocks: fenced ? blocks.map(\.block) : [])
            // The result-side parser must find exactly the spans and blocks written, or the markup is ambiguous.
            let parsed = TranslationMarkup(markup, inline: source.inlineOptions)
            if parsed.displayText == display.displayText, parsed.spans.count == links.count + candidate.count,
               parsed.blocks.filter({ $0.fence != nil }) == fences,
               !parsed.spans.contains(where: { span in fences.contains { NSIntersectionRange($0.range, span.range).length > 0 } }) {
                report.inline = candidate.isEmpty ? "links" : "chips+links"
                return CapturedSource(plain: cleaned, markup: source, raw: plain, removed: removed)
            }
        }
        let markup = fenced ? SourceMarkup(text: base, links: [], code: [], blocks: blocks.map(\.block)) : nil
        return CapturedSource(plain: cleaned, markup: markup, raw: plain, removed: removed)
    }

    /// UTF-16 ranges of the copied text that cleaning dropped: each removed line with the line break the join
    /// drops with it, and each cut edge of a code line.
    private static func removedRanges(_ p: [Unicode.Scalar], lines: [Range<Int>], cleaning: Cleaning) -> [NSRange] {
        var offsets = [0]
        for scalar in p { offsets.append(offsets[offsets.count - 1] + scalar.utf16.count) }
        let range = { (scalars: Range<Int>) in NSRange(location: offsets[scalars.lowerBound], length: offsets[scalars.upperBound] - offsets[scalars.lowerBound]) }
        var removed: [NSRange] = []
        var keptBefore = false
        for (line, scalars) in lines.enumerated() {
            if cleaning.removed[line] {
                removed.append(range(keptBefore ? (scalars.lowerBound - 1)..<scalars.upperBound : scalars.lowerBound..<min(p.count, scalars.upperBound + 1)))
                continue
            }
            keptBefore = true
            guard let cut = cleaning.cuts[line] else { continue }
            if cut.lowerBound > scalars.lowerBound { removed.append(range(scalars.lowerBound..<cut.lowerBound)) }
            if cut.upperBound < scalars.upperBound { removed.append(range(cut.upperBound..<scalars.upperBound)) }
        }
        return removed
    }

    /// Writes the cleaned text with app fences around its code blocks and, in prose, chips and link tags. A titled
    /// block's opener takes the place of its title lines.
    private struct Writer {
        let c: [Unicode.Scalar]
        let lines: [Range<Int>]
        let blocks: [(lines: ClosedRange<Int>, title: Range<Int>, block: SourceCodeBlock)]

        func text(fences: Bool, links: [Span] = [], code: [Span] = [], text: (Span) -> String = { _ in "" }) -> (text: String, links: [SourceLink]) {
            var opens: [Int: String] = [:], closes: [Int: String] = [:]
            var sourceLinks: [SourceLink] = []
            // Links open outside code and close after it, so a linked code span nests the right way.
            for span in links {
                guard case .link(let url) = span.kind else { continue }
                sourceLinks.append(SourceLink(url: url, text: text(span)))
                opens[span.first, default: ""] += "<a\(sourceLinks.count)>"
                closes[span.last] = "</a\(sourceLinks.count)>" + (closes[span.last] ?? "")
            }
            for span in code {
                opens[span.first, default: ""] += "`"
                closes[span.last] = "`" + (closes[span.last] ?? "")
            }
            var out = String.UnicodeScalarView()
            var next = 0
            var started = false
            for (line, range) in lines.enumerated() {
                let block = fences && next < blocks.count ? blocks[next] : nil
                if block?.title.contains(line) == true { continue }
                if started { out.append("\n") }
                started = true
                if let block, block.lines.lowerBound == line { out.append(contentsOf: (block.block.opener + "\n").unicodeScalars) }
                for index in range {
                    out.append(contentsOf: (opens[index] ?? "").unicodeScalars)
                    out.append(c[index])
                    out.append(contentsOf: (closes[index] ?? "").unicodeScalars)
                }
                if let block, block.lines.upperBound == line {
                    out.append(contentsOf: ("\n" + block.block.closer).unicodeScalars)
                    next += 1
                }
            }
            return (String(out), sourceLinks)
        }
    }
}
