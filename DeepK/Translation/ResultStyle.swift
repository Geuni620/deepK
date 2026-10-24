import CoreGraphics
import Foundation

/// A color with a light and a dark variant. The app forces the light appearance (the result panel and the
/// settings window), so the dark variants are only drawn offscreen for now.
///
/// Dark variants follow one rule and wait for the user's sign-off:
/// 1. A color whose source defines a dark counterpart uses it: Apple system colors (#007AFF → #0A84FF,
///    #8E8E93 → #98989D, the #767680 fill 12% → 24%), Xcode Default (Dark) for Native's syntax palette,
///    Primer dark for GitHub.
/// 2. A neutral tint without one (the Native card, its border) becomes a white tint whose alpha gives at least
///    the ΔL* against the dark window background (#1E1E1E) that the light tint has against the light one,
///    and never less than 4 for a fill.
/// 3. A translucent accent fill (the source pill) doubles its alpha, as Apple's fills do.
struct StyleColor: Hashable, Sendable {
    struct Variant: Hashable, Sendable {
        /// 0xRRGGBB.
        let rgb: UInt32
        let alpha: CGFloat

        var red: CGFloat { CGFloat(rgb >> 16 & 0xFF) / 255 }
        var green: CGFloat { CGFloat(rgb >> 8 & 0xFF) / 255 }
        var blue: CGFloat { CGFloat(rgb & 0xFF) / 255 }
    }

    let light: Variant
    let dark: Variant

    func variant(dark: Bool) -> Variant { dark ? self.dark : light }

    /// An opaque color; without `dark` both appearances use the same value.
    static func hex(_ light: UInt32, dark: UInt32? = nil) -> StyleColor {
        StyleColor(light: Variant(rgb: light, alpha: 1), dark: Variant(rgb: dark ?? light, alpha: 1))
    }

    /// A translucent color; the dark variant keeps the hue unless `darkRGB` is given.
    static func alpha(_ rgb: UInt32, _ alpha: CGFloat, dark: CGFloat, darkRGB: UInt32? = nil) -> StyleColor {
        StyleColor(light: Variant(rgb: rgb, alpha: alpha), dark: Variant(rgb: darkRGB ?? rgb, alpha: dark))
    }

    /// The same color at `opacity` of its alpha, as a folded block's last shown line is drawn.
    func faded(_ opacity: CGFloat) -> StyleColor {
        StyleColor(light: Variant(rgb: light.rgb, alpha: light.alpha * opacity), dark: Variant(rgb: dark.rgb, alpha: dark.alpha * opacity))
    }
}

struct FontSpec: Hashable, Sendable {
    enum Family: Hashable, Sendable { case system, mono }
    enum Weight: Hashable, Sendable { case regular, medium }

    let family: Family
    let size: CGFloat
    var weight = Weight.regular

    static func system(_ size: CGFloat, _ weight: Weight = .regular) -> FontSpec { FontSpec(family: .system, size: size, weight: weight) }
    static func mono(_ size: CGFloat) -> FontSpec { FontSpec(family: .mono, size: size) }
}

/// How the result view draws code blocks, inline code and links. One renderer reads these values, so a new
/// style is a new value. Behaviors (folding, link source, syntax color) live in `ResultDisplaySettings`.
/// Values come from the pen.dev nodes eK0C3 (Native) and Ubex8 (GitHub). Their paddings are CSS boxes with a 1.6
/// line height, so `bodyTop` and `bodyBottom` add that line's half-leading around SF Mono's 16pt line: 2 above, 3 below.
struct ResultStyle: Identifiable, Hashable, Sendable {
    struct ID: RawRepresentable, Hashable, Sendable {
        let rawValue: String

        static let native = ID(rawValue: "native")
        static let github = ID(rawValue: "github")
    }

    struct Stroke: Hashable, Sendable {
        let color: StyleColor
        var width: CGFloat = 1
    }

    struct Insets: Hashable, Sendable {
        let left: CGFloat
        let right: CGFloat
    }

