#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import CoreML
import CoreText

enum ImageRenderIssue: String, Sendable {
    case background, layout, collision
    var explanation: String {
        switch self {
        case .background: "배경과 글자를 안전하게 분리하지 못해"
        case .layout: "번역문을 넣을 공간이 부족해"
        case .collision: "다른 글자 영역과 겹칠 수 있어"
        }
    }
}

struct NaturalImageRender: @unchecked Sendable {
    let image: CGImage
    let renderedIDs: Set<Int>
    let keptOriginalIDs: Set<Int>
    let issues: [Int: ImageRenderIssue]
    /// Pixel coordinates, upper-left origin. Memory-only, for display and synthetic layout checks.
    let placements: [Int: CGRect]
}

/// Local, memory-only restoration. Original pixels remain immutable; rejected blocks stay original.
final class NaturalImageRenderer: @unchecked Sendable {
    private let width: Int, height: Int
    private let original: [UInt8]
    private let regions: [ImageTextRegion]
    private let inpainter = LocalImageInpainter()
    private let lock = NSLock()
    private var cached: [Int: Patch] = [:]
    private struct RGB { var r: Double; var g: Double; var b: Double }
    private struct Sample { let x: Double; let y: Double; let color: RGB }
    private struct Plane {
        let r: [Double], g: [Double], b: [Double]
        func color(_ x: Double, _ y: Double) -> RGB {
            RGB(r: r[0] + r[1] * x + r[2] * y, g: g[0] + g[1] * x + g[2] * y, b: b[0] + b[1] * x + b[2] * y)
        }
    }
    private struct Patch {
        let rect: CGRect
        let bytes: [UInt8]
        let mask: [UInt8]
        let foreground: RGB
        let lineHeight: CGFloat
        let simple: Bool
        let coverage: Double
        let background: Plane
        let inkLines: [CGRect]
    }

