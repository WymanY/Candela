import DisplayCore
import Foundation

public final class PersistenceStore: PersistenceStoring {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let schemaVersion = "schemaVersion"
        static let global = "global"
        static let displays = "displays"
        static let aliases = "aliases"
    }

    public init() {
        self.defaults = .standard
    }

    public func record(for key: String) -> DisplayRecord? {
        guard hasSchema else { return nil }
        return loadDisplays()[resolveAlias(key)]
    }

    public func save(_ record: DisplayRecord) {
        ensureSchema()
        var displays = loadDisplays()
        displays[record.persistentKey] = record
        saveDisplays(displays)
    }

    public func resolveAlias(_ key: String) -> String {
        loadAliases()[key] ?? key
    }

    public func alias(old: String, new: String) {
        ensureSchema()
        var aliases = loadAliases()
        aliases[old] = new
        saveAliases(aliases)
    }

    public func global() -> GlobalSettings {
        guard hasSchema else { return GlobalSettings() }
        guard let data = defaults.data(forKey: Key.global),
              let settings = try? decoder.decode(GlobalSettings.self, from: data)
        else {
            return GlobalSettings()
        }
        return settings
    }

    public func saveGlobal(_ settings: GlobalSettings) {
        ensureSchema()
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: Key.global)
        }
        defaults.set(settings.schemaVersion, forKey: Key.schemaVersion)
    }

    public func allRecords() -> [String: DisplayRecord] {
        guard hasSchema else { return [:] }
        return loadDisplays()
    }

    public func allAliases() -> [String: String] {
        guard hasSchema else { return [:] }
        return loadAliases()
    }

    private var hasSchema: Bool {
        defaults.object(forKey: Key.schemaVersion) != nil
    }

    private func ensureSchema() {
        if defaults.object(forKey: Key.schemaVersion) == nil {
            defaults.set(1, forKey: Key.schemaVersion)
        }
    }

    private func loadDisplays() -> [String: DisplayRecord] {
        guard let data = defaults.data(forKey: Key.displays),
              let records = try? decoder.decode([String: DisplayRecord].self, from: data)
        else {
            return [:]
        }
        return records
    }

    private func saveDisplays(_ records: [String: DisplayRecord]) {
        if let data = try? encoder.encode(records) {
            defaults.set(data, forKey: Key.displays)
        }
    }

    private func loadAliases() -> [String: String] {
        guard let data = defaults.data(forKey: Key.aliases),
              let aliases = try? decoder.decode([String: String].self, from: data)
        else {
            return [:]
        }
        return aliases
    }

    private func saveAliases(_ aliases: [String: String]) {
        if let data = try? encoder.encode(aliases) {
            defaults.set(data, forKey: Key.aliases)
        }
    }
}
