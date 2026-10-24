import CoreGraphics
import Foundation

@main
private enum CodeStylePickerModelTests {
    static func main() {
        sectionsForTheBuiltIns()
        sectionsForManyStyles()
        searchStartsAtTen()
        arrowKeysClampAtTheEnds()
        arrowKeysFollowTheSearch()
        statusChipsAndRowWords()
        darkStyles()
        settingsFrameKeepsTheTopLeft()
        settingsFrameStaysOnScreen()
        settingsFrameReturns()
        settingsFrameWithoutAScreen()
        rapidChangesKeepTheLatest()
        print("CodeStylePickerModelTests passed")
    }

    private static func sectionsForTheBuiltIns() {
        let sections = CodeStylePickerModel.sections(styles: ResultStyle.builtIns)
        require(sections == [.init(title: "기본 제공", styles: [.native, .github])], "two styles are one '기본 제공' section")
        require(!CodeStylePickerModel.showsSearch(styleCount: ResultStyle.builtIns.count), "no search for two styles")
        require(CodeStylePickerModel.sections(styles: ResultStyle.builtIns, query: "git") == sections,
                "a short list ignores a query (it has no search field)")
    }

    private static func sectionsForManyStyles() {
        let styles = (1...12).map { fixture($0, dark: $0 > 8) }
        require(CodeStylePickerModel.showsSearch(styleCount: styles.count), "ten or more styles get a search field")
        let sections = CodeStylePickerModel.sections(styles: styles)
        require(sections.map(\.title) == ["밝은 코드", "어두운 코드"], "light and dark sections: \(sections.map(\.title))")
        require(sections.map(\.styles.count) == [8, 4], "8 light, 4 dark")
        require(sections[0].styles.map(\.name) == (1...8).map { "Style \($0)" }, "sections keep the list order")

        let found = CodeStylePickerModel.sections(styles: styles, query: "  style 1 ")
        require(found.flatMap(\.styles).map(\.name) == ["Style 1", "Style 10", "Style 11", "Style 12"],
                "search trims and ignores case: \(found.flatMap(\.styles).map(\.name))")
        require(found.map(\.title) == ["밝은 코드", "어두운 코드"], "both sections still match")
        let onlyDark = CodeStylePickerModel.sections(styles: styles, query: "Style 9")
        require(onlyDark.map(\.title) == ["어두운 코드"], "an empty section is left out")
        require(CodeStylePickerModel.sections(styles: styles, query: "dark summary").flatMap(\.styles).count == 4,
                "search reads the summary too")
        require(CodeStylePickerModel.sections(styles: styles, query: "zzz").isEmpty, "no match, no sections")
    }

    /// Ten styles is where the search field and the light/dark sections start; nine stay one list.
    private static func searchStartsAtTen() {
        let nine = (1...9).map { fixture($0, dark: $0 > 7) }
        require(!CodeStylePickerModel.showsSearch(styleCount: 9), "nine styles get no search field")
        require(CodeStylePickerModel.sections(styles: nine).map(\.title) == ["기본 제공"], "nine styles are one section")
        let ten = (1...10).map { fixture($0, dark: $0 > 7) }
        require(CodeStylePickerModel.showsSearch(styleCount: 10), "ten styles get a search field")
        require(CodeStylePickerModel.sections(styles: ten).map(\.title) == ["밝은 코드", "어두운 코드"], "ten styles split light and dark")
    }

