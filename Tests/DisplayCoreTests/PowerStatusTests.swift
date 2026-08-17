import DisplayCore
import IOKit.ps
import XCTest

final class PowerStatusTests: XCTestCase {
    func testHidesDesktopsWithoutAnInternalBattery() {
        XCTAssertFalse(PowerStatusReader.snapshot(from: []).showsInPanel)
        XCTAssertFalse(PowerStatusReader.snapshot(from: []).showsOnBattery)
        XCTAssertFalse(PowerStatusReader.snapshot(from: []).showsOnPower)
    }

    func testShowsChargingSymbolWhenPluggedIn() {
        let status = PowerStatusReader.snapshot(from: [
            [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: true,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue,
                kIOPSCurrentCapacityKey: 80,
                kIOPSMaxCapacityKey: 100,
                kIOPSIsChargingKey: true,
            ],
        ])

        XCTAssertTrue(status.showsInPanel)
        XCTAssertTrue(status.showsOnPower)
        XCTAssertFalse(status.showsOnBattery)
        XCTAssertTrue(status.isCharging)
        XCTAssertNil(PowerStatusPresentation.title(for: status))
        XCTAssertEqual(PowerStatusPresentation.symbolName(for: status), "battery.100percent.bolt")
        XCTAssertEqual(
            PowerStatusPresentation.accessibilityTitle(for: status),
            "Charging, Battery 80 percent"
        )
    }

    func testReadsInternalBatteryPercentWhenUnplugged() {
        let status = PowerStatusReader.snapshot(from: [
            [
                kIOPSTypeKey: "UPS",
                kIOPSIsPresentKey: true,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
                kIOPSCurrentCapacityKey: 12,
                kIOPSMaxCapacityKey: 100,
            ],
            [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: true,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
                kIOPSCurrentCapacityKey: 37,
                kIOPSMaxCapacityKey: 100,
                kIOPSTimeToEmptyKey: 148,
            ],
        ], isLowPowerModeEnabled: true)

        XCTAssertTrue(status.showsOnBattery)
        XCTAssertEqual(status.percent, 37)
        XCTAssertEqual(status.minutesToEmpty, 148)
        XCTAssertTrue(status.isLowPowerModeEnabled)
        XCTAssertEqual(PowerStatusPresentation.title(for: status), "37%")
        XCTAssertEqual(PowerStatusPresentation.remainingTitle(for: status), "2h 28m left")
        XCTAssertEqual(PowerStatusPresentation.symbolName(for: status), "battery.25percent")
        XCTAssertEqual(
            PowerStatusPresentation.accessibilityTitle(for: status),
            "Battery 37 percent, 2h 28m left, Low Power Mode"
        )
    }

    func testPrefersTheUnpluggedInternalBattery() {
        let status = PowerStatusReader.snapshot(from: [
            [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: true,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue,
                kIOPSCurrentCapacityKey: 99,
                kIOPSMaxCapacityKey: 100,
            ],
            [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: true,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
                kIOPSCurrentCapacityKey: 18,
                kIOPSMaxCapacityKey: 100,
                kIOPSTimeToEmptyKey: 41,
            ],
        ])

        XCTAssertEqual(status.percent, 18)
        XCTAssertEqual(PowerStatusPresentation.remainingTitle(for: status), "41m left")
        XCTAssertEqual(PowerStatusPresentation.symbolName(for: status), "battery.25percent")
    }

    func testLowBatteryUsesEmptySymbol() {
        let status = PowerStatus(
            source: .battery,
            isPresent: true,
            percent: 6,
            minutesToEmpty: 60
        )
        XCTAssertEqual(PowerStatusPresentation.symbolName(for: status), "battery.0percent")
        XCTAssertEqual(PowerStatusPresentation.remainingTitle(for: status), "1h left")
    }
}
