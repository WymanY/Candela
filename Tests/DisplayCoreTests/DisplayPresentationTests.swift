import XCTest
@testable import DisplayCore
import TestSupport

final class DisplayPresentationTests: XCTestCase {
    func testBuiltInShowsModeAndDisplayServices() {
        let snapshot = FakeSnapshots.builtIn()
        XCTAssertTrue(["Built-in", "内置"].contains(DisplayPresentation.connectionTitle(for: snapshot)))
        XCTAssertEqual(DisplayPresentation.modeTitle(for: snapshot), "2560 × 1600")
        XCTAssertEqual(DisplayPresentation.refreshTitle(for: snapshot), "60 Hz")
        XCTAssertEqual(DisplayPresentation.scaleTitle(for: snapshot), "2×")
        XCTAssertEqual(DisplayPresentation.brightnessBackendTitle(for: snapshot), "DisplayServices")
        XCTAssertTrue(["None", "无"].contains(DisplayPresentation.volumeBackendTitle(for: snapshot)))
        XCTAssertEqual(DisplayPresentation.vendorTitle(for: snapshot), "Apple")
        XCTAssertEqual(DisplayPresentation.identityTitle(for: snapshot), "0x0610 / 0xA050")
    }

    func testDellShowsDDCVolumeAndUSB() {
        let snapshot = FakeSnapshots.dellUSBC()
        XCTAssertEqual(DisplayPresentation.connectionTitle(for: snapshot), "USB-C")
        XCTAssertEqual(DisplayPresentation.modeTitle(for: snapshot), "3840 × 2160")
        XCTAssertEqual(DisplayPresentation.brightnessBackendTitle(for: snapshot), "DDC")
        XCTAssertEqual(DisplayPresentation.volumeBackendTitle(for: snapshot), "DDC")
        XCTAssertEqual(DisplayPresentation.vendorTitle(for: snapshot), "Dell")
    }

    func testFractionalRefreshKeepsDecimals() {
        var snapshot = FakeSnapshots.hdmiTV()
        snapshot.refreshHz = 59.94
        XCTAssertEqual(DisplayPresentation.refreshTitle(for: snapshot), "59.94 Hz")
        XCTAssertTrue(["Software", "软件"].contains(DisplayPresentation.brightnessBackendTitle(for: snapshot)))
    }

    func testRotationLabels() {
        var snapshot = FakeSnapshots.dellUSBC()
        XCTAssertTrue(snapshot.rotation.supportsRotation)
        XCTAssertTrue(["0° · Landscape", "0° · 横向"].contains(DisplayPresentation.rotationTitle(for: snapshot)))
        snapshot.rotation.current = .deg90
        XCTAssertTrue(["90° · Portrait", "90° · 纵向"].contains(DisplayPresentation.rotationTitle(for: snapshot)))
        XCTAssertEqual(DisplayRotation.from(query: "portrait"), .deg90)
        XCTAssertEqual(DisplayRotation.from(degrees: 268), .deg270)
        XCTAssertFalse(FakeSnapshots.builtIn().rotation.supportsRotation)
    }

    func testUntitledSceneFallsBack() {
        let scene = DisplayScene(name: "  ", targets: [])
        XCTAssertTrue(["Untitled Scene", "未命名场景"].contains(scene.displayName))
    }
}
