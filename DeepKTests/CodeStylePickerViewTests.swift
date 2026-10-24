import AppKit
import SwiftUI

/// Offscreen checks of the 표시 tab and the code style picker: the preview is the real result view and fits its well
/// for every setting, follows changes at once, keeps the keyboard with the picker and opens no link; the tab's controls
/// and the picker's rows and ↑↓ change the settings they name. Windows stay far off the screens. With
/// `DEEPK_SETTINGS_SNAPSHOTS` set to a directory, also writes PNGs of both stages for a visual check.
@main
@MainActor
private enum CodeStylePickerViewTests {
    static func main() {
        _ = NSApplication.shared
        previewFitsEverySetting()
        previewFollowsEveryChange()
        previewKeepsTheKeyboardAway()
        previewOpensNoLink()
        previewCursorIsAnArrow()
        hostedPreviewIsTheSample()
        displayTabControlsChangeTheirSettings()
        pickerRowsAndKeysChooseTheStyle()
        stagesFitTheirWindows()
        if let directory = ProcessInfo.processInfo.environment["DEEPK_SETTINGS_SNAPSHOTS"] {
            writeSnapshots(to: URL(fileURLWithPath: directory))
        }
        print("CodeStylePickerViewTests passed (offscreen)")
    }

    /// The window is sized so the sample never scrolls for a built-in style, whatever the 표시 tab says.
    private static func previewFitsEverySetting() {
        var tallest: CGFloat = 0
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            for folds in [true, false] {
                for count in ResultDisplaySettings.foldLineChoices {
                    for pill in [false, true] {
                        for colors in [false, true] {
                            var display = ResultDisplaySettings.standard
                            display.style = style
                            display.foldsLongCode = folds
                            display.foldLineCount = count
                            display.showsLinkSource = pill
                            display.colorsSyntax = colors
                            let (_, view) = preview(display)
                            tallest = max(tallest, view.frame.height)
                            require(view.frame.height <= CodeStylePickerModel.previewHeight,
                                    "\(style.name) fold \(folds) \(count) pill \(pill): \(view.frame.height) > \(CodeStylePickerModel.previewHeight)")
                        }
                    }
                }
            }
        }
        require(tallest == CodeStylePickerModel.previewHeight, "the well is exactly as tall as the tallest sample (\(tallest))")

