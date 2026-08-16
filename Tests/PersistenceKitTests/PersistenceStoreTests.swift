import DisplayCore
import PersistenceKit
import XCTest

final class PersistenceStoreTests: XCTestCase {
    private let keys = ["schemaVersion", "global", "displays", "aliases", "scenes"]

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
        settings.preferredLanguage = "zh-Hans"
        store.saveGlobal(settings)
        let loaded = store.global()
        XCTAssertTrue(loaded.hasOpenedPanelOnce)
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(loaded.preferredLanguage, "zh-Hans")
    }

    func testSavesScenes() {
        let store = PersistenceStore()
        let scene = DisplayScene(
            name: "Desk",
            targets: [DisplaySceneTarget(persistentKey: "v1:desk", brightness: 0.4)]
        )
        store.saveScenes([scene])
        XCTAssertEqual(store.allScenes().first?.name, "Desk")
        XCTAssertEqual(store.allScenes().first?.targets.first?.brightness, 0.4)
    }

    func testSceneRoundTripKeepsValues() {
        let store = PersistenceStore()
        let scene = DisplayScene(
            name: "Night",
            targets: [
                DisplaySceneTarget(
                    persistentKey: "v1:desk",
                    brightness: 0.22,
                    volume: 0.31,
                    muted: true,
                    contrast: 0.44,
                    inputCode: 0x11,
                    rotationDegrees: 90,
                    pictureInPicture: true
                )
            ],
            speakerUID: "macbook",
            speakerVolume: 0.43,
            speakerMuted: false
        )
        store.saveScenes([scene])
        let loaded = PersistenceStore().allScenes()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.targets.first?.brightness, 0.22)
        XCTAssertEqual(loaded.first?.targets.first?.volume, 0.31)
        XCTAssertEqual(loaded.first?.targets.first?.muted, true)
        XCTAssertEqual(loaded.first?.targets.first?.contrast, 0.44)
        XCTAssertEqual(loaded.first?.targets.first?.inputCode, 0x11)
        XCTAssertEqual(loaded.first?.targets.first?.rotationDegrees, 90)
        XCTAssertEqual(loaded.first?.targets.first?.pictureInPicture, true)
        XCTAssertEqual(loaded.first?.speakerUID, "macbook")
        XCTAssertEqual(loaded.first?.speakerVolume, 0.43)
        XCTAssertEqual(loaded.first?.speakerMuted, false)
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

    func testSavesPictureInPicturePlacement() {
        let store = PersistenceStore()
        var record = DisplayRecord(persistentKey: "v1:tv")
        record.pictureInPicture = PictureInPicturePlacement(
            opacity: 0.55,
            clickThrough: true,
            corner: .topLeft,
            frame: PictureInPictureFrame(x: 80, y: 40, width: 480, height: 300),
            hostDisplayID: 7,
            mirrored: true,
            mode: .magnifier,
            window: PictureInPictureWindowIdentity(bundleIdentifier: "com.tinyspeck.slackmacgap", title: "#design", ownerName: "Slack"),
            magnifierZoom: 3
        )
        store.save(record)
        let loaded = store.record(for: "v1:tv")?.pictureInPicture
        XCTAssertEqual(loaded?.opacity ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertEqual(loaded?.clickThrough, true)
        XCTAssertEqual(loaded?.corner, .topLeft)
        XCTAssertEqual(loaded?.frame?.x ?? -1, 80, accuracy: 0.0001)
        XCTAssertEqual(loaded?.hostDisplayID, 7)
        XCTAssertEqual(loaded?.mirrored, true)
        XCTAssertEqual(loaded?.mode, .magnifier)
        XCTAssertEqual(loaded?.window?.title, "#design")
        XCTAssertEqual(loaded?.magnifierZoom ?? -1, 3, accuracy: 0.0001)

        var settings = store.global()
        settings.pictureInPictureWall = PictureInPicturePlacement(opacity: 0.8, corner: .bottomLeft)
        store.saveGlobal(settings)
        XCTAssertEqual(store.global().pictureInPictureWall?.corner, .bottomLeft)
    }

    private func clearStore() {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
