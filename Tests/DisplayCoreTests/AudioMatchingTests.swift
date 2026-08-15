import XCTest
@testable import DisplayCore

final class AudioMatchingTests: XCTestCase {
    func testDellHDMISameNameBinds() {
        let display = snapshot(
            key: "v1:dell-hdmi",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let device = hdmiDevice(uid: "hdmi-dell", name: "DELL U2723QE", manufacturer: "Dell")
        XCTAssertEqual(
            AudioMatching.match(display: display, overrideUID: nil, devices: [device]),
            "hdmi-dell"
        )
    }

    func testTwoWayTieBindsNeither() {
        let first = snapshot(
            key: "v1:dell-a",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let second = snapshot(
            key: "v1:dell-b",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let devices = [
            hdmiDevice(uid: "hdmi-1", name: "DELL U2723QE", manufacturer: "Dell"),
            hdmiDevice(uid: "hdmi-2", name: "DELL U2723QE", manufacturer: "Dell"),
        ]
        XCTAssertNil(AudioMatching.match(display: first, overrideUID: nil, devices: devices))
        XCTAssertNil(AudioMatching.match(display: second, overrideUID: nil, devices: devices))
        XCTAssertTrue(
            AudioMatching.assign(
                displays: [(first, nil), (second, nil)],
                devices: devices
            ).isEmpty
        )
    }

    func testUSBHeadsetDoesNotBindGenericDell() {
        let display = snapshot(
            key: "v1:dell-usbc",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .usb,
            vendorID: 0x10AC
        )
        let headset = HALOutputDevice(
            uid: "usb-headset",
            name: "DELL U2723QE",
            manufacturer: "Dell",
            transport: AudioMatching.transportUSB,
            hasVolume: true,
            hasMute: true
        )
        XCTAssertNil(AudioMatching.match(display: display, overrideUID: nil, devices: [headset]))
    }

    func testDisplayPortDeviceWithoutHALVolumeStillMatches() {
        let display = snapshot(
            key: "v1:mi-dp",
            name: "Mi Monitor",
            kind: .genericExternal,
            connection: .displayPort,
            vendorID: 0x26D0
        )
        let device = HALOutputDevice(
            uid: "dp-mi",
            name: "Mi Monitor",
            manufacturer: "XMI",
            transport: AudioMatching.transportDisplayPort,
            hasVolume: false,
            hasMute: false
        )
        XCTAssertEqual(
            AudioMatching.match(display: display, overrideUID: nil, devices: [device]),
            "dp-mi"
        )
    }

    func testStudioDisplayBindsUSBSpeakers() {
        let display = snapshot(
            key: "v1:studio",
            name: "Studio Display",
            kind: .appleExternal,
            connection: .thunderbolt,
            vendorID: 0x0610
        )
        let speakers = HALOutputDevice(
            uid: "usb-studio",
            name: "Studio Display",
            manufacturer: "Apple Inc.",
            transport: AudioMatching.transportUSB,
            hasVolume: true,
            hasMute: true
        )
        XCTAssertEqual(
            AudioMatching.match(display: display, overrideUID: nil, devices: [speakers]),
            "usb-studio"
        )
    }

    func testOverrideUIDWinsDespiteNameMismatch() {
        let display = snapshot(
            key: "v1:dell-hdmi",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let named = hdmiDevice(uid: "hdmi-named", name: "DELL U2723QE", manufacturer: "Dell")
        let forced = HALOutputDevice(
            uid: "forced-headset",
            name: "USB Headset",
            manufacturer: "Logitech",
            transport: AudioMatching.transportUSB,
            hasVolume: true,
            hasMute: true
        )
        XCTAssertEqual(
            AudioMatching.match(
                display: display,
                overrideUID: "forced-headset",
                devices: [named, forced]
            ),
            "forced-headset"
        )
    }

    func testLeftoverDuplicateSuffixStillMatches() {
        let display = snapshot(
            key: "v1:dell-hdmi",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let device = hdmiDevice(uid: "hdmi-dup", name: "DELL U2723QE (2)", manufacturer: "Dell")
        XCTAssertEqual(
            AudioMatching.match(display: display, overrideUID: nil, devices: [device]),
            "hdmi-dup"
        )
    }

    func testMissingOverrideRematchesByName() {
        let display = snapshot(
            key: "v1:dell-hdmi",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let device = hdmiDevice(uid: "hdmi-dell", name: "DELL U2723QE", manufacturer: "Dell")
        XCTAssertEqual(
            AudioMatching.match(
                display: display,
                overrideUID: "missing-uid",
                devices: [device]
            ),
            "hdmi-dell"
        )
    }

    func testBuiltInAndVirtualNeverBind() {
        let builtIn = snapshot(
            key: "v1:builtin",
            name: "Built-in Display",
            kind: .builtIn,
            connection: .builtIn,
            vendorID: 0x0610,
            isBuiltin: true
        )
        let virtual = snapshot(
            key: "v1:sidecar",
            name: "Sidecar",
            kind: .virtualUnsupported,
            connection: .unknown,
            vendorID: 0xF0F0
        )
        let device = hdmiDevice(uid: "hdmi-any", name: "Built-in Display", manufacturer: "Apple")
        XCTAssertNil(
            AudioMatching.match(display: builtIn, overrideUID: "hdmi-any", devices: [device])
        )
        XCTAssertNil(
            AudioMatching.match(display: virtual, overrideUID: nil, devices: [device])
        )
    }

    func testSameScoreTieFallsThroughToLowerUniquePair() {
        let display = snapshot(
            key: "v1:dell-hdmi",
            name: "DELL U2723QE",
            kind: .genericExternal,
            connection: .hdmi,
            vendorID: 0x10AC
        )
        let tied = [
            hdmiDevice(uid: "hdmi-a", name: "DELL U2723QE", manufacturer: "Dell"),
            hdmiDevice(uid: "hdmi-b", name: "DELL U2723QE", manufacturer: "Dell"),
        ]
        let uniqueLower = hdmiDevice(uid: "hdmi-lower", name: "DELL", manufacturer: "Dell")
        XCTAssertEqual(
            AudioMatching.match(
                display: display,
                overrideUID: nil,
                devices: tied + [uniqueLower]
            ),
            "hdmi-lower"
        )
    }
}

private func hdmiDevice(uid: String, name: String, manufacturer: String) -> HALOutputDevice {
    HALOutputDevice(
        uid: uid,
        name: name,
        manufacturer: manufacturer,
        transport: AudioMatching.transportHDMI,
        hasVolume: true,
        hasMute: true
    )
}

private func snapshot(
    key: String,
    name: String,
    kind: DisplayKind,
    connection: ConnectionKind,
    vendorID: UInt32,
    isBuiltin: Bool = false
) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayIdentity(
            persistentKey: key,
            fields: DisplayIdentityFields(
                inputs: DisplayIdentityInputs(
                    vendorID: vendorID,
                    productID: 1,
                    serial: 1,
                    portLocation: "port",
                    unitNumber: 1,
                    fallbackName: name
                )
            )
        ),
        sessionDisplayID: 2,
        name: name,
        kind: kind,
        isMain: false,
        isBuiltin: isBuiltin,
        connection: connection,
        brightness: BrightnessCapabilities(
            backend: .none,
            supportsHardware: false,
            supportsSoftware: false,
            current: 1
        ),
        volume: VolumeCapabilities(
            backend: .none,
            supportsVolume: false,
            supportsMute: false,
            current: 0
        )
    )
}
