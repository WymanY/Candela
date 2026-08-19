import CoreGraphics
import XCTest
@testable import DisplayCore

final class DisplayArrangementTests: XCTestCase {
    func testCaptureKeepsOriginsAndMirrorLinks() {
        let builtin = target(id: 1, key: "builtin", builtin: true, main: true, origin: CGPoint(x: 0, y: 0))
        let desk = target(id: 2, key: "desk", origin: CGPoint(x: 1512, y: 0), mirrors: 1)
        let snapshot = DisplayArrangementPlanning.capture(
            targets: [builtin, desk],
            keysByDisplayID: [1: "builtin", 2: "desk"]
        )
        XCTAssertEqual(snapshot.slots.count, 2)
        XCTAssertEqual(snapshot.slots[0].persistentKey, "builtin")
        XCTAssertEqual(snapshot.slots[1].mirrorsPersistentKey, "builtin")
        XCTAssertEqual(snapshot.slots[1].originX, 1512, accuracy: 0.001)
    }

    func testKindDetectsBuiltinMirror() {
        let builtin = target(id: 1, key: "builtin", builtin: true, main: true)
        let desk = target(id: 2, key: "desk", mirrors: 1)
        XCTAssertEqual(DisplayArrangementPlanning.kind(for: [builtin, desk]), .builtin)
        XCTAssertEqual(DisplayArrangementPlanning.kind(for: [builtin, target(id: 2, key: "desk")]), .none)
        XCTAssertEqual(
            DisplayArrangementPlanning.kind(for: [
                target(id: 1, key: "builtin", builtin: true, mirrors: 2),
                target(id: 2, key: "desk", main: true),
            ]),
            .other
        )
    }

    func testAvailabilityNeedsARealExternalOrSavedLayout() {
        let builtin = target(id: 1, key: "builtin", builtin: true, main: true)
        let desk = target(id: 2, key: "desk")
        XCTAssertEqual(DisplayArrangementPlanning.availability(targets: [builtin], savedArrangement: nil), .unavailable)
        XCTAssertEqual(DisplayArrangementPlanning.availability(targets: [builtin, desk], savedArrangement: nil), .available)
        XCTAssertEqual(
            DisplayArrangementPlanning.availability(
                targets: [builtin, target(id: 2, key: "desk", mirrors: 1)],
                savedArrangement: nil
            ),
            .mirroringBuiltIn
        )
        let saved = DisplayArrangementSnapshot(slots: [
            DisplayArrangementSlot(
                persistentKey: "desk",
                originX: 1512,
                originY: 0,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshHz: 60,
                isMain: false,
                isBuiltin: false
            )
        ])
        XCTAssertEqual(DisplayArrangementPlanning.availability(targets: [builtin], savedArrangement: saved), .available)
    }

    func testMirrorPlanSkipsVirtualScreens() {
        let builtin = target(id: 1, key: "builtin", builtin: true, main: true)
        let desk = target(id: 2, key: "desk")
        let sidecar = target(id: 3, key: "sidecar", virtual: true)
        XCTAssertEqual(DisplayArrangementPlanning.mirrorPlan(targets: [builtin, desk, sidecar]), [2])
        XCTAssertNil(DisplayArrangementPlanning.mirrorPlan(targets: [builtin, sidecar]))
    }

    func testRestorePlanDropsMissingAndVirtualSlots() {
        let saved = DisplayArrangementSnapshot(slots: [
            DisplayArrangementSlot(persistentKey: "builtin", originX: 0, originY: 0, pixelWidth: 1512, pixelHeight: 982, refreshHz: 120, isMain: true, isBuiltin: true),
            DisplayArrangementSlot(persistentKey: "desk", originX: 1512, originY: 0, pixelWidth: 3840, pixelHeight: 2160, refreshHz: 60, isMain: false, isBuiltin: false),
            DisplayArrangementSlot(persistentKey: "gone", originX: 4000, originY: 0, pixelWidth: 1920, pixelHeight: 1080, refreshHz: 60, isMain: false, isBuiltin: false),
        ])
        let restored = DisplayArrangementPlanning.restorePlan(
            saved: saved,
            targets: [
                target(id: 1, key: "builtin", builtin: true, main: true),
                target(id: 2, key: "desk"),
                target(id: 3, key: "sidecar", virtual: true),
            ]
        )
        XCTAssertEqual(restored.map(\.persistentKey), ["builtin", "desk"])
    }

    private func target(
        id: CGDirectDisplayID,
        key: String,
        builtin: Bool = false,
        virtual: Bool = false,
        main: Bool = false,
        origin: CGPoint = .zero,
        mirrors: CGDirectDisplayID = 0
    ) -> DisplayMirrorTarget {
        DisplayMirrorTarget(
            displayID: id,
            persistentKey: key,
            isBuiltin: builtin,
            isVirtual: virtual,
            origin: origin,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshHz: 60,
            isMain: main,
            mirrorsDisplayID: mirrors
        )
    }
}
