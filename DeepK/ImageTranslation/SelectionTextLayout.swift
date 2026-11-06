#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import SwiftUI

struct SelectionInlineImage: @unchecked Sendable {
    let id: Int
    let offset: Int
    let size: CGSize
    let pixels: CGImage?
}

struct SelectionTextLayout: Sendable, Equatable {
    struct Part: Sendable, Equatable { let id: Int; let source: String }
    enum Node: Sendable, Equatable { case text(Part), icon(Int) }
    let nodes: [Node]
    var parts: [Part] { nodes.compactMap { if case .text(let part) = $0 { return part }; return nil } }
    var regions: [ImageTextRegion] { parts.filter { !$0.source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.map { ImageTextRegion(id:$0.id,text:$0.source,box:.zero) } }
    init(text: String, icons: [SelectionInlineImage] = []) {
        let value = text as NSString
        var nodes: [Node] = [], position = 0, ordinal = 0
        for icon in icons.sorted(by: { $0.offset == $1.offset ? $0.id < $1.id : $0.offset < $1.offset }) {
            let end = max(position,min(value.length,icon.offset))
            if end > position { nodes.append(.text(.init(id:ordinal == 0 ? 0 : 100000 + ordinal,source:value.substring(with:NSRange(location:position,length:end-position)))));ordinal += 1 }
            nodes.append(.icon(icon.id));position = end
        }
        if position < value.length { nodes.append(.text(.init(id:ordinal == 0 ? 0 : 100000 + ordinal,source:value.substring(from:position)))) }
        self.nodes = nodes
    }
    func translatedText(_ values: [Int:String], pending: String? = nil) -> String {
        parts.map { part in Self.display(part,translation:values[part.id],pending:pending) }.joined()
    }
    static func display(_ part: Part, translation: String?, pending: String?) -> String {
        guard let translation else { return pending ?? part.source }
        let prefix = String(part.source.prefix(while: { $0.isWhitespace }))
        let suffix = String(part.source.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return prefix + translation.trimmingCharacters(in:.whitespacesAndNewlines) + suffix
    }
}

@MainActor struct SelectionTextView: View {
    let layout: SelectionTextLayout
    let icons: [SelectionInlineImage]
    var translations: [Int:String]?
    var body: some View {
        ScrollView {
            content.font(.system(size:16)).textSelection(.enabled)
                .frame(maxWidth:.infinity,alignment:.leading).padding(12)
        }
    }
    private var content: Text {
        var result = Text("")
        for node in layout.nodes {
            let part: Text
            switch node {
            case .text(let value):
                part = Text(translations.map { SelectionTextLayout.display(value,translation:$0[value.id],pending:"…") } ?? value.source)
            case .icon(let id):
                guard let icon = icons.first(where:{$0.id == id}) else { continue }
                part = Text(Image(nsImage:Self.iconImage(icon))).baselineOffset(-3)
            }
            result = Text("\(result)\(part)")
        }
        return result
    }
    static func iconImage(_ icon:SelectionInlineImage) -> NSImage {
        let image = icon.pixels.map { NSImage(cgImage:$0,size:icon.size) } ?? NSImage(systemSymbolName:"photo",accessibilityDescription:"읽지 못한 아이콘")!
        image.size = icon.size
        return image
    }
}
#endif
