#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import CoreText

@MainActor enum ChatLayoutTests {
    static func run() throws {
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let lines: [POCTextRecognition.Line] = [
            .init(text: "Morgan 09:21", box: box(0.2, 0.82, 0.35, 0.04)),
            .init(text: "@ The layout stays here.", box: box(0.14, 0.77, 0.6, 0.04), words: [
                .init(text: "@", box: box(0.14, 0.77, 0.025, 0.04)),
                .init(text: "The layout stays here.", box: box(0.2, 0.77, 0.54, 0.04))
            ])
        ]
        let grouped = try POCTextRecognition.regions(from: lines)
        check(grouped.count == 2 && grouped[0].isMetadata && !grouped[1].isMetadata, "chat header stays separate from its message")
        check(grouped[1].text == "The layout stays here." && grouped[1].box.minX == 0.2, "avatar badge does not become a leading message symbol or anchor")

        let fixture = fixture()
        let image = fixture.image, width = image.pixels.width, height = image.pixels.height
        let avatarRects = fixture.avatars, headerRects = fixture.headers
        let regions = try POCTextRecognition.recognize(image)
        var translations: [Int: String] = [:], lastID: Int?
        for region in regions {
            if region.isMetadata { translations[region.id] = region.text }
            else if region.text.contains("interface") { translations[region.id] = "원래 화면 배치를 유지합니다." }
            else if region.text.contains("changed") { translations[region.id] = "어떤 부분이 달라졌나요?" }
            else if region.text.contains("fixed") {
                translations[region.id] = "실제로 문제 24개를 발견했고 모두 수정했습니다."; lastID = region.id
            }
        }
        check(regions.filter(\.isMetadata).count >= 3, "timestamp rows are recognized without mixing body text")
        guard let lastID else { throw ImagePOCError.message("synthetic last chat line not recognized") }
        let result = try NaturalImageRenderer(image: image.pixels, regions: regions).render(translations)
        try write(image.pixels, name: "chat-original.png"); try write(result.image, name: "chat-translated.png")
        #if IMAGE_LAYOUT_BASELINE
        print("BASELINE: synthetic chat rendered=\(result.renderedIDs.count) held=\(result.keptOriginalIDs.count) lastLineHeld=\(result.keptOriginalIDs.contains(lastID))")
        #else
        check(result.keptOriginalIDs.isEmpty, "all synthetic chat blocks fit without hiding the final message")
        check(result.renderedIDs.contains(lastID), "the longer final translation is displayed")
        let last = regions.first { $0.id == lastID }!
        let placement = result.placements[lastID]!
        check(placement.minX >= floor(last.box.minX * 1000) - 0.5, "translated body never shifts into the avatar column")
        check(placement.height > last.box.height * 780 * 1.3, "a longer last message uses a real extra line")
        let before = pixels(image.pixels), after = pixels(result.image)
        for rect in avatarRects + headerRects {
            check(unchanged(before, after, rect: rect, width: width, height: height), "avatars and original author/time typography remain pixel-identical")
        }
        let output = try POCTextRecognition.recognize(POCImage(pixels: result.image, name: "synthetic chat output"))
        let text = output.map(\.text).joined().filter { !$0.isWhitespace }
        check(text.contains("24개") && text.contains("수정했습니다"), "the final Korean message survives re-OCR")
        print("PASS: synthetic chat header boundaries, badge anchor, avatar pixels and wrapped final message")
        #endif
    }
    struct Fixture { let image: POCImage; let avatars: [CGRect]; let headers: [CGRect] }
    static func fixture() -> Fixture {
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let width = 1000, height = 780
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSBezierPath(rect: box(0, 0, 1000, 780)).fill()
        let context = NSGraphicsContext.current!.cgContext
        var avatarRects: [CGRect] = [], headerRects: [CGRect] = []
        func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
            context.textMatrix = .identity; context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])), context)
        }
        for (index, y) in [CGFloat(650), 430, 230].enumerated() {
            let avatar = box(60, y - 75, 80, 100); avatarRects.append(avatar)
            NSColor(calibratedRed: 0.3 + Double(index) * 0.1, green: 0.55, blue: 0.7, alpha: 1).setFill()
            NSBezierPath(roundedRect: avatar, xRadius: 12, yRadius: 12).fill()
            draw(index == 1 ? "Riley" : "Morgan", x: 160, y: y, size: 28, color: .black, weight: .bold)
            draw("09:2\(index + 1)", x: 310, y: y, size: 20, color: .gray)
            headerRects.append(box(152, y - 7, 260, 40))
        }
        draw("The interface keeps its layout.", x: 160, y: 610, size: 26, color: .black)
        draw("What changed?", x: 160, y: 390, size: 26, color: .black)
        draw("It fixed 24 issues. (edited)", x: 160, y: 190, size: 26, color: .black)
        NSGraphicsContext.restoreGraphicsState()
        let image = POCImage(pixels: rep.cgImage!, name: "synthetic chat layout")
        return Fixture(image: image, avatars: avatarRects, headers: headerRects)
    }
    private static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private static func unchanged(_ a: [UInt8], _ b: [UInt8], rect: CGRect, width: Int, height: Int) -> Bool {
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            let index = ((height - 1 - y) * width + x) * 4
            for c in 0..<4 where a[index + c] != b[index + c] { return false }
        } }
        return true
    }
    private static func check(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) } }
    private static func write(_ image: CGImage, name: String) throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--synthetic-output"), CommandLine.arguments.count > index + 1 else { return }
        let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
#endif
