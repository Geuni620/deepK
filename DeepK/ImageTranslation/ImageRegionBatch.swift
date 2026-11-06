#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import Foundation

/// Independent OCR blocks, deliberately different from the text translator's link markup.
struct NativeImageRegionBatch: Sendable {
    struct Draft: Equatable { let id: Int; let text: String }
    private static let completed = try! NSRegularExpression(pattern: #"<r([0-9]+)>([\s\S]*?)</r\1>"#)
    private static let opening = try! NSRegularExpression(pattern: #"<r([0-9]+)>"#)
    let regions: [ImageTextRegion]
    var payload: String { regions.map { "<r\($0.id)>\(Self.escape($0.text))</r\($0.id)>" }.joined(separator: "\n\n") }
    static func make(_ regions: [ImageTextRegion], limit: Int = 3800) throws -> [Self] {
        var result: [Self] = [], current: [ImageTextRegion] = []
        for region in regions {
            guard Self(regions: [region]).payload.count <= limit else { throw ImagePOCError.message("한 문단이 너무 깁니다. 영역을 나누어 다시 읽어 주세요.") }
            if Self(regions: current + [region]).payload.count > limit { result.append(Self(regions: current)); current = [] }
            current.append(region)
        }
        if !current.isEmpty { result.append(Self(regions: current)) }
        return result
    }
    /// Closed, uniquely identified blocks can be shown even when other blocks are absent or still streaming.
    func completedTranslations(in response: String) -> [Int: String] {
        let value = response as NSString
        let wanted = Set(regions.map(\.id))
        var found: [Int: String] = [:], duplicates = Set<Int>()
        for match in Self.completed.matches(in: response, range: NSRange(location: 0, length: value.length)) {
            guard let id = Int(value.substring(with: match.range(at: 1))), wanted.contains(id) else { continue }
            let text = Self.unescape(value.substring(with: match.range(at: 2))).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.contains("<r"), !text.contains("</r") else { continue }
            if found[id] != nil { duplicates.insert(id) }
            found[id] = text
        }
        for id in duplicates { found[id] = nil }
        return found
    }
    /// A real open block can be previewed as text while its final image layout is still pending.
    func draft(in response: String) -> Draft? {
        let value = response as NSString
        guard let match = Self.opening.matches(in: response, range: NSRange(location: 0, length: value.length)).last,
              let id = Int(value.substring(with: match.range(at: 1))), regions.contains(where: { $0.id == id }) else { return nil }
        let remainder = value.substring(from: match.range.location + match.range.length)
        guard !remainder.contains("</r\(id)>") else { return nil }
        let text = Self.unescape(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("<r"), !text.contains("</r") else { return nil }
        return Draft(id: id, text: String(text.suffix(160)))
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
}
#endif
