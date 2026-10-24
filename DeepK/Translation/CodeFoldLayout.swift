import AppKit

/// How one code block folds. Folding is layout only: the storage keeps every character, so ⌘C, drag, Services, the copy
/// button, insertion, the block's copy control and VoiceOver all get the whole code.
struct CodeFoldPlan: Equatable {
    /// Lines in the block, not counting the break after its last line.
    let lineCount: Int
    /// Lines up to the last one with more than whitespace; only these count toward the limit, so blank lines at the end
    /// of a fence never make a footer that shows nothing.
    let contentLineCount: Int
    /// Lines a folded block shows, or nil with 긴 코드 접기 off.
    let limit: Int?
    let expanded: Bool
    /// What is not laid out: the lines after the limit with their breaks, to the block's end. The break that ends the last
    /// shown line stays, so that line keeps its own paragraph.
    let hidden: NSRange?

    static let unfolded = CodeFoldPlan(lineCount: 1, contentLineCount: 1, limit: nil, expanded: false, hidden: nil)

    /// A block with more lines of content than the limit has a footer, folded or expanded.
    var hasFooter: Bool { limit.map { contentLineCount > $0 } ?? false }
    var isFolded: Bool { hidden != nil }
    var hiddenLineCount: Int { limit.map { max(0, lineCount - $0) } ?? 0 }
    /// The break that ends the last shown line of a folded block.
    var lastShown: Int? { hidden.map { $0.location - 1 } }
}

enum CodeFold {
    /// The fold for a block in `text`: folded when it has more than `limit` lines and the reader has not expanded it.
    /// A single long line never folds; lines are counted by their breaks. Blank lines at the block's end do not count
    /// toward the limit; when a block folds they are hidden with the lines before them.
    static func plan(block: NSRange, in text: NSString, limit: Int?, expanded: Bool) -> CodeFoldPlan {
        let end = min(NSMaxRange(block), text.length)
        var lines = 1, contentLines = 0
        var lineHasContent = false
        var hiddenStart: Int?
        for index in block.location..<max(block.location, end - 1) {
            let character = text.character(at: index)
            if character == 0x0A {
                if lineHasContent { contentLines = lines }
                lines += 1
                lineHasContent = false
                if let limit, lines == limit + 1 { hiddenStart = index + 1 }
            } else if !lineHasContent, !(character == 0x20 || character == 0x09 || character == 0x0D) {
                lineHasContent = true
            }
        }
        // The last line, unless it is only its break.
        if lineHasContent || (end > block.location && ![0x0A, 0x0D, 0x20, 0x09].contains(text.character(at: end - 1))) {
            contentLines = lines
        }
        let folds = limit.map { contentLines > $0 } == true && !expanded
        return CodeFoldPlan(lineCount: lines, contentLineCount: contentLines, limit: limit, expanded: expanded,
                            hidden: folds ? hiddenStart.map { NSRange(location: $0, length: end - $0) } : nil)
    }

    /// The footer's words: "12줄 모두 보기" (Native) or "2줄 더 보기" (GitHub) while folded, "접기" while expanded.
    static func footerLabel(_ plan: CodeFoldPlan, style: ResultStyle) -> String {
        guard plan.isFolded else { return "접기" }
        return switch style.fold.template {
        case .totalCount: "\(plan.lineCount)줄 모두 보기"
        case .moreCount: "\(plan.hiddenLineCount)줄 더 보기"
        }
    }
}

/// Lays out folded code as nothing (`.deepKCodeFolded`): its glyphs draw nothing and take no width, its lines take no
/// height, and its last line becomes the room for the box's bottom, footer and margin (`.deepKFoldSpacer`). Only glyphs
/// and line fragments change, never characters, so the result view's offsets, selection and streaming hold.
/// Stateless; it reads the attributes from the layout manager's storage.
final class CodeFoldLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    /// Folded characters become control characters, which the next method lays out with no advance. Line breaks stay
    /// breaks, so every hidden line is its own fragment however long it is.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        var changed: [NSLayoutManager.GlyphProperty]?
        for offset in 0..<glyphRange.length where storage.attribute(.deepKCodeFolded, at: characterIndexes[offset], effectiveRange: nil) != nil {
            if changed == nil { changed = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)) }
            changed?[offset] = .controlCharacter
        }
        guard let changed else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length,
              storage.attribute(.deepKCodeFolded, at: charIndex, effectiveRange: nil) != nil else { return action }
        let character = (storage.string as NSString).character(at: charIndex)
        return character == 0x0A || character == 0x0D ? action : .zeroAdvancement
    }

    /// A fragment of folded characters only takes no room, except the block's last one, which takes its spacer.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard let storage = layoutManager.textStorage else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characters.length > 0, NSMaxRange(characters) <= storage.length else { return false }
        var run = NSRange()
        guard storage.attribute(.deepKCodeFolded, at: characters.location, longestEffectiveRange: &run, in: characters) != nil,
              run == characters else { return false }
        let spacer = storage.attribute(.deepKFoldSpacer, at: NSMaxRange(characters) - 1, effectiveRange: nil) as? CGFloat ?? 0
        lineFragmentRect.pointee.size.height = spacer
        lineFragmentUsedRect.pointee = NSRect(x: lineFragmentRect.pointee.minX, y: lineFragmentRect.pointee.minY, width: 0, height: 0)
        baselineOffset.pointee = 0
        return true
    }
}

/// Draws only what is not folded. Hidden glyphs take no room but their zero-height fragments all sit at the footer's
/// height, so a redraw there asks for every one of them; a long folded block would draw its hidden lines on every
/// pointer move, copy mark and streamed chunk. Layout is the delegate's and does not change here.
final class CodeFoldLayoutManager: NSLayoutManager {
    /// Glyphs handed to TextKit's drawing; tests check a long folded block draws only its shown lines.
    private(set) var drawnGlyphs = 0

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        forEachShownPart(of: glyphsToShow) { part in
            drawnGlyphs += part.length
            super.drawGlyphs(forGlyphRange: part, at: origin)
        }
    }

    /// The glyph runs of `glyphs` outside folded characters, found by attribute run, never glyph by glyph.
    private func forEachShownPart(of glyphs: NSRange, _ body: (NSRange) -> Void) {
        guard let storage = textStorage, glyphs.length > 0 else { return body(glyphs) }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard NSMaxRange(characters) <= storage.length else { return body(glyphs) }
        storage.enumerateAttribute(.deepKCodeFolded, in: characters) { value, run, _ in
            guard value == nil else { return }
            let part = NSIntersectionRange(glyphRange(forCharacterRange: run, actualCharacterRange: nil), glyphs)
            if part.length > 0 { body(part) }
        }
    }
}

extension NSAttributedString.Key {
    /// A character of a folded block that is not laid out.
    static let deepKCodeFolded = NSAttributedString.Key("deepK.codeFolded")
    /// On a folded block's last character: the height its line takes instead (CGFloat).
    static let deepKFoldSpacer = NSAttributedString.Key("deepK.foldSpacer")
}
