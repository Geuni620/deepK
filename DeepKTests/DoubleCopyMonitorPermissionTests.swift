import AppKit
import CoreGraphics

@main
@MainActor
struct DoubleCopyMonitorPermissionTests {
    static func main() {
        let down = CGEventMask(1) << CGEventType.keyDown.rawValue
        let up = CGEventMask(1) << CGEventType.keyUp.rawValue
        let flags = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        precondition(!DoubleCopyMonitor.includesCopyEvents(0))
        precondition(!DoubleCopyMonitor.includesCopyEvents(flags), "보조 키만 허용된 감시는 번역 단축키를 받을 수 없다")
        precondition(!DoubleCopyMonitor.includesCopyEvents(down | flags))
        precondition(DoubleCopyMonitor.includesCopyEvents(down | up | flags))
        clipboardCaptureRequiresFreshChangeCount()
        clipboardCaptureDistinguishesEmptyAndNonText()
        readsHTMLOnlyFromChromiumCopies()
        rejectsConcealedCopies()
        pollStepsRejectConcealedCopies()
        print("DoubleCopyMonitor permission tests passed")
    }

    private static func clipboardCaptureRequiresFreshChangeCount() {
        let result = DoubleCopyMonitor.captureResult(
            changeCount: 41,
            baselineChangeCount: 41,
            text: "이전 복사 텍스트"
        )
        guard case .failure(.clipboardNotUpdated) = result else {
            fatalError("stale pasteboard text must never be captured")
        }
    }

    private static func clipboardCaptureDistinguishesEmptyAndNonText() {
        let empty = DoubleCopyMonitor.captureResult(
            changeCount: 42,
            baselineChangeCount: 41,
            text: " \n\t"
        )
        guard case .failure(.clipboardTextEmpty) = empty else {
            fatalError("a fresh whitespace-only string must be reported as empty text")
        }

        let nonText = DoubleCopyMonitor.captureResult(
            changeCount: 43,
            baselineChangeCount: 42,
            text: nil
        )
        guard case .failure(.clipboardNonText) = nonText else {
            fatalError("a fresh pasteboard without a string must be reported as non-text")
        }

        let fileURLWithText = DoubleCopyMonitor.captureResult(
            changeCount: 44,
            baselineChangeCount: 43,
            text: "file:///tmp/document.txt",
            containsFileURL: true
        )
        guard case .failure(.clipboardNonText) = fileURLWithText else {
            fatalError("a file URL pasteboard must remain non-text even with a string representation")
        }

        let text = DoubleCopyMonitor.captureResult(
            changeCount: 45,
            baselineChangeCount: 44,
            text: "새 복사 텍스트"
        )
        guard case .success("새 복사 텍스트") = text else {
            fatalError("a fresh non-empty string must be captured")
        }
    }

    private static func rejectsConcealedCopies() {
        let concealed = DoubleCopyMonitor.captureResult(
            changeCount: 46,
            baselineChangeCount: 45,
            text: nil,
            isConcealed: true
        )
        guard case .failure(.clipboardConcealed) = concealed else {
            fatalError("a concealed copy must be rejected before reading its text")
        }

        for type in DoubleCopyMonitor.sensitivePasteboardTypes {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.deepk.tests.concealed.\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            let item = NSPasteboardItem()
            item.setString("hunter2", forType: .string)
            item.setString("", forType: type)
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            precondition(DoubleCopyMonitor.isConcealed(pasteboard), "\(type.rawValue) must mark the copy as concealed")
        }

        let ordinary = NSPasteboard(name: NSPasteboard.Name("com.deepk.tests.ordinary.\(UUID().uuidString)"))
        defer { ordinary.releaseGlobally() }
        ordinary.clearContents()
        ordinary.setString("ordinary text", forType: .string)
        precondition(!DoubleCopyMonitor.isConcealed(ordinary), "an ordinary copy must not be treated as concealed")
    }

    /// 실제 poll이 쓰는 읽기·확정 단계로 확인한다. 이름 있는 개별 pasteboard만 쓴다.
    private static func pollStepsRejectConcealedCopies() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.deepk.tests.poll-steps.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setString("", forType: concealedType)
        let concealed = DoubleCopyMonitor.readPasteboard(pasteboard)
        precondition(
            concealed.isStable && concealed.isConcealed && concealed.text == nil && concealed.html == nil,
            "a concealed copy must be refused before its string is read"
        )

        // arboard 순서: 문자열을 쓰고, 그 사이 poll이 읽은 뒤에 표시를 붙인다.
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        let early = DoubleCopyMonitor.readPasteboard(pasteboard)
        guard case .success(let text) = DoubleCopyMonitor.captureResult(
            changeCount: early.changeCount,
            baselineChangeCount: early.changeCount - 1,
            text: early.text,
            containsFileURL: early.containsFileURL,
            isConcealed: early.isConcealed
        ) else {
            fatalError("the string read before the marker is only a candidate")
        }
        let candidate = DoubleCopyMonitor.PendingCapture(changeCount: early.changeCount, text: text, html: early.html)
        guard case .success? = DoubleCopyMonitor.confirmCapture(candidate, on: pasteboard) else {
            fatalError("an unmarked copy must be confirmed on the next poll")
        }
        pasteboard.setString("", forType: concealedType)
        precondition(pasteboard.changeCount == early.changeCount, "adding the marker keeps the changeCount")
        guard case .failure(.clipboardConcealed)? = DoubleCopyMonitor.confirmCapture(candidate, on: pasteboard) else {
            fatalError("a marker added after the string must be refused before the copy is confirmed")
        }

        pasteboard.clearContents()
        pasteboard.setString("next copy", forType: .string)
        precondition(DoubleCopyMonitor.confirmCapture(candidate, on: pasteboard) == nil, "a replaced item must be read again")
    }

    /// 이름 있는 개별 pasteboard만 쓴다. 일반 클립보드는 건드리지 않는다.
    private static func readsHTMLOnlyFromChromiumCopies() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.deepk.tests.copied-html.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        // 다른 앱이 HTML을 지연 제공하면 읽는 순간 그 앱이 HTML을 만들 때까지 기다린다.
        let provider = PromisedHTML()
        let promised = NSPasteboardItem()
        promised.setString("ordinary table text", forType: .string)
        promised.setDataProvider(provider, forTypes: [.html])
        pasteboard.clearContents()
        precondition(pasteboard.writeObjects([promised]))
        precondition(DoubleCopyMonitor.copiedHTML(from: pasteboard) == nil, "HTML from a non-Chromium copy must not be read")
        precondition(provider.requests == 0, "a promised HTML must not be rendered while polling the clipboard")

        let html = "<meta charset='utf-8'><b>x</b>"
        let chromium = NSPasteboardItem()
        chromium.setString("x", forType: .string)
        chromium.setString("https://example.com/", forType: DoubleCopyMonitor.chromiumSourceURLType)
        chromium.setString(html, forType: .html)
        pasteboard.clearContents()
        precondition(pasteboard.writeObjects([chromium]))
        precondition(DoubleCopyMonitor.copiedHTML(from: pasteboard) == html, "HTML from a Chromium copy is read")
    }
}

private final class PromisedHTML: NSObject, NSPasteboardItemDataProvider {
    var requests = 0

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        requests += 1
        item.setString("<table><tr><td>ordinary</td></tr></table>", forType: type)
    }
}
