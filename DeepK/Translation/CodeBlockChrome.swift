import AppKit

/// Identifies a code block across restyles by its start, fence and first line. Per-block state is keyed by it,
/// never by the block's position, so a block rewritten in place or a replacement translation starts fresh.
/// The fence counts by its backticks and language only: a title restored or reworded in place heads the same code,
/// so the block keeps its state.
struct CodeBlockKey: Hashable {
    private(set) var start: Int
    let fence: String
    let firstLine: Int

    /// The same block after text before it was edited.
    func moved(to start: Int) -> CodeBlockKey {
        var key = self
        key.start = start
        return key
    }

    init(block: TranslationMarkup.Block, in text: NSString) {
        start = block.range.location
        fence = block.fence.map { $0.delimiter + ($0.language ?? "") } ?? ""
        let line = NSIntersectionRange(text.paragraphRange(for: NSRange(location: block.range.location, length: 0)), block.range)
        firstLine = text.substring(with: line).hashValue
    }
}

/// A control the result view draws itself. Finding the control under a point is separate from running it,
/// so a click, VoiceOver and tests take the same path.
enum ResultChromeControl: Hashable {
    case copy(CodeBlockKey)
    /// The footer of a block longer than the fold limit: expands or folds it.
    case fold(CodeBlockKey)
    /// The source pill after the link at this range.
    case pill(NSRange)
}

/// Where a block's header, copy control and fold footer go, in view coordinates (flipped). Pure, so it is tested without layout.
struct CodeBlockGeometry: Equatable {
    static let minimumHit: CGFloat = 24
    static let labelGap: CGFloat = 8

    let box: NSRect
    let header: NSRect
    /// Room for the glyph and label; it ends before the copy control.
    let label: NSRect
    let copy: NSRect
    /// The copy control grown to at least 24×24 for the pointer, inside the box.
    let copyHit: NSRect
    let headerSeparator: NSRect?
    /// The fold footer across the box's bottom, for a block longer than the fold limit; the whole row takes the click.
    var footer: NSRect?
    var footerSeparator: NSRect?

    static func make(box: NSRect, style: ResultStyle, copySize: NSSize, footer hasFooter: Bool = false) -> CodeBlockGeometry {
        let header = NSRect(x: box.minX, y: box.minY, width: box.width, height: style.header.height)
        let copy = NSRect(x: header.maxX - style.header.insets.right - copySize.width, y: header.midY - copySize.height / 2,
                          width: copySize.width, height: copySize.height)
        let hitWidth = max(copy.width, minimumHit), hitHeight = max(copy.height, minimumHit)
        let copyHit = NSRect(x: min(copy.midX - hitWidth / 2, box.maxX - hitWidth), y: copy.midY - hitHeight / 2,
                             width: hitWidth, height: hitHeight)
        let labelX = header.minX + style.header.insets.left
        let label = NSRect(x: labelX, y: header.minY, width: max(0, copy.minX - labelGap - labelX), height: header.height)
        let border = style.box.border?.width ?? 0
        let separator = style.header.separator.map { _ in
            NSRect(x: box.minX + border, y: header.maxY - 1, width: box.width - 2 * border, height: 1)
        }
        let footer = hasFooter ? NSRect(x: box.minX, y: box.maxY - style.fold.height, width: box.width, height: style.fold.height) : nil
        let footerSeparator = footer.flatMap { footer in
            style.fold.separator.map { _ in NSRect(x: box.minX + border, y: footer.minY, width: box.width - 2 * border, height: 1) }
        }
        return CodeBlockGeometry(box: box, header: header, label: label, copy: copy, copyHit: copyHit, headerSeparator: separator,
                                 footer: footer, footerSeparator: footerSeparator)
    }
}

/// A code block as laid out: its key, its markup block and where its chrome goes.
struct CodeBoxLayout {
    let key: CodeBlockKey
    let block: TranslationMarkup.Block
    /// 1-based position, only for spoken names.
    let number: Int
    let geometry: CodeBlockGeometry
    var fold = CodeFoldPlan.unfolded