    enum Visibility: Hashable, Sendable { case always, hover }

    /// The card around a block.
    struct Box: Hashable, Sendable {
        let fill: StyleColor?
        let border: Stroke?
        /// A vertical rule at the left edge instead of a card.
        var rule: Stroke?
        let radius: CGFloat
        /// From the box edge to the code, inside any border or rule.
        let insets: Insets
        /// Between the header and the first code line, and below the last one.
        let bodyTop: CGFloat
        let bodyBottom: CGFloat
        /// Outside the box, above and below.
        var margin: CGFloat = 4
    }

    enum HeaderLabel: Hashable, Sendable {
        /// The fence tag as written, lowercased.
        case rawTag
        /// "TypeScript".
        case displayName
        /// "TYPESCRIPT", letter-spaced.
        case uppercaseTracked(kern: CGFloat)
    }

    /// The per-block copy control. Its words are always "복사" and "복사됨".
    enum CopyAffordance: Hashable, Sendable {
        case text(color: StyleColor, font: FontSpec)
        case icon(color: StyleColor, size: CGFloat)
        case iconText(fill: StyleColor, border: StyleColor, color: StyleColor, font: FontSpec)
        case iconButton(IconButton)
    }

    struct IconButton: Hashable, Sendable {
        let fill: StyleColor
        let hoverFill: StyleColor
        let border: StyleColor
        let icon: StyleColor
        let size: CGFloat
        let iconSize: CGFloat
        let radius: CGFloat
    }

    /// The band at the top of a block: language, line count and the copy control.
    struct Header: Hashable, Sendable {
        let height: CGFloat
        let insets: Insets
        let separator: StyleColor?
        let label: HeaderLabel
        let labelFont: FontSpec
        let labelColor: StyleColor
        /// The `</>` symbol before the label.
        let showsGlyph: Bool
        /// "· 12줄" after the label.
        let showsLineCount: Bool
        let copy: CopyAffordance
        let copyVisibility: Visibility
    }

    struct Code: Hashable, Sendable {
        let font: FontSpec
        /// Line pitch; the renderer turns it into line spacing for the font.
        let lineHeight: CGFloat
        let color: StyleColor
    }

    /// Every token kind the highlighter emits has a color. Kinds a source does not name fall back:
    /// command to function, flag to property, tag to keyword.
    struct SyntaxPalette: Hashable, Sendable {
        let keyword: StyleColor
        let type: StyleColor
        let function: StyleColor
        let string: StyleColor
        let number: StyleColor
        let comment: StyleColor
        let property: StyleColor
        let tag: StyleColor
        let command: StyleColor
        let flag: StyleColor
        var commentItalic = false
    }

    enum FoldAlignment: Hashable, Sendable { case leading, center }

    enum FoldTemplate: Hashable, Sendable {
        /// "⌄ 2줄 더 보기".
        case moreCount
        /// "12줄 모두 보기 ⌄".
        case totalCount
    }

    /// The row under a block longer than the fold limit: "더 보기" while folded, "접기" while expanded.
    struct FoldFooter: Hashable, Sendable {
        let alignment: FoldAlignment
        let template: FoldTemplate
        let font: FontSpec
        let color: StyleColor
        let separator: StyleColor?
        var bandFill: StyleColor?
        /// From the last shown code line to the footer; nil keeps the box's `bodyBottom`.
        var gapAbove: CGFloat?
        let height: CGFloat
        /// Leading padding of a leading-aligned footer.
        let inset: CGFloat
        let chevronSize: CGFloat
        /// Opacity of the last visible line of a folded block, or nil for no fade.
        let fade: CGFloat?
    }

    struct InlineChip: Hashable, Sendable {
        let font: FontSpec
        /// Nil draws no chip; the code shows only through its font and color.
        let fill: StyleColor?
        var border: Stroke?
        /// Nil keeps the prose color.
        let text: StyleColor?
        let radius: CGFloat
        /// Horizontal padding inside the chip.
        let padding: CGFloat
        /// Room added after the chip and after the character before it; at least `padding`.
        let kern: CGFloat
    }

