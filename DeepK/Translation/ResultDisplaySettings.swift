import Foundation

/// The 표시 settings: which style the result view draws, and the behaviors that apply to every style.
/// Saved in UserDefaults; a missing or unreadable value falls back to its default.
struct ResultDisplaySettings: Equatable, Sendable {
    enum Key {
        static let style = "resultCodeStyle"
        static let foldsLongCode = "resultFoldsLongCode"
        static let foldLineCount = "resultFoldLineCount"
        static let showsLinkSource = "resultShowsLinkSource"
        static let colorsSyntax = "resultSyntaxColor"
    }

    static let foldLineChoices = [3, 5, 8, 10, 15, 20]
    static let standard = ResultDisplaySettings()

    var style = ResultStyle.native
    var foldsLongCode = true
    /// Lines a folded block keeps visible; always one of `foldLineChoices`.
    var foldLineCount = 5 {
        didSet { if !Self.foldLineChoices.contains(foldLineCount) { foldLineCount = Self.snapped(foldLineCount) } }
    }
    var showsLinkSource = false
    var colorsSyntax = true

    /// The nearest choice; a tie goes to the shorter one. A count outside the choices is first brought to the
    /// nearest end, so a hand-written value as far as `Int.min` cannot overflow the distance.
    static func snapped(_ count: Int) -> Int {
        guard let shortest = foldLineChoices.first, let longest = foldLineChoices.last else { return 5 }
        let count = min(max(count, shortest), longest)
        return foldLineChoices.min { abs($0 - count) < abs($1 - count) } ?? 5
    }

    static func load(from defaults: UserDefaults) -> Self {
        var settings = Self()
        settings.style = ResultStyle.style(for: defaults.string(forKey: Key.style))
        settings.foldsLongCode = defaults.object(forKey: Key.foldsLongCode) as? Bool ?? settings.foldsLongCode
        if let count = defaults.object(forKey: Key.foldLineCount) as? Int { settings.foldLineCount = count }
        settings.showsLinkSource = defaults.object(forKey: Key.showsLinkSource) as? Bool ?? settings.showsLinkSource
        settings.colorsSyntax = defaults.object(forKey: Key.colorsSyntax) as? Bool ?? settings.colorsSyntax
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(style.id.rawValue, forKey: Key.style)
        defaults.set(foldsLongCode, forKey: Key.foldsLongCode)
        defaults.set(foldLineCount, forKey: Key.foldLineCount)
        defaults.set(showsLinkSource, forKey: Key.showsLinkSource)
        defaults.set(colorsSyntax, forKey: Key.colorsSyntax)
    }
}