    /// The title its fence gives the block. It heads the block but is not part of its code.
    var title: String? { block.fence.flatMap { CodeBlockChrome.title(fromInfo: $0.info) } }

    /// How VoiceOver names the block: "Most Agents", "npm, Bash", or "" with neither.
    private var spokenName: String {
        let title = title
        return [title, CodeLanguageName.display(for: block.fence?.language, under: title)].compactMap { $0 }.joined(separator: ", ")
    }

    /// The name VoiceOver gives the block's copy action: "Most Agents 코드 복사", "npm, Bash 코드 복사".
    var copyActionName: String {
        let name = spokenName
        return name.isEmpty ? "코드 블록 \(number) 복사" : "\(name) 코드 복사"
    }

    /// The name of the footer's action: "TypeScript 코드 12줄 모두 보기" while folded, "TypeScript 코드 접기" while expanded.
    var foldActionName: String {
        let name = spokenName
        let action = fold.isFolded ? "\(fold.lineCount)줄 모두 보기" : "접기"
        return name.isEmpty ? "코드 블록 \(number) \(action)" : "\(name) 코드 \(action)"
    }
}

@MainActor private var dynamicColors: [StyleColor: NSColor] = [:]

extension StyleColor {
    /// One dynamic color per value: storage attributes compare equal across restyles and resolve for the
    /// appearance they are drawn in.
    @MainActor var nsColor: NSColor {
        if let color = dynamicColors[self] { return color }
        let color = NSColor(name: nil) { [self] appearance in
            resolved(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
        dynamicColors[self] = color
        return color
    }

    func resolved(dark: Bool) -> NSColor {
        let variant = variant(dark: dark)
        return NSColor(srgbRed: variant.red, green: variant.green, blue: variant.blue, alpha: variant.alpha)
    }
}

extension ResultStyle.SyntaxPalette {
    func color(for kind: SyntaxTokenKind) -> StyleColor {
        switch kind {
        case .keyword: keyword
        case .type: type
        case .function: function
        case .string: string
        case .number: number
        case .comment: comment
        case .property: property
        case .tag: tag
        case .command: command
        case .flag: flag
        }
    }
}

extension FontSpec {
    var nsFont: NSFont {
        let weight: NSFont.Weight = weight == .medium ? .medium : .regular
        return family == .mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }
}

/// Paragraph styles for a block's lines. The box's padding is spacing on its first and last lines. Every line has the
/// same line spacing, so a wrapped last line keeps the block's pitch. TextKit leaves that spacing out under the text's
/// last line only, so the last line's paragraph spacing gives it back and the box is measured without it.
/// A folded block's last shown line is a middle line; its hidden last line takes `foldSpacer` instead (`CodeFoldLayoutDelegate`).
struct CodeParagraphs {
    private let first: NSParagraphStyle
    private let middle: NSParagraphStyle
    private let last: NSParagraphStyle
    private let single: NSParagraphStyle
    /// The last line of a block that ends with a fold footer, expanded.
    private let lastAboveFooter: NSParagraphStyle
    /// The height a folded block's last hidden line takes: the box's bottom with its footer and the margin below it,
    /// less the line spacing under the last shown line.
    let foldSpacer: CGFloat

    /// A blank line next to a box only needs a small gap; the full line wastes the small window.
    @MainActor static let spacer: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ResultStyle.blankLineGap
        paragraph.maximumLineHeight = ResultStyle.blankLineGap
        return paragraph
    }()

    init(style: ResultStyle, font: NSFont, naturalLineHeight: CGFloat) {
        let box = style.box
        let border = box.border?.width ?? 0
        let lineSpacing = max(0, style.code.lineHeight - naturalLineHeight)
        func make(first: Bool, bottom: CGFloat?) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = box.insets.left + border + (box.rule?.width ?? 0)
            paragraph.headIndent = paragraph.firstLineHeadIndent
            paragraph.tailIndent = -(box.insets.right + border)
            paragraph.lineSpacing = lineSpacing
            paragraph.tabStops = []
            paragraph.defaultTabInterval = 4 * ("0" as NSString).size(withAttributes: [.font: font]).width
            if first { paragraph.paragraphSpacingBefore = box.margin + style.topPortion }
            if let bottom { paragraph.paragraphSpacing = max(0, bottom + box.margin - lineSpacing) }
            return paragraph
        }
        first = make(first: true, bottom: nil)
        middle = make(first: false, bottom: nil)
        last = make(first: false, bottom: style.bottomPortion)
        single = make(first: true, bottom: style.bottomPortion)
        lastAboveFooter = make(first: false, bottom: style.bottomPortion(footer: true))
        foldSpacer = max(0, style.bottomPortion(footer: true) + box.margin - lineSpacing)
    }

