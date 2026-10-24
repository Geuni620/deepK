import AppKit

@main
@MainActor
private enum ResultStyleTests {
    static func main() {
        _ = NSApplication.shared
        builtInStyles()
        palettesNameEveryKind()
        contrastAgainstTheWindow()
        darkCardsStayVisible()
        displaySettingsRoundTrip()
        headerGeometry()
        footerGeometry()
        languageNames()
        blockTitles()
        print("ResultStyleTests passed (no windows opened)")
    }

    private static func builtInStyles() {
        require(ResultStyle.builtIns.map(\.id) == [.native, .github], "Native and GitHub ship, Native first")
        let all = ResultStyle.builtIns + ResultStyle.fixtures
        require(Set(all.map(\.id)).count == all.count, "ids are unique")
        require(ResultStyle.style(for: nil) == .native && ResultStyle.style(for: "notion") == .native, "missing or unknown ids are Native")
        require(ResultStyle.style(for: "github") == .github, "a saved id resolves")
        require(ResultDisplaySettings.standard.style == .native, "Native is the default")
        require(ResultStyle.native.pill == ResultStyle.github.pill, "every built-in style uses Native's source pill")
        require(ResultStyle.native.header.showsGlyph && ResultStyle.native.header.showsLineCount
                && !ResultStyle.github.header.showsLineCount, "Native counts lines, GitHub does not")
    }

    /// Sources that do not name a kind fall back: command to function, flag to property, tag to keyword.
    private static func palettesNameEveryKind() {
        let native = ResultStyle.native.syntax!, github = ResultStyle.github.syntax!
        require(native.command == native.function && native.flag == native.property && native.tag == native.keyword,
                "Xcode has no command, flag or tag color")
        require(github.command == github.function && github.flag == github.property && github.tag != github.keyword,
                "Primer has a tag color, no command or flag")
        require(ResultStyle.native.syntax?.keyword.light.rgb == 0x9B2393 && ResultStyle.github.syntax?.keyword.light.rgb == 0xCF222E,
                "Xcode Default and Primer keywords")
    }

    /// Text on its surface, against the window background the system resolves for each appearance.
    private static func contrastAgainstTheWindow() {
        for dark in [false, true] {
            let window = windowBackground(dark: dark)
            for style in ResultStyle.builtIns {
                let name = "\(style.name) \(dark ? "dark" : "light")"
                let surface = composite(style.box.fill?.variant(dark: dark), over: window)
                require(contrast(composite(style.code.color.variant(dark: dark), over: surface), surface) >= 4.5, "\(name): code text")
                if let syntax = style.syntax {
                    let tokens = [syntax.keyword, syntax.type, syntax.function, syntax.string, syntax.number, syntax.comment,
                                  syntax.property, syntax.tag, syntax.command, syntax.flag]
                    for token in tokens {
                        require(contrast(composite(token.variant(dark: dark), over: surface), surface) >= 3, "\(name): token \(token)")
                    }
                }
                if let link = style.link.color {
                    require(contrast(composite(link.variant(dark: dark), over: window), window) >= 3, "\(name): link")
                }
                require(contrast(composite(style.fold.color.variant(dark: dark), over: surface), surface) >= 3, "\(name): fold footer")
                let pill = composite(style.pill.fill.variant(dark: dark), over: window)
                require(contrast(composite(style.pill.text.variant(dark: dark), over: pill), pill) >= 3, "\(name): pill text")
                switch style.header.copy {
                case .text(let color, _):
                    require(contrast(composite(color.variant(dark: dark), over: surface), surface) >= 3, "\(name): copy")
                case .iconButton(let button):
                    let fill = composite(button.fill.variant(dark: dark), over: surface)
                    require(contrast(composite(button.icon.variant(dark: dark), over: fill), fill) >= 3, "\(name): copy icon")
                case .icon, .iconText:
                    require(false, "\(name): no built-in style uses this copy control yet")
                }
            }
        }
    }

