import CoreGraphics
import DisplayCore
import XCTest

final class StatusPanelLayoutTests: XCTestCase {
    func testFirstLaunchIgnoresAFullWidthMenuBarWindow() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let menuBarWindow = CGRect(x: 0, y: 944, width: 1512, height: 38)
        let unresolvedButton = CGRect(x: 0, y: 0, width: 0, height: 0)

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
        XCTAssertGreaterThan(frame.minX, visible.midX)
    }

    func testReadyStatusItemAnchorsThePanelUnderTheButton() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let button = CGRect(x: 1288, y: 948, width: 28, height: 24)
        XCTAssertTrue(StatusPanelLayout.isUsableStatusButtonFrame(button, visible: visible))

        let frame = StatusPanelLayout.panelFrame(button: button, height: 520, visible: visible)
        XCTAssertEqual(frame.midX, button.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, button.minY - 8, accuracy: 0.001)
        XCTAssertEqual(frame.height, 520, accuracy: 0.001)
    }
}