    private static func arrowKeysClampAtTheEnds() {
        let builtIns = CodeStylePickerModel.sections(styles: ResultStyle.builtIns)
        require(CodeStylePickerModel.adjacent(to: .native, offset: 1, in: builtIns) == .github, "↓ moves to the next style")
        require(CodeStylePickerModel.adjacent(to: .github, offset: -1, in: builtIns) == .native, "↑ moves back")
        require(CodeStylePickerModel.adjacent(to: .native, offset: -1, in: builtIns) == .native, "↑ stops at the first style")
        require(CodeStylePickerModel.adjacent(to: .github, offset: 1, in: builtIns) == .github, "↓ stops at the last style")

        let styles = (1...12).map { fixture($0, dark: $0 > 8) }
        let sections = CodeStylePickerModel.sections(styles: styles)
        require(CodeStylePickerModel.adjacent(to: styles[7].id, offset: 1, in: sections) == styles[8].id,
                "↓ crosses from the light section into the dark one")
        require(CodeStylePickerModel.adjacent(to: styles[11].id, offset: 1, in: sections) == styles[11].id, "clamps at the end")
        let filtered = CodeStylePickerModel.sections(styles: styles, query: "Style 1")
        require(CodeStylePickerModel.adjacent(to: styles[4].id, offset: 1, in: filtered) == styles[0].id,
                "a style hidden by the search moves to the first listed one on ↓")
        require(CodeStylePickerModel.adjacent(to: styles[4].id, offset: -1, in: filtered) == styles[11].id,
                "and to the last one on ↑")
        require(CodeStylePickerModel.adjacent(to: .native, offset: 1, in: []) == nil, "nothing listed, nothing to select")
    }

    /// ↑↓ move through the styles the search leaves listed, as the picker shows them.
    private static func arrowKeysFollowTheSearch() {
        let styles = (1...12).map { fixture($0, dark: $0 > 8) }
        require(CodeStylePickerModel.style(offset: 1, from: styles[0], in: styles, query: "") == styles[1], "↓ without a search")
        require(CodeStylePickerModel.style(offset: 1, from: styles[0], in: styles, query: "Style 1") == styles[9],
                "↓ skips the styles the search hides (Style 1 → Style 10)")
        require(CodeStylePickerModel.style(offset: -1, from: styles[9], in: styles, query: "Style 1") == styles[0], "and ↑ back")
        require(CodeStylePickerModel.style(offset: 1, from: styles[4], in: styles, query: "Style 1") == styles[0],
                "a hidden style moves to the first listed one")
        require(CodeStylePickerModel.style(offset: 1, from: styles[0], in: styles, query: "zzz") == nil, "nothing listed")
        require(CodeStylePickerModel.style(offset: 1, from: .native, in: ResultStyle.builtIns, query: "") == .github, "the built-ins")
    }

    private static func statusChipsAndRowWords() {
        for folds in [false, true] {
            for colors in [false, true] {
                for source in [false, true] {
                    for count in ResultDisplaySettings.foldLineChoices {
                        var display = ResultDisplaySettings.standard
                        display.foldsLongCode = folds
                        display.foldLineCount = count
                        display.colorsSyntax = colors
                        display.showsLinkSource = source
                        let chips = CodeStylePickerModel.statusChips(display)
                        require(chips == [
                            .init(text: folds ? "접기 \(count)줄" : "접기 끔", isOn: folds),
                            .init(text: colors ? "문법 색" : "문법 색 끔", isOn: colors),
                            .init(text: source ? "출처 표시" : "출처 끔", isOn: source)
                        ], "chips for fold \(folds) \(count), syntax \(colors), source \(source): \(chips)")
                        require(CodeStylePickerModel.foldSubtitle(display)
                                == (folds ? "\(count)줄이 넘으면 접고 ‘더 보기’로 펼칩니다" : "긴 코드를 모두 펼쳐 보여 줍니다"),
                                "fold row subtitle")
                    }
                }
            }
        }
        require(ResultDisplaySettings.foldLineChoices.map(CodeStylePickerModel.foldChoiceTitle)
                == ["3줄", "5줄", "8줄", "10줄", "15줄", "20줄"], "fold menu choices")
    }

