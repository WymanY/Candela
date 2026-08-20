import DisplayCore
import Foundation
import PersistenceKit

func localizedText(_ value: String.LocalizationValue) -> String {
    CandelaText.string(value, bundle: .main)
}

enum AppLanguage: String, CaseIterable, Sendable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let appleLanguagesKey = "AppleLanguages"

    var menuTitle: String {
        switch self {
        case .system:
            return localizedText("System")
        case .english:
            return localizedText("English")
        case .simplifiedChinese:
            return localizedText("简体中文")
        }
    }

    static func applyStoredPreference() {
        apply(PersistenceStore().global().preferredLanguage)
    }

    static func apply(_ rawValue: String) {
        let language = AppLanguage(rawValue: rawValue) ?? .system
        let defaults = UserDefaults.standard
        switch language {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        case .english, .simplifiedChinese:
            defaults.set([language.rawValue], forKey: appleLanguagesKey)
        }
        defaults.synchronize()
        CandelaText.applyPreferredLanguage(rawValue)
    }
}