    enum Underline: Hashable, Sendable { case always, hover, never }

    struct Link: Hashable, Sendable {
        /// Nil keeps the prose color.
        let color: StyleColor?
        let underline: Underline
        var underlineColor: StyleColor?
        /// A small ↗ after the link.
        var trailingArrow = false
    }

    /// The site chip after a link when 링크 출처 표시 is on. Every built-in style uses Native's look.
    struct SourcePill: Hashable, Sendable {
        let fill: StyleColor
        let text: StyleColor
        let font: FontSpec
        let height: CGFloat
        let radius: CGFloat
        let padding: CGFloat
        let iconSize: CGFloat
        /// Between the globe and the host.
        let gap: CGFloat
        /// Before the pill, after the link's last character, and after the pill.
        let leading: CGFloat
        let trailing: CGFloat
    }

    let id: ID
    let name: String
    /// The 표시 tab subtitle.
    let summary: String
    /// The style picker subtitle.
    let detail: String
    let box: Box
    let header: Header
    let code: Code
    /// Nil keeps code in one color; 문법 색 then has no effect.
    let syntax: SyntaxPalette?
    let fold: FoldFooter
    let chip: InlineChip
    let link: Link
    let pill: SourcePill

    /// From the box top to the first code line.
    var topPortion: CGFloat { header.height + box.bodyTop }
    /// From the last code line to the box bottom.
    var bottomPortion: CGFloat { box.bodyBottom }
    /// From the last shown code line to the box bottom, past the fold footer when the block has one.
    func bottomPortion(footer: Bool) -> CGFloat { footer ? (fold.gapAbove ?? box.bodyBottom) + fold.height : box.bodyBottom }
    /// A blank line next to a box keeps only this much height.
    static let blankLineGap: CGFloat = 6

    static let builtIns: [ResultStyle] = [.native, .github]

    /// The saved style, or Native for a missing or unknown one.
    static func style(for id: String?) -> ResultStyle {
        builtIns.first { $0.id.rawValue == id } ?? .native
    }
}

extension ResultStyle.SourcePill {
    /// The host a pill shows: without "www.", at most 28 characters cut in the middle. IDN hosts stay in punycode so
    /// the real destination is visible. Mail and other non-web links get no pill.
    static func host(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard host.count > 28 else { return host }
        return String(host.prefix(13)) + "…" + String(host.suffix(14))
    }
}

extension ResultStyle {
    /// E · macOS Native (eK0C3), the default. The card is a tint, so it stays darker than any window background.
    static let native = ResultStyle(
        id: .native, name: "macOS Native",
        summary: "시스템 카드 · 시스템 칩 · 파란 링크",
        detail: "시스템 카드 + 언어·줄 수 머리줄 · 시스템 칩 · 파란 링크",
        // The design shows Native code only folded, above its footer; an unfolded block keeps 10 below its last line.
        box: Box(
            // Composites to the design's #F2F2F7 over white.
            fill: .alpha(0x00005F, 0.05, dark: 0.04, darkRGB: 0xFFFFFF),
            border: Stroke(color: .alpha(0x000000, 0.06, dark: 0.05, darkRGB: 0xFFFFFF)),
            radius: 8, insets: Insets(left: 12, right: 12), bodyTop: 2, bodyBottom: 10
        ),
        header: Header(
            height: 32, insets: Insets(left: 12, right: 12), separator: nil,
            label: .displayName, labelFont: .system(11), labelColor: .hex(0x8E8E93, dark: 0x98989D),
            showsGlyph: true, showsLineCount: true,
            copy: .text(color: .hex(0x007AFF, dark: 0x0A84FF), font: .system(11, .medium)), copyVisibility: .always
        ),
        code: Code(font: .mono(13), lineHeight: 21, color: .hex(0x1D1D1F, dark: 0xF5F5F7)),
        // Xcode Default (Light) and (Dark).
        syntax: SyntaxPalette(
            keyword: .hex(0x9B2393, dark: 0xFC5FA3), type: .hex(0x3900A0, dark: 0xD0A8FF),
            function: .hex(0x6C36A9, dark: 0xA167E6), string: .hex(0xC41A16, dark: 0xFC6A5D),
            number: .hex(0x1C00CF, dark: 0xD0BF69), comment: .hex(0x5D6C79, dark: 0x6C7986),
            property: .hex(0x326D74, dark: 0x67B7A4), tag: .hex(0x9B2393, dark: 0xFC5FA3),
            command: .hex(0x6C36A9, dark: 0xA167E6), flag: .hex(0x326D74, dark: 0x67B7A4)
        ),
        // The design's folded block has no padding under its code: the footer follows the last line's half-leading.
        fold: FoldFooter(
            alignment: .center, template: .totalCount, font: .system(11, .medium), color: .hex(0x007AFF, dark: 0x0A84FF),
            separator: .alpha(0x000000, 0.05, dark: 0.045, darkRGB: 0xFFFFFF), gapAbove: 3, height: 30, inset: 0, chevronSize: 12,
            fade: 0.35
        ),
        chip: InlineChip(font: .mono(14), fill: .alpha(0x767680, 0.12, dark: 0.24), text: nil, radius: 4, padding: 5, kern: 6),
        link: Link(color: .hex(0x007AFF, dark: 0x0A84FF), underline: .never),
        pill: .native
    )

