import CoreGraphics
import Foundation

/// What the 표시 tab and the code style picker decide without a view: list sections, arrow-key selection, row and
/// chip words, and the settings window frame. Pure, so the tests run without a window.
enum CodeStylePickerModel {
    struct Section: Equatable {
        let title: String
        let styles: [ResultStyle]
    }

    struct StatusChip: Equatable {
        let text: String
        let isOn: Bool
    }

    /// The 일반·번역·표시 tabs.
    static let tabsSize = CGSize(width: 340, height: 376)
    /// The picker: 620 wide (S6′), and tall enough that the preview never scrolls for a built-in style (see `previewHeight`).
    static let pickerSize = CGSize(width: 620, height: 460)
    static let sidebarWidth: CGFloat = 200
    /// The preview is the result view at the small window's width: 366pt of text plus the 18pt scroller gutter.
    static let previewWidth: CGFloat = 384
    /// The sample's tallest built-in rendering: GitHub with the source pill and the block unfolded (N ≥ 8 or 접기 끔).
    static let previewHeight: CGFloat = 262
    /// From this many styles the list gets a search field and light/dark sections.
    static let searchThreshold = 10

    static func showsSearch(styleCount: Int) -> Bool { styleCount >= searchThreshold }

    /// One "기본 제공" section for a short list; from `searchThreshold` styles, the ones matching `query` split into
    /// light and dark code, and an empty section is left out.
    static func sections(styles: [ResultStyle], query: String = "") -> [Section] {
        guard showsSearch(styleCount: styles.count) else { return [Section(title: "기본 제공", styles: styles)] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = needle.isEmpty ? styles : styles.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.summary.localizedCaseInsensitiveContains(needle)
        }
        return [
            Section(title: "밝은 코드", styles: matching.filter { !isDark($0) }),
            Section(title: "어두운 코드", styles: matching.filter(isDark))
        ].filter { !$0.styles.isEmpty }
    }

    /// The style `offset` rows from `id` in list order, stopping at the ends. A style that is not listed (filtered
    /// out by a search) moves to the first or last listed one.
    static func adjacent(to id: ResultStyle.ID, offset: Int, in sections: [Section]) -> ResultStyle.ID? {
        let listed = sections.flatMap(\.styles).map(\.id)
        guard !listed.isEmpty else { return nil }
        guard let index = listed.firstIndex(of: id) else { return offset < 0 ? listed.last : listed.first }
        return listed[min(max(index + offset, 0), listed.count - 1)]
    }

    /// The style ↑↓ selects: `offset` rows from `current` among the styles the search `query` leaves listed.
    static func style(offset: Int, from current: ResultStyle, in styles: [ResultStyle], query: String) -> ResultStyle? {
        guard let id = adjacent(to: current.id, offset: offset, in: sections(styles: styles, query: query)) else { return nil }
        return styles.first { $0.id == id }
    }

    /// The picker's reminder that the 표시 tab's behaviors apply to every style.
    static func statusChips(_ display: ResultDisplaySettings) -> [StatusChip] {
        [
            StatusChip(text: display.foldsLongCode ? "접기 \(display.foldLineCount)줄" : "접기 끔", isOn: display.foldsLongCode),
            StatusChip(text: display.colorsSyntax ? "문법 색" : "문법 색 끔", isOn: display.colorsSyntax),
            StatusChip(text: display.showsLinkSource ? "출처 표시" : "출처 끔", isOn: display.showsLinkSource)
        ]
    }

    static func foldSubtitle(_ display: ResultDisplaySettings) -> String {
        display.foldsLongCode ? "\(display.foldLineCount)줄이 넘으면 접고 ‘더 보기’로 펼칩니다" : "긴 코드를 모두 펼쳐 보여 줍니다"
    }

    static func foldChoiceTitle(_ count: Int) -> String { "\(count)줄" }

    /// A style whose light card is dark: the card over white has a relative luminance under 0.4. A style without a
    /// card (a rail) is light.
    static func isDark(_ style: ResultStyle) -> Bool {
        guard let fill = style.box.fill?.light else { return false }
        func channel(_ value: CGFloat) -> CGFloat {
            let over = value * fill.alpha + (1 - fill.alpha)
            return over <= 0.03928 ? over / 12.92 : pow((over + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(fill.red) + 0.7152 * channel(fill.green) + 0.0722 * channel(fill.blue) < 0.4
    }

    /// The settings window frame for `targetSize`, keeping the top-left corner and staying inside `visibleFrame`.
    /// `shift` is how far the screen edges pushed the window; pass it back on the way back so the window returns to
    /// where it was. Pass zero when the window was moved in between: the reader put it there.
    static func settingsFrame(current: CGRect, targetSize: CGSize, visibleFrame: CGRect,
                              rememberedShift: CGVector = .zero) -> (frame: CGRect, shift: CGVector) {
        let left = current.minX - rememberedShift.dx
        let top = current.maxY - rememberedShift.dy
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return (CGRect(x: left, y: top - targetSize.height, width: targetSize.width, height: targetSize.height), .zero)
        }
        let width = min(targetSize.width, visibleFrame.width)
        let height = min(targetSize.height, visibleFrame.height)
        let x = min(max(left, visibleFrame.minX), visibleFrame.maxX - width)
        let clampedTop = min(max(top, visibleFrame.minY + height), visibleFrame.maxY)
        let frame = CGRect(x: x, y: clampedTop - height, width: width, height: height)
        return (frame, CGVector(dx: x - left, dy: clampedTop - top))
    }
}

/// Keeps only the newest of rapid changes: each `submit` restarts the quiet interval, and `fire` hands back the
/// newest value once the interval has passed. The caller owns the clock and the timer.
struct LatestValueCoalescer<Value> {
    let interval: Duration
    private(set) var pending: Value?
    private(set) var deadline: ContinuousClock.Instant?

    init(interval: Duration) {
        self.interval = interval
    }

    /// Holds `value` as the newest. Returns true when no wait was running, so the caller starts one.
    mutating func submit(_ value: Value, at now: ContinuousClock.Instant) -> Bool {
        let waiting = deadline != nil
        pending = value
        deadline = now + interval
        return !waiting
    }

    /// The newest value once the interval has passed, or nil before it (wait until `deadline` again).
    mutating func fire(at now: ContinuousClock.Instant) -> Value? {
        guard let deadline, now >= deadline else { return nil }
        return flush()
    }

    /// The pending value now, ending the wait.
    mutating func flush() -> Value? {
        defer {
            pending = nil
            deadline = nil
        }
        return pending
    }
}