    private static func darkStyles() {
        require(!CodeStylePickerModel.isDark(.native) && !CodeStylePickerModel.isDark(.github), "the built-ins are light")
        require(CodeStylePickerModel.isDark(fixture(1, dark: true)), "#282C34 is dark")
        require(!CodeStylePickerModel.isDark(fixture(1, dark: false)), "#F6F8FA is light")
        require(!CodeStylePickerModel.isDark(fixture(1, dark: false, fill: .some(nil))), "no card is light")
        require(!CodeStylePickerModel.isDark(fixture(1, dark: false, fill: StyleColor.alpha(0x000000, 0.3, dark: 0.3))),
                "a translucent card is judged over white (30% black is light)")
        require(CodeStylePickerModel.isDark(fixture(1, dark: false, fill: StyleColor.alpha(0x000000, 0.7, dark: 0.7))),
                "70% black is dark")
        // The 0.4 line: #A9A9A9 is 0.397, #AAAAAA 0.402.
        require(CodeStylePickerModel.isDark(fixture(1, dark: false, fill: StyleColor.hex(0xA9A9A9))), "just under 0.4 is dark")
        require(!CodeStylePickerModel.isDark(fixture(1, dark: false, fill: StyleColor.hex(0xAAAAAA))), "just over 0.4 is light")
    }

    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private static let tabs = CodeStylePickerModel.tabsSize
    private static let picker = CodeStylePickerModel.pickerSize

    private static func settingsFrameKeepsTheTopLeft() {
        require(tabs == CGSize(width: 340, height: 376), "the tabs keep the window size every tab has")
        require(picker.width == 620, "the picker is 620 wide")
        let current = CGRect(x: 300, y: 300, width: tabs.width, height: tabs.height)
        let wide = CodeStylePickerModel.settingsFrame(current: current, targetSize: picker, visibleFrame: screen)
        require(wide.frame == CGRect(x: 300, y: current.maxY - picker.height, width: picker.width, height: picker.height),
                "the left and top edges stay: \(wide.frame)")
        require(wide.shift == .zero, "nothing pushed it")
    }

    private static func settingsFrameStaysOnScreen() {
        // Near the right edge: the window moves left by what does not fit.
        let right = CGRect(x: 1000, y: 300, width: tabs.width, height: tabs.height)
        let pushedLeft = CodeStylePickerModel.settingsFrame(current: right, targetSize: picker, visibleFrame: screen)
        require(pushedLeft.frame.maxX == screen.maxX && pushedLeft.frame.maxY == right.maxY, "clamped at the right edge: \(pushedLeft.frame)")
        require(pushedLeft.shift == CGVector(dx: -180, dy: 0), "the shift is remembered: \(pushedLeft.shift)")

        // Near the bottom: the taller picker moves up.
        let low = CGRect(x: 300, y: 20, width: tabs.width, height: tabs.height)
        let pushedUp = CodeStylePickerModel.settingsFrame(current: low, targetSize: picker, visibleFrame: screen)
        require(pushedUp.frame.minY == screen.minY && pushedUp.frame.minX == 300, "clamped at the bottom edge: \(pushedUp.frame)")
        require(pushedUp.shift == CGVector(dx: 0, dy: picker.height - tabs.height - 20), "upward shift: \(pushedUp.shift)")

        // Left of the screen (a second display's visible frame starts elsewhere) and above it.
        let display = CGRect(x: -1280, y: 100, width: 1280, height: 700)
        let off = CGRect(x: -1400, y: 600, width: tabs.width, height: tabs.height)
        let pulled = CodeStylePickerModel.settingsFrame(current: off, targetSize: picker, visibleFrame: display)
        require(pulled.frame.minX == display.minX && pulled.frame.maxY == display.maxY, "clamped at the left and top edges: \(pulled.frame)")

        // A screen narrower or shorter than the picker: as large as fits.
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let fitted = CodeStylePickerModel.settingsFrame(current: CGRect(x: 100, y: 10, width: 340, height: 376),
                                                        targetSize: picker, visibleFrame: small)
        require(fitted.frame == small, "fills a screen too small for it: \(fitted.frame)")
    }

