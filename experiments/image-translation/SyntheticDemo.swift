#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Explicit test command only. Recording is restricted to this app's synthetic translation window.
@MainActor final class POCSyntheticDemo: NSObject {
    static let shared = POCSyntheticDemo()
    static let plain = "Please check the platform before boarding."
    static var armed = false
    private var recordingTask: Task<Void, Error>?
    private var stopRequested = false
    private var failure = false
    private var directory: URL?
    static var chatFixture: Bool { CommandLine.arguments.contains("--chat-layout-demo") }
    static var sampleImage: POCImage { chatFixture ? ChatLayoutTests.fixture().image : POCFixtures.sample() }
    static var fixturePNG: Data { NSBitmapImageRep(cgImage: sampleImage.pixels).representation(using: .png, properties: [:])! }
    static func auditedConfiguration(_ configuration: CodexTranslationClient.Configuration) -> CodexTranslationClient.Configuration {
        guard CommandLine.arguments.contains("--record-synthetic-demo") || CommandLine.arguments.contains("--scan-live-smoke") else { return configuration }
        func argument(_ flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.count > index + 1 else { return nil }; return CommandLine.arguments[index + 1]
        }
        guard let proxy = argument("--audit-proxy"), let real = argument("--real-codex"), let output = argument("--audit-output"),
              let regions = try? POCTextRecognition.recognize(sampleImage) else { return configuration }
        var result = configuration
        result.executableURL = URL(fileURLWithPath: proxy)
        result.environment = ["DEEPK_POC_AUDIT_REAL_CODEX": real, "DEEPK_POC_AUDIT_OUTPUT": output,
                              "DEEPK_POC_AUDIT_EXPECTED_TEXT": NativeImageRegionBatch(regions: regions + [ImageTextRegion(id: 0, text: plain, box: .zero)]).payload]
        return result
    }
    static func accepts(plain: String, html: String?) -> Bool {
        guard plain.trimmingCharacters(in: .whitespacesAndNewlines) == Self.plain, let html else { return false }
        return ClipboardImageSelection.parse(html).references == [.embedded(fixturePNG)]
    }
    func begin() async {
        guard let index = CommandLine.arguments.firstIndex(of: "--synthetic-output"), CommandLine.arguments.count > index + 1 else {
            fputs("Synthetic demo requires --synthetic-output.\n", stderr); return
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let html = """
            <!doctype html><meta charset="utf-8"><title>deepK synthetic X selection</title>
            <style>body{font:20px -apple-system;padding:32px;margin:0;background:#fff;max-width:1000px}p{margin:0 0 20px}figure{margin:0;width:900px;height:525px;position:relative}img{position:absolute;inset:0;user-select:none;-webkit-user-select:none}figure div{position:absolute;inset:0;background-size:contain;background-repeat:no-repeat}</style>
            <p>\(Self.plain)</p><figure><div style="background-image:url('data:image/png;base64,\(Self.fixturePNG.base64EncodedString())')"></div><img draggable="true" width="900" height="525" src="data:image/png;base64,\(Self.fixturePNG.base64EncodedString())"></figure>
            """
            try html.write(to: directory.appendingPathComponent("synthetic-x-selection.html"), atomically: true, encoding: .utf8)
            let app = AppModel.shared
            Self.armed = true
            let replay = CommandLine.arguments.contains("--synthetic-copy-replay")
            let seeded = CommandLine.arguments.contains("--seed-synthetic-input")
            app.store.setDirection(.englishToKorean)
            app.beginImageImport(plain: "")
            app.imageInput.status = replay ? "브라우저 복사 입력 검증 · 시스템 단축키 조작 제외" : "합성 샘플에서 글·이미지를 선택하고 ⌘C 두 번"
            guard let window = NSApp.windows.first(where: { $0 is TranslationPanel }) else {
                throw ImagePOCError.message("Synthetic translation window unavailable")
            }
            window.title = replay ? "deepK · 합성 이미지 실제 번역 검증 (단축키 제외)" : "deepK · 합성 이미지 실제 번역 검증"
            app.showWindow()
            guard CGPreflightScreenCaptureAccess() else { throw ImagePOCError.message("Screen permission not available for synthetic recording") }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else {
                throw ImagePOCError.message("Synthetic window capture target unavailable")
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width) * 2; config.height = Int(window.frame.height) * 2
            config.showsCursor = false; config.capturesAudio = false
            let writer = try SyntheticWindowVideo(url: directory.appendingPathComponent("deepk-image-translation-test.mp4"), width: config.width, height: config.height)
            let clock = ContinuousClock.now
            let first = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try writer.append(first, seconds: 0)
            recordingTask = Task {
                do {
                    while !self.stopRequested {
                        try await Task.sleep(for: .milliseconds(125))
                        let frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        let elapsed = clock.duration(to: .now).components
                        try writer.append(frame, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                    }
                } catch { self.failure = true; throw error }
            }
            print("READY: synthetic-only translation window recording; no other windows or audio")
            fflush(stdout)
            let deadline = ContinuousClock.now.advanced(by: .seconds(150))
            var replayed = false
            if seeded {
                try await Task.sleep(for: .milliseconds(700))
                replayed = ImagePOCIntegration.shared.accept(plain: Self.plain, html: html)
            }
            while app.imageInput.image == nil && !failure && ContinuousClock.now < deadline {
                if replay, !replayed, !POCImage.isConcealed(.general),
                   let html = NSPasteboard.general.string(forType: .html), Self.accepts(plain: NSPasteboard.general.string(forType: .string) ?? "", html: html) {
                    replayed = ImagePOCIntegration.shared.accept(plain: Self.plain, html: html)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            while app.imageInput.busy && !failure && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            guard let image = app.imageInput.renderedImage, app.imageInput.image != nil else { throw ImagePOCError.message("Synthetic copy did not arrive") }
            let regions = try await Task.detached { try POCTextRecognition.recognize(POCImage(pixels: image, name: "synthetic recorded output")) }.value
            let koreanRegions = regions.filter { $0.text.range(of: "[가-힣]", options: .regularExpression) != nil }.count
            let expectedKorean = Self.chatFixture ? 3 : 5
            let koreanMatches = Self.chatFixture ? koreanRegions >= expectedKorean : koreanRegions == expectedKorean
            let passed = app.imageInput.complete && app.imageInput.translations.count == app.imageInput.regions.count + 1 && koreanMatches
            let metadata: [String: Any] = ["syntheticOnly": true, "providerResponseMocked": false, "windowCount": NSApp.windows.filter { $0.isVisible && !$0.isSheet }.count,
                "passed": passed, "mappedRegions": app.imageInput.translations.count, "koreanImageRegions": koreanRegions,
                "ocrSeconds": app.imageInput.ocrSeconds ?? -1, "firstRenderedSeconds": app.imageInput.firstResultSeconds ?? -1,
                "firstDraftSeconds": app.imageInput.firstTextSeconds ?? -1,
                "translationSeconds": app.imageInput.translationSeconds ?? -1, "rawContentSaved": false,
                "systemShortcutExercised": !replay, "syntheticClipboardReplay": replayed, "shortcutMonitorReady": app.shortcutReady,
                "seededSyntheticInput": seeded,
                "fixture": Self.chatFixture ? "synthetic-chat" : "synthetic-station",
                "failureKind": app.imageInput.failureKind ?? "none", "provider": app.selectedProvider.rawValue,
                "translationWindowCount": NSApp.windows.filter { $0 is TranslationPanel && $0.isVisible }.count,
                "visibleAppWindowTypes": NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) }]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("synthetic-demo-checks.json"))
            try await Task.sleep(for: .seconds(5))
            stopRequested = true
            try await recordingTask?.value
            let finished = await writer.finish()
            print(passed && finished && !failure ? "PASS: synthetic browser image import -> OCR -> actual provider -> natural image; recording complete" : "FAIL: synthetic demo did not satisfy all checks")
            fflush(stdout)
            // The audited client accepts only this fixture. Never leave it open for normal user input.
            finishTest(success: passed && finished && !failure)
        } catch {
            stopRequested = true; recordingTask?.cancel()
            fputs("FAIL: synthetic recording (\(type(of: error))); no other windows captured\n", stderr)
            finishTest(success: false)
        }
    }