    /// A block's lines: the last one leaves room for the box's bottom, and for the footer when the block has one.
    /// A block with a footer is longer than any fold limit, so its first line is never its last.
    func style(first isFirst: Bool, last isLast: Bool, footer: Bool = false) -> NSParagraphStyle {
        isFirst ? (isLast ? single : first) : (isLast ? (footer ? lastAboveFooter : last) : middle)
    }
}

/// Drawing for code block headers, inline chips and link adornments. Colors are resolved for the view's appearance.
@MainActor enum CodeBlockChrome {
    enum CopyState: Equatable { case normal, hover, pressed, copied, disabled, hidden }

    static let glyphSize: CGFloat = 12
    static let glyphGap: CGFloat = 5
    static let arrowSize: CGFloat = 9
    /// The ↗ and a gap on each side.
    static let arrowWidth: CGFloat = 12
    private static let iconTextHeight: CGFloat = 20

    /// Lines in a block, not counting the break that ends its last line.
    static func lineCount(of range: NSRange, in text: NSString) -> Int {
        var count = 1
        for index in range.location..<max(range.location, NSMaxRange(range) - 1) where text.character(at: index) == 0x0A { count += 1 }
        return count
    }

    /// The title a fence's info gives its block, as the app writes a copied tab widget's selected tab (```text title="Most Agents"`):
    /// the first `title` attribute after the tag or `{…}` group, in double or single quotes, read with the grammar
    /// `TranslationMarkup` reads info strings with. A `{…}` group is not looked into (`{.py title="x"}` has no title):
    /// its insides are Pandoc's own syntax, and no app-made fence writes one. Nil for no title, an empty one, or a
    /// fence line that is code (```npm install). The title is shown as written.
    nonisolated static func title(fromInfo info: String) -> String? {
        let head = #"(?:[A-Za-z0-9_+#.\-]{1,24}(?::\S+)?|\{[^{}]*\})"#
        // An attribute (`{…}` or `name="…"`) or a bare flag, after whitespace.
        let token = #"\s+(?:\{[^{}]*\}|[a-z][A-Za-z0-9_\-]*=(?:"[^"]*"|'[^']*')|[A-Za-z][A-Za-z0-9_\-]*)"#
        // The whole line must be an info string; the shortest run of tokens before a title then finds the first one.
        guard info.range(of: "^\(head)(?:\(token))*$", options: .regularExpression) != nil,
              let found = info.range(of: "^\(head)(?:\(token))*?" + #"\s+title=(?:"[^"]*"|'[^']*')"#, options: .regularExpression),
              let quote = info[found].last, let open = info[found].dropLast().lastIndex(of: quote) else { return nil }
        let title = info[info.index(after: open)..<info.index(before: found.upperBound)].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// The header words: the block's title, then its language and line count as the style shows them, as in
    /// "npm · Bash · 1줄" for Native and "npm · bash" for GitHub. Only the language is lowercased or uppercased; the
    /// title is shown as written. Plain text and untagged blocks name no language, nor does a title that names it.
    static func headerLabel(title: String?, tag: String?, lineCount: Int, style: ResultStyle) -> String? {
        let header = style.header
        var name = CodeLanguageName.display(for: tag, under: title)
        switch header.label {
        case .rawTag: name = name == nil ? nil : tag?.lowercased()
        case .displayName: break
        case .uppercaseTracked: name = name?.uppercased()
        }
        let parts = [title, name, header.showsLineCount ? CodeLanguageName.lineCountText(lineCount) : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A header label as drawn in the room left of the copy control, which never moves for it: whole, or cut at its
    /// end with "…", as a long title is. The cut never leaves a separator before the "…", where it reads as a row of dots.
    static func fittedLabel(_ label: String, in geometry: CodeBlockGeometry, style: ResultStyle) -> String {
        let attributes = labelAttributes(style.header)
        let room = geometry.label.maxX - labelStart(in: geometry, style: style)
        func fits(_ text: String) -> Bool { (text as NSString).size(withAttributes: attributes).width <= room }
        if fits(label) { return label }
        // The longest start that fits with the "…"; a longer start is never narrower.
        var low = 0, high = label.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(label.prefix(middle) + "…") { low = middle } else { high = middle - 1 }
        }
        var start = label.prefix(low)
        while let last = start.last, last == "·" || last.isWhitespace { start.removeLast() }
        return start.isEmpty ? "" : start + "…"
    }

    /// The label's words follow the `</>` when the style draws it.
    private static func labelStart(in geometry: CodeBlockGeometry, style: ResultStyle) -> CGFloat {
        let x = geometry.label.minX
        return style.header.showsGlyph && x + glyphSize <= geometry.label.maxX ? x + glyphSize + glyphGap : x
    }

    private static func labelAttributes(_ header: ResultStyle.Header) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: header.labelFont.nsFont]
        if case .uppercaseTracked(let kern) = header.label { attributes[.kern] = kern }
        return attributes
    }

    /// The control's words before and after a click.
    static let copyWords = ["복사", "복사됨"]

    /// The control has room for the wider of its words, so "복사됨" never reaches into the label's room.
    static func copySize(for style: ResultStyle) -> NSSize {
        func words(_ font: FontSpec) -> NSSize {
            let sizes = copyWords.map { ($0 as NSString).size(withAttributes: [.font: font.nsFont]) }
            return NSSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
        }
        switch style.header.copy {
        case .text(_, let font):
            let size = words(font)
            return NSSize(width: ceil(size.width), height: ceil(size.height))
        case .icon(_, let size):
            return NSSize(width: size, height: size)
        case .iconText(_, _, _, let font):
            return NSSize(width: ceil(6 + glyphSize + 4 + words(font).width + 6), height: iconTextHeight)
        case .iconButton(let button):
            return NSSize(width: button.size, height: button.size)
        }
    }

    static func drawBox(_ geometry: CodeBlockGeometry, style: ResultStyle, dark: Bool) {
        let box = style.box
        if let fill = box.fill {
            fill.resolved(dark: dark).setFill()
            NSBezierPath(roundedRect: geometry.box, xRadius: box.radius, yRadius: box.radius).fill()
        }
        if let border = box.border {
            let inset = border.width / 2
            let outline = NSBezierPath(roundedRect: geometry.box.insetBy(dx: inset, dy: inset),
                                       xRadius: max(0, box.radius - inset), yRadius: max(0, box.radius - inset))
            outline.lineWidth = border.width
            border.color.resolved(dark: dark).setStroke()
            outline.stroke()
        }
        if let rule = box.rule {
            rule.color.resolved(dark: dark).setFill()
            NSBezierPath(rect: NSRect(x: geometry.box.minX, y: geometry.box.minY, width: rule.width, height: geometry.box.height)).fill()
        }
        if let separator = style.header.separator, let line = geometry.headerSeparator {
            separator.resolved(dark: dark).setFill()
            NSBezierPath(rect: line).fill()
        }
    }

    static func drawHeader(_ geometry: CodeBlockGeometry, label: String?, style: ResultStyle, dark: Bool, copy state: CopyState) {
        let header = style.header
        let color = header.labelColor.resolved(dark: dark)
        let x = labelStart(in: geometry, style: style)
        if x > geometry.label.minX {
            drawSymbol("chevron.left.forwardslash.chevron.right",
                       in: NSRect(x: geometry.label.minX, y: geometry.header.midY - glyphSize / 2, width: glyphSize, height: glyphSize), color: color)
        }
        if let label, x < geometry.label.maxX {
            var attributes = labelAttributes(header)
            attributes[.foregroundColor] = color
            let shown = fittedLabel(label, in: geometry, style: style) as NSString
            let height = ceil(shown.size(withAttributes: attributes).height)
            shown.draw(at: NSPoint(x: x, y: geometry.header.midY - height / 2), withAttributes: attributes)
        }
        drawCopy(state, in: geometry.copy, style: style, dark: dark)
    }

    private static func drawCopy(_ state: CopyState, in rect: NSRect, style: ResultStyle, dark: Bool) {
        guard state != .hidden, let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        context.cgContext.setAlpha(state == .disabled ? 0.35 : state == .pressed ? 0.6 : 1)
        let copied = state == .copied
        let word = copied ? "복사됨" : "복사"
        let icon = copied ? "checkmark" : "doc.on.doc"
        switch style.header.copy {
        case .text(let color, let font):
            let attributes: [NSAttributedString.Key: Any] = [.font: font.nsFont, .foregroundColor: color.resolved(dark: dark)]
            let size = (word as NSString).size(withAttributes: attributes)
            (word as NSString).draw(at: NSPoint(x: rect.maxX - size.width, y: rect.midY - size.height / 2), withAttributes: attributes)
        case .icon(let color, let size):
            drawSymbol(icon, in: NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size), color: color.resolved(dark: dark))
        case .iconText(let fill, let border, let color, let font):
            drawButton(rect, radius: 5, fill: fill.resolved(dark: dark), border: border.resolved(dark: dark))
            let foreground = color.resolved(dark: dark)
            let attributes: [NSAttributedString.Key: Any] = [.font: font.nsFont, .foregroundColor: foreground]
            let size = (word as NSString).size(withAttributes: attributes)
            // The button fits "복사됨"; the shorter word sits in its middle.
            let x = max(rect.minX + 6, rect.midX - (glyphSize + 4 + size.width) / 2)
            drawSymbol(icon, in: NSRect(x: x, y: rect.midY - glyphSize / 2, width: glyphSize, height: glyphSize), color: foreground)
            (word as NSString).draw(at: NSPoint(x: x + glyphSize + 4, y: rect.midY - size.height / 2), withAttributes: attributes)
        case .iconButton(let button):
            let fill = state == .hover || state == .pressed ? button.hoverFill : button.fill
            drawButton(rect, radius: button.radius, fill: fill.resolved(dark: dark), border: button.border.resolved(dark: dark))
            drawSymbol(icon, in: NSRect(x: rect.midX - button.iconSize / 2, y: rect.midY - button.iconSize / 2,
                                        width: button.iconSize, height: button.iconSize), color: button.icon.resolved(dark: dark))
        }
    }