    private static func settingsFrameReturns() {
        for start in [CGRect(x: 300, y: 300, width: 340, height: 376), CGRect(x: 1050, y: 30, width: 340, height: 376)] {
            let wide = CodeStylePickerModel.settingsFrame(current: start, targetSize: picker, visibleFrame: screen)
            let back = CodeStylePickerModel.settingsFrame(current: wide.frame, targetSize: tabs, visibleFrame: screen,
                                                          rememberedShift: wide.shift)
            require(back.frame == start, "back to 340×376 where it was: \(back.frame) for \(start)")
            require(back.shift == .zero, "nothing left to undo")
        }
        // Moved while wide: the reader's place wins and only the size changes back.
        let wide = CodeStylePickerModel.settingsFrame(current: CGRect(x: 1050, y: 300, width: 340, height: 376),
                                                      targetSize: picker, visibleFrame: screen)
        let moved = wide.frame.offsetBy(dx: -400, dy: 50)
        let back = CodeStylePickerModel.settingsFrame(current: moved, targetSize: tabs, visibleFrame: screen)
        require(back.frame == CGRect(x: moved.minX, y: moved.maxY - tabs.height, width: tabs.width, height: tabs.height),
                "a moved window keeps its top-left: \(back.frame)")
    }

    /// No screen (the window is between displays): the size changes around the top-left corner and nothing is clamped.
    private static func settingsFrameWithoutAScreen() {
        let current = CGRect(x: 300, y: 300, width: tabs.width, height: tabs.height)
        let wide = CodeStylePickerModel.settingsFrame(current: current, targetSize: picker, visibleFrame: .zero)
        require(wide.frame == CGRect(x: 300, y: current.maxY - picker.height, width: picker.width, height: picker.height),
                "the picker size around the top-left: \(wide.frame)")
        require(wide.shift == .zero, "nothing to undo")
        let back = CodeStylePickerModel.settingsFrame(current: wide.frame, targetSize: tabs, visibleFrame: .zero,
                                                      rememberedShift: CGVector(dx: -40, dy: 10))
        require(back.frame == CGRect(x: 340, y: current.maxY - 10 - tabs.height, width: tabs.width, height: tabs.height),
                "a remembered shift is still undone: \(back.frame)")
    }

    private static func rapidChangesKeepTheLatest() {
        let start = ContinuousClock.now
        var saves = LatestValueCoalescer<Int>(interval: .milliseconds(300))
        require(saves.submit(1, at: start), "the first change starts a wait")
        require(!saves.submit(2, at: start + .milliseconds(100)), "a change during the wait joins it")
        require(!saves.submit(3, at: start + .milliseconds(200)), "and so does the next")
        require(saves.deadline == start + .milliseconds(500), "each change restarts the quiet interval")
        require(saves.fire(at: start + .milliseconds(300)) == nil, "the first deadline has moved: wait again")
        require(saves.pending == 3, "only the newest value is held")
        require(saves.fire(at: start + .milliseconds(500)) == 3, "once quiet, the newest value is saved")
        require(saves.fire(at: start + .milliseconds(900)) == nil && saves.deadline == nil, "and only once")
        require(saves.submit(4, at: start + .seconds(1)), "a later change starts a new wait")
        require(saves.flush() == 4 && saves.flush() == nil, "closing the window saves at once, once")
    }

    private static func fixture(_ number: Int, dark: Bool, fill: StyleColor?? = .none) -> ResultStyle {
        let base = ResultStyle.github
        // `.some(nil)` is a style without a card.
        let card: StyleColor? = fill ?? StyleColor.hex(dark ? 0x282C34 : 0xF6F8FA)
        return ResultStyle(
            id: ResultStyle.ID(rawValue: "fixture-\(number)"), name: "Style \(number)",
            summary: dark ? "dark summary" : "light summary", detail: "",
            box: ResultStyle.Box(fill: card, border: nil, radius: 6, insets: base.box.insets, bodyTop: 2, bodyBottom: 14),
            header: base.header, code: base.code, syntax: base.syntax, fold: base.fold, chip: base.chip, link: base.link,
            pill: base.pill
        )
    }

    private static func require(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("CodeStylePickerModelTests failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