        let (_, view) = preview(.standard)
        require(view.textContainer?.size.width == 366, "the preview wraps at the small result window's 366pt")
        let folded = view.codeBoxes()
        require(folded.count == 1 && folded[0].fold.hasFooter && folded[0].fold.isFolded,
                "the 7-line block is folded to 5 with a footer")
        require(!view.string.contains("`") && !view.string.contains("<a1>"), "chips and the link are styled, not shown as markup")
    }

    /// Unlike a result window, the preview applies each ↑↓ step at once instead of coalescing it.
    private static func previewFollowsEveryChange() {
        var github = ResultDisplaySettings.standard
        github.style = .github
        let (previewScroll, previewView) = preview(.standard)
        for display in [github, .standard, github] {
            TranslationResultTextView.update(previewScroll, content: CodeStylePreview.content, lineSpacing: 3, display: display)
            require(previewView.display == display && previewScroll.appliedDisplay == display, "the preview shows every step")
        }

        let result = TranslationResultTextView.makeScrollView() as! ResultScrollView
        result.frame = NSRect(x: 0, y: 0, width: CodeStylePickerModel.previewWidth, height: 400)
        TranslationResultTextView.update(result, content: CodeStylePreview.content, lineSpacing: 3, display: .standard)
        TranslationResultTextView.update(result, content: CodeStylePreview.content, lineSpacing: 3, display: github)
        TranslationResultTextView.update(result, content: CodeStylePreview.content, lineSpacing: 3, display: .standard)
        require(result.appliedDisplay == github, "a result window holds a step inside the coalescing interval")
        require(result.coalescesDisplay && !previewScroll.coalescesDisplay, "only the preview opts out")
    }

    /// Clicking the preview must not move focus off the list: ↑↓ keep switching styles. Its fold footer still works.
    private static func previewKeepsTheKeyboardAway() {
        let (scroll, view) = preview(.standard)
        require(!view.isSelectable && !view.acceptsFirstResponder, "the preview text does not take the keyboard")
        require(view.accessibilityLabel() == "코드 스타일 미리보기", "VoiceOver names the preview")
        let box = view.codeBoxes()[0]
        guard let footerRect = box.geometry.footer else { return require(false, "the folded sample has a footer") }
        let footer = NSPoint(x: footerRect.midX, y: footerRect.midY)
        require(view.chromeControl(at: footer) == .fold(box.key), "the footer is a control in the preview")
        let heightFolded = view.frame.height
        view.perform(.fold(box.key))
        require(view.frame.height > heightFolded && !view.codeBoxes()[0].fold.isFolded, "the footer expands the sample")
        view.perform(.fold(box.key))
        require(view.codeBoxes()[0].fold.isFolded, "and folds it again")
        _ = scroll
    }

    /// The sample's links go nowhere: its source pill is drawn but is neither a control nor a link, while a result window's
    /// pill at the same place opens its link. The fold footer and block copy still work.
    private static func previewOpensNoLink() {
        var display = ResultDisplaySettings.standard
        display.showsLinkSource = true
        var opened: [URL] = []
        let previousLink = TranslationResultTextView.openLink
        TranslationResultTextView.openLink = { opened.append($0) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deepk-test-\(UUID().uuidString)"))
        let previousBoard = TranslationResultTextView.copyPasteboard
        TranslationResultTextView.copyPasteboard = { pasteboard }
        defer {
            TranslationResultTextView.openLink = previousLink
            TranslationResultTextView.copyPasteboard = previousBoard
            pasteboard.releaseGlobally()
        }
        let (_, view) = preview(display)
        let result = TranslationResultTextView.makeScrollView() as! ResultScrollView
        result.frame = NSRect(x: 0, y: 0, width: CodeStylePickerModel.previewWidth, height: CodeStylePickerModel.previewHeight)
        TranslationResultTextView.update(result, content: CodeStylePreview.content, lineSpacing: 3, display: display)
        let resultView = result.documentView as! ResultTextView
        guard let (pill, range) = pillPoint(in: resultView) else { return require(false, "a result window draws the pill") }
        require(view.string == resultView.string && view.frame.height == resultView.frame.height, "the preview lays out as a result window")
        require(!view.followsLinks && resultView.followsLinks, "only the preview opts out")

        require(view.chromeControl(at: pill) == nil, "the preview's pill is not a control")
        require(!view.perform(.pill(range)) && opened.isEmpty, "running the pill opens nothing")
        view.clicked(onLink: CodeStylePreview.content.inline.links[0].url, at: range.location)
        require(opened.isEmpty, "nor does a click on the link")
        view.updateHover(at: pill)
        require(view.hoveredControl == nil, "no hover mark on the pill")
        view.updateHover(at: nil)
        require(resultView.perform(.pill(range)) && opened == [CodeStylePreview.content.inline.links[0].url],
                "a result window's pill opens its link (recorded, not opened)")

        let box = view.codeBoxes()[0]
        require(view.chromeControl(at: NSPoint(x: box.geometry.copyHit.midX, y: box.geometry.copyHit.midY)) == .copy(box.key),
                "block copy is a control in the preview")
        require(view.perform(.copy(box.key)) && pasteboard.string(forType: .string)?.hasPrefix("// wire only two tools") == true,
                "and copies the sample code (to a test pasteboard)")
    }

    /// The preview text is not selectable, so leaving one of its controls puts back the arrow, not the I-beam.
    private static func previewCursorIsAnArrow() {
        for isPreview in [true, false] {
            let scroll = TranslationResultTextView.makeScrollView(preview: isPreview) as! ResultScrollView
            scroll.frame = NSRect(x: 0, y: 0, width: CodeStylePickerModel.previewWidth, height: CodeStylePickerModel.previewHeight)
            let window = NSWindow(contentRect: scroll.frame.offsetBy(dx: -10_000, dy: -10_000), styleMask: [.borderless],
                                  backing: .buffered, defer: true)
            window.contentView = scroll
            defer { window.contentView = nil }
            TranslationResultTextView.update(scroll, content: CodeStylePreview.content, lineSpacing: 3, display: .standard)
            let view = scroll.documentView as! ResultTextView
            let box = view.codeBoxes()[0]
            guard let footer = box.geometry.footer else { return require(false, "the folded sample has a footer") }
            let code = NSPoint(x: box.geometry.box.midX, y: box.geometry.box.midY)
            func move(to point: NSPoint) {
                view.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: view.convert(point, to: nil), modifierFlags: [],
                                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 0, pressure: 0)!)
            }
            NSCursor.arrow.set()
            move(to: NSPoint(x: footer.midX, y: footer.midY))
            require(NSCursor.current == NSCursor.pointingHand, "a pointing hand over the footer (preview \(isPreview))")
            move(to: code)
            require(view.hoveredControl == nil && NSCursor.current == (isPreview ? NSCursor.arrow : NSCursor.iBeam),
                    "leaving the footer: the arrow in the preview, the I-beam in a result window (preview \(isPreview))")
        }
        NSCursor.arrow.set()
    }

    /// The picker's `CodeStylePreview` itself: the preview flavor of the result view, showing every style it is given.
    private static func hostedPreviewIsTheSample() {
        var github = ResultDisplaySettings.standard
        github.style = .github
        let host = NSHostingView(rootView: CodeStylePreview(display: .standard))
        let window = offscreenWindow(host, size: CGSize(width: CodeStylePickerModel.previewWidth, height: CodeStylePickerModel.previewHeight))
        defer { close(window) }
        guard let scroll = subviews(of: host).compactMap({ $0 as? ResultScrollView }).first,
              let view = scroll.documentView as? ResultTextView else { return require(false, "the preview hosts a result view") }
        require(!scroll.coalescesDisplay && !view.isSelectable && !view.followsLinks, "the hosted view is the preview flavor")
        require(scroll.accessibilityIdentifier() == "code-style-preview-scroll", "and is named as one")
        require(scroll.appliedDisplay == .standard && scroll.applied == CodeStylePreview.content, "it shows the sample")
        for display in [github, .standard, github] {
            host.rootView = CodeStylePreview(display: display)
            host.layoutSubtreeIfNeeded()
            require(scroll.appliedDisplay == display && view.display == display, "each style shows at once")
        }
    }

    /// Each control of the 표시 tab shows and changes its own setting; the style row opens the picker.
    private static func displayTabControlsChangeTheirSettings() {
        var display = ResultDisplaySettings.standard
        display.foldsLongCode = true
        display.showsLinkSource = false
        display.colorsSyntax = true
        var changes: [ResultDisplaySettings] = []
        var opened = 0
        let update: ResultDisplayUpdate = { change in
            var changed = display
            change(&changed)
            changes.append(changed)
        }
        let host = NSHostingView(rootView: DisplaySettingsTab(display: display, update: update, openPicker: { opened += 1 })
            .frame(width: CodeStylePickerModel.tabsSize.width).font(.system(size: 13)))
        let window = offscreenWindow(host, size: CGSize(width: CodeStylePickerModel.tabsSize.width, height: 240))
        defer { close(window) }

        // Top to bottom: 긴 코드 접기, 링크 출처 표시, 문법 색.
        let switches = subviews(of: host).compactMap { $0 as? NSSwitch }
            .sorted { host.convert($0.bounds, from: $0).minY < host.convert($1.bounds, from: $1).minY }
        let keyPaths: [WritableKeyPath<ResultDisplaySettings, Bool>] = [\.foldsLongCode, \.showsLinkSource, \.colorsSyntax]
        require(switches.count == keyPaths.count, "three switches: \(switches.count)")
        for (control, keyPath) in zip(switches, keyPaths) {
            require((control.state == .on) == display[keyPath: keyPath], "each switch shows its setting")
            changes = []
            control.performClick(nil)
            var expected = display
            expected[keyPath: keyPath].toggle()
            require(changes == [expected], "each switch changes its own setting")
        }

        // The line count menu: on only while folding, and its choices set the count.
        guard let menu = subviews(of: host).compactMap({ $0 as? NSPopUpButton }).first else { return require(false, "the line count menu") }
        require(menu.isEnabled, "the line count menu works while folding")
        for count in ResultDisplaySettings.foldLineChoices {
            changes = []
            DisplaySettingsTab(display: display, update: update, openPicker: {}).chooseFoldLines(count)
            require(changes.map(\.foldLineCount) == [count], "choosing \(count)줄")
        }
        var unfolded = display
        unfolded.foldsLongCode = false
        host.rootView = DisplaySettingsTab(display: unfolded, update: update, openPicker: { opened += 1 })
            .frame(width: CodeStylePickerModel.tabsSize.width).font(.system(size: 13))
        host.layoutSubtreeIfNeeded()
        require(!menu.isEnabled, "and is off while folding is off")

        click(window, host, at: NSPoint(x: 100, y: 35))
        require(opened == 1, "the code style row opens the picker")
    }

    /// The picker's rows and ↑↓ choose the style, and the chosen row is the highlighted one. An offscreen window never
    /// becomes key and SwiftUI sends it keys whether or not the picker asked for focus, so focus on open is not checked.
    private static func pickerRowsAndKeysChooseTheStyle() {
        var display = ResultDisplaySettings.standard
        var host: NSHostingView<AnyView>!
        func picker() -> AnyView {
            AnyView(CodeStylePickerView(display: display, update: { change in
                change(&display)
                host.rootView = picker()
                host.layoutSubtreeIfNeeded()
            }, back: {}).font(.system(size: 13)))
        }
        host = NSHostingView(rootView: picker())
        let window = offscreenWindow(host, size: CodeStylePickerModel.pickerSize)
        defer { close(window) }
        // Under the 44pt top bar and its rule, the section title takes 32pt, then 28pt rows.
        let nativeRow = NSPoint(x: 100, y: 45 + 32 + 14), githubRow = NSPoint(x: 100, y: 45 + 32 + 28 + 14)
        // Left of the swatch, inside the row's fill.
        func highlighted(_ row: NSPoint) -> Bool { isHighlighted(host, at: NSPoint(x: 12, y: row.y)) }

        require(highlighted(nativeRow) && !highlighted(githubRow), "the chosen row (Native) is highlighted, the other is not")
        key(window, NSDownArrowFunctionKey, keyCode: 125)
        require(display.style == .github, "↓ chooses the next style")
        require(highlighted(githubRow) && !highlighted(nativeRow), "the highlight follows")
        key(window, NSDownArrowFunctionKey, keyCode: 125)
        require(display.style == .github, "↓ stops at the last style")
        key(window, NSUpArrowFunctionKey, keyCode: 126)
        require(display.style == .native, "↑ chooses the previous style")
        click(window, host, at: githubRow)
        require(display.style == .github, "clicking a row chooses its style")
        click(window, host, at: nativeRow)
        require(display.style == .native, "and back")
    }

    /// Stage 1 fits the 340×376 window under the tab bar; the picker fits 620 wide at its height.
    private static func stagesFitTheirWindows() {
        let tab = NSHostingView(rootView: displayTab(.standard))
        tab.frame.size = NSSize(width: CodeStylePickerModel.tabsSize.width, height: 300)
        let tabHeight = tab.fittingSize.height
        // The window less the tab bar (44), the footer (38) and their two rules.
        require(tabHeight <= CodeStylePickerModel.tabsSize.height - 44 - 38 - 2, "the 표시 tab fits without scrolling: \(tabHeight)")

        let picker = NSHostingView(rootView: pickerView(.standard))
        let pickerHeight = picker.fittingSize.height
        require(picker.fittingSize.width == CodeStylePickerModel.pickerSize.width, "the picker is 620 wide: \(picker.fittingSize.width)")
        require(pickerHeight <= CodeStylePickerModel.pickerSize.height - 38 - 1, "the picker fits above the footer: \(pickerHeight)")
    }

    private static func writeSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var github = ResultDisplaySettings.standard
        github.style = .github
        var off = github
        off.foldsLongCode = false
        off.colorsSyntax = false
        off.showsLinkSource = true
        var three = ResultDisplaySettings.standard
        three.foldLineCount = 3
        three.showsLinkSource = true
        var longest = ResultDisplaySettings.standard
        longest.foldLineCount = 20
        longest.colorsSyntax = false
        for (name, display) in [("native", ResultDisplaySettings.standard), ("github", github), ("github-off-pill", off),
                                ("native-3-pill", three), ("native-20-plain", longest)] {
            snapshot(stageOne(display), size: CodeStylePickerModel.tabsSize, to: directory.appendingPathComponent("stage1-\(name).png"))
            snapshot(stageTwo(display), size: CodeStylePickerModel.pickerSize, to: directory.appendingPathComponent("stage2-\(name).png"))
        }
        print("CodeStylePickerViewTests wrote snapshots to \(directory.path)")
    }

    // MARK: - Helpers

    private static func preview(_ display: ResultDisplaySettings) -> (ResultScrollView, ResultTextView) {
        let scroll = TranslationResultTextView.makeScrollView(preview: true) as! ResultScrollView
        scroll.frame = NSRect(x: 0, y: 0, width: CodeStylePickerModel.previewWidth, height: CodeStylePickerModel.previewHeight)
        TranslationResultTextView.update(scroll, content: CodeStylePreview.content, lineSpacing: 3, display: display)
        return (scroll, scroll.documentView as! ResultTextView)
    }

    private static func displayTab(_ display: ResultDisplaySettings) -> some View {
        DisplaySettingsTab(display: display, update: { _ in }, openPicker: {})
            .frame(width: CodeStylePickerModel.tabsSize.width)
            .font(.system(size: 13))
    }

    private static func pickerView(_ display: ResultDisplaySettings) -> some View {
        CodeStylePickerView(display: display, update: { _ in }, back: {})
            .font(.system(size: 13))
    }

    /// The settings window around each stage as FinalSettingsView lays it out; the tab bar is a stand-in.
    private static func stageOne(_ display: ResultDisplaySettings) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("설정 영역", selection: .constant(2)) {
                    Text("일반").tag(0)
                    Text("번역").tag(1)
                    Text("표시").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 186)
            }
            .frame(height: 44)
            Divider()
            displayTab(display)
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: CodeStylePickerModel.tabsSize.width, height: CodeStylePickerModel.tabsSize.height)
    }

    private static func stageTwo(_ display: ResultDisplaySettings) -> some View {
        VStack(spacing: 0) {
            pickerView(display).frame(maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: CodeStylePickerModel.pickerSize.width, height: CodeStylePickerModel.pickerSize.height)
    }

    private static var footer: some View {
        HStack {
            Text("deepK 개발 버전").font(.system(size: 11)).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
    }

    private static func snapshot(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor))
            .foregroundStyle(Color(nsColor: .labelColor)).font(.system(size: 13)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A point on the sample's source pill, found where a result window makes it a control, and its link's range.
    private static func pillPoint(in view: ResultTextView) -> (NSPoint, NSRange)? {
        for y in stride(from: 0, to: view.frame.height, by: 1) {
            for x in stride(from: 0, to: view.frame.width, by: 1) {
                if case .pill(let range)? = view.chromeControl(at: NSPoint(x: x, y: y)) { return (NSPoint(x: x + 4, y: y + 3), range) }
            }
        }
        return nil
    }

    /// A borderless window far off the screens. It is ordered in, which SwiftUI buttons need to take a click, but no
    /// screen shows it.
    private static func offscreenWindow(_ host: NSView, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return window
    }

    private static func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews(of:))
    }

    /// A press and its release apart, as SwiftUI buttons need.
    private static func click(_ window: NSWindow, _ host: NSView, at point: NSPoint) {
        let location = host.convert(point, to: nil)
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, 0)] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private static func key(_ window: NSWindow, _ function: Int, keyCode: UInt16) {
        let characters = String(UnicodeScalar(UInt32(function))!)
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                          characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    /// A row drawn in the selection color rather than the list's light gray.
    private static func isHighlighted(_ view: NSView, at point: NSPoint) -> Bool {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        guard let color = rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return false }
        return color.brightnessComponent < 0.9
    }

    private static func require(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("CodeStylePickerViewTests failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
