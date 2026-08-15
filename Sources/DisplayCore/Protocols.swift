import Foundation

public protocol DDCCommanding: AnyObject {
    var isAvailable: Bool { get }
    func read(vcp: UInt8) throws -> (current: UInt16, max: UInt16)
    func write(vcp: UInt8, value: UInt16) throws
    func recreateHandle() throws
}

public protocol DisplayCataloging: AnyObject {
    var snapshots: [DisplaySnapshot] { get }
    var updates: AsyncStream<[DisplaySnapshot]> { get }
    func start()
    func stop()
    func requestRescan()
}

public extension DisplayCataloging {
    func requestRescan() {}
}

extension Notification.Name {
    /// AppKit observers post this so kits can rescan without importing AppKit.
    public static let candelaCatalogShouldRescan = Notification.Name("app.candela.catalogShouldRescan")
}

public protocol PersistenceStoring: AnyObject {
    func record(for key: String) -> DisplayRecord?
    func save(_ record: DisplayRecord)
    func resolveAlias(_ key: String) -> String
    func alias(old: String, new: String)
    func global() -> GlobalSettings
    func saveGlobal(_ settings: GlobalSettings)
    func allRecords() -> [String: DisplayRecord]
    func allAliases() -> [String: String]
}

public extension PersistenceStoring {
    func allRecords() -> [String: DisplayRecord] { [:] }
    func allAliases() -> [String: String] { [:] }
}