    private func finishTest(success: Bool) {
        let code: Int32 = success ? 0 : 1
        // Calling terminateLater from an actor task can enter AppKit's nested termination loop
        // while the cleanup task is still waiting for that actor. This explicit test process
        // owns only synthetic input; close its clients, then exit with a bounded fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(code) }
        Task { @MainActor in
            await ImagePOCIntegration.shared.shutdown()
            await AppModel.shared.shutdown()
            exit(code)
        }
    }

    static func clipboardSession() {
        let board = NSPasteboard.general
        guard !POCImage.isConcealed(board) else { fputs("Sensitive clipboard: backup not started.\n", stderr); exit(1) }
        var total = 0
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
            guard let data = item.data(forType: type) else { return nil }; total += data.count; return (type, data)
        } }
        guard total <= 30_000_000 else { fputs("Clipboard too large for in-memory backup.\n", stderr); exit(1) }
        print("READY: clipboard backup in RAM only; send restore after synthetic copy")
        fflush(stdout)
        _ = readLine()
        let version = board.changeCount
        guard !POCImage.isConcealed(board), board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) == plain else {
            print("Clipboard changed outside synthetic test; left untouched."); return
        }
        let html = board.string(forType: .html) ?? ""
        guard version == board.changeCount, accepts(plain: plain, html: html) else { print("Clipboard differs from fixture; left untouched."); return }
        let items = saved.map { entries in let item = NSPasteboardItem(); for (type, data) in entries { item.setData(data, forType: type) }; return item }
        board.clearContents(); board.writeObjects(items)
        print("PASS: original clipboard restored; backup released")
    }
}

/// Writes only app-owned synthetic window frames. Avoids ReplayKit's remote file-write extension path.
@MainActor private final class SyntheticWindowVideo {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int, height: Int
    init(url: URL, width: Int, height: Int) throws {
        self.width = width; self.height = height
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ImagePOCError.message("Synthetic video writer could not start") }
        writer.startSession(atSourceTime: .zero)
    }
    func append(_ image: CGImage, seconds: Double) throws {
        guard input.isReadyForMoreMediaData else { return }
        guard let pool = adaptor.pixelBufferPool else { throw ImagePOCError.message("Synthetic frame pool unavailable") }
        var frame: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &frame) == kCVReturnSuccess, let frame else { throw ImagePOCError.message("Synthetic frame allocation failed") }
        CVPixelBufferLockBaseAddress(frame, [])
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(frame), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(frame), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ImagePOCError.message("Synthetic frame context unavailable")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard adaptor.append(frame, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600)) else { throw ImagePOCError.message("Synthetic frame write failed") }
    }
    func finish() async -> Bool {
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }
}
#endif
