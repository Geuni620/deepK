#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import ImageIO
import Vision

enum ImagePOCError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}

/// Image names and pixels stay on the input/display side. Only `NativeImageRegionBatch.payload` reaches a provider.
struct POCImage: @unchecked Sendable {
    let pixels: CGImage
    let name: String
    var size: CGSize { CGSize(width: pixels.width, height: pixels.height) }

    static func file(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw ImagePOCError.message("이 Mac에 있는 이미지 파일을 선택해 주세요.") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 30_000_000 else {
            throw ImagePOCError.message("30MB 이하의 이미지 파일을 선택해 주세요.")
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe), name: url.lastPathComponent)
    }

    static func decode(_ data: Data, name: String) throws -> Self {
        guard data.count <= 30_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 40_000_000,
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3200
              ] as CFDictionary) else {
            throw ImagePOCError.message("이미지를 읽지 못했습니다. 30MB·4천만 화소 이하의 PNG, JPEG, HEIC 등을 사용해 주세요.")
        }
        return Self(pixels: pixels, name: name)
    }

    @MainActor static func clipboard(_ board: NSPasteboard) throws -> Self {
        guard !isConcealed(board) else {
            throw ImagePOCError.message("민감·임시 항목으로 표시된 클립보드는 읽지 않습니다.")
        }
        let version = board.changeCount
        let image: Self
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            image = try decode(data, name: "클립보드 이미지")
        } else if let value = board.string(forType: .fileURL), let url = URL(string: value), url.isFileURL {
            image = try file(url)
        } else {
            throw ImagePOCError.message("복사된 이미지가 없습니다. 이미지 파일을 놓거나 ‘이미지 복사’ 후 붙여넣어 주세요.")
        }
        guard board.changeCount == version, !isConcealed(board) else {
            throw ImagePOCError.message("복사한 내용이 바뀌었거나 민감 항목으로 표시되었습니다. 다시 복사해 주세요.")
        }
        return image
    }

    @MainActor static func isConcealed(_ board: NSPasteboard) -> Bool {
        let sensitive: Set<NSPasteboard.PasteboardType> = [
            .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType")
        ]
        return board.pasteboardItems?.contains { !sensitive.isDisjoint(with: $0.types) } ?? false
    }
}

struct ImageTextRegion: Sendable, Equatable, Identifiable {
    let id: Int
    let text: String
    /// Vision coordinates: normalized, lower-left origin. They never leave this process.
    let box: CGRect
    let lineBoxes: [CGRect]
    let isMetadata: Bool
    init(id: Int, text: String, box: CGRect, lineBoxes: [CGRect]? = nil, isMetadata: Bool = false) {
        self.id = id; self.text = text; self.box = box; self.lineBoxes = lineBoxes ?? [box]; self.isMetadata = isMetadata
    }
}

enum POCTextRecognition {
    struct Word { let text: String; let box: CGRect }
    struct Line { let text: String; let box: CGRect; var words: [Word] = [] }
    private static let tokens = try! NSRegularExpression(pattern: #"\S+"#)
    private static let timestamp = try! NSRegularExpression(pattern: #"(?<![0-9])(?:[01]?[0-9]|2[0-3])[:：][0-5][0-9](?:\s?[AaPp][Mm])?\s*$"#)

    static func recognize(_ image: POCImage) throws -> [ImageTextRegion] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        // Korean-first also recognizes English; English-first missed Korean in the mixed synthetic fixture.
        request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
        try VNImageRequestHandler(cgImage: image.pixels, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            guard
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let mayHaveBadge = text.first.map { ["©", "®", "ⓒ", "@"].contains(String($0)) } ?? false
            var ranges = (mayHaveBadge ? tokens.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) : []).compactMap { Range($0.range, in: text) }
            if let first = ranges.first, text.distance(from: first.lowerBound, to: first.upperBound) > 1 {
                let end = text.index(after: first.lowerBound)
                ranges.replaceSubrange(0...0, with: [first.lowerBound..<end, end..<first.upperBound])
            }
            let words = ranges.compactMap { range -> Word? in
                guard let rectangle = try? candidate.boundingBox(for: range) else { return nil }
                return Word(text: String(text[range]), box: rectangle.boundingBox)
            }
            return Line(text: text, box: observation.boundingBox, words: words)
        }
        return try regions(from: lines)
    }

