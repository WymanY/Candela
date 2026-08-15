import XCTest
@testable import DisplayCore
import TestSupport

final class DisplayPresentationTests: XCTestCase {
    func testBuiltInShowsModeAndDisplayServices() {
        let snapshot = FakeSnapshots.builtIn()
        XCTAssertEqual(DisplayPresentation.connectionTitle(for: snapshot), "Built-in")
        XCTAssertEqual(DisplayPresentation.modeTitle(for: snapshot), "2560 × 1600")
        XCTAssertEqual(DisplayPresentation.refreshTitle(for: snapshot), "60 Hz")
        XCTAssertEqual(DisplayPresentation.scaleTitle(for: snapshot), "2×")
        XCTAssertEqual(DisplayPresentation.brightnessBackendTitle(for: snapshot), "DisplayServices")
        XCTAssertEqual(DisplayPresentation.volumeBackendTitle(for: snapshot), "None")
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
        XCTAssertEqual(DisplayPresentation.brightnessBackendTitle(for: snapshot), "Software")
    }

    func testRotationLabels() {
        var snapshot = FakeSnapshots.dellUSBC()
        XCTAssertTrue(snapshot.rotation.supportsRotation)
        XCTAssertEqual(DisplayPresentation.rotationTitle(for: snapshot), "0° · Landscape")
        snapshot.rotation.current = .deg90
        XCTAssertEqual(DisplayPresentation.rotationTitle(for: snapshot), "90° · Portrait")
        XCTAssertEqual(DisplayRotation.from(query: "portrait"), .deg90)
        XCTAssertEqual(DisplayRotation.from(degrees: 268), .deg270)
        XCTAssertFalse(FakeSnapshots.builtIn().rotation.supportsRotation)
    }
}
