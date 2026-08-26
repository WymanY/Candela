import XCTest
@testable import DisplayCore

final class DisplayLayoutTests: XCTestCase {
    func testDraftKeepsCoordinateSpaceDimensions() throws {
        let draft = DisplayLayoutDraft(slots: [
            slot("main", x: 0, y: 0, width: 1512, height: 982, main: true),
            slot("dell", x: 1512, y: -240, width: 1920, height: 1080),
        ])

        try draft.validated()
        XCTAssertEqual(draft.slot(for: "main")?.size, DisplayLayoutSize(width: 1512, height: 982))
        XCTAssertEqual(draft.slot(for: "dell")?.origin, DisplayLayoutPoint(x: 1512, y: -240))
    }

    func testSnapsToAllFourSides() throws {
        let anchor = slot("main", x: 0, y: 0, width: 100, height: 80, main: true)
        let moving = slot("dell", x: 100, y: 0, width: 60, height: 50)

        XCTAssertEqual(
            DisplayLayoutPlanning.snappedOrigin(
                moving: moving,
                proposedOrigin: .init(x: 97, y: 12),
                otherSlots: [anchor],
                snapDistance: 5
            ).x,
            100
        )
        XCTAssertEqual(
            DisplayLayoutPlanning.snappedOrigin(
                moving: moving,
                proposedOrigin: .init(x: -57, y: 12),
                otherSlots: [anchor],
                snapDistance: 5
            ).x,
            -60
        )
        XCTAssertEqual(
            DisplayLayoutPlanning.snappedOrigin(
                moving: moving,
                proposedOrigin: .init(x: 12, y: 77),
                otherSlots: [anchor],
                snapDistance: 5
            ).y,
            80
        )
        XCTAssertEqual(
            DisplayLayoutPlanning.snappedOrigin(
                moving: moving,
                proposedOrigin: .init(x: 12, y: -47),
                otherSlots: [anchor],
                snapDistance: 5
            ).y,
            -50
        )
    }

    func testSnapsMatchingEdges() {
        let anchor = slot("main", x: 0, y: 0, width: 100, height: 80, main: true)
        let moving = slot("dell", x: 100, y: 0, width: 60, height: 50)
        let aligned = DisplayLayoutPlanning.snappedOrigin(
            moving: moving,
            proposedOrigin: .init(x: 43, y: 28),
            otherSlots: [anchor],
            snapDistance: 4
        )
        XCTAssertEqual(aligned.x, 40, "right edges should align")
        XCTAssertEqual(aligned.y, 30, "bottom edges should align")
    }

    func testMainDisplayCannotMove() {
        let draft = connectedDraft()
        XCTAssertThrowsError(
            try draft.moving(
                persistentKey: "main",
                to: .init(x: 50, y: 50),
                snapDistance: 0
            )
        ) { error in
            XCTAssertEqual(error as? DisplayLayoutValidationError, .mainDisplayIsAnchored)
        }
    }

    func testValidationRejectsOverlap() throws {
        let draft = connectedDraft()
        let overlapping = try draft.moving(
            persistentKey: "dell",
            to: .init(x: 50, y: 0),
            snapDistance: 0
        )
        XCTAssertThrowsError(try overlapping.validated()) { error in
            XCTAssertEqual(
                error as? DisplayLayoutValidationError,
                .overlappingDisplays("main", "dell")
            )
        }
    }

    func testValidationRejectsDisconnectedTopology() throws {
        let draft = connectedDraft()
        let disconnected = try draft.moving(
            persistentKey: "dell",
            to: .init(x: 300, y: 0),
            snapDistance: 0
        )
        XCTAssertThrowsError(try disconnected.validated()) { error in
            XCTAssertEqual(
                error as? DisplayLayoutValidationError,
                .disconnectedDisplays(["dell"])
            )
        }
    }

    func testValidationRejectsChangedDeviceSet() {
        let draft = connectedDraft()
        XCTAssertThrowsError(try draft.validated(liveDeviceKeys: ["main", "other"])) { error in
            XCTAssertEqual(
                error as? DisplayLayoutValidationError,
                .deviceSetChanged(expected: ["dell", "main"], actual: ["main", "other"])
            )
        }
    }

    func testAvailabilityRequiresExtendedNonVirtualDisplays() {
        let main = mirrorTarget(id: 1, key: "main", main: true)
        let dell = mirrorTarget(id: 2, key: "dell")
        let sidecar = mirrorTarget(id: 3, key: "sidecar", virtual: true)
        XCTAssertEqual(DisplayLayoutPlanning.availability(targets: [main]), .insufficientDisplays)
        XCTAssertEqual(DisplayLayoutPlanning.availability(targets: [main, sidecar]), .insufficientDisplays)
        XCTAssertEqual(DisplayLayoutPlanning.availability(targets: [main, dell]), .available)
        XCTAssertEqual(
            DisplayLayoutPlanning.availability(targets: [main, mirrorTarget(id: 2, key: "dell", mirrors: 1)]),
            .mirroring
        )
    }

    private func connectedDraft() -> DisplayLayoutDraft {
        DisplayLayoutDraft(slots: [
            slot("main", x: 0, y: 0, width: 100, height: 100, main: true),
            slot("dell", x: 100, y: 0, width: 100, height: 100),
        ])
    }

    private func slot(
        _ key: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        main: Bool = false
    ) -> DisplayLayoutSlot {
        DisplayLayoutSlot(
            persistentKey: key,
            name: key,
            origin: .init(x: x, y: y),
            size: .init(width: width, height: height),
            isMain: main,
            isBuiltin: main
        )
    }

    private func mirrorTarget(
        id: CGDirectDisplayID,
        key: String,
        virtual: Bool = false,
        main: Bool = false,
        mirrors: CGDirectDisplayID = 0
    ) -> DisplayMirrorTarget {
        DisplayMirrorTarget(
            displayID: id,
            persistentKey: key,
            isBuiltin: main,
            isVirtual: virtual,
            origin: .zero,
            pixelWidth: 100,
            pixelHeight: 100,
            refreshHz: 60,
            isMain: main,
            mirrorsDisplayID: mirrors
        )
    }
}
