import Foundation

/// Test-only styles from the designs that do not ship yet (A · Notion, C · Dark Code, D · Minimal Rail; values from
/// the investigation's annotations and 1.5× exports). With Native and GitHub they draw every case the style values
/// allow, so a later style really needs values only. Dark variants are not designed; they repeat the light ones.
extension ResultStyle {
    static let fixtures: [ResultStyle] = [.notionFixture, .darkFixture, .railFixture]

    /// Grey box without a border, copy with icon and words on hover, red chips, prose links underlined.
    static let notionFixture = ResultStyle(
        id: ID(rawValue: "notion"), name: "Notion", summary: "연회색 박스 · 빨간 칩 · 밑줄 링크", detail: "",
        box: Box(fill: .hex(0xF7F6F3), border: nil, radius: 4, insets: Insets(left: 16, right: 16), bodyTop: 2, bodyBottom: 14),
        header: Header(
            height: 34, insets: Insets(left: 16, right: 10), separator: nil, label: .displayName, labelFont: .system(12.5),
            labelColor: .hex(0x9B9A97), showsGlyph: false, showsLineCount: false,
            copy: .iconText(fill: .hex(0xFFFFFF), border: .hex(0xE0DFDC), color: .hex(0x37352F), font: .system(12)),
            copyVisibility: .hover
        ),
        code: Code(font: .mono(13), lineHeight: 21, color: .hex(0x37352F)),
        syntax: SyntaxPalette(
            keyword: .hex(0x0077AA), type: .hex(0xDD4A68), function: .hex(0xDD4A68), string: .hex(0x669900),
            number: .hex(0x990055), comment: .hex(0x9B9A97), property: .hex(0x990055), tag: .hex(0x990055),
            command: .hex(0xDD4A68), flag: .hex(0x990055)
        ),
        fold: FoldFooter(alignment: .leading, template: .moreCount, font: .system(11), color: .hex(0x9B9A97), separator: nil,
                         height: 28, inset: 16, chevronSize: 11, fade: nil),
        chip: InlineChip(font: .mono(14), fill: .hex(0xEDEDEB), text: .hex(0xEB5757), radius: 4, padding: 4, kern: 5),
        link: Link(color: nil, underline: .always, underlineColor: .hex(0xB4B3B1)),
        pill: .native
    )

    /// Dark card with an icon-only copy, bordered white chips, blue links with ↗.
    static let darkFixture = ResultStyle(
        id: ID(rawValue: "dark"), name: "Dark Code", summary: "어두운 카드 · 테두리 칩 · 파랑+↗", detail: "",
        box: Box(fill: .hex(0x282C34), border: nil, radius: 10, insets: Insets(left: 16, right: 16), bodyTop: 2, bodyBottom: 14),
        header: Header(
            height: 32, insets: Insets(left: 16, right: 12), separator: nil, label: .displayName, labelFont: .system(12),
            labelColor: .hex(0x8B929E), showsGlyph: false, showsLineCount: false,
            copy: .icon(color: .hex(0x8B929E), size: 14), copyVisibility: .always
        ),
        code: Code(font: .mono(13), lineHeight: 21, color: .hex(0xABB2BF)),
        syntax: SyntaxPalette(
            keyword: .hex(0xC678DD), type: .hex(0xE5C07B), function: .hex(0x61AFEF), string: .hex(0x98C379),
            number: .hex(0xD19A66), comment: .hex(0x7F848E), property: .hex(0xE06C75), tag: .hex(0xE06C75),
            command: .hex(0x61AFEF), flag: .hex(0xD19A66), commentItalic: true
        ),
        fold: FoldFooter(alignment: .leading, template: .moreCount, font: .system(11), color: .hex(0x61AFEF), separator: nil,
                         bandFill: .hex(0x21252B), height: 30, inset: 16, chevronSize: 11, fade: nil),
        chip: InlineChip(font: .mono(13.5), fill: .hex(0xFFFFFF), border: Stroke(color: .hex(0xD9D9DE)), text: nil,
                         radius: 4, padding: 4, kern: 5),
        link: Link(color: .hex(0x0A66D8), underline: .never, trailingArrow: true),
        pill: .native
    )

    /// No card: a left rule, an uppercase label, chipless orange code and underlined prose links with ↗.
    static let railFixture = ResultStyle(
        id: ID(rawValue: "rail"), name: "Minimal Rail", summary: "세로선 · 글꼴만 · 옅은 밑줄", detail: "",
        box: Box(fill: nil, border: nil, rule: Stroke(color: .hex(0xD2D2D7), width: 2), radius: 0,
                 insets: Insets(left: 12, right: 0), bodyTop: 0, bodyBottom: 4),
        header: Header(
            height: 24, insets: Insets(left: 14, right: 0), separator: nil, label: .uppercaseTracked(kern: 0.8),
            labelFont: .system(10), labelColor: .hex(0xA1A1A6), showsGlyph: false, showsLineCount: false,
            copy: .text(color: .hex(0xB9B9BC), font: .system(11)), copyVisibility: .always
        ),
        code: Code(font: .mono(13), lineHeight: 21, color: .hex(0x1D1D1F)),
        syntax: nil,
        fold: FoldFooter(alignment: .leading, template: .moreCount, font: .system(11), color: .hex(0x6E6E73), separator: nil,
                         height: 24, inset: 14, chevronSize: 11, fade: nil),
        chip: InlineChip(font: .mono(13), fill: nil, text: .hex(0xB4441C), radius: 0, padding: 0, kern: 0),
        link: Link(color: nil, underline: .always, underlineColor: .hex(0xC4C4C5), trailingArrow: true),
        pill: .native
    )
}
