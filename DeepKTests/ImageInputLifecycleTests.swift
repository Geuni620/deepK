#if IMAGE_INPUT_RELEASE_TESTS
import AppKit

@MainActor enum ImageInputLifecycleTests {
    actor Calls {
        var directions: [String] = []
        func add(_ value:String) { directions.append(value) }
        func reset() { directions = [] }
    }
    static func run() async throws {
        let longText = String(repeating:"Synthetic article & <text> 👩🏽‍💻. ",count:200)
        let longLayout = SelectionTextLayout(text:longText)
        check(longLayout.parts.map(\.source).joined() == longText,"long selection preserves every source character")
        do {
            let batches = try NativeImageRegionBatch.make(longLayout.regions)
            check(batches.count > 1 && batches.allSatisfy { $0.payload.count <= 3800 },"long selection fits escaped provider batches")
        } catch { check(false,"long selection must not block text and image processing") }
        // A regressed guard must fail locally instead of ever launching an authenticated CLI.
        let defaults = UserDefaults.standard
        let keys = ["codexExecutablePath","claudeExecutablePath","translationDirection"]
        let previous = keys.map { defaults.object(forKey:$0) }
        defaults.set("/nonexistent/deepk-synthetic-cli",forKey:keys[0])
        defaults.set("/nonexistent/deepk-synthetic-cli",forKey:keys[1])
        defer {
            for (key,value) in zip(keys,previous) {
                if let value { defaults.set(value,forKey:key) } else { defaults.removeObject(forKey:key) }
            }
        }
        let app = AppModel()
        let promisedBoard = NSPasteboard.withUniqueName()
        defer { promisedBoard.releaseGlobally() }
        let promised = ImageInputPromisedHTML(),item = NSPasteboardItem()
        item.setString("Synthetic selection",forType:.string)
        item.setDataProvider(promised,forTypes:[.html])
        promisedBoard.writeObjects([item])
        check(DoubleCopyMonitor.copiedHTML(from:promisedBoard) == nil && promised.requests == 0,"production image flag never requests non-Chromium promised HTML while polling")

        let translationWindow = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:420,height:264),styleMask:.titled,backing:.buffered,defer:true)
        let otherWindow = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:340,height:376),styleMask:.titled,backing:.buffered,defer:true)
        app.attach(translationWindow)
        var imports = 0,standardPastes = 0
        for window in [otherWindow,nil] {
            ImagePOCIntegration.handleMenuPaste(in:window,app:app,importSelection:{ imports += 1;return true },pasteText:{ standardPastes += 1 })
        }
        check(imports == 0 && standardPastes == 2,"settings and missing key window paste without reading image clipboard")
        ImagePOCIntegration.handleMenuPaste(in:translationWindow,app:app,importSelection:{ imports += 1;return true },pasteText:{ standardPastes += 1 })
        check(imports == 1 && standardPastes == 2,"translation window can consume image paste")
        ImagePOCIntegration.handleMenuPaste(in:translationWindow,app:app,importSelection:{ false },pasteText:{ standardPastes += 1 })
        check(standardPastes == 3,"ordinary translation input paste retains responder fallback")
        app.captureMessage = "Synthetic pending copy"
        check(!app.cancelCopyIfSourceChanged(from:42,frontmostPID:42) && app.captureMessage != nil,"same source keeps pending capture")
        check(app.cancelCopyIfSourceChanged(from:42,frontmostPID:43) && app.captureMessage == nil && app.feedback.contains("앱이 바뀌었습니다"),"changed source clears capture and reports cancellation")
        for provider in TranslationProvider.allCases {
            app.selectedProvider = provider
            let captured = app.imageInput.makeTranslator!()
            await app.disconnectProvider(provider)
            check(!app.imageTranslationAllowed(for:provider),"explicit disconnect disables image requests")
            do {
                _ = try await captured.run(NativeImageRegionBatch(regions:[ImageTextRegion(id:0,text:"Synthetic words",box:.zero)]),"en","ko",{_ in})
                check(false,"translator captured before disconnect must be blocked")
            } catch is ImagePOCError {}
            catch { check(false,"disconnect gate must reject before resolving or connecting a CLI") }
        }
        let calls = Calls(),selection = ClipboardImageSelection.parse("<p>Synthetic words<img src='file:///synthetic-icon.jpg' width='18' height='18'></p>")
        app.imageInput.makeTranslator = {
            NativeImageTranslator(label:"Synthetic lifecycle",provider:.codex,run:{ batch,source,target,_ in
                await calls.add(source+"->"+target)
                return batch.regions.map { "<r\($0.id)>준비된 번역문</r\($0.id)>" }.joined()
            })
        }
        let longSelection = ClipboardImageSelection.parse("<p>Synthetic article<img src='file:///synthetic-body.jpg' width='180' height='180'></p>")
        app.imageInput.loadSelection(longSelection,plain:longText,direction:.englishToKorean)
        try await finish(app.imageInput)
        check(app.imageInput.textReady && app.imageInput.failedImages == 1 && app.imageInput.stage == .finished,"long text translates even when a body image is unavailable")
        check(app.imageInput.textLayout.translatedText([:]) == longText,"untranslated long selection keeps exact source order")
        await calls.reset()
        app.imageInput.loadSelection(selection,plain:"Synthetic words",direction:.englishToKorean)
        try await finish(app.imageInput)
        check(app.imageInput.image == nil && app.imageInput.isActive,"inline session is active without a body bitmap")
        app.changeDirection(.koreanToEnglish)
        try await finish(app.imageInput)
        check(await calls.directions == ["en->ko","ko->en"],"language change retranslates inline-only selection")
        check(app.imageInput.targetLanguage == "en","result language follows new direction")

        let canceled = NativeImageInput()
        canceled.makeTranslator = { NativeImageTranslator(label:"Synthetic cancellation",run:{_,_,_,_ in throw CancellationError()}) }
        canceled.loadSelection(selection,plain:"Synthetic words",direction:.englishToKorean)
        try await finish(canceled)
        check(!canceled.busy && !canceled.isImporting && canceled.failureKind == "cancelled","provider-originated cancellation releases progress and retry state")

        app.imageInput.makeTranslator = {
            NativeImageTranslator(label:"Synthetic pending",provider:.codex,run:{_,_,_,_ in try await Task.sleep(for:.seconds(10));return ""})
        }
        app.imageInput.loadSelection(selection,plain:"Synthetic words",direction:.englishToKorean)
        try await Task.sleep(for:.milliseconds(20))
        await app.disconnectProvider(.codex)
        check(!app.imageInput.busy && !app.imageInput.isImporting && app.imageInput.failureKind == "provider-disconnected","disconnect cancels pending image work immediately")

        app.imageInput.makeTranslator = {
            NativeImageTranslator(label:"Synthetic scan",run:{batch,_,_,_ in batch.regions.map { "<r\($0.id)>\($0.text)</r\($0.id)>" }.joined()})
        }
        let region = POCScanRegion(display:.init(id:1,frame:CGRect(x:0,y:0,width:1000,height:800),scale:1),rect:CGRect(x:50,y:50,width:300,height:200))
        app.imageInput.clear()
        app.imageInput.scanner.completeCapture(POCFixtures.sample(),region:region) { app.acceptScannedImage($0,present:false) }
        try await finish(app.imageInput)
        check(app.imageInput.scanner.lastRegion == region,"fresh scan keeps its rectangle through the real AppModel input-reset path")
        app.imageInput.clear()
        check(app.imageInput.scanner.lastRegion == nil,"closing or replacing source clears the stored scan rectangle")
        canceled.clear()
        await app.shutdown()
        print("PASS: bounded long selection, promised HTML, scoped paste, invocation cancellation, disconnect guard/cancel, inline direction retry, provider cancellation and scan-region lifetime; no provider process")
    }
    private static func finish(_ input:NativeImageInput) async throws {
        let deadline = ContinuousClock.now.advanced(by:.seconds(20))
        while input.busy && ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(10)) }
        check(!input.busy,"synthetic lifecycle task reaches terminal state")
    }
    private static func check(_ value:Bool,_ message:String) {
        guard value else { fputs("FAIL: \(message)\n",stderr);exit(1) }
    }
}

private final class ImageInputPromisedHTML: NSObject,NSPasteboardItemDataProvider {
    var requests = 0
    func pasteboard(_ pasteboard:NSPasteboard?,item:NSPasteboardItem,provideDataForType type:NSPasteboard.PasteboardType) {
        requests += 1;item.setString("<p>Synthetic delayed HTML</p>",forType:type)
    }
}
#endif
