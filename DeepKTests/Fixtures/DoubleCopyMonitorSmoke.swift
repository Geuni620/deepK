import AppKit
import CoreGraphics

/// 합성 CGEvent로 이벤트 전달과 클립보드 갱신을 확인한다. 실제 키보드 검증을 대체하지 않는다.
@main
struct DoubleCopyMonitorSmoke {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        Task { @MainActor in
            await run()
            exit(0)
        }
        app.run()
    }

    @MainActor
    private static func run() async {
        guard let host = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "deepk-test-host"
        }) else {
            print("Fixture missing")
            exit(1)
        }

        host.activate(options: [.activateAllWindows])
        try? await Task.sleep(for: .milliseconds(300))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier else {
            print("Fixture activation failed")
            exit(1)
        }

        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        let monitor = DoubleCopyMonitor()
        var callbackCount = 0
        var capturedText = ""
        var failure: DoubleCopyMonitor.Failure?
        monitor.onCopiedText = { text, _, processIdentifier, _ in
            guard processIdentifier == host.processIdentifier else { return }
            callbackCount += 1
            capturedText = text
        }
        monitor.onFailure = { failure = $0 }

        guard monitor.start() else {
            print("Monitor unavailable: \(String(describing: monitor.lastFailure))")
            exit(1)
        }

        // 테스트 앱의 편집 → 복사 메뉴로 원래 복사 경로를 실행하며, 감시기는 이벤트를 수신만 한다.
        func postCommandC() {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier else {
                return
            }
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: keyDown)!
                event.flags = .maskCommand
                event.post(tap: .cghidEventTap)
            }
        }

        postCommandC()
        try? await Task.sleep(for: .milliseconds(120))
        guard callbackCount == 0 else {
            print("Single copy incorrectly invoked")
            monitor.stop()
            exit(1)
        }

        postCommandC()
        try? await Task.sleep(for: .milliseconds(400))
        monitor.stop()

        let expectedText = "Please keep the original window open."
        let passed = callbackCount == 1 && capturedText == expectedText && failure == nil
        print("Actual double copy callbacks: \(callbackCount), correct text: \(capturedText == expectedText)")

        if pasteboard.string(forType: .string) == expectedText {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }

        if !passed {
            print("Monitor failure: \(String(describing: failure))")
            exit(1)
        }
    }
}
