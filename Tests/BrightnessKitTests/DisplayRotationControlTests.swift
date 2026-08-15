import XCTest
@testable import BrightnessKit
import CoreGraphics
import DisplayCore

final class DisplayRotationControlTests: XCTestCase {
    func testProbeOptionsUseScaleRotateFlags() {
        XCTAssertEqual(DisplayRotationControl.probeOption(for: .deg0), 0x00000400)
        XCTAssertEqual(DisplayRotationControl.probeOption(for: .deg90), 0x00300400)
        XCTAssertEqual(DisplayRotationControl.probeOption(for: .deg180), 0x00600400)
        XCTAssertEqual(DisplayRotationControl.probeOption(for: .deg270), 0x00500400)
        XCTAssertNotEqual(DisplayRotationControl.probeOption(for: .deg90), 0x00010400)
    }

    func testUsesMonitorPanelOrientation() throws {
        let production = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrightnessKit/DisplayRotationControl.swift")
        let body = try String(contentsOf: production, encoding: .utf8)
        XCTAssertTrue(body.contains("CandelaDisplaySetOrientation"))
        XCTAssertFalse(body.contains("cgsServiceForDisplayNumber"))
        XCTAssertFalse(body.contains("IOServiceRequestProbe"))
        let privateIO = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CandelaPrivateIO/CandelaPrivateIO.c")
        let ioBody = try String(contentsOf: privateIO, encoding: .utf8)
        XCTAssertTrue(ioBody.contains("displayWithID:"))
        XCTAssertTrue(ioBody.contains("sharedMgr"))
        XCTAssertFalse(ioBody.contains("usleep"))
        XCTAssertFalse(ioBody.contains("initWithCGSDisplayID:"))
    }

    func testCanQueryLiveOrientation() {
        let builtin = CGMainDisplayID()
        // Query only. Setting orientation here would rotate the developer's screen.
        _ = DisplayRotationControl.current(for: builtin)
        if CGDisplayIsBuiltin(builtin) != 0 {
            XCTAssertFalse(DisplayRotationControl.canRotate(builtin))
            XCTAssertFalse(DisplayRotationControl.set(.deg90, displayID: builtin))
        } else {
            _ = DisplayRotationControl.canRotate(builtin)
        }
    }
}
