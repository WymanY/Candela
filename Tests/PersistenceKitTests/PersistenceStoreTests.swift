import DisplayCore
import PersistenceKit
import XCTest

final class PersistenceStoreTests: XCTestCase {
    private let keys = ["schemaVersion", "global", "displays", "aliases"]

    override func setUp() {
        super.setUp()
        clearStore()
    }

    override func tearDown() {
        clearStore()
        super.tearDown()
    }

    func testMissingSchemaIsEmpty() {
        let store = PersistenceStore()
        XCTAssertNil(store.record(for: "v1:anything"))
        XCTAssertFalse(store.global().hasOpenedPanelOnce)
        XCTAssertTrue(store.global().restoreOnReconnect)
    }

    func testSaveAndResolveRecord() {
        let store = PersistenceStore()
        var record = DisplayRecord(persistentKey: "v1:v10AC-pD14C-s12345678")
        record.lastBrightness = 0.33
        store.save(record)
        XCTAssertEqual(store.record(for: record.persistentKey)?.lastBrightness, 0.33)
    }

    func testAliasOneHop() {
        let store = PersistenceStore()
        store.save(DisplayRecord(persistentKey: "v1:new"))
        store.alias(old: "v1:old", new: "v1:new")
        XCTAssertEqual(store.resolveAlias("v1:old"), "v1:new")
        XCTAssertEqual(store.record(for: "v1:old")?.persistentKey, "v1:new")
    }

    func testSaveGlobal() {
        let store = PersistenceStore()
        var settings = GlobalSettings()
        settings.hasOpenedPanelOnce = true
        settings.launchAtLogin = true
        store.saveGlobal(settings)
        let loaded = store.global()
        XCTAssertTrue(loaded.hasOpenedPanelOnce)
        XCTAssertTrue(loaded.launchAtLogin)
    }

    func testSavesCustomNameAndContrast() {
        let store = PersistenceStore()
        var record = DisplayRecord(persistentKey: "v1:desk")
        record.customName = "Desk"
        record.lastContrast = 0.4
        record.lastInputCode = 0x11
        record.lastRotationDegrees = 90
        store.save(record)
        let loaded = store.record(for: "v1:desk")
        XCTAssertEqual(loaded?.customName, "Desk")
        XCTAssertEqual(loaded?.lastContrast, 0.4)
        XCTAssertEqual(loaded?.lastInputCode, 0x11)
        XCTAssertEqual(loaded?.lastRotationDegrees, 90)
    }

    private func clearStore() {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