    private static func drawButton(_ rect: NSRect, radius: CGFloat, fill: NSColor, border: NSColor) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        path.lineWidth = 1
        border.setStroke()
        path.stroke()
    }

    /// The fold footer: its band and separator, then "12줄 모두 보기 ⌄" centered (Native) or "⌄ 2줄 더 보기" at the leading
    /// edge (GitHub); "접기" with an up chevron while expanded.
    static func drawFooter(_ geometry: CodeBlockGeometry, label: String, folded: Bool, style: ResultStyle, dark: Bool, pressed: Bool) {
        guard let footer = geometry.footer, let context = NSGraphicsContext.current else { return }
        let fold = style.fold
        if let fill = fold.bandFill {
            context.saveGraphicsState()
            NSBezierPath(roundedRect: geometry.box, xRadius: style.box.radius, yRadius: style.box.radius).addClip()
            fill.resolved(dark: dark).setFill()
            footer.fill()
            context.restoreGraphicsState()
        }
        if let separator = fold.separator, let line = geometry.footerSeparator {
            separator.resolved(dark: dark).setFill()
            NSBezierPath(rect: line).fill()
        }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        if pressed { context.cgContext.setAlpha(0.6) }
        let color = fold.color.resolved(dark: dark)
        let attributes: [NSAttributedString.Key: Any] = [.font: fold.font.nsFont, .foregroundColor: color]
        let size = (label as NSString).size(withAttributes: attributes)
        let width = size.width + footerChevronGap + fold.chevronSize
        let border = style.box.border?.width ?? 0
        var x = fold.alignment == .center ? footer.midX - width / 2 : footer.minX + border + (style.box.rule?.width ?? 0) + fold.inset
        let symbol = folded ? "chevron.down" : "chevron.up"
        let middle = footer.midY + (geometry.footerSeparator == nil ? 0 : 0.5)
        func chevron() {
            drawSymbol(symbol, in: NSRect(x: x, y: middle - fold.chevronSize / 2, width: fold.chevronSize, height: fold.chevronSize), color: color)
            x += fold.chevronSize + footerChevronGap
        }
        if fold.template == .moreCount { chevron() }
        (label as NSString).draw(at: NSPoint(x: x, y: middle - size.height / 2), withAttributes: attributes)
        x += size.width + footerChevronGap
        if fold.template == .totalCount { chevron() }
    }

    static let footerChevronGap: CGFloat = 4

    static func drawChip(_ rect: NSRect, chip: ResultStyle.InlineChip, dark: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: chip.radius, yRadius: chip.radius)
        if let fill = chip.fill {
            fill.resolved(dark: dark).setFill()
            path.fill()
        }
        if let border = chip.border {
            let inset = border.width / 2
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: chip.radius, yRadius: chip.radius)
            outline.lineWidth = border.width
            border.color.resolved(dark: dark).setStroke()
            outline.stroke()
        }
    }

    // MARK: - After links

    /// The kern a link's last character gets for its ↗ and source pill.
    static func adornmentWidth(host: String?, arrow: Bool, style: ResultStyle) -> CGFloat {
        adornmentWidth(pillWidth: host.map { pillWidth(host: $0, pill: style.pill) }, arrow: arrow, style: style)
    }

    /// The same for a pill already measured, or none.
    static func adornmentWidth(pillWidth: CGFloat?, arrow: Bool, style: ResultStyle) -> CGFloat {
        let pill = style.pill
        return (arrow ? arrowWidth : 0) + (pillWidth.map { pill.leading + $0 + pill.trailing } ?? 0)
    }

    static func pillWidth(host: String, pill: ResultStyle.SourcePill) -> CGFloat {
        let text = (host as NSString).size(withAttributes: [.font: pill.font.nsFont]).width
        return ceil(pill.padding + pill.iconSize + pill.gap + text + pill.padding)
    }

    static func drawPill(host: String, in rect: NSRect, pill: ResultStyle.SourcePill, dark: Bool, dimmed: Bool) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        if dimmed { context.cgContext.setAlpha(0.5) }
        pill.fill.resolved(dark: dark).setFill()
        NSBezierPath(roundedRect: rect, xRadius: pill.radius, yRadius: pill.radius).fill()
        let color = pill.text.resolved(dark: dark)
        drawSymbol("globe", in: NSRect(x: rect.minX + pill.padding, y: rect.midY - pill.iconSize / 2, width: pill.iconSize, height: pill.iconSize),
                   color: color)
        let attributes: [NSAttributedString.Key: Any] = [.font: pill.font.nsFont, .foregroundColor: color]
        let size = (host as NSString).size(withAttributes: attributes)
        (host as NSString).draw(at: NSPoint(x: rect.minX + pill.padding + pill.iconSize + pill.gap, y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }

    /// An SF Symbol fitted into `rect` in one color.
    static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.85, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height, 1)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