    /// B · GitHub (Ubex8), Primer light and dark.
    static let github = ResultStyle(
        id: .github, name: "GitHub",
        summary: "테두리 카드 · 회색 칩 · 파란 링크",
        detail: "테두리 카드 + 언어·복사 머리줄 · 회색 칩 · 파란 링크",
        box: Box(
            fill: .hex(0xF6F8FA, dark: 0x151B23), border: Stroke(color: .hex(0xD0D7DE, dark: 0x3D444D)),
            radius: 6, insets: Insets(left: 16, right: 16), bodyTop: 14, bodyBottom: 17
        ),
        header: Header(
            height: 35, insets: Insets(left: 12, right: 8), separator: .hex(0xD0D7DE, dark: 0x3D444D),
            label: .rawTag, labelFont: .mono(12), labelColor: .hex(0x59636E, dark: 0x9198A1),
            showsGlyph: false, showsLineCount: false,
            copy: .iconButton(IconButton(
                fill: .hex(0xFFFFFF, dark: 0x212830), hoverFill: .hex(0xF3F4F6, dark: 0x262C36),
                border: .hex(0xD0D7DE, dark: 0x3D444D), icon: .hex(0x59636E, dark: 0x9198A1), size: 23, iconSize: 13, radius: 6
            )),
            copyVisibility: .always
        ),
        code: Code(font: .mono(13), lineHeight: 21, color: .hex(0x1F2328, dark: 0xF0F6FC)),
        syntax: SyntaxPalette(
            keyword: .hex(0xCF222E, dark: 0xFF7B72), type: .hex(0x953800, dark: 0xFFA657),
            function: .hex(0x8250DF, dark: 0xD2A8FF), string: .hex(0x0A3069, dark: 0xA5D6FF),
            number: .hex(0x0550AE, dark: 0x79C0FF), comment: .hex(0x6E7781, dark: 0x9198A1),
            property: .hex(0x0550AE, dark: 0x79C0FF), tag: .hex(0x116329, dark: 0x7EE787),
            command: .hex(0x8250DF, dark: 0xD2A8FF), flag: .hex(0x0550AE, dark: 0x79C0FF)
        ),
        fold: FoldFooter(
            alignment: .leading, template: .moreCount, font: .system(11), color: .hex(0x0969DA, dark: 0x4493F8),
            separator: .hex(0xD0D7DE, dark: 0x3D444D), height: 30, inset: 10, chevronSize: 11, fade: nil
        ),
        chip: InlineChip(font: .mono(13.5), fill: .alpha(0x818B98, 0.12, dark: 0.4, darkRGB: 0x656C76),
                         text: .hex(0x1F2328, dark: 0xF0F6FC), radius: 6, padding: 6, kern: 7),
        link: Link(color: .hex(0x0969DA, dark: 0x4493F8), underline: .hover),
        pill: .native
    )
}