    static func regions(from input: [Line]) throws -> [ImageTextRegion] {
        func hasLettersOrDigits(_ text: String) -> Bool { text.contains { $0.isLetter || $0.isNumber } }
        let clockRows = input.filter { timestamp.firstMatch(in: $0.text, range: NSRange(location: 0, length: ($0.text as NSString).length)) != nil }
        func sameRow(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.midY - b.midY) < max(a.height, b.height) * 0.5 }
        let lines = input.compactMap { line -> (String, CGRect, Bool)? in
            let isHeader = hasLettersOrDigits(line.text) && clockRows.contains { sameRow(line.box, $0.box) }
            let nearbyHeader = clockRows.filter { $0.box.midY >= line.box.midY - line.box.height * 0.5 && $0.box.midY - line.box.midY < 0.35 }
                .min { abs($0.box.midY - line.box.midY) < abs($1.box.midY - line.box.midY) }
            if let header = nearbyHeader, !line.words.isEmpty {
                let anchors = input.filter { hasLettersOrDigits($0.text) && sameRow($0.box, header.box) }.map { $0.box.minX }
                if let left = anchors.min() {
                    let graphicSymbols: Set<String> = ["©", "®", "ⓒ", "@"]
                    let kept = line.words.filter { !graphicSymbols.contains($0.text) || $0.box.maxX > left }
                    if kept.isEmpty { return nil }
                    if kept.count != line.words.count {
                        return (kept.map(\.text).joined(separator: " "), kept.map(\.box).reduce(CGRect.null) { $0.union($1) }, isHeader)
                    }
                }
            }
            return (line.text, line.box, isHeader)
        }.sorted {
            if abs($0.1.midY - $1.1.midY) < min($0.1.height, $1.1.height) * 0.5 { return $0.1.minX < $1.1.minX }
            return $0.1.midY > $1.1.midY
        }
        guard !lines.isEmpty else { throw ImagePOCError.message("이미지에서 글자를 찾지 못했습니다. 글자가 더 크게 보이는 이미지를 사용해 주세요.") }
        guard lines.count <= 160 else { throw ImagePOCError.message("글자가 많습니다. 번역할 부분을 나누어 가져와 주세요. 한 번에 160줄까지 처리합니다.") }

        // Metadata rows use different typography and must never be merged with a chat message.
        var paragraphs: [(text: String, box: CGRect, last: CGRect, lines: [CGRect], metadata: Bool)] = []
        for (text, box, metadata) in lines {
            let candidate = paragraphs.indices.filter { index in
                let previous = paragraphs[index]
                guard !metadata, !previous.metadata else { return false }
                let gap = previous.last.minY - box.maxY
                let height = max(previous.last.height, box.height)
                let tolerance = max(0.008, height * 0.45)
                let aligned = min(abs(previous.last.minX - box.minX), abs(previous.last.midX - box.midX), abs(previous.last.maxX - box.maxX)) < tolerance
                let overlap = min(previous.last.maxX, box.maxX) - max(previous.last.minX, box.minX)
                let similarHeight = min(previous.last.height, box.height) > height * 0.65
                return aligned && overlap > min(previous.last.width, box.width) * 0.5 && similarHeight && gap >= -height * 0.15 && gap < height * 0.9
            }.min { paragraphs[$0].last.minY - box.maxY < paragraphs[$1].last.minY - box.maxY }
            if let index = candidate {
                let previous = paragraphs[index]
                paragraphs[index] = (previous.text + "\n" + text, previous.box.union(box), box, previous.lines + [box], false)
                continue
            }
            paragraphs.append((text, box, box, [box], metadata))
        }
        return paragraphs.enumerated().map { ImageTextRegion(id: $0.offset + 1, text: $0.element.text, box: $0.element.box, lineBoxes: $0.element.lines, isMetadata: $0.element.metadata) }
    }
}
#endif
