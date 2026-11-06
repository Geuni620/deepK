#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit

/// Fixed synthetic stream; measures local presentation delay, never provider/model throughput.
@MainActor enum ImageFeedbackBenchmark {
    actor Probe {
        var firstID: Int?
        var firstImageBlockSeconds: Double?
        var finished = false
        func begin(_ id: Int) { if firstID == nil { firstID = id } }
        func imageBlock(_ seconds: Double) { if firstImageBlockSeconds == nil { firstImageBlockSeconds = seconds } }
        func finish() { finished = true }
    }
    static func run() async {
        let input = NativeImageInput(), probe = Probe()
        let image = POCFixtures.sample()
        let body = String(repeating: "Please read the station information before boarding. ", count: 8)
        let clock = ContinuousClock.now
        input.makeTranslator = {
            NativeImageTranslator(label: "Synthetic stream · no provider", run: { batch, _, _, partial in
                if let first = batch.regions.first { await probe.begin(first.id) }
                var response = ""
                for region in batch.regions {
                    let target = region.id == 0 ? String(repeating: "탑승 전에 역 안내를 확인해 주세요. ", count: 8) : Self.fixtureTranslation(region.text)
                    response += "<r\(region.id)>"
                    let letters = Array(target)
                    for offset in stride(from: 0, to: letters.count, by: 4) {
                        try Task.checkCancellation()
                        response += String(letters[offset..<min(letters.count, offset + 4)])
                        partial(response)
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    response += "</r\(region.id)>"; partial(response)
                    if region.id != 0 { await probe.imageBlock(seconds(clock.duration(to: .now))) }
                }
                await probe.finish()
                return response
            })
        }
        input.load(image, direction: .englishToKorean, selectionText: body)
        var observedBeforeEnd = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while input.busy && ContinuousClock.now < deadline {
            if input.firstResultSeconds != nil, !(await probe.finished) { observedBeforeEnd = true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let scroll = NativeImageScroll(frame: CGRect(x: 0, y: 0, width: 500, height: 450))
        scroll.canvas.image = image.pixels; scroll.tile(); scroll.layoutImage()
        let originalWidth = scroll.canvas.frame.width
        scroll.magnification = 2; scroll.tile(); scroll.layoutImage()
        let zoomRatio = scroll.canvas.frame.width * scroll.magnification / originalWidth
        let metadata: [String: Any] = [
            "scope": "fixed synthetic mock stream; local UI delay only, not provider speed",
            "firstRequestedID": await probe.firstID ?? -1,
            "firstImageBlockClosedSeconds": await probe.firstImageBlockSeconds ?? -1,
            "firstBitmapSeconds": input.firstResultSeconds ?? -1,
            "completedSeconds": seconds(clock.duration(to: .now)),
            "imageVisibleBeforeEngineFinished": observedBeforeEnd,
            "twoTimesZoomActualRatio": zoomRatio,
            "complete": input.complete, "providerRequests": 0
        ]
        if let index = CommandLine.arguments.firstIndex(of: "--synthetic-output"), CommandLine.arguments.count > index + 1 {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("feedback-benchmark.json"))
        }
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
        if CommandLine.arguments.contains("--assert-feedback") {
            NativeImageTests.expect(observedBeforeEnd, "continuous token streaming must display a completed image block before final response")
            NativeImageTests.expect(await probe.firstID != 0, "image blocks are requested before copied prose")
            NativeImageTests.expect(abs(zoomRatio - 2) < 0.05, "2x zoom remains 2x after layout")
            NativeImageTests.expect(input.complete, "progressive rendering still completes all text regions")
        }
        input.clear()
    }
    nonisolated private static func fixtureTranslation(_ text: String) -> String {
        switch text.lowercased() {
        case "station guide": "역 이용 안내"
        case "tickets": "승차권"
        case "information": "안내"
        case "platform 2": "2번 승강장"
        case "exit": "출구"
        default: "안내"
        }
    }
    nonisolated private static func seconds(_ duration: Duration) -> Double { Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
}
#endif