extension ResultStyle.SourcePill {
    static let native = Self(
        fill: .alpha(0x007AFF, 0.08, dark: 0.16, darkRGB: 0x0A84FF), text: .hex(0x007AFF, dark: 0x0A84FF),
        font: .system(10.5), height: 17, radius: 8.5, padding: 6, iconSize: 10, gap: 3, leading: 6, trailing: 2
    )
}

/// Names a fence tag in a block header. Tags are matched lowercased; the model may write any case.
enum CodeLanguageName {
    /// Plain text shows no name, only the line count.
    static let plainTextTags: Set<String> = ["text", "txt", "plaintext", "plain"]

    /// The header name for a tag: nil for no tag or plain text, the tag itself when it is not a known language.
    static func display(for tag: String?) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        let key = tag.lowercased()
        if plainTextTags.contains(key) { return nil }
        return names[key] ?? tag
    }

    /// The name under a block's title: none when the title already names the language, by its name or its tag in any
    /// case, as a language tab's label does ("Python" over ```python`), so a header never reads "Python · Python".
    static func display(for tag: String?, under title: String?) -> String? {
        guard let name = display(for: tag) else { return nil }
        guard let title = title?.lowercased() else { return name }
        return title == name.lowercased() || title == tag?.lowercased() ? nil : name
    }

    static func lineCountText(_ count: Int) -> String { "\(count)줄" }

    private static let names: [String: String] = [
        "bash": "Bash", "sh": "Shell", "shell": "Shell", "zsh": "Zsh", "fish": "Fish",
        "powershell": "PowerShell", "ps1": "PowerShell", "bat": "Batch", "batch": "Batch", "cmd": "Batch",
        "console": "Console", "terminal": "Terminal", "shell-session": "Shell",
        "c": "C", "h": "C", "cpp": "C++", "c++": "C++", "cc": "C++", "cxx": "C++", "hpp": "C++",
        "cs": "C#", "csharp": "C#", "c#": "C#", "objc": "Objective-C", "objective-c": "Objective-C",
        "swift": "Swift", "js": "JavaScript", "javascript": "JavaScript", "jsx": "JavaScript",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TypeScript",
        "py": "Python", "python": "Python", "python3": "Python", "rb": "Ruby", "ruby": "Ruby",
        "go": "Go", "golang": "Go", "rust": "Rust", "rs": "Rust", "java": "Java", "kotlin": "Kotlin", "kt": "Kotlin",
        "scala": "Scala", "php": "PHP", "perl": "Perl", "pl": "Perl", "lua": "Lua", "r": "R", "dart": "Dart",
        "elixir": "Elixir", "ex": "Elixir", "erlang": "Erlang", "erl": "Erlang", "haskell": "Haskell", "hs": "Haskell",
        "clojure": "Clojure", "clj": "Clojure", "lisp": "Lisp", "julia": "Julia", "jl": "Julia", "sql": "SQL",
        "html": "HTML", "htm": "HTML", "xml": "XML", "css": "CSS", "scss": "SCSS", "sass": "Sass", "less": "Less",
        "json": "JSON", "jsonc": "JSONC", "yaml": "YAML", "yml": "YAML", "toml": "TOML", "ini": "INI",
        "md": "Markdown", "markdown": "Markdown", "mdx": "MDX", "diff": "Diff", "patch": "Diff",
        "dockerfile": "Dockerfile", "makefile": "Makefile", "cmake": "CMake", "graphql": "GraphQL", "gql": "GraphQL",
        "proto": "Protobuf", "protobuf": "Protobuf", "vue": "Vue", "svelte": "Svelte", "astro": "Astro",
        "mermaid": "Mermaid", "regex": "Regex", "regexp": "Regex"
    ]
}
