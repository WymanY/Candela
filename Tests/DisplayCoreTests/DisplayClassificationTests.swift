import XCTest
@testable import DisplayCore

final class DisplayClassificationTests: XCTestCase {
    func testVirtualDetectorVendorF0F0() {
        let evidence = VirtualDisplayEvidence(vendorID: 0xF0F0, names: ["Something"])
        XCTAssertTrue(isVirtualUnsupported(evidence))
        XCTAssertEqual(classifyDisplayKind(isVirtual: true, isBuiltin: false), .virtualUnsupported)
    }

    func testVirtualDetectorNames() {
        for name in ["Dummy Display", "Sidecar", "AirPlay Screen", "Continuity Camera", "DisplayLink USB"] {
            XCTAssertTrue(
                isVirtualUnsupported(VirtualDisplayEvidence(vendorID: 0x10AC, names: [name])),
                name
            )
        }
        XCTAssertFalse(
            isVirtualUnsupported(VirtualDisplayEvidence(vendorID: 0x10AC, names: ["DELL U2723QE"]))
        )
    }

    func testVirtualDetectorFlagsAndClass() {
        XCTAssertTrue(
            isVirtualUnsupported(
                VirtualDisplayEvidence(vendorID: 1, names: ["Screen"], isVirtualDevice: true)
            )
        )
        XCTAssertTrue(
            isVirtualUnsupported(
                VirtualDisplayEvidence(vendorID: 1, names: ["Screen"], isAirPlay: true)
            )
        )
        XCTAssertTrue(
            isVirtualUnsupported(
                VirtualDisplayEvidence(vendorID: 1, names: ["Screen"], classOrName: "DisplayLinkDriver")
            )
        )
    }

    func testClassifyBuiltinAndGeneric() {
        XCTAssertEqual(classifyDisplayKind(isVirtual: false, isBuiltin: true), .builtIn)
        XCTAssertEqual(classifyDisplayKind(isVirtual: false, isBuiltin: false), .genericExternal)
    }

    func testConnectionKindBuiltinFirst() {
        XCTAssertEqual(
            connectionKind(
                isBuiltin: true,
                transportDownstream: "HDMI",
                transportUpstream: nil,
                location: "IOService:/hdmi"
            ),
            .builtIn
        )
    }

    func testConnectionKindFromTransport() {
        XCTAssertEqual(connectionKind(fromTransport: "HDMI"), .hdmi)
        XCTAssertEqual(connectionKind(fromTransport: "DisplayPort"), .displayPort)
        XCTAssertEqual(connectionKind(fromTransport: "DP"), .displayPort)
        XCTAssertEqual(connectionKind(fromTransport: "Thunderbolt"), .thunderbolt)
        XCTAssertEqual(connectionKind(fromTransport: "USB"), .usb)
        XCTAssertNil(connectionKind(fromTransport: "ADP"))
        XCTAssertEqual(
            connectionKind(
                isBuiltin: false,
                transportDownstream: nil,
                transportUpstream: "HDMI",
                location: ""
            ),
            .hdmi
        )
    }

    func testConnectionKindFromLocation() {
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/AppleACPI/hdmi0"), .hdmi)
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/displayport@1"), .displayPort)
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/GPU/dp@1/display"), .displayPort)
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/Thunderbolt/device"), .thunderbolt)
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/USB-C/display"), .usb)
        XCTAssertEqual(connectionKind(fromLocation: "IOService:/AppleCLCD2"), .unknown)
    }

    func testEffectiveDisplayIDAndClamshell() {
        XCTAssertEqual(effectiveDisplayID(7, mirrorsDisplay: 0), 7)
        XCTAssertEqual(effectiveDisplayID(8, mirrorsDisplay: 2), 2)
        XCTAssertTrue(shouldHideClamshellBuiltin(isBuiltin: true, isAsleep: true))
        XCTAssertFalse(shouldHideClamshellBuiltin(isBuiltin: true, isAsleep: false))
        XCTAssertFalse(shouldHideClamshellBuiltin(isBuiltin: false, isAsleep: true))
    }

    func testVisibleOnlineFiltersClamshellAndMirrors() {
        let ids: [UInt32] = [1, 2, 3, 4]
        let visible = visibleOnlineDisplayIDs(
            ids,
            isBuiltin: { $0 == 1 },
            isAsleep: { $0 == 1 },
            mirrorsDisplay: { $0 == 3 ? 2 : 0 }
        )
        XCTAssertEqual(visible, [2, 4])
    }

    func testUnitNumberFromLocationDecimalOnly() {
        XCTAssertEqual(unitNumberFromLocation("IOService:/AppleIntelFramebuffer@1"), 1)
        XCTAssertEqual(unitNumberFromLocation("IOService:/display@12"), 12)
        XCTAssertNil(unitNumberFromLocation("IOService:/disp0@30000000/AppleCLCD2"))
        XCTAssertNil(unitNumberFromLocation("IOService:/no-unit"))
    }

    func testPreferredLocalizedNamePrefersEnUS() {
        let map: [String: String] = ["de_DE": "Farb-LCD", "en_US": "Color LCD"]
        XCTAssertEqual(preferredLocalizedName(from: map), "Color LCD")
        XCTAssertEqual(preferredLocalizedName(from: "Plain"), "Plain")
        XCTAssertNil(preferredLocalizedName(from: "  "))
    }

    func testBoolFlagAndUint32() {
        XCTAssertTrue(boolFlag(1))
        XCTAssertFalse(boolFlag(0))
        XCTAssertTrue(boolFlag(true))
        XCTAssertEqual(uint32Value(NSNumber(value: 0x10AC)), 0x10AC)
    }
}