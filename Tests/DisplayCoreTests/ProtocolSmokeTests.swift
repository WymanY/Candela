import XCTest
@testable import DisplayCore

final class ProtocolSmokeTests: XCTestCase {
    func testDDCCommandingSmoke() throws {
        let ddc = InMemoryDDC()
        XCTAssertTrue(ddc.isAvailable)
        let brightness = try ddc.read(vcp: 0x10)
        XCTAssertEqual(brightness.current, 50)
        XCTAssertEqual(brightness.max, 100)
        try ddc.write(vcp: 0x10, value: 80)
        XCTAssertEqual(try ddc.read(vcp: 0x10).current, 80)
        try ddc.recreateHandle()
        XCTAssertEqual(ddc.recreateCount, 1)
    }

    func testDisplayCatalogingSmoke() {
        let catalog = StaticCatalog(snapshots: [])
        XCTAssertTrue(catalog.snapshots.isEmpty)
        catalog.start()
        XCTAssertTrue(catalog.started)
        catalog.stop()
        XCTAssertFalse(catalog.started)
    }

    func testPersistenceStoringSmoke() {
        let store = MemoryStore()
        XCTAssertNil(store.record(for: "v1:missing"))
        var record = DisplayRecord(persistentKey: "v1:foo")
        record.lastBrightness = 0.4
        store.save(record)
        XCTAssertEqual(store.record(for: "v1:foo")?.lastBrightness, 0.4)
        store.alias(old: "v1:old", new: "v1:foo")
        XCTAssertEqual(store.resolveAlias("v1:old"), "v1:foo")
        var settings = store.global()
        settings.hasOpenedPanelOnce = true
        store.saveGlobal(settings)
        XCTAssertTrue(store.global().hasOpenedPanelOnce)
        XCTAssertEqual(store.allRecords()["v1:foo"]?.lastBrightness, 0.4)
        XCTAssertEqual(store.allAliases()["v1:old"], "v1:foo")
    }

    func testAudioMatchingBuiltInNeverBinds() {
        let snapshot = DisplaySnapshot(
            id: DisplayIdentity(
                persistentKey: "v1:v0610-pA050-s00000001",
                fields: DisplayIdentityFields(
                    inputs: DisplayIdentityInputs(
                        vendorID: 0x0610,
                        productID: 0xA050,
                        serial: 0x0000_0001,
                        portLocation: "port",
                        unitNumber: 0,
                        fallbackName: "Built-in Display"
                    )
                )
            ),
            sessionDisplayID: 1,
            name: "Built-in Display",
            kind: .builtIn,
            isMain: true,
            isBuiltin: true,
            connection: .builtIn,
            brightness: BrightnessCapabilities(
                backend: .displayServices,
                supportsHardware: true,
                supportsSoftware: false,
                current: 0.5
            ),
            volume: VolumeCapabilities(
                backend: .none,
                supportsVolume: false,
                supportsMute: false,
                current: 0
            )
        )
        let uid = AudioMatching.match(
            display: snapshot,
            overrideUID: "dev-1",
            devices: [
                HALOutputDevice(
                    uid: "dev-1",
                    name: "Built-in Display",
                    manufacturer: "Apple",
                    transport: AudioMatching.transportHDMI,
                    hasVolume: true,
                    hasMute: true
                ),
            ]
        )
        XCTAssertNil(uid)
    }
}

private final class InMemoryDDC: DDCCommanding {
    var isAvailable = true
    var values: [UInt8: (current: UInt16, max: UInt16)] = [0x10: (50, 100)]
    var recreateCount = 0

    func read(vcp: UInt8) throws -> (current: UInt16, max: UInt16) {
        values[vcp] ?? (0, 0)
    }

    func write(vcp: UInt8, value: UInt16) throws {
        let max = values[vcp]?.max ?? 100
        values[vcp] = (value, max)
    }

    func recreateHandle() throws {
        recreateCount += 1
    }
}

private final class StaticCatalog: DisplayCataloging {
    let snapshots: [DisplaySnapshot]
    let updates: AsyncStream<[DisplaySnapshot]>
    private let continuation: AsyncStream<[DisplaySnapshot]>.Continuation
    var started = false

    init(snapshots: [DisplaySnapshot]) {
        self.snapshots = snapshots
        let stream = AsyncStream<[DisplaySnapshot]>.makeStream()
        self.updates = stream.0
        self.continuation = stream.1
    }

    func start() {
        started = true
        continuation.yield(snapshots)
    }

    func stop() {
        started = false
        continuation.finish()
    }
}

private final class MemoryStore: PersistenceStoring {
    private var records: [String: DisplayRecord] = [:]
    private var aliases: [String: String] = [:]
    private var settings = GlobalSettings()

    func record(for key: String) -> DisplayRecord? {
        records[resolveAlias(key)]
    }

    func save(_ record: DisplayRecord) {
        records[record.persistentKey] = record
    }

    func resolveAlias(_ key: String) -> String {
        aliases[key] ?? key
    }

    func alias(old: String, new: String) {
        aliases[old] = new
    }

    func global() -> GlobalSettings {
        settings
    }

    func saveGlobal(_ settings: GlobalSettings) {
        self.settings = settings
    }

    func allRecords() -> [String: DisplayRecord] {
        records
    }

    func allAliases() -> [String: String] {
        aliases
    }
}