    /// The dark variants are rule-derived (StyleColor): a Native card keeps at least ΔL* 4 from the window in both
    /// appearances, also on a gray window background like older macOS releases paint. GitHub's card is carried by
    /// its border.
    private static func darkCardsStayVisible() {
        let gray = RGB(0xEC / 255, 0xEC / 255, 0xEC / 255)
        for (dark, window) in [(false, windowBackground(dark: false)), (true, windowBackground(dark: true)), (false, gray)] {
            let native = ResultStyle.native.box
            let card = composite(native.fill?.variant(dark: dark), over: window)
            require(abs(lightness(card) - lightness(window)) >= 4 && contrast(card, window) >= 1.1, "Native card on \(window): \(lightness(card))")
            let edge = composite(native.border?.color.variant(dark: dark), over: card)
            require(abs(lightness(edge) - lightness(window)) >= 4, "Native border on \(window)")
            let github = composite(ResultStyle.github.box.border?.color.variant(dark: dark), over: window)
            require(abs(lightness(github) - lightness(window)) >= 4, "GitHub border on \(window)")
        }
        // The fill before this change, black at 5.5%, disappears on the dark window.
        let old = StyleColor.alpha(0x000000, 0.055, dark: 0.055)
        let window = windowBackground(dark: true)
        require(abs(lightness(composite(old.dark, over: window)) - lightness(window)) < 4, "the old fill fails the dark check")
    }

    private static func displaySettingsRoundTrip() {
        let suite = "deepk-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        require(ResultDisplaySettings.load(from: defaults) == .standard, "missing keys load the defaults")
        let standard = ResultDisplaySettings.standard
        require(standard.style == .native && standard.foldsLongCode && standard.foldLineCount == 5
                && !standard.showsLinkSource && standard.colorsSyntax, "defaults")

        var changed = ResultDisplaySettings.standard
        changed.style = .github
        changed.foldsLongCode = false
        changed.foldLineCount = 10
        changed.showsLinkSource = true
        changed.colorsSyntax = false
        changed.save(to: defaults)
        require(ResultDisplaySettings.load(from: defaults) == changed, "settings round-trip")
        require(defaults.string(forKey: ResultDisplaySettings.Key.style) == "github", "the style is saved by id")

        for (stored, expected) in [(7, 8), (4, 3), (9, 8), (100, 20), (0, 3), (15, 15), (-1, 3), (Int.min, 3), (Int.min + 5, 3), (Int.max, 20)] {
            defaults.set(stored, forKey: ResultDisplaySettings.Key.foldLineCount)
            require(ResultDisplaySettings.load(from: defaults).foldLineCount == expected, "\(stored) lines snaps to \(expected)")
        }
        var snapped = ResultDisplaySettings.standard
        snapped.foldLineCount = 12
        require(snapped.foldLineCount == 10, "a set value snaps to a choice")

        defaults.set("notion", forKey: ResultDisplaySettings.Key.style)
        defaults.set("yes", forKey: ResultDisplaySettings.Key.showsLinkSource)
        defaults.set("seven", forKey: ResultDisplaySettings.Key.foldLineCount)
        let odd = ResultDisplaySettings.load(from: defaults)
        require(odd.style == .native && !odd.showsLinkSource && odd.foldLineCount == 5, "unreadable values fall back")
    }

