import Foundation

/// Runtime locale used by Candela UI strings.
///
/// String(localized:) follows the process language chosen at launch, so a
/// Settings change looks up strings from the catalog instead of that cache.
public enum CandelaText {
    public static var locale = Locale.autoupdatingCurrent
    public static let supportedLanguageCodes = ["en", "zh-Hans"]
    fileprivate static var catalogs: [ObjectIdentifier: Catalog] = [:]

    public static func applyPreferredLanguage(_ rawValue: String) {
        locale = locale(forPreferredLanguage: rawValue)
    }

    public static func locale(forPreferredLanguage rawValue: String) -> Locale {
        let preferences = rawValue.isEmpty ? systemLanguageCodes() : [rawValue]
        let code = Bundle.preferredLocalizations(
            from: supportedLanguageCodes,
            forPreferences: preferences
        ).first ?? "en"
        return Locale(identifier: code)
    }

    public static func string(
        _ value: String.LocalizationValue,
        bundle: Bundle,
        locale preferredLocale: Locale? = nil
    ) -> String {
        let used = preferredLocale ?? locale
        let extracted = Extraction(value)
        if let template = lookup(extracted.key, bundle: bundle, locale: used) {
            return extracted.format(template, locale: used)
        }
        return String(localized: value, bundle: bundle, locale: used)
    }

    public static func systemLanguageCodes() -> [String] {
        if let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
           !languages.isEmpty
        {
            return languages
        }
        return Locale.preferredLanguages
    }

    fileprivate static func lookup(_ key: String, bundle: Bundle, locale: Locale) -> String? {
        if let template = catalog(for: bundle).template(for: key, locale: locale) {
            return template
        }
        let sentinel = "<<missing>>"
        for identifier in localizationCandidates(for: locale) {
            guard let path = bundle.path(forResource: identifier, ofType: "lproj"),
                  let child = Bundle(path: path)
            else {
                continue
            }
            let value = child.localizedString(forKey: key, value: sentinel, table: "Localizable")
            if value != sentinel {
                return value
            }
        }
        return nil
    }

    fileprivate static func catalog(for bundle: Bundle) -> Catalog {
        let id = ObjectIdentifier(bundle)
        if let existing = catalogs[id] {
            return existing
        }
        let created = Catalog(bundle: bundle)
        catalogs[id] = created
        return created
    }

    fileprivate static func localizationCandidates(for locale: Locale) -> [String] {
        var items = [resolvedCode(for: locale), locale.identifier]
        switch resolvedCode(for: locale) {
        case "zh-Hans":
            items += ["zh_Hans", "zh-CN", "zh_CN", "zh"]
        case "en":
            items += ["en-US", "en_US", "Base"]
        default:
            break
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    fileprivate static func resolvedCode(for locale: Locale) -> String {
        let identifier = locale.identifier
        if supportedLanguageCodes.contains(identifier) {
            return identifier
        }
        if identifier.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en"
    }
}

func localized(_ value: String.LocalizationValue) -> String {
    CandelaText.string(value, bundle: .module)
}

private struct Extraction {
    let key: String
    let arguments: [CVarArg]

    init(_ value: String.LocalizationValue) {
        var key = ""
        var arguments: [CVarArg] = []
        for child in Mirror(reflecting: value).children {
            if child.label == "key", let text = child.value as? String {
                key = text
            } else if child.label == "arguments" {
                arguments = Self.unwrapArguments(child.value)
            }
        }
        self.key = key
        self.arguments = arguments
    }

    func format(_ template: String, locale: Locale) -> String {
        if arguments.isEmpty {
            return template
        }
        return String(format: template, locale: locale, arguments: arguments)
    }

    static func unwrapArguments(_ value: Any) -> [CVarArg] {
        var result: [CVarArg] = []
        for child in Mirror(reflecting: value).children {
            if let arg = unwrap(child.value) {
                result.append(arg)
            }
        }
        return result
    }

    static func unwrap(_ value: Any) -> CVarArg? {
        var current: Any = value
        for _ in 0..<8 {
            if let number = current as? Int {
                return number
            }
            if let number = current as? Int64 {
                return number
            }
            if let number = current as? UInt64 {
                return number
            }
            if let number = current as? Double {
                return number
            }
            if let text = current as? String {
                return text
            }
            let children = Array(Mirror(reflecting: current).children)
            if children.isEmpty {
                return nil
            }
            if let labeled = children.first(where: { child in
                child.label == "value" || child.label == "some"
            }) {
                current = labeled.value
                continue
            }
            if children.count == 1 {
                current = children[0].value
                continue
            }
            return nil
        }
        return nil
    }
}

private struct Catalog {
    let translations: [String: [String: String]]

    init(bundle: Bundle) {
        var translations: [String: [String: String]] = [:]
        let urls = [
            bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
            bundle.resourceURL?.appendingPathComponent("Localizable.xcstrings"),
        ].compactMap { url in url }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let strings = root["strings"] as? [String: Any]
            else {
                continue
            }
            for (key, raw) in strings {
                guard let entry = raw as? [String: Any],
                      let localizations = entry["localizations"] as? [String: Any]
                else {
                    continue
                }
                var byLocale: [String: String] = [:]
                for (locale, payload) in localizations {
                    guard let body = payload as? [String: Any],
                          let unit = body["stringUnit"] as? [String: Any],
                          let value = unit["value"] as? String
                    else {
                        continue
                    }
                    byLocale[locale] = value
                }
                translations[key] = byLocale
            }
            break
        }
        self.translations = translations
    }

    func template(for key: String, locale: Locale) -> String? {
        guard let byLocale = translations[key] else {
            return nil
        }
        let code = CandelaText.resolvedCode(for: locale)
        return byLocale[code] ?? byLocale["en"] ?? byLocale.values.first
    }
}
