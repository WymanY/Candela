import CoreGraphics
import XCTest
@testable import DisplayCore

final class LiveCatalogBuilderTests: XCTestCase {
    func testVirtualGetsNoSliderGenericGetsPreview() {
        let builtIn = fact(
            id: 1,
            builtin: true,
            main: true,
            vendor: 0x0610,
            product: 0xA050,
            serial: 1,
            port: "IOService:/built-in",
            name: "Color LCD"
        )
        let sidecar = fact(
            id: 4,
            builtin: false,
            main: false,
            vendor: 0xF0F0,
            product: 0,
            serial: 0,
            port: "IOService:/virtual/sidecar",
            name: "Sidecar"
        )
        let result = buildLiveCatalog(
            facts: [builtIn, sidecar],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        XCTAssertEqual(result.snapshots.count, 2)
        let lcd = result.snapshots.first { $0.name == "Color LCD" }
        let virtual = result.snapshots.first { $0.name == "Sidecar" }
        XCTAssertEqual(lcd?.kind, .builtIn)
        XCTAssertEqual(lcd?.connection, .builtIn)
        XCTAssertEqual(lcd?.brightness.backend, BrightnessBackendKind.none)
        XCTAssertTrue(lcd?.brightness.showsBrightnessSlider ?? false)
        XCTAssertEqual(virtual?.kind, .virtualUnsupported)
        XCTAssertFalse(virtual?.brightness.showsBrightnessSlider ?? true)
        XCTAssertFalse(virtual?.volume.supportsVolume ?? true)
        XCTAssertFalse(lcd?.rotation.supportsRotation ?? true)
        XCTAssertFalse(virtual?.rotation.supportsRotation ?? true)
        XCTAssertEqual(lcd?.id.persistentKey, makePersistentKey(inputs: builtIn.identityInputs, siblings: [builtIn.identityInputs], records: [:]))
    }

    func testTwinsGetPortSuffix() {
        let a = fact(id: 2, port: "IOService:/port/A", name: "DELL U2723QE")
        let b = fact(id: 3, port: "IOService:/port/B", name: "DELL U2723QE")
        let result = buildLiveCatalog(
            facts: [a, b],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        let keys = result.snapshots.map(\.id.persistentKey)
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.allSatisfy { $0.contains("-port-") })
        XCTAssertNotEqual(keys[0], keys[1])
    }

    func testLiveKeyAliasWhenTwinAppears() {
        let a = fact(id: 2, port: "IOService:/port/A", name: "DELL U2723QE")
        let first = buildLiveCatalog(
            facts: [a],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        let oldKey = first.snapshots[0].id.persistentKey
        XCTAssertFalse(oldKey.contains("-port-"))
        var records = [oldKey: DisplayRecord(persistentKey: oldKey, lastBrightness: 0.4)]
        let b = fact(id: 3, port: "IOService:/port/B", name: "DELL U2723QE")
        let second = buildLiveCatalog(
            facts: [a, b],
            records: records,
            aliases: [:],
            previousKeysByDisplayID: [2: oldKey]
        )
        let newA = second.snapshots.first { $0.sessionDisplayID == 2 }?.id.persistentKey
        XCTAssertNotEqual(newA, oldKey)
        XCTAssertTrue(newA?.contains("-port-") ?? false)
        XCTAssertEqual(second.keyAliases.first?.oldKey, oldKey)
        XCTAssertEqual(second.keyAliases.first?.newKey, newA)
        XCTAssertEqual(second.copiedRecords.first?.lastBrightness, 0.4)
        XCTAssertEqual(second.copiedRecords.first?.persistentKey, newA)

        records[oldKey] = DisplayRecord(persistentKey: oldKey, lastBrightness: 0.4)
        if let copied = second.copiedRecords.first {
            records[copied.persistentKey] = copied
        }
        XCTAssertEqual(records[newA ?? ""]?.lastBrightness, 0.4)
    }

    func testDoesNotOverwriteExistingNewKeyRecord() {
        let a = fact(id: 2, port: "IOService:/port/A", name: "DELL U2723QE")
        let oldKey = "v1:" + makeCore(a.identityInputs)
        let newKey = oldKey + "-port-" + fnv1a32Hex(a.portLocation)
        let records = [
            oldKey: DisplayRecord(persistentKey: oldKey, lastBrightness: 0.2),
            newKey: DisplayRecord(persistentKey: newKey, lastBrightness: 0.9),
        ]
        let result = applyLiveKeyAlias(
            oldKey: oldKey,
            newKey: newKey,
            recordAtOld: records[oldKey],
            recordAtNew: records[newKey]
        )
        XCTAssertNil(result.copiedRecord)
        XCTAssertEqual(result.aliasOldKey, oldKey)
        XCTAssertEqual(result.aliasNewKey, newKey)
    }

    func testPreservesMailboxCurrentAcrossRescan() {
        let a = fact(id: 2, port: "IOService:/port/A", name: "DELL U2723QE")
        let first = buildLiveCatalog(
            facts: [a],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        var previous = first.snapshots
        previous[0].brightness.current = 0.33
        let second = buildLiveCatalog(
            facts: [a],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: first.keysByDisplayID,
            previousSnapshots: previous
        )
        XCTAssertEqual(second.snapshots[0].brightness.current, 0.33, accuracy: 0.000_1)
    }

    func testCustomNameOverridesHardwareName() {
        let dell = fact(id: 2, port: "IOService:/GPU/dp@1", name: "DELL U2723QE")
        let key = makePersistentKey(inputs: dell.identityInputs, siblings: [dell.identityInputs], records: [:])
        let result = buildLiveCatalog(
            facts: [dell],
            records: [key: DisplayRecord(persistentKey: key, customName: "Desk")],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        XCTAssertEqual(result.snapshots[0].hardwareName, "DELL U2723QE")
        XCTAssertEqual(result.snapshots[0].name, "Desk")
    }

    func testScreenFallbackNameWhenProductEmpty() {
        var facts = fact(id: 5, port: "IOService:/unknown", name: "")
        facts.screenFallbackName = "LG UltraFine"
        XCTAssertEqual(facts.resolvedName, "LG UltraFine")
    }

    func testGenericExternalNotAppleExternal() {
        let dell = fact(id: 2, port: "IOService:/GPU/dp@1", name: "DELL U2723QE")
        let result = buildLiveCatalog(
            facts: [dell],
            records: [:],
            aliases: [:],
            previousKeysByDisplayID: [:]
        )
        XCTAssertEqual(result.snapshots[0].kind, .genericExternal)
        XCTAssertEqual(result.snapshots[0].connection, .displayPort)
        XCTAssertNotEqual(result.snapshots[0].kind, .appleExternal)
        XCTAssertTrue(result.snapshots[0].rotation.supportsRotation)
    }

    private func fact(
        id: CGDirectDisplayID,
        builtin: Bool = false,
        main: Bool = false,
        vendor: UInt32 = 0x10AC,
        product: UInt32 = 0xD14C,
        serial: UInt32 = 0,
        port: String,
        name: String
    ) -> DisplayHardwareFacts {
        DisplayHardwareFacts(
            displayID: id,
            isBuiltin: builtin,
            isMain: main,
            vendorID: vendor,
            productID: product,
            serial: serial,
            unitNumber: 0,
            portLocation: port,
            productName: name
        )
    }
}