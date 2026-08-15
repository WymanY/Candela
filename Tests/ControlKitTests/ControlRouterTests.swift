import ControlKit
import DisplayCore
import TestSupport
import XCTest

final class ControlRouterTests: XCTestCase {
    func testListAndSetBrightness() {
        var snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { key, value in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].brightness.current = value
                }
            },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            rename: { _, _ in true },
            applyPreset: { preset, key in
                for index in snapshots.indices where key == nil || snapshots[index].id.persistentKey == key {
                    if snapshots[index].brightness.showsBrightnessSlider {
                        snapshots[index].brightness.current = preset.value
                    }
                }
            },
            matchAll: { key in
                guard let source = snapshots.first(where: { $0.id.persistentKey == key }) else { return }
                for index in snapshots.indices where snapshots[index].id.persistentKey != key {
                    if snapshots[index].brightness.showsBrightnessSlider {
                        snapshots[index].brightness.current = source.brightness.current
                    }
                }
            },
            dump: { _ in "dump" }
        )

        let listed = ControlRouter.apply(ControlRequest(action: .list), backend: backend)
        XCTAssertTrue(listed.ok)
        XCTAssertEqual(listed.displays?.count, 4)

        let set = ControlRouter.apply(
            ControlRequest(action: .setBrightness, display: "Built-in", value: 0.2),
            backend: backend
        )
        XCTAssertTrue(set.ok)
        XCTAssertEqual(set.displays?.first?.brightness ?? 0, 0.2, accuracy: 0.0001)

        let preset = ControlRouter.apply(
            ControlRequest(action: .preset, preset: "max"),
            backend: backend
        )
        XCTAssertTrue(preset.ok)
        XCTAssertEqual(snapshots[0].brightness.current, 1.0, accuracy: 0.0001)
    }

    func testUnknownDisplayFails() {
        let snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let response = ControlRouter.apply(
            ControlRequest(action: .get, display: "No Such Panel"),
            backend: backend
        )
        XCTAssertFalse(response.ok)
    }

    func testSetRotation() {
        var snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { key, rotation in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].rotation.current = rotation
                }
            },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let builtin = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: "Built-in", rotation: "portrait"),
            backend: backend
        )
        XCTAssertFalse(builtin.ok)
        XCTAssertEqual(snapshots[0].rotation.current, .deg0)

        let response = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: FakeSnapshots.dellName, rotation: "portrait"),
            backend: backend
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.displays?.first?.rotation, "90")
        XCTAssertEqual(snapshots[1].rotation.current, .deg90)

        let sidecar = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: "Sidecar", rotation: "90"),
            backend: backend
        )
        XCTAssertFalse(sidecar.ok)
    }
}

final class DisplayQueryTests: XCTestCase {
    func testResolvesAliasesAndCustomNames() {
        var snapshots = FakeSnapshots.standard()
        snapshots[1].name = "Desk Dell"
        XCTAssertEqual(DisplayQuery.resolve("main", in: snapshots)?.isMain, true)
        XCTAssertEqual(DisplayQuery.resolve("builtin", in: snapshots)?.isBuiltin, true)
        XCTAssertEqual(DisplayQuery.resolve("Desk Dell", in: snapshots)?.hardwareName, FakeSnapshots.dellName)
        XCTAssertEqual(DisplayQuery.resolve("DELL", in: snapshots)?.kind, .genericExternal)
        XCTAssertNil(DisplayQuery.resolve("Display", in: snapshots))
    }
}

final class DisplayNameResolverTests: XCTestCase {
    func testCustomNameWinsUntilCleared() {
        XCTAssertEqual(DisplayNameResolver.displayName(hardwareName: "DELL", customName: " Desk "), "Desk")
        XCTAssertEqual(DisplayNameResolver.displayName(hardwareName: "DELL", customName: "  "), "DELL")
    }
}
