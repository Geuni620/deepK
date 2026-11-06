#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import SwiftUI

@MainActor enum NativeImageTests {
    static func publicCopyProbe() async {
        let board = NSPasteboard.general
        guard !POCImage.isConcealed(board) else { fputs("Sensitive clipboard: probe not started.\n", stderr); exit(1) }
        var total = 0
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
            guard let data = item.data(forType: type) else { return nil }; total += data.count; return (type, data)
        } }
        guard total <= 30_000_000 else { fputs("Clipboard too large for RAM-only backup.\n", stderr); exit(1) }
        print("READY: public-copy image metadata probe; clipboard backed up in RAM only"); fflush(stdout)
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            if !POCImage.isConcealed(board), board.string(forType: .string)?.contains("deepk-public-copy-probe") == true,
               let data = board.data(forType: .html), data.count <= 1 << 20, let html = String(data: data, encoding: .utf8) {
                let version = board.changeCount
                let selection = ClipboardImageSelection.parse(html)
                var imported = false
                if let image = try? await selection.load() { imported = image.pixels.width > 0 && image.pixels.height > 0 }
                var restored = false
                if board.changeCount == version, !POCImage.isConcealed(board) {
                    let items = saved.map { entries in let item = NSPasteboardItem(); for (type, value) in entries { item.setData(value, forType: type) }; return item }
                    board.clearContents(); board.writeObjects(items); restored = true
                }
                let raw = html as NSString
                let imageTags = (try? NSRegularExpression(pattern: "(?i)<img\\b").numberOfMatches(in: html, range: NSRange(location: 0, length: raw.length))) ?? -1
                let metadata: [String: Any] = ["htmlImageTags": imageTags, "acceptedImageReferences": selection.references.count,
                    "unsupportedImages": selection.unavailable, "imageFetchedInMemory": imported, "clipboardRestored": restored,
                    "providerCalled": false, "contentWritten": false]
                if let output = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), let text = String(data: output, encoding: .utf8) { print(text) }
                exit(imported && restored ? 0 : 1)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        fputs("FAIL: controlled public copy did not arrive; clipboard untouched\n", stderr); exit(1)
    }
    static func run() async {
        do {
            let url = "https://pbs.twimg.com/media/synthetic-only?format=png&name=large"
            let html = "<p>Read this guide.</p><div style='background-image: url(&quot;\(url.replacingOccurrences(of: "&", with: "&amp;"))&quot;)'></div>"
            let selection = ClipboardImageSelection.parse(html)
            expect(selection.references == [.remote(URL(string: url)!)], "X CSS image is extracted without an IMG tag")
            expect(selection.documentText(from: "Read this guide.\n\(url)") == "Read this guide.", "an image drag URL is excluded from provider text")
            expect(selection.documentText(from: "data:image/png;base64,synthetic") == "", "an image data URL is excluded from provider text")
            expect(ClipboardImageSelection.parse("<div aria-hidden='true'>\(html)</div>").references.count == 1, "accessibility-hidden visual image layers remain importable")
            expect(ClipboardImageSelection.parse("<div style='backface-visibility:hidden'>\(html)</div>").references.count == 1, "X backface rendering property does not hide its image")
            expect(ClipboardImageSelection.parse(html + "<img src='\(url)'>").references.count == 1, "CSS and IMG sources are deduplicated")
            expect(!ClipboardImageSelection.parse("<div hidden>\(html)</div><script>\(html)</script>").containsImages, "hidden containers and scripts are skipped")
            expect(!ClipboardImageSelection.parse("<img src='https://pbs.twimg.com/outside'><!--StartFragment--><p>only selected</p><!--EndFragment-->").containsImages, "only the copied fragment is imported")
            for source in ["file:///private/synthetic.png", "http://pbs.twimg.com/a.png", "https://pbs.twimg.com.evil.invalid/a", "https://user:pass@pbs.twimg.com/a", "https://127.0.0.1/a", "https://pbs.twimg.com:444/a"] {
                expect(ClipboardImageSelection.parse("<img src='\(source)'>").unavailable == 1, "unsupported image destinations are rejected")
            }
            let sample = POCFixtures.sample()
            let imported = try await selection.load(fetch: { _ in sample })
            expect(imported.pixels.width == sample.pixels.width, "CSS input reaches memory-only image decoder")
            let regions = try POCTextRecognition.recognize(sample)
            let batch = NativeImageRegionBatch(regions: regions)
            let first = regions[0].id, second = regions[1].id
            let partial = batch.completedTranslations(in: "```xml\n<r\(first)>안내</r\(first)><r\(second)>미완성")
            expect(partial == [first: "안내"], "streaming commits only complete regions and accepts outer fences")
            expect(batch.draft(in: "<r\(first)>안내</r\(first)><r\(second)>번역 생성 중") == .init(id: second, text: "번역 생성 중"), "only the real active region is previewed as generated text")
            expect(batch.draft(in: "<r99999>unknown") == nil, "unknown IDs cannot become progress text")
            let readable = ImageReadingGeometry.magnification(imageWidth: 1200, viewportWidth: 432, bodyFontPixels: 24, readable: true, zoom: 1)
            expect(24 * (432 - 12) / 1200 * readable >= 15.99, "image text uses a 16pt reading scale instead of a tiny fit preview")
            expect(ImageReadingGeometry.magnification(imageWidth: 1200, viewportWidth: 432, bodyFontPixels: 24, readable: false, zoom: 1) == 1, "fit mode remains available")
            let duplicate = batch.completedTranslations(in: "<r\(first)>가</r\(first)><r\(first)>나</r\(first)><r\(second)>승차권</r\(second)>")
            expect(duplicate[first] == nil && duplicate[second] == "승차권", "duplicate IDs do not discard another successful region")
            let renderer = try NaturalImageRenderer(image: sample.pixels, regions: regions)
            let unchanged = try renderer.render([:])
            expect(pixels(unchanged.image) == pixels(sample.pixels), "no translations leaves every source pixel unchanged")
            let rendered = try renderer.render(POCFixtures.translations(for: regions))
            print("synthetic station: rendered=\(rendered.renderedIDs.count) kept=\(rendered.keptOriginalIDs.count)")
            try writeSynthetic(sample.pixels, "native-station-original.png")
            try writeSynthetic(rendered.image, "native-station-translated.png")
            expect(rendered.renderedIDs.count == 5, "five labels pass native background and layout checks")
            let outputRegions = try POCTextRecognition.recognize(POCImage(pixels: rendered.image, name: "synthetic output"))
            let outputText = outputRegions.map(\.text).joined(separator: "").replacingOccurrences(of: " ", with: "")
            expect(["역이용안내", "승차권", "안내", "2번승강장", "출구"].allSatisfy { outputText.contains($0) }, "native output can be read back as five Korean labels")
            let rejected = try renderer.render([first: String(repeating: "공간을넘기는번역문", count: 100)])
            expect(rejected.keptOriginalIDs == [first] && pixels(rejected.image) == pixels(sample.pixels), "overflow keeps the original intact")
            try await cards()
            try ChatLayoutTests.run()
            try await InputResilienceTests.run()
            try await snapshotSyntheticUI()
            print("PASS: native CSS image input, region streaming, pixel preservation, Korean re-OCR and overflow gates; synthetic only")
        } catch {
            fputs("FAIL: native image checks: \(type(of: error))\n", stderr); exit(1)
        }
    }
    /// Runs the actual SwiftUI translation surface offscreen with prepared responses.
    /// No app delegate, global monitor, system clipboard, screen capture or provider is started.
    private static func snapshotSyntheticUI() async throws {
        guard CommandLine.arguments.contains("--synthetic-output") else { return }
        let app = AppModel.shared
        let input = app.imageInput
        input.makeTranslator = {
            NativeImageTranslator(label: "Synthetic prepared response · no provider", run: { batch, _, _, _ in
                batch.regions.map { region in
                    let value: String
                    if region.isMetadata { value = region.text }
                    else if region.text.contains("interface") { value = "원래 화면 배치를 유지합니다." }
                    else if region.text.contains("changed") { value = "어떤 부분이 달라졌나요?" }
                    else { value = "실제로 문제 24개를 발견했고 모두 수정했습니다." }
                    return "<r\(region.id)>\(value)</r\(region.id)>"
                }.joined(separator: "\n")
            })
        }
        app.store.setDirection(.englishToKorean)
        input.load(ChatLayoutTests.fixture().image, direction: .englishToKorean)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while input.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        expect(input.complete, "offscreen UI receives all prepared synthetic translations")
        input.prefersReadableSize = false
        let view = NSHostingView(rootView: TranslationView().environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 720), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close(); input.clear() }
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ImagePOCError.message("Synthetic UI snapshot could not allocate pixels")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { throw ImagePOCError.message("Synthetic UI snapshot is empty") }
        try writeSynthetic(image, "synthetic-translation-window.png")
        print("PASS: actual translation view rendered offscreen with synthetic prepared responses; no live keys or provider")
    }
    private static func cards() async throws {
        let width = 1200, height = 760
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        let labels = ["Please choose your platform.", "Your ticket is ready.", "Check the departure time.", "Thank you for your help."]
        let targets = ["승강장을 선택해 주세요.", "승차권이 준비되었습니다.", "출발 시간을 확인하세요.", "도와주셔서 감사합니다."]
        let rects = [CGRect(x: 45, y: 430, width: 530, height: 260), CGRect(x: 625, y: 430, width: 530, height: 260),
                     CGRect(x: 45, y: 100, width: 530, height: 260), CGRect(x: 625, y: 100, width: 530, height: 260)]
        for (index, rect) in rects.enumerated() {
            let color = index.isMultiple(of: 2) ? NSColor(calibratedWhite: 0.95, alpha: 1) : NSColor(calibratedRed: 0.91, green: 0.94, blue: 1, alpha: 1)
            color.setFill(); let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16); path.fill()
            NSColor(calibratedWhite: 0.78, alpha: 1).setStroke(); path.lineWidth = 2; path.stroke()
            (labels[index] as NSString).draw(in: rect.insetBy(dx: 24, dy: 66), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)])
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = POCImage(pixels: rep.cgImage!, name: "synthetic cards")
        let regions = try POCTextRecognition.recognize(image)
        let values = Dictionary(uniqueKeysWithValues: regions.compactMap { region -> (Int, String)? in
            let key = region.text.replacingOccurrences(of: "\n", with: " ")
            guard let index = labels.firstIndex(of: key) else { return nil }; return (region.id, targets[index])
        })
        expect(values.count == 4, "two-column OCR keeps four independent paragraphs")
        let rendered = try NaturalImageRenderer(image: image.pixels, regions: regions).render(values)
        try writeSynthetic(image.pixels, "native-cards-original.png"); try writeSynthetic(rendered.image, "native-cards-translated.png")
        expect(rendered.renderedIDs.count == 4, "grey and blue card backgrounds preserve four translated paragraphs")
        let before = pixels(image.pixels), after = pixels(rendered.image)
        var outsideChanges = 0
        for y in 0..<height { for x in 0..<width {
            let inside = rects.contains { rect in rect.insetBy(dx: 12, dy: 12).contains(CGPoint(x: x, y: height - 1 - y)) }
            if !inside { for c in 0..<4 where before[(y * width + x) * 4 + c] != after[(y * width + x) * 4 + c] { outsideChanges += 1 } }
        } }
        expect(outsideChanges == 0, "card borders, rounded corners and page pixels are unchanged")
        let result = try POCTextRecognition.recognize(POCImage(pixels: rendered.image, name: "synthetic card output"))
        let text = result.map(\.text).joined().filter { !$0.isWhitespace }
        expect(targets.allSatisfy { text.contains($0.filter { !$0.isWhitespace }) }, "four translated card paragraphs remain readable")
    }
    static func writeSynthetic(_ image: CGImage, _ name: String) throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--synthetic-output"), CommandLine.arguments.count > index + 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try data.write(to: directory.appendingPathComponent(name))
    }
    static func pixels(_ image: CGImage) -> Data {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Data(bytes)
    }
    static func expect(_ condition: Bool, _ name: String) { if !condition { fputs("FAIL: \(name)\n", stderr); exit(1) } }
}
#endif
