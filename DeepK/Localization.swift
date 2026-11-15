import Foundation

/// Keep interface language separate from the translation target. Simplified Chinese UI uses English.
func DKUILanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
    for identifier in preferredLanguages {
        let code = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if code.hasPrefix("zh") {
            if code.contains("hant") { return "zh-Hant" }
            return code.contains("hans") || code.contains("-cn") || code.contains("-sg") ? "en" : "zh-Hant"
        }
        for supported in ["ko", "ja", "en"] where code == supported || code.hasPrefix(supported + "-") { return supported }
    }
    return "en"
}

func DKLocalized(_ key: String) -> String {
    guard let path = Bundle.main.path(forResource: DKUILanguage(), ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
}

func DKFormat(_ key: String, _ arguments: Any...) -> String {
    String(format: DKLocalized(key), locale: Locale(identifier: DKUILanguage()),
           arguments: arguments.map { String(describing: $0) as CVarArg })
}
