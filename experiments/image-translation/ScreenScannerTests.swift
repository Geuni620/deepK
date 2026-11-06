#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit

@MainActor enum ScreenScannerTests {
    static func run() throws {
        let display = POCScanDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let normal = POCScanRegion.selected(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 700, y: 650), on: display)!
        expect(normal.rect == CGRect(x: 100, y: 200, width: 600, height: 450), "region includes the entire rectangle")
        expect(normal.sourceRect == CGRect(x: 100, y: 250, width: 600, height: 450), "AppKit to screen-capture coordinate conversion")
        let reversed = POCScanRegion.selected(from: CGPoint(x: 700, y: 650), to: CGPoint(x: 100, y: 200), on: display)
        expect(reversed == normal, "all drag directions select the same pixels")
        expect(POCScanRegion.selected(from: .zero, to: CGPoint(x: 3, y: 3), on: display) == nil, "tiny selections are ignored")
        let other = POCScanDisplay(id: 2, frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), scale: 1)
        let negative = POCScanRegion.selected(from: CGPoint(x: -1900, y: 0), to: CGPoint(x: -1000, y: 700), on: other)!
        expect(negative.sourceRect == CGRect(x: 20, y: 180, width: 900, height: 700), "secondary display with negative origin")
        let bounded = POCScanRegion.selected(from: CGPoint(x: -300, y: -200), to: CGPoint(x: 700, y: 650), on: display)!
        expect(bounded.rect == CGRect(x: 0, y: 0, width: 700, height: 650), "selection stays on one display")
        expect(normal.pixelSize(scale: 2) == CGSize(width: 1200, height: 900), "retina capture dimensions")
        let large = POCScanRegion(display: display, rect: CGRect(x: 0, y: 0, width: 6000, height: 4000)).pixelSize(scale: 2)
        expect(large.width == 3200 && large.height <= 3200, "capture is bounded before allocating pixels")

        // Offscreen AppKit event dispatch: no real screen pixels, system clipboard, keyboard, or permissions used.
        let window = POCSelectionPanel(contentRect: display.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = POCSelectionView(display: display); window.contentView = view
        var selected: POCScanRegion?
        view.onSelection = { selected = $0 }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 200)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 700, y: 650)))
        expect(selected == nil, "dragging alone does not begin capture")
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 700, y: 650)))
        expect(selected == normal, "releasing confirms a rectangle including text and pictures")
        window.close()

        print("PASS: scanner geometry and offscreen drag confirmation; no live screen capture")
    }

    static func liveTranslation() async {
        guard ProcessInfo.processInfo.environment["DEEPK_IMAGE_POC_LIVE"] == "1" else {
            fputs("Set DEEPK_IMAGE_POC_LIVE=1 for a synthetic screen-image subscription request.\n", stderr); exit(64)
        }
        let app = AppModel.shared
        let model = app.imageInput
        model.load(POCFixtures.sample(), direction: .englishToKorean, selectionText: POCSyntheticDemo.plain)
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while model.busy && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        do {
            guard model.complete && !model.busy, let image = model.renderedImage else { throw ImagePOCError.message("scan test did not complete") }
            let result = try POCTextRecognition.recognize(POCImage(pixels: image, name: "synthetic live output"))
            guard model.translations.count == 6, result.filter({ $0.text.range(of: "[가-힣]", options: .regularExpression) != nil }).count == 5 else {
                throw ImagePOCError.message("scan test rendering did not match")
            }
            try NativeImageTests.writeSynthetic(image, "native-live-translated.png")
            print("PASS: native input -> OCR -> shared app client -> actual provider -> 5 Korean image regions + selected text; \(model.timing)")
            model.clear(); await app.shutdown()
        } catch {
            model.clear(); await app.shutdown()
            fputs("FAIL: synthetic screen-image translation path (no content or paths logged)\n", stderr); exit(1)
        }
    }
    private static func expect(_ value: Bool, _ label: String) { if !value { fputs("FAIL: \(label)\n", stderr); exit(1) } }
}
#endif
