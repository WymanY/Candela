import CoreGraphics
import DisplayCore
import XCTest

final class StatusPanelLayoutTests: XCTestCase {
    func testFirstLaunchIgnoresAFullWidthMenuBarWindow() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let menuBarWindow = CGRect(x: 0, y: 944, width: 1512, height: 38)
        let unresolvedButton = CGRect.zero

        XCTAssertFalse(StatusPanelLayout.isUsableStatusButtonFrame(unresolvedButton, visible: visible))
        XCTAssertFalse(StatusPanelLayout.isUsableStatusButtonFrame(menuBarWindow, visible: visible))

        let fallback = StatusPanelLayout.resolvedButtonFrame(
            converted: unresolvedButton,
            windowFrame: menuBarWindow,
            visible: visible
        )
        XCTAssertEqual(fallback.origin.x, 1460, accuracy: 0.001)
        XCTAssertEqual(fallback.origin.y, 944, accuracy: 0.001)

        let frame = StatusPanelLayout.panelFrame(button: fallback, height: 520, visible: visible)
        XCTAssertEqual(frame.maxY, visible.maxY - 8, accuracy: 0.001)
        XCTAssertEqual(frame.maxX, visible.maxX - 8, accuracy: 0.001)
    }

    func testStatusItemMustIntersectTheTargetScreenHorizontally() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let verticallyAlignedButOffscreen = CGRect(x: -9249, y: 870.5, width: 22.5, height: 30)

        XCTAssertFalse(
            StatusPanelLayout.isUsableStatusButtonFrame(
                verticallyAlignedButOffscreen,
                visible: visible
            )
        )
    }

    func testPanelReanchorsFromTemporaryTrailingPositionToRestoredPosition() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let temporaryButton = CGRect(x: 1410, y: 870.5, width: 22.5, height: 30)
        let restoredButton = CGRect(x: 846, y: 870.5, width: 22.5, height: 30)

        let temporaryPanel = StatusPanelLayout.panelFrame(
            button: temporaryButton,
            height: 325,
            visible: visible
        )
        let restoredPanel = StatusPanelLayout.panelFrame(
            button: restoredButton,
            height: 325,
            visible: visible
        )

        XCTAssertEqual(temporaryPanel.minX, 1040, accuracy: 0.001)
        XCTAssertEqual(restoredPanel.minX, 661.25, accuracy: 0.001)
        XCTAssertEqual(restoredPanel.midX, restoredButton.midX, accuracy: 0.001)
    }

    func testAnchorTrackerRequiresConsecutiveStableSamplesAndResetsAfterMovement() {
        var tracker = StatusItemAnchorTracker(requiredStableSamples: 3, tolerance: 1)
        let temporary = CGRect(x: 1410, y: 870.5, width: 22.5, height: 30)
        let restored = CGRect(x: 846, y: 870.5, width: 22.5, height: 30)

        XCTAssertFalse(tracker.observe(temporary))
        XCTAssertFalse(tracker.observe(temporary.offsetBy(dx: 0.5, dy: 0)))
        XCTAssertTrue(tracker.observe(temporary))

        XCTAssertFalse(tracker.observe(restored))
        XCTAssertFalse(tracker.observe(restored))
        XCTAssertTrue(tracker.observe(restored))

        XCTAssertFalse(tracker.observe(nil))
        XCTAssertEqual(tracker.stableSampleCount, 0)
        XCTAssertNil(tracker.lastFrame)
    }
}
