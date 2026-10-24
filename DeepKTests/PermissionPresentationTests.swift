import Foundation
import AppKit
import SwiftUI

@main
struct PermissionPresentationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let app = AppModel()
        precondition(app.shortcutMessage == TranslationFooterState.shortcutChecking, "시작 전 문구는 하단이 알리지 않는 확인 중 상태다")
        app.shortcutEnabled = true
        app.shortcutReady = false
        app.inputMonitoringAllowed = false
        app.accessibilityReady = false
        precondition(app.inputMonitoringStatusText == "감시 연결 안 됨")
        precondition(app.accessibilityStatusText == "앱 연결 미확인")
        app.inputMonitoringAllowed = true
        app.accessibilityReady = true
        precondition(app.inputMonitoringStatusText == "감시 연결 안 됨", "권한 사전 조회 성공만으로 감시 연결을 표시하지 않는다")
        precondition(app.accessibilityStatusText == "연결됨")
        app.shortcutReady = true
        precondition(app.inputMonitoringStatusText == "감지 중")
        app.shortcutEnabled = false
        app.restartShortcut()
        precondition(!app.shortcutReady)
        precondition(app.inputMonitoringStatusText == "감시 꺼짐")
        precondition(app.shortcutMessage == TranslationFooterState.shortcutDisabled)
        // Not connected yet: the empty result pane says so. Double copy turned off is the user's choice; the footer is quiet.
        precondition(footer(app).pane?.text == "번역 제공자 연결 전")
        precondition(footer(app).status == nil, "설정에서 끈 두 번 복사는 하단에 늘 남기지 않는다")
        app.shortcutEnabled = true
        app.shortcutReady = true
        app.refreshPermissionStatus()
        precondition(!app.shortcutReady, "실제 감시가 없으면 과거 준비됨 값을 유지하지 않는다")
        app.selectedProvider = .codex
        app.selectedModel = "removed-model"
        app.providerStates[.codex] = .connected(message: "연결됨")
        app.providerModels[.codex] = [TranslationModelOption(id: "available", model: "available", displayName: "사용 가능한 모델")]
        precondition(app.providerState(for: .codex).isConnected)
        precondition(!app.isSelectedModelAvailable, "계정 연결과 모델 가용 여부를 구분한다")
        app.selectedModel = "available"
        precondition(app.isSelectedModelAvailable)
        // 설정 창 없이 고르기 화면 상태만 확인한다(창을 열면 제공자 연결 확인이 CLI를 부른다).
        precondition(!app.showsCodeStylePicker)
        app.openCodeStylePicker()
        precondition(app.showsCodeStylePicker, "코드 스타일 행을 누르면 고르기 화면")
        app.closeCodeStylePicker()
        precondition(!app.showsCodeStylePicker, "‹ 표시·Esc로 탭에 돌아간다")
        app.openCodeStylePicker()
        app.closeSettingsWindow()
        precondition(!app.showsCodeStylePicker, "설정 창을 닫으면 다음에는 탭으로 연다")
        settingsViewsAreWired(app)
        escapeOrder(app)
        displaySettingsAreSaved(app)
        settingsWindowSizes(app)
        settingsHostLeavesTheSizeToTheWindow()
        footerReadsTheModel(app)
        briefFeedbackClearsItself(app)
        copyIsConfirmedOnThePill(app)
        newRequestClearsOldFeedback(app)
        statusTextDoesNotMoveForTheSpinner()
        emptyPaneShowsTheWholeError()
        hoverIsTrackedWhileInactive()
        resultTextIsParsedOncePerResult()
        print("Permission presentation, disabled shortcut and footer checks passed")
    }

    /// The window as it opens with nothing translated: the result pane is empty.
    @MainActor private static func footer(_ app: AppModel, showsText: Bool = false) -> TranslationFooterState {
        TranslationFooterState(model: app, resultShowsText: showsText, newContentBelow: false)
    }

    /// The footer's inputs come from the model: the label falls back from the shown result to the request to the
    /// selection, the normal shortcut state stays quiet, feedback is shown.
    @MainActor private static func footerReadsTheModel(_ app: AppModel) {
        app.shortcutMessage = TranslationFooterState.shortcutWatching
        app.feedback = ""
        precondition(app.store.resultModelLabel == nil)
        app.requestModelLabel = nil
        precondition(footer(app).detail == "\(app.selectedProvider.title) · \(app.selectedModel)", "선택한 제공자·모델로 돌아간다")
        app.requestModelLabel = "Claude Code · claude-haiku-5-5"
        precondition(footer(app).detail == "Claude Code · claude-haiku-5-5", "요청 시점의 모델을 쓴다")
        precondition(footer(app).status == nil, "평소 상태에서는 하단 문구가 없다")
        app.feedback = "결과가 변경되어 삽입을 중단했습니다"
        precondition(footer(app).status?.text == "결과가 변경되어 삽입을 중단했습니다")
        app.feedback = ""
        precondition(app.insertionNote == nil, "삽입할 수 없는 이유는 호출이 있을 때만 생긴다")
    }

    @MainActor private static func wait(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// '삽입됨' shows briefly and clears itself; feedback that arrives meanwhile stays.
    @MainActor private static func briefFeedbackClearsItself(_ app: AppModel) {
        app.showBriefly("삽입됨", for: .milliseconds(30))
        precondition(app.feedback == "삽입됨")
        precondition(footer(app).status?.text == "삽입됨")
        wait(3) { app.feedback.isEmpty }
        precondition(app.feedback.isEmpty, "삽입 확인은 스스로 지운다")

        app.showBriefly("삽입됨", for: .milliseconds(30))
        app.feedback = "결과가 변경되어 삽입을 중단했습니다"
        wait(0.3)
        precondition(app.feedback == "결과가 변경되어 삽입을 중단했습니다", "그 사이 온 안내는 지우지 않는다")

        // A second confirmation is not cut short by the first one's clock.
        app.showBriefly("삽입됨", for: .milliseconds(30))
        app.showBriefly("삽입됨", for: .seconds(5))
        wait(0.3)
        precondition(app.feedback == "삽입됨", "새 확인은 이전 확인의 시계에 지워지지 않는다")
        app.feedback = ""
    }

    /// A copy is confirmed where it was pressed: the 복사 pill reads '복사됨' for about two seconds. The footer's
    /// status slot, far to the left, does not carry it. A failed copy stays in the slot until something replaces it.
    /// `reportCopy` is what `copyResult` calls after writing; no test writes the general pasteboard.
    @MainActor private static func copyIsConfirmedOnThePill(_ app: AppModel) {
        app.feedback = ""
        app.reportCopy(true, confirmationDuration: .milliseconds(30))
        precondition(app.copyConfirmed && app.feedback.isEmpty, "성공은 버튼에서 확인하고 상태 칸에는 쓰지 않는다")
        precondition(footer(app, showsText: true).status?.text != "복사됨", "하단 왼쪽에 '복사됨'이 없다")
        wait(3) { !app.copyConfirmed }
        precondition(!app.copyConfirmed, "버튼은 스스로 '복사'로 돌아온다")

        app.reportCopy(false, confirmationDuration: .milliseconds(30))
        precondition(!app.copyConfirmed && app.feedback == AppModel.copyFailedMessage, "실패는 상태 칸에 쓴다")
        wait(0.3)
        precondition(app.feedback == AppModel.copyFailedMessage, "실패 문구는 저절로 지우지 않는다")
        app.reportCopy(true, confirmationDuration: .seconds(5))
        precondition(app.copyConfirmed && app.feedback.isEmpty, "이어서 성공하면 실패 문구를 지운다")

        // A second copy is not cut short by the first one's clock.
        app.reportCopy(true, confirmationDuration: .milliseconds(30))
        app.reportCopy(true, confirmationDuration: .seconds(5))
        wait(0.3)
        precondition(app.copyConfirmed, "새 확인은 이전 확인의 시계에 지워지지 않는다")
        app.feedback = "결과가 변경되어 삽입을 중단했습니다"
        app.reportCopy(true, confirmationDuration: .milliseconds(30))
        precondition(app.feedback == "결과가 변경되어 삽입을 중단했습니다", "다른 안내는 성공한 복사가 지우지 않는다")
        wait(3) { !app.copyConfirmed }
        app.feedback = ""
    }

    /// Feedback from before a new request (a failed insert, an old copy failure) must not hide that request's
    /// progress or error: '다시 시도' clears it like typing and '전체 다시 번역' do.
    @MainActor private static func newRequestClearsOldFeedback(_ app: AppModel) {
        app.feedback = "삽입을 확인하지 못했습니다. 원래 내용을 확인해 주세요"
        app.retry()
        precondition(app.feedback.isEmpty, "'다시 시도'는 앞 요청의 안내를 지운다")
        app.captureMessage = "복사한 텍스트를 확인하는 중…"
        precondition(!app.canRetranslateWholeDocument, "복사 확인 중에는 전체 다시 번역을 시작하지 않는다")
        app.captureMessage = nil
    }

    @MainActor private static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: width, height: height, alignment: .leading)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// '입력 중…' → '번역 중…' must not move the words: the spinner follows the text instead of pushing it.
    /// Rendered without a window; the text's pixels are compared with and without the spinner.
    @MainActor private static func statusTextDoesNotMoveForTheSpinner() {
        let text = "추가 내용 번역 중…"
        let still = render(StatusLineLabel(line: .init(text: text)), width: 240, height: 24)
        let spinning = render(StatusLineLabel(line: .init(text: text, showsProgress: true)), width: 240, height: 24)
        let ink = (0..<still.pixelsWide).filter { x in
            (0..<still.pixelsHigh).contains { (still.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.2 }
        }
        guard let first = ink.first, let last = ink.last else { preconditionFailure("the status text is drawn") }
        precondition(first <= 4, "the text starts at the slot's leading edge: \(first)")
        let same = (0...last).allSatisfy { x in
            (0..<still.pixelsHigh).allSatisfy { still.colorAt(x: x, y: $0) == spinning.colorAt(x: x, y: $0) }
        }
        precondition(same, "the spinner does not move the text")
        let beyond = (last + 1..<spinning.pixelsWide).contains { x in
            (0..<spinning.pixelsHigh).contains { (spinning.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.2 }
        }
        precondition(beyond, "the spinner is drawn after the text")
    }

    /// An empty result pane has room: a long error wraps there instead of ending in '…', and it can be selected.
    @MainActor private static func emptyPaneShowsTheWholeError() {
        let error = "Claude Code CLI를 찾을 수 없습니다: /usr/local/bin/claude 경로에서 실행 파일을 찾지 못했습니다. 설정에서 다시 확인해 주세요."
        let pane = NSHostingView(rootView: ResultPaneStatus(line: .init(text: error)).frame(width: 260))
        let line = NSHostingView(rootView: StatusLineLabel(line: .init(text: error)).frame(width: 260))
        precondition(pane.fittingSize.height >= 2 * line.fittingSize.height,
                     "the pane wraps the error: \(pane.fittingSize.height) vs \(line.fittingSize.height)")
    }

    /// The window usually appears without activating deepK (⌘C twice). The footer's hover detail is tracked with an
    /// `.activeAlways` area, so it does not wait for a click; the tracker never takes clicks.
    @MainActor private static func hoverIsTrackedWhileInactive() {
        let view = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        var states: [Bool] = []
        view.onChange = { states.append($0) }
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        precondition(view.trackingAreas.count == 1, "one tracking area, replaced on update")
        let options = view.trackingAreas[0].options
        precondition(options.contains(.activeAlways) && options.contains(.mouseEnteredAndExited) && options.contains(.inVisibleRect),
                     "tracked while the app is inactive")
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseEntered(with: enter)
        view.mouseExited(with: exit)
        precondition(states == [true, false], "entering and leaving are reported")
        precondition(view.hitTest(NSPoint(x: 10, y: 10)) == nil, "clicks go to the status button")
    }

    /// The pane and the footer both ask whether the result shows text; a streamed chunk is parsed once for both.
    @MainActor private static func resultTextIsParsedOncePerResult() {
        let presence = ResultTextPresence()
        func content(_ text: String, streaming: Bool = false) -> TranslationResultContent {
            TranslationResultContent(identity: UUID(), text: text, tailStart: 0, isStreaming: streaming, isStale: false)
        }
        let chunk = content("번역 문단입니다.", streaming: true)
        precondition(presence.showsText(chunk) && presence.showsText(chunk) && presence.parses == 1, "the same chunk is parsed once")
        precondition(!presence.showsText(content("```swift\n", streaming: true)) && presence.parses == 2,
                     "a draft that is only an opening fence shows nothing yet")
        precondition(!presence.showsText(content("")) && presence.showsText(content("완료된 번역")), "empty and finished text")
    }

    /// 표시 탭과 고르기 화면은 설정 창이 만드는 그대로(`init(app:)`) 앱의 열기·돌아가기·변경에 이어진다.
    @MainActor static func settingsViewsAreWired(_ app: AppModel) {
        let defaults = testDefaults()
        defer { defaults.store.removePersistentDomain(forName: defaults.suiteName) }
        app.displayDefaults = defaults.store
        app.resultDisplay = .standard
        DisplaySettingsTab(app: app).openPicker()
        precondition(app.showsCodeStylePicker, "코드 스타일 행은 고르기 화면을 연다")
        let picker = CodeStylePickerView(app: app)
        precondition(picker.display == app.resultDisplay)
        picker.update { $0.style = .github }
        precondition(app.resultDisplay.style == .github, "고르기 화면의 변경은 앱 설정을 바꾼다")
        picker.back()
        precondition(!app.showsCodeStylePicker, "'‹ 표시'는 탭으로 돌아간다")
        DisplaySettingsTab(app: app).update { $0.colorsSyntax = false }
        precondition(!app.resultDisplay.colorsSyntax, "표시 탭의 변경도 앱 설정을 바꾼다")
        app.closeSettingsWindow()
        app.displayDefaults = .standard
    }

    /// Esc는 고르기 화면 → 권한 팝오버 → 설정 창 순서로 닫는다.
    @MainActor static func escapeOrder(_ app: AppModel) {
        app.showSettings = true
        app.openCodeStylePicker()
        precondition(app.escapeSettings(permissionsShown: true) == .picker && !app.showsCodeStylePicker && app.showSettings,
                     "고르기 화면에서 Esc는 탭으로 돌아가고 창은 그대로")
        precondition(app.escapeSettings(permissionsShown: true) == .permissions && app.showSettings, "다음 Esc는 권한 팝오버를 닫는다")
        precondition(app.escapeSettings(permissionsShown: false) == .window && !app.showSettings, "그다음 Esc는 설정 창을 닫는다")
    }

    /// 연속 변경은 멈춘 뒤 마지막 값 하나만, 설정 창을 닫으면 바로 저장한다. 시험용 저장소에만 쓴다.
    @MainActor static func displaySettingsAreSaved(_ app: AppModel) {
        let defaults = testDefaults()
        defer { defaults.store.removePersistentDomain(forName: defaults.suiteName) }
        let store = defaults.store
        app.displayDefaults = store
        defer { app.displayDefaults = .standard }
        app.resultDisplay = .standard
        app.updateResultDisplay { $0.style = .github }
        app.updateResultDisplay { $0.foldLineCount = 8 }
        app.updateResultDisplay { $0.colorsSyntax = false }
        var expected = app.resultDisplay
        precondition(ResultDisplaySettings.load(from: store) == .standard, "변경 중에는 저장하지 않는다")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        precondition(ResultDisplaySettings.load(from: store) == .standard, "멈춘 지 300ms가 지나기 전에는 저장하지 않는다")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        precondition(ResultDisplaySettings.load(from: store) == expected, "멈추면 마지막 값을 저장한다")

        app.updateResultDisplay { $0.showsLinkSource = true }
        expected = app.resultDisplay
        app.closeSettingsWindow()
        precondition(ResultDisplaySettings.load(from: store) == expected, "설정 창을 닫으면 기다리지 않고 저장한다")

        // 닫아서 저장한 바로 뒤의 변경은 자기 기다림으로 저장된다. 취소된 기다림이 그 저장을 가로채지 않는다.
        app.updateResultDisplay { $0.foldsLongCode = false }
        app.closeSettingsWindow()
        app.updateResultDisplay { $0.foldLineCount = 3 }
        expected = app.resultDisplay
        precondition(ResultDisplaySettings.load(from: store).foldLineCount == 8, "닫은 뒤의 변경은 아직 저장하지 않는다")
        // 취소된 기다림이 새 기한까지 헛돌면 메인 스레드가 그동안 CPU를 쓴다.
        let busyBefore = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let busy = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - busyBefore) / 1_000_000
        precondition(ResultDisplaySettings.load(from: store) == expected, "그 변경도 멈추면 저장한다")
        precondition(busy < 50, "취소된 기다림은 헛돌지 않고 끝난다: 기다리는 0.5초 동안 메인 스레드 \(busy)ms")
    }

    /// 화면 밖 창으로 설정 창 크기를 확인한다: 왼쪽 위 고정, 화면 끝에서 밀린 거리 되돌리기, 옮긴 창은 옮긴 자리,
    /// 고르기 화면에서 닫으면 탭 크기. 넓히는 중에 닫거나(0.2초 애니메이션) 돌아와도 끝 크기·자리가 맞는다.
    @MainActor static func settingsWindowSizes(_ app: AppModel) {
        let screen = CGRect(x: -12_000, y: -12_000, width: 1440, height: 875)
        app.settingsScreenFrame = { _ in screen }
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 300, y: screen.minY + 300, width: 340, height: 376),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        app.settingsWindow = window
        defer {
            window.orderOut(nil)
            app.settingsWindow = nil
        }
        let tabs = CodeStylePickerModel.tabsSize, picker = CodeStylePickerModel.pickerSize
        func tabsFrame(left: CGFloat, top: CGFloat) -> NSRect {
            NSRect(x: screen.minX + left, y: screen.minY + top - tabs.height, width: tabs.width, height: tabs.height)
        }

        // 가운데: 왼쪽 위를 지키며 넓어졌다가 그 자리로 돌아온다.
        let middle = tabsFrame(left: 300, top: 676)
        window.setFrame(middle, display: false)
        app.openCodeStylePicker()
        precondition(window.frame == NSRect(x: middle.minX, y: middle.maxY - picker.height, width: picker.width, height: picker.height),
                     "고르기 화면은 620×460, 왼쪽 위 그대로: \(window.frame)")
        app.closeCodeStylePicker()
        precondition(window.frame == middle, "돌아오면 340×376 제자리: \(window.frame)")

        // 오른쪽 끝: 밀린 만큼 되돌린다.
        let edge = tabsFrame(left: screen.width - 360, top: 676)
        window.setFrame(edge, display: false)
        app.openCodeStylePicker()
        precondition(window.frame.maxX == screen.maxX, "화면 안으로 밀린다: \(window.frame)")
        app.closeCodeStylePicker()
        precondition(window.frame == edge, "밀린 거리를 되돌린다: \(window.frame)")

        // 넓은 동안 옮긴 창은 옮긴 자리의 왼쪽 위를 지킨다.
        app.openCodeStylePicker()
        window.setFrameOrigin(NSPoint(x: screen.minX + 500, y: screen.minY + 200))
        let moved = window.frame
        app.closeCodeStylePicker()
        precondition(window.frame == NSRect(x: moved.minX, y: moved.maxY - tabs.height, width: tabs.width, height: tabs.height),
                     "옮긴 창은 그 자리에서 줄어든다: \(window.frame)")

        // 고르기 화면에서 설정 창을 닫으면 탭 크기로 돌아간다.
        window.setFrame(middle, display: false)
        app.openCodeStylePicker()
        app.closeSettingsWindow()
        precondition(window.frame == middle && !app.showsCodeStylePicker, "닫으면 탭 크기: \(window.frame)")

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return print("'동작 줄이기'가 켜져 있어 설정 창 애니메이션 확인을 건너뜀")
        }
        // 보이는 창만 움직이므로 화면 밖에서 띄운다. 화면이 잠들거나 잠기면 창 애니메이션이 돌지 않으니 먼저 확인한다.
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
        window.setFrame(middle, display: false)
        window.orderFront(nil)
        app.openCodeStylePicker()
        settle()
        guard window.frame.width == picker.width else {
            app.closeSettingsWindow()
            return print("창 애니메이션이 돌지 않아(화면 잠김·잠자기) 설정 창 애니메이션 확인을 건너뜀")
        }
        app.closeCodeStylePicker()
        settle()
        precondition(window.frame == middle, "애니메이션으로도 넓어졌다가 제자리로 돌아온다: \(window.frame)")
        app.openCodeStylePicker()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        precondition(window.frame.width < picker.width, "넓히는 중이다: \(window.frame)")
        app.closeSettingsWindow()
        settle()
        precondition(window.frame == middle, "넓히는 중에 닫아도 340×376으로 끝난다: \(window.frame)")

        window.setFrame(edge, display: false)
        window.orderFront(nil)
        app.openCodeStylePicker()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        app.closeCodeStylePicker()
        settle()
        precondition(window.frame == edge, "넓히는 중에 돌아와도 밀린 거리를 되돌린다: \(window.frame)")
        app.openCodeStylePicker()
        settle()
        precondition(window.frame.maxX == screen.maxX && window.frame.width == picker.width, "다시 열면 다시 밀린다: \(window.frame)")
        app.closeCodeStylePicker()
        settle()
        precondition(window.frame == edge, "애니메이션이 끝난 뒤에 돌아와도 제자리: \(window.frame)")
    }

    /// 창이 크기를 정한다. 내용이 620폭이어도 340폭 창을 넓히거나 묶지 않는다. 호스팅 뷰는 띄운 창에서만 크기를 맞추므로
    /// 화면 밖에서 띄운다.
    @MainActor static func settingsHostLeavesTheSizeToTheWindow() {
        let window = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 340, height: 376),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = AppModel.settingsHost(Color.clear.frame(width: 620, height: 460))
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(window.frame == NSRect(x: -12_000, y: -12_000, width: 340, height: 376), "내용이 창 크기를 바꾸지 않는다: \(window.frame)")
        window.setContentSize(NSSize(width: 620, height: 460))
        window.setContentSize(NSSize(width: 340, height: 376))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(window.frame.size == NSSize(width: 340, height: 376), "넓혔다가 다시 줄일 수 있다: \(window.frame.size)")
    }

    private static func testDefaults() -> (store: UserDefaults, suiteName: String) {
        let suiteName = "deepk-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