    /// The header and copy control of every style in a box as wide as the small window's text (366pt).
    private static func headerGeometry() {
        let box = NSRect(x: 0, y: 40, width: 366, height: 120)
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            let geometry = CodeBlockGeometry.make(box: box, style: style, copySize: CodeBlockChrome.copySize(for: style))
            let header = style.header
            require(geometry.header == NSRect(x: 0, y: 40, width: 366, height: header.height), "\(style.name): header band")
            require(abs(geometry.copy.maxX - (box.maxX - header.insets.right)) < 0.01 && abs(geometry.copy.midY - geometry.header.midY) < 0.01,
                    "\(style.name): copy sits at the right inset, centered")
            require(geometry.copyHit.width >= 24 && geometry.copyHit.height >= 24 && geometry.copyHit.contains(geometry.copy)
                    && geometry.copyHit.maxX <= box.maxX && geometry.header.contains(geometry.copyHit), "\(style.name): copy hit area")
            require(geometry.label.minX == box.minX + header.insets.left && geometry.label.maxX <= geometry.copy.minX - CodeBlockGeometry.labelGap,
                    "\(style.name): the label ends before the copy control")
            require((geometry.headerSeparator != nil) == (header.separator != nil), "\(style.name): separator")
            // The control has room for "복사됨", the wider word, so it never reaches into the label's room.
            func copied(_ font: FontSpec) -> CGFloat { ("복사됨" as NSString).size(withAttributes: [.font: font.nsFont]).width }
            switch header.copy {
            case .text(_, let font): require(geometry.copy.width >= copied(font), "\(style.name): room for 복사됨")
            case .iconText(_, _, _, let font):
                require(geometry.copy.width >= 6 + CodeBlockChrome.glyphSize + 4 + copied(font) + 6, "\(style.name): room for 복사됨")
            case .icon, .iconButton: break
            }
        }
        let github = CodeBlockGeometry.make(box: box, style: .github, copySize: CodeBlockChrome.copySize(for: .github))
        require(github.copy.size == NSSize(width: 23, height: 23) && github.header.height == 35, "GitHub's 23pt button in a 35pt header")
        require(github.headerSeparator == NSRect(x: 1, y: 74, width: 364, height: 1), "the separator runs inside the border")
        let native = CodeBlockGeometry.make(box: box, style: .native, copySize: CodeBlockChrome.copySize(for: .native))
        require(native.header.height == 32 && native.copyHit.height == 24 && native.copyHit.width == max(24, native.copy.width),
                "Native's text control grows to 24pt")
        require(native.footer == nil && native.footerSeparator == nil, "a block within the fold limit has no footer")
    }

    /// A block longer than the fold limit ends with its footer: across the box's bottom, under a separator inside the border.
    private static func footerGeometry() {
        let box = NSRect(x: 0, y: 40, width: 366, height: 200)
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            let geometry = CodeBlockGeometry.make(box: box, style: style, copySize: CodeBlockChrome.copySize(for: style), footer: true)
            require(geometry.footer == NSRect(x: 0, y: box.maxY - style.fold.height, width: 366, height: style.fold.height),
                    "\(style.name): the footer spans the box's bottom")
            require((geometry.footerSeparator != nil) == (style.fold.separator != nil)
                    && geometry.footerSeparator.map { $0.minY == geometry.footer!.minY && $0.height == 1 } != false,
                    "\(style.name): the separator tops the footer")
            require(style.bottomPortion(footer: true) == (style.fold.gapAbove ?? style.box.bodyBottom) + style.fold.height
                    && style.bottomPortion(footer: false) == style.bottomPortion, "\(style.name): room under the last shown line")
        }
        require(ResultStyle.native.fold.template == .totalCount && ResultStyle.native.fold.alignment == .center
                && ResultStyle.native.fold.fade == 0.35 && ResultStyle.native.fold.gapAbove == 3,
                "Native: '12줄 모두 보기 ⌄' centered right under the faded last line")
        require(ResultStyle.github.fold.template == .moreCount && ResultStyle.github.fold.alignment == .leading
                && ResultStyle.github.fold.fade == nil && ResultStyle.github.fold.gapAbove == nil,
                "GitHub: '⌄ 2줄 더 보기' at the leading edge below the body's padding")
        let faded = ResultStyle.native.code.color.faded(0.35)
        require(faded.light.rgb == 0x1D1D1F && abs(faded.light.alpha - 0.35) < 0.001 && abs(faded.dark.alpha - 0.35) < 0.001,
                "a faded color keeps its hue at 35%")
    }

    private static func languageNames() {
        for tag in languageTags.union(["console", "terminal", "shell-session"]) {
            let name = CodeLanguageName.display(for: tag)
            require(CodeLanguageName.plainTextTags.contains(tag) ? name == nil : name != nil && name != tag,
                    "\(tag) has a display name: \(name ?? "nil")")
        }
        require(CodeLanguageName.display(for: "TS") == "TypeScript" && CodeLanguageName.display(for: "Python3") == "Python", "tags are matched lowercased")
        require(CodeLanguageName.display(for: "nginx") == "nginx" && CodeLanguageName.display(for: nil) == nil
                && CodeLanguageName.display(for: "TEXT") == nil, "unknown tags show themselves, plain text shows nothing")
        require(CodeLanguageName.lineCountText(12) == "12줄", "line count")

        let text = "a\nb\n" as NSString
        require(CodeBlockChrome.lineCount(of: NSRange(location: 0, length: 4), in: text) == 2
                && CodeBlockChrome.lineCount(of: NSRange(location: 0, length: 3), in: text) == 2
                && CodeBlockChrome.lineCount(of: NSRange(location: 0, length: 4), in: "a\r\nb" as NSString) == 2
                && CodeBlockChrome.lineCount(of: NSRange(location: 0, length: 3), in: "a\n\n" as NSString) == 2,
                "the break after the last line is not a line")
        require(CodeBlockChrome.headerLabel(title: nil, tag: "TypeScript", lineCount: 12, style: .native) == "TypeScript · 12줄"
                && CodeBlockChrome.headerLabel(title: nil, tag: "text", lineCount: 1, style: .native) == "1줄"
                && CodeBlockChrome.headerLabel(title: nil, tag: nil, lineCount: 3, style: .native) == "3줄", "Native header words")
        require(CodeBlockChrome.headerLabel(title: nil, tag: "TypeScript", lineCount: 12, style: .github) == "typescript"
                && CodeBlockChrome.headerLabel(title: nil, tag: "plain", lineCount: 1, style: .github) == nil
                && CodeBlockChrome.headerLabel(title: nil, tag: "ts", lineCount: 1, style: .railFixture) == "TYPESCRIPT", "raw and uppercase labels")
    }

    /// A fence's title (B writes a selected tab's label as one) heads the block as written, before the language.
    private static func blockTitles() {
        let cases: [(info: String, title: String?)] = [
            (#"text title="Most Agents""#, "Most Agents"),
            (#"bash title='npm'"#, "npm"),
            (#"js title="a.js" showLineNumbers"#, "a.js"),
            (#"js showLineNumbers title="a.js""#, "a.js"),
            (#"js {.numberLines} title="a.js""#, "a.js"),
            (#"text title='Say "hi"'"#, #"Say "hi""#),
            (#"js title="a.js" title="b.js""#, "a.js"),
            (#"js title="  a.js ""#, "a.js"),
            // Not a title: inside a `{…}` group, inside another value, another name, empty.
            (#"{.py title="x"}"#, nil),
            (#"js data="x title='y'""#, nil),
            (#"js subtitle="x""#, nil),
            (#"text title="""#, nil),
            (#"text title="  ""#, nil),
            ("js", nil),
            ("", nil),
            // Not an info string, so TranslationMarkup reads the fence line as code.
            (#"title="x""#, nil),
            ("npm install", nil),
            (#"js title="a.js"#, nil),
            (#"js Title="a.js""#, nil),
            // Junk after the attributes: the line is not an info string, so it has no title.
            (#"py title="x" $(rm)"#, nil)
        ]
        for (info, title) in cases {
            require(CodeBlockChrome.title(fromInfo: info) == title, "the title of \(info): \(CodeBlockChrome.title(fromInfo: info) ?? "nil")")
            // A title is read only where TranslationMarkup reads the fence line as an info string.
            if title != nil {
                let fence = TranslationMarkup("```\(info)\ncode\n```").blocks.first?.fence
                require(fence?.info == info && fence?.inlineCode == nil, "\(info) is an info string")
            }
        }
        // The structured source's openers round-trip: the title the importer put on a block is the title the header shows.
        let blocks: [(SourceCodeBlock, String?)] = [
            (SourceCodeBlock(language: nil, code: "/impeccable document", title: "Most Agents"), "Most Agents"),
            (SourceCodeBlock(language: "bash", code: "npm install foo", title: "npm"), "npm"),
            (SourceCodeBlock(language: "text", code: "ls", title: #"say "hi""#), #"say "hi""#),
            (SourceCodeBlock(language: "python", code: "print(1)", title: "it's"), "it's"),
            (SourceCodeBlock(language: "bash", code: "ls"), nil),
            (SourceCodeBlock(language: nil, code: "ls"), nil)
        ]
        for (block, title) in blocks {
            require(CodeBlockChrome.title(fromInfo: block.info) == title, "the title of the opener \(block.opener)")
            require(TranslationMarkup(block.opener + "\n" + block.code + "\n" + block.closer).blocks.first?.fence?.info == block.info,
                    "\(block.opener) is read as an info string")
        }
        for code in [#"title="x""#, "npm install", #"js title="a.js"#] {
            require(TranslationMarkup("```\(code)\ncode\n```").blocks.first?.fence?.inlineCode == code, "\(code) is code on the fence line")
        }

        require(CodeBlockChrome.headerLabel(title: "Most Agents", tag: "text", lineCount: 1, style: .native) == "Most Agents · 1줄"
                && CodeBlockChrome.headerLabel(title: "npm", tag: "bash", lineCount: 1, style: .native) == "npm · Bash · 1줄"
                && CodeBlockChrome.headerLabel(title: "a.js", tag: nil, lineCount: 2, style: .native) == "a.js · 2줄", "Native titles")
        require(CodeBlockChrome.headerLabel(title: "Most Agents", tag: "text", lineCount: 1, style: .github) == "Most Agents"
                && CodeBlockChrome.headerLabel(title: "npm", tag: "bash", lineCount: 1, style: .github) == "npm · bash"
                && CodeBlockChrome.headerLabel(title: "README.md", tag: "MD", lineCount: 1, style: .github) == "README.md · md",
                "GitHub titles keep their case")
        require(CodeBlockChrome.headerLabel(title: "npm", tag: "bash", lineCount: 1, style: .railFixture) == "npm · BASH"
                && CodeBlockChrome.headerLabel(title: "Most Agents", tag: "text", lineCount: 1, style: .railFixture) == "Most Agents",
                "an uppercase style uppercases only the language")
        // A language tab's label names the language, by its name or tag in any case, so the header says it once.
        require(CodeBlockChrome.headerLabel(title: "Python", tag: "python", lineCount: 2, style: .native) == "Python · 2줄"
                && CodeBlockChrome.headerLabel(title: "JavaScript", tag: "js", lineCount: 2, style: .native) == "JavaScript · 2줄"
                && CodeBlockChrome.headerLabel(title: "TS", tag: "ts", lineCount: 1, style: .native) == "TS · 1줄"
                && CodeBlockChrome.headerLabel(title: "bash", tag: "Bash", lineCount: 1, style: .native) == "bash · 1줄"
                && CodeBlockChrome.headerLabel(title: "Python", tag: "python", lineCount: 2, style: .github) == "Python"
                && CodeBlockChrome.headerLabel(title: "JavaScript", tag: "js", lineCount: 2, style: .github) == "JavaScript"
                && CodeBlockChrome.headerLabel(title: "Python", tag: "python", lineCount: 2, style: .railFixture) == "Python",
                "a title that names the language stands for it")
        require(CodeBlockChrome.headerLabel(title: "Python 3", tag: "python", lineCount: 2, style: .native) == "Python 3 · Python · 2줄"
                && CodeBlockChrome.headerLabel(title: "Node.js", tag: "js", lineCount: 1, style: .github) == "Node.js · js",
                "a title that only mentions the language keeps it")

        // In the small window's box a short title fits every style; a long one is cut at its end, never right after a
        // separator, where the "…" would run into the "·".
        let box = NSRect(x: 0, y: 0, width: 366, height: 120)
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            let geometry = CodeBlockGeometry.make(box: box, style: style, copySize: CodeBlockChrome.copySize(for: style))
            let fits = CodeBlockChrome.headerLabel(title: "Most Agents", tag: "bash", lineCount: 1, style: style)!
            require(CodeBlockChrome.fittedLabel(fits, in: geometry, style: style) == fits, "\(style.name): a short label is whole")
            let long = CodeBlockChrome.headerLabel(title: String(repeating: "Most Agents ", count: 6), tag: "bash", lineCount: 1, style: style)!
            let cut = CodeBlockChrome.fittedLabel(long, in: geometry, style: style)
            require(cut.hasSuffix("…") && long.hasPrefix(cut.dropLast()) && cut.count > 10, "\(style.name): a long label is cut: \(cut)")
            for end in 1..<long.count {
                let label = String(long.prefix(end)) + " · TypeScript · 12줄"
                let shown = CodeBlockChrome.fittedLabel(label, in: geometry, style: style)
                require(!shown.hasSuffix("·…") && !shown.hasSuffix(" …"), "\(style.name): no separator before the cut: \(shown)")
            }
        }
    }

    /// A temporary copy of TranslationMarkup's private language tags; dropped for `TranslationMarkup.knownLanguageTags`
    /// when PR B lands.
    private static let languageTags: Set<String> = [
        "bash", "sh", "shell", "zsh", "fish", "powershell", "ps1", "bat", "batch", "cmd",
        "c", "h", "cpp", "c++", "cc", "cxx", "hpp", "cs", "csharp", "c#", "objc", "objective-c",
        "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "py", "python", "python3",
        "rb", "ruby", "go", "golang", "rust", "rs", "java", "kotlin", "kt", "scala", "php",
        "perl", "pl", "lua", "r", "dart", "elixir", "ex", "erlang", "erl", "haskell", "hs",
        "clojure", "clj", "lisp", "julia", "jl", "sql", "html", "htm", "xml", "css", "scss", "sass", "less",
        "json", "jsonc", "yaml", "yml", "toml", "ini", "text", "txt", "plaintext", "plain",
        "md", "markdown", "mdx", "diff", "patch", "dockerfile", "makefile", "cmake",
        "graphql", "gql", "proto", "protobuf", "vue", "svelte", "astro", "mermaid", "regex", "regexp"
    ]

    // MARK: - Color math (WCAG 2 luminance and CIE L*)

    private struct RGB: CustomStringConvertible {
        let red: CGFloat, green: CGFloat, blue: CGFloat
        init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) { (self.red, self.green, self.blue) = (red, green, blue) }
        var description: String { String(format: "#%02X%02X%02X", Int(red * 255 + 0.5), Int(green * 255 + 0.5), Int(blue * 255 + 0.5)) }
    }

    private static func windowBackground(dark: Bool) -> RGB {
        var color = NSColor.white
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
        }
        return RGB(color.redComponent, color.greenComponent, color.blueComponent)
    }

    private static func composite(_ color: StyleColor.Variant?, over base: RGB) -> RGB {
        guard let color else { return base }
        func mix(_ top: CGFloat, _ under: CGFloat) -> CGFloat { top * color.alpha + under * (1 - color.alpha) }
        return RGB(mix(color.red, base.red), mix(color.green, base.green), mix(color.blue, base.blue))
    }

    private static func luminance(_ color: RGB) -> CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat { channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func contrast(_ a: RGB, _ b: RGB) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func lightness(_ color: RGB) -> CGFloat {
        let y = luminance(color)
        return y > 216.0 / 24389 ? 116 * cbrt(y) - 16 : y * 24389 / 27
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "ResultStyleTests: \(message)")
    }
}