    init(image: CGImage, regions: [ImageTextRegion]) throws {
        let width = image.width, height = image.height
        self.width = width; self.height = height; self.regions = regions
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Self.bitmapInfo) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ImagePOCError.message("이미지 표시를 준비하지 못했습니다.") }
        original = bytes
    }

    func render(_ translations: [Int: String]) throws -> NaturalImageRender {
        var output = original
        var rendered = Set<Int>(), kept = Set<Int>()
        var issues: [Int: ImageRenderIssue] = [:], placements: [Int: CGRect] = [:]
        // Rendering and erasure are committed together, after layout has passed. Never erase an untranslated block.
        for region in regions {
            try Task.checkCancellation()
            guard let text = translations[region.id], !text.isEmpty else { continue }
            let sourceKey = Self.identity(region.text, metadata: region.isMetadata)
            if Self.identity(text, metadata: region.isMetadata) == sourceKey {
                // Preserve exact author/time typography rather than repainting an unchanged label.
                rendered.insert(region.id); placements[region.id] = pixelRect(region.box); continue
            }
            let restored: Patch?
            do { restored = try patch(for: region) }
            catch is CancellationError { throw CancellationError() }
            catch { kept.insert(region.id); issues[region.id] = .background; continue }
            guard let patch = restored else { kept.insert(region.id); issues[region.id] = .background; continue }
            guard let layout = layout(text: text, region: region, patch: patch) else {
                kept.insert(region.id); issues[region.id] = .layout; continue
            }
            let neighbors = regions.filter { $0.id != region.id }.map { pixelRect($0.box).insetBy(dx: 0.5, dy: 0.5) }
            if layout.inkLines.contains(where: { ink in neighbors.contains { $0.intersects(ink) } }) {
                kept.insert(region.id); issues[region.id] = .collision; continue
            }
            let px = Int(patch.rect.minX), py = Int(patch.rect.minY), pw = Int(patch.rect.width), ph = Int(patch.rect.height)
            for y in 0..<ph { for x in 0..<pw where patch.mask[y * pw + x] != 0 {
                let source = (y * pw + x) * 4, destination = ((py + y) * width + px + x) * 4
                output[destination] = patch.bytes[source]; output[destination + 1] = patch.bytes[source + 1]
                output[destination + 2] = patch.bytes[source + 2]
            } }
            output.withUnsafeMutableBytes { raw in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Self.bitmapInfo) else { return }
                context.saveGState(); context.clip(to: layout.clip)
                context.textMatrix = .identity
                context.translateBy(x: layout.offsetX, y: layout.offsetY)
                CTFrameDraw(layout.frame, context)
                context.restoreGState()
            }
            rendered.insert(region.id)
            placements[region.id] = layout.inkLines.reduce(CGRect.null) { $0.union($1) }
        }
        guard let image = Self.image(output, width: width, height: height) else { throw ImagePOCError.message("번역 이미지를 만들지 못했습니다.") }
        return NaturalImageRender(image: image, renderedIDs: rendered, keptOriginalIDs: kept, issues: issues, placements: placements)
    }

    private static func identity(_ text: String, metadata: Bool) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return metadata ? words.joined().lowercased() : words.joined(separator: " ")
    }

    private func pixelRect(_ box: CGRect) -> CGRect {
        CGRect(x: floor(box.minX * CGFloat(width)), y: floor((1 - box.maxY) * CGFloat(height)),
               width: ceil(box.width * CGFloat(width)), height: ceil(box.height * CGFloat(height)))
    }
    private func color(_ x: Int, _ y: Int) -> RGB {
        let i = (min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))) * 4
        return RGB(r: Double(original[i]), g: Double(original[i + 1]), b: Double(original[i + 2]))
    }
    private static func distance(_ a: RGB, _ b: RGB) -> Double { sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2)) }
    private static func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }

    private func patch(for region: ImageTextRegion) throws -> Patch? {
        if let value = lock.withLock({ cached[region.id] }) { return value }
        let lines = region.lineBoxes.map(pixelRect)
        let lineHeight = lines.map(\.height).sorted()[lines.count / 2]
        let padding = max(3, ceil(lineHeight * 0.25))
        let rect = pixelRect(region.box).insetBy(dx: -padding, dy: -padding).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        let x0 = Int(rect.minX), y0 = Int(rect.minY), pw = Int(rect.width), ph = Int(rect.height)
        guard pw > 0, ph > 0 else { return nil }
        var samples: [Sample] = []
        let step = max(1, Int(max(rect.width, rect.height) / 160))
        for y in stride(from: y0, to: y0 + ph, by: step) { for x in stride(from: x0, to: x0 + pw, by: step) {
            if x < x0 + 2 || x >= x0 + pw - 2 || y < y0 + 2 || y >= y0 + ph - 2 {
                samples.append(Sample(x: Double(x - x0) / Double(pw), y: Double(y - y0) / Double(ph), color: color(x, y)))
            }
        } }
        guard var plane = Self.fit(samples) else { return nil }
        var residual: [Double] = []
        for _ in 0..<2 {
            residual = samples.map { Self.distance($0.color, plane.color($0.x, $0.y)) }.sorted()
            let cutoff = max(7, (residual.isEmpty ? 0 : residual[residual.count / 2]) * 2.5)
            let filtered = samples.filter { Self.distance($0.color, plane.color($0.x, $0.y)) <= cutoff }
            if let next = Self.fit(filtered) { plane = next }
        }
        let simple = !residual.isEmpty && residual[residual.count / 2] < 7 && residual[Int(Double(residual.count - 1) * 0.9)] < 16
        var mask = [UInt8](repeating: 0, count: pw * ph)
        var foreground: [(Double, RGB)] = []
        var inkLines: [CGRect] = []
        var inkCount = 0, textArea = 0
        for line in lines {
            let area = line.insetBy(dx: -max(2, lineHeight * 0.12), dy: -max(2, lineHeight * 0.18)).integral.intersection(rect)
            var ink = CGRect.null
            for y in Int(area.minY)..<Int(area.maxY) { for x in Int(area.minX)..<Int(area.maxX) {
                let p = color(x, y), bg = plane.color(Double(x - x0) / Double(pw), Double(y - y0) / Double(ph))
                let d = Self.distance(p, bg)
                textArea += 1
                if d > 22 { foreground.append((d, p)); inkCount += 1; ink = ink.union(CGRect(x: x, y: y, width: 1, height: 1)) }
                if !simple || d > 11 { mask[(y - y0) * pw + x - x0] = 1 }
            } }
            inkLines.append(simple && !ink.isNull ? ink : line)
        }
        guard !foreground.isEmpty else { return nil }
        let sorted = foreground.sorted { $0.0 > $1.0 }.prefix(max(1, foreground.count / 3)).map(\.1)
        let fg = RGB(r: sorted.map(\.r).sorted()[sorted.count / 2], g: sorted.map(\.g).sorted()[sorted.count / 2], b: sorted.map(\.b).sorted()[sorted.count / 2])
        if simple {
            let before = mask
            for y in 1..<max(1, ph - 1) { for x in 1..<max(1, pw - 1) where before[y * pw + x] != 0 {
                for dy in -1...1 { for dx in -1...1 { mask[(y + dy) * pw + x + dx] = 1 } }
            } }
        }
        var bytes = [UInt8](repeating: 0, count: pw * ph * 4)
        for y in 0..<ph { for x in 0..<pw {
            let i = (y * pw + x) * 4
            let c = simple ? plane.color(Double(x) / Double(pw), Double(y) / Double(ph)) : color(x0 + x, y0 + y)
            bytes[i] = Self.byte(c.r); bytes[i + 1] = Self.byte(c.g); bytes[i + 2] = Self.byte(c.b); bytes[i + 3] = 255
        } }
        if !simple {
            guard let restored = try inpainter.restore(original: original, width: width, height: height, rect: rect, mask: mask) else { return nil }
            bytes = restored
        }
        let actualHeights = inkLines.map(\.height).sorted()
        let result = Patch(rect: rect, bytes: bytes, mask: mask, foreground: fg, lineHeight: actualHeights[actualHeights.count / 2],
                           simple: simple, coverage: Double(inkCount) / Double(max(1, textArea)), background: plane, inkLines: inkLines)
        lock.withLock { cached[region.id] = result }
        return result
    }

    private struct Layout {
        let frame: CTFrame
        let offsetX: CGFloat
        let offsetY: CGFloat
        let clip: CGRect
        let inkLines: [CGRect]
    }
    private func layout(text: String, region: ImageTextRegion, patch: Patch) -> Layout? {
        let sourceLine = region.text.components(separatedBy: "\n").first ?? region.text
        let weight: NSFont.Weight = patch.coverage > 0.38 ? .semibold : .regular
        let unitFont = NSFont.systemFont(ofSize: 100, weight: weight)
        let unitLine = CTLineCreateWithAttributedString(NSAttributedString(string: sourceLine, attributes: [.font: unitFont]))
        let unitBounds = CTLineGetImageBounds(unitLine, nil)
        guard unitBounds.height > 0 else { return nil }
        let startSize = patch.lineHeight * 100 / unitBounds.height
        let sourceBox = pixelRect(region.box), boxes = patch.inkLines
        let firstInk = boxes.first ?? sourceBox
        // Never derive the text column from unrelated pixels picked up by an expanded erasure mask.
        let anchorX = max(sourceBox.minX, min(firstInk.minX, sourceBox.minX + max(2, patch.lineHeight * 0.25)))
        let centered = boxes.count > 1 && boxes.allSatisfy { abs($0.midX - sourceBox.midX) < patch.lineHeight * 0.3 }
        let gaps = zip(boxes, boxes.dropFirst()).map { $1.minY - $0.minY }.filter { $0 > 0 }.sorted()
        let spacing = gaps.isEmpty ? startSize * 1.25 : max(patch.lineHeight, gaps[gaps.count / 2])
        let padding = max(3, patch.lineHeight * 0.25)
        var room = CGRect(x: centered ? sourceBox.minX - padding : sourceBox.minX,
                          y: max(0, sourceBox.minY - padding),
                          width: sourceBox.width + (centered ? padding * 2 : padding), height: sourceBox.height + padding * 2)
        let neighbors = regions.filter { $0.id != region.id }.map { pixelRect($0.box) }
        func backgroundMatches(_ x: Int, _ y: Int) -> Bool {
            let predicted = patch.background.color((Double(x) - patch.rect.minX) / patch.rect.width,
                                                    (Double(y) - patch.rect.minY) / patch.rect.height)
            return Self.distance(color(x, y), predicted) < 16
        }
        if patch.simple {
            let band = sourceBox.insetBy(dx: 0, dy: -padding)
            let rightNeighbor = neighbors.filter { $0.minX >= sourceBox.maxX && $0.intersects(band) }.map(\.minX).min() ?? CGFloat(width)
            let rightLimit = min(CGFloat(width - 1), sourceBox.maxX + patch.lineHeight * 5, rightNeighbor - 3)
            for x in stride(from: Int(ceil(room.maxX)), to: Int(max(room.maxX, rightLimit)), by: 2) {
                let clear = stride(from: max(0, Int(room.minY)), to: min(height, Int(ceil(room.maxY))), by: 2).allSatisfy { backgroundMatches(x, $0) }
                if !clear { break }
                room.size.width = CGFloat(x + 1) - room.minX
            }
            if centered {
                let leftNeighbor = neighbors.filter { $0.maxX <= sourceBox.minX && $0.intersects(band) }.map(\.maxX).max() ?? 0
                let leftLimit = max(0, sourceBox.minX - patch.lineHeight * 5, leftNeighbor + 3)
                for x in stride(from: Int(floor(room.minX)) - 1, through: Int(ceil(leftLimit)), by: -2) {
                    let clear = stride(from: max(0, Int(room.minY)), to: min(height, Int(ceil(room.maxY))), by: 2).allSatisfy { backgroundMatches(x, $0) }
                    if !clear { break }
                    let right = room.maxX; room.origin.x = CGFloat(x); room.size.width = right - room.minX
                }
            }
            // One extra line is allowed only in verified empty background before the next message.
            let below = neighbors.filter { $0.minY >= sourceBox.maxY && $0.maxX > room.minX && $0.minX < room.maxX }.map(\.minY).min() ?? CGFloat(height)
            let bottomLimit = min(CGFloat(height - 1), room.maxY + spacing, below - 3)
            for y in stride(from: Int(ceil(room.maxY)), to: Int(max(room.maxY, bottomLimit)), by: 1) {
                let clear = stride(from: max(0, Int(room.minX)), to: min(width, Int(ceil(room.maxX))), by: 2).allSatisfy { backgroundMatches($0, y) }
                if !clear { break }
                room.size.height = CGFloat(y + 1) - room.minY
            }
        }
        room = room.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !room.isEmpty else { return nil }
        let clip = CGRect(x: room.minX, y: CGFloat(height) - room.maxY, width: room.width, height: room.height)
        var size = startSize
        while size >= startSize * 0.85 - 0.01 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = centered ? .center : .left
            paragraph.lineBreakStrategy = .hangulWordPriority
            paragraph.minimumLineHeight = spacing; paragraph.maximumLineHeight = spacing
            let string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(calibratedRed: patch.foreground.r / 255, green: patch.foreground.g / 255, blue: patch.foreground.b / 255, alpha: 1),
                .paragraphStyle: paragraph
            ])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let typesettingBox = CGRect(x: clip.minX, y: clip.minY, width: clip.width, height: clip.height + startSize * 3)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: string.length), CGPath(rect: typesettingBox, transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame), lines = CTFrameGetLines(frame) as! [CTLine]
            guard !lines.isEmpty else { return nil }
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            let first = CTLineGetImageBounds(lines[0], nil)
            let shiftX = centered ? firstInk.midX - (clip.minX + origins[0].x + first.midX) : anchorX - (clip.minX + origins[0].x + first.minX)
            let shiftY = CGFloat(height) - firstInk.minY - (clip.minY + origins[0].y + first.maxY)
            let ink = lines.indices.map { index in
                CTLineGetImageBounds(lines[index], nil).offsetBy(dx: clip.minX + origins[index].x + shiftX, dy: clip.minY + origins[index].y + shiftY)
            }
            if visible.length == string.length, lines.count <= boxes.count + 1,
               ink.allSatisfy({ clip.insetBy(dx: -0.5, dy: -0.5).contains($0) }) {
                return Layout(frame: frame, offsetX: shiftX, offsetY: shiftY, clip: clip,
                              inkLines: ink.map { CGRect(x: $0.minX, y: CGFloat(height) - $0.maxY, width: $0.width, height: $0.height) })
            }
            size -= max(0.5, startSize * 0.025)
        }
        return nil
    }

    private static func fit(_ samples: [Sample]) -> Plane? {
        guard samples.count >= 6 else { return nil }
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 3)
        for sample in samples {
            let v = [1.0, sample.x, sample.y], c = [sample.color.r, sample.color.g, sample.color.b]
            for i in 0..<3 { for j in 0..<3 { matrix[i][j] += v[i] * v[j] }; for k in 0..<3 { matrix[i][k + 3] += v[i] * c[k] } }
        }
        for i in 0..<3 {
            let pivot = (i..<3).max { abs(matrix[$0][i]) < abs(matrix[$1][i]) }!
            guard abs(matrix[pivot][i]) > 1e-8 else { return nil }
            matrix.swapAt(i, pivot)
            let divisor = matrix[i][i]
            for j in i..<6 { matrix[i][j] /= divisor }
            for row in 0..<3 where row != i { let f = matrix[row][i]; for j in i..<6 { matrix[row][j] -= f * matrix[i][j] } }
        }
        return Plane(r: matrix.map { $0[3] }, g: matrix.map { $0[4] }, b: matrix.map { $0[5] })
    }
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Optional, pinned local model. It restores only the requested mask, never the rest of the original image.
private final class LocalImageInpainter: @unchecked Sendable {
    private let lock = NSLock()
    private var model: MLModel?
    private var unavailable = false
    func restore(original: [UInt8], width: Int, height: Int, rect: CGRect, mask: [UInt8]) throws -> [UInt8]? {
        try lock.withLock {
            if model == nil {
                guard !unavailable, let url = Bundle.main.url(forResource: "MIGAN_512", withExtension: "mlmodelc") else { unavailable = true; return nil }
                let config = MLModelConfiguration(); config.computeUnits = .cpuAndGPU
                model = try MLModel(contentsOf: url, configuration: config)
            }
            guard let model else { return nil }
            let side = 512, step = 384, pw = Int(rect.width), ph = Int(rect.height), x0 = Int(rect.minX), y0 = Int(rect.minY)
            var output = [UInt8](repeating: 0, count: pw * ph * 4)
            for y in 0..<ph { for x in 0..<pw { for c in 0..<4 { output[(y * pw + x) * 4 + c] = original[((y0 + y) * width + x0 + x) * 4 + c] } } }
            for ty in stride(from: 0, to: ph, by: step) { for tx in stride(from: 0, to: pw, by: step) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let tw = min(step, pw - tx), th = min(step, ph - ty)
                    let wx = min(max(0, x0 + tx + tw / 2 - side / 2), max(0, width - side))
                    let wy = min(max(0, y0 + ty + th / 2 - side / 2), max(0, height - side))
                    let input = try MLMultiArray(shape: [1, 4, 512, 512], dataType: .float32)
                    let ptr = input.dataPointer.bindMemory(to: Float.self, capacity: 4 * side * side)
                    func hole(_ x: Int, _ y: Int) -> Bool {
                        let mx = x - x0, my = y - y0
                        return mx >= 0 && mx < pw && my >= 0 && my < ph && mask[my * pw + mx] != 0
                    }
                    let plane = side * side
                    for y in 0..<side { for x in 0..<side {
                        let sx = min(width - 1, wx + x), sy = min(height - 1, wy + y), i = y * side + x
                        let erased = hole(sx, sy), pixel = (sy * width + sx) * 4
                        ptr[i] = erased ? -0.5 : 0.5
                        for c in 0..<3 { ptr[(c + 1) * plane + i] = erased ? 0 : Float(original[pixel + c]) / 127.5 - 1 }
                    } }
                    let features = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
                    let prediction = try model.prediction(from: features)
                    guard let values = prediction.featureValue(for: "output")?.multiArrayValue else { throw ImagePOCError.message("배경 복원 모델의 출력이 맞지 않습니다.") }
                    let fp32 = values.dataType == .float32
                    let data = values.dataPointer.bindMemory(to: Float.self, capacity: 3 * plane)
                    for y in ty..<(ty + th) { for x in tx..<(tx + tw) where mask[y * pw + x] != 0 {
                        let ix = x0 + x - wx, iy = y0 + y - wy
                        guard ix >= 0, ix < side, iy >= 0, iy < side else { continue }
                        for c in 0..<3 {
                            let v = fp32 ? data[c * plane + iy * side + ix] : values[[0, NSNumber(value: c), NSNumber(value: iy), NSNumber(value: ix)]].floatValue
                            output[(y * pw + x) * 4 + c] = UInt8(max(0, min(255, Int(((max(-1, min(1, v)) + 1) * 127.5).rounded()))))
                        }
                    } }
                }
            } }
            return output
        }
    }
}
#endif
