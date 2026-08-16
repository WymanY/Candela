import Foundation
import PersistenceKit

enum AppLanguage: String, CaseIterable, Sendable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let appleLanguagesKey = "AppleLanguages"

    var menuTitle: String {
        switch self {
        case .system:
            return String(localized: "System")
        case .english:
            return String(localized: "English")
        case .simplifiedChinese:
            return String(localized: "简体中文")
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
    }
}
