#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import SwiftUI

/// Explicit synthetic test commands only; never starts the global shortcut or reads user clipboard.
@MainActor enum ResilienceLiveEvidence {
    static let plain = "Hello, my name is Morgan.\n\nPlease check the platform before boarding."
    static let html = "<p>Hello, my name is <img src='file:///synthetic-icon.jpg' width='18' height='18'>Morgan.</p><p>Please check the platform before boarding.</p>"
    static var selection: ClipboardImageSelection { ClipboardImageSelection.parse(html) }
    static var expected: String {
        NativeImageRegionBatch(regions:SelectionTextLayout(text:plain,icons:selection.inlinePlaceholders(in:plain)).regions).payload
    }
    static func argument(_ name:String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of:name),CommandLine.arguments.count > i+1 else { return nil }
        return CommandLine.arguments[i+1]
    }
    static func configuration(_ original:CodexTranslationClient.Configuration) -> CodexTranslationClient.Configuration {
        guard let proxy = argument("--audit-proxy"),let real = argument("--real-codex"),let output = argument("--audit-output") else { return original }
        var result = original
        result.executableURL = URL(fileURLWithPath:proxy);result.prewarmEnabled = false
        result.environment.merge(["DEEPK_POC_AUDIT_REAL_CODEX":real,"DEEPK_POC_AUDIT_OUTPUT":output,"DEEPK_POC_AUDIT_EXPECTED_TEXT":expected]) { _,next in next }
        return result
    }
    static func run() async {
        guard ProcessInfo.processInfo.environment["DEEPK_IMAGE_POC_LIVE"] == "1",
              let output = argument("--synthetic-output"),argument("--audit-proxy") != nil else {
            fputs("Explicit live opt-in, synthetic output and audit proxy required.\n",stderr);exit(64)
        }
        POCSyntheticDemo.armed = true
        let app = AppModel.shared,input = app.imageInput
        guard app.selectedProvider == .codex else { fputs("The selected provider is not Codex; no provider request made.\n",stderr);exit(64) }
        var panel: TranslationPanel?
        do {
            let directory = URL(fileURLWithPath:output,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            app.store.setDirection(.englishToKorean)
            let view = NSHostingView(rootView:VStack(spacing:0) {
                Text("AFTER · 실제 Codex · 합성 입력 · 물리적 단축키 제외").font(.system(size:15,weight:.semibold)).padding(10)
                TranslationView()
            }.environment(\.colorScheme,.light))
            let window = TranslationPanel(contentRect:CGRect(x:0,y:0,width:1000,height:760),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false;window.contentView = view;app.attach(window);panel = window
            let writer = try SyntheticWindowVideo(url:directory.appendingPathComponent("after-live-codex.mp4"),width:1000,height:760)
            let clock = ContinuousClock.now
            var finished: ContinuousClock.Instant?
            input.loadSelection(selection,plain:plain,direction:.englishToKorean)
            while clock.duration(to:.now) < .seconds(120) {
                try await Task.sleep(for:.milliseconds(120));view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    if let image = bitmap.cgImage {
                        let duration = clock.duration(to:.now)
                        try writer.append(image,seconds:Double(duration.components.seconds)+Double(duration.components.attoseconds)/1e18)
                    }
                }
                if !input.busy {
                    if finished == nil { finished = .now }
                    if finished!.duration(to:.now) > .seconds(2) { break }
                }
            }
            let encoded = await writer.finish()
            let board = NSPasteboard.withUniqueName()
            let copied = input.copySelectedText(to:board) && board.string(forType:.string) == input.textLayout.translatedText(input.translations)
            board.releaseGlobally()
            let korean = input.textLayout.regions.allSatisfy { input.translations[$0.id]?.range(of:"[가-힣]",options:.regularExpression) != nil }
            let passed = encoded && input.textReady && !input.busy && input.failedIcons == 1 && input.regions.isEmpty && copied && korean
            let checks: [String:Any] = ["passed":passed,"syntheticOnly":true,"provider":"codex","expectedRequests":1,
                "selectedModel":app.selectedModel,"providerLabel":input.providerLabel,
                "textBlocks":input.textLayout.regions.count,"textReady":input.textReady,"copyVerified":copied,
                "failedIcons":input.failedIcons,"ocrRegions":input.regions.count,"firstTextSeconds":input.firstTextSeconds ?? -1,
                "translationSeconds":input.translationSeconds ?? -1,"physicalShortcutExercised":false,
                "imageOrPathIncludedInModelInput":false,"failureKind":input.failureKind ?? "none"]
            try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("live-checks.json"))
            input.clear();panel?.close();await app.shutdown()
            print(passed ? "PASS: actual Codex synthetic text translation survives failed inline icon; native copy verified on named board" : "FAIL: synthetic live resilience checks")
            exit(passed ? 0 : 1)
        } catch {
            input.clear();panel?.close();await app.shutdown()
            fputs("FAIL: synthetic live evidence; no content logged\n",stderr);exit(1)
        }
    }
    static func fetchCheck() async {
        do {
            let url = URL(string:"https://raw.githubusercontent.com/Geuni620/deepK/596fea1507ee11c26332e91dc086a39c4eeb83c8/experiments/image-translation/evidence/chat-original.png")!
            let image = try await MemoryImageDownload.fetch(url)
            guard image.pixels.width == 1000,image.pixels.height == 780 else { throw ImagePOCError.message("Synthetic dimensions do not match") }
            print("PASS: real HTTPS non-X synthetic image GET -> memory-only decoder; width1000 height780; no provider or content files")
        } catch { fputs("FAIL: synthetic public image fetch; no content logged\n",stderr);exit(1) }
    }
}
#endif
