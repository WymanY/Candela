import XCTest
@testable import DisplayCore

final class VolumeResolutionTests: XCTestCase {
    func testHALVolumeWins() {
        let device = HALOutputDevice(
            uid: "hdmi-1",
            name: "DELL",
            manufacturer: "Dell",
            transport: AudioMatching.transportHDMI,
            hasVolume: true,
            hasMute: true
        )
        let bound = VolumeResolution.bind(
            device: device,
            existing: VolumeCapabilities(backend: .none, supportsVolume: false, supportsMute: false, current: 0),
            lastVolume: 0.4,
            lastMuted: false
        )
        XCTAssertEqual(bound.backend, .coreAudio)
        XCTAssertTrue(bound.supportsVolume)
        XCTAssertEqual(bound.audioDeviceUID, "hdmi-1")
        XCTAssertEqual(bound.current, 0.4, accuracy: 0.0001)
        XCTAssertFalse(bound.isMuted)
    }

    func testMatchedDeviceWithoutHALUsesSoftware() {
        let device = HALOutputDevice(
            uid: "dp-mi",
            name: "Mi Monitor",
            manufacturer: "XMI",
            transport: AudioMatching.transportDisplayPort,
            hasVolume: false,
            hasMute: false
        )
        let bound = VolumeResolution.bind(
            device: device,
            existing: VolumeCapabilities(backend: .none, supportsVolume: false, supportsMute: false, current: 0),
            lastVolume: nil,
            lastMuted: nil
        )
        XCTAssertEqual(bound.backend, .software)
        XCTAssertTrue(bound.supportsVolume)
        XCTAssertTrue(bound.supportsMute)
        XCTAssertEqual(bound.current, 1, accuracy: 0.0001)
        XCTAssertEqual(bound.audioDeviceUID, "dp-mi")
    }

    func testDDCBeatsSoftwareWhenProbeSucceeded() {
        let device = HALOutputDevice(
            uid: "hdmi-1",
            name: "DELL",
            manufacturer: "Dell",
            transport: AudioMatching.transportHDMI,
            hasVolume: false,
            hasMute: false
        )
        let existing = VolumeCapabilities(
            backend: .ddc,
            supportsVolume: true,
            supportsMute: true,
            current: 0.25
        )
        let bound = VolumeResolution.bind(
            device: device,
            existing: existing,
            lastVolume: 0.8,
            lastMuted: false
        )
        XCTAssertEqual(bound.backend, .ddc)
        XCTAssertEqual(bound.current, 0.25, accuracy: 0.0001)
        XCTAssertEqual(bound.audioDeviceUID, "hdmi-1")
    }

    func testMissingDeviceKeepsDDCAndDropsSoftware() {
        let ddc = VolumeResolution.bind(
            device: nil,
            existing: VolumeCapabilities(backend: .ddc, supportsVolume: true, supportsMute: true, current: 0.3),
            lastVolume: nil,
            lastMuted: nil
        )
        XCTAssertEqual(ddc.backend, .ddc)
        XCTAssertTrue(ddc.supportsVolume)

        let software = VolumeResolution.bind(
            device: nil,
            existing: VolumeCapabilities(
                backend: .software,
                supportsVolume: true,
                supportsMute: true,
                current: 0.5,
                audioDeviceUID: "gone"
            ),
            lastVolume: nil,
            lastMuted: nil
        )
        XCTAssertEqual(software.backend, .none)
        XCTAssertFalse(software.supportsVolume)
        XCTAssertNil(software.audioDeviceUID)
    }

    func testRestoresLastSoftwareVolume() {
        let device = HALOutputDevice(
            uid: "hdmi-tv",
            name: "TV",
            manufacturer: "LG",
            transport: AudioMatching.transportHDMI,
            hasVolume: false,
            hasMute: false
        )
        let bound = VolumeResolution.bind(
            device: device,
            existing: VolumeCapabilities(backend: .none, supportsVolume: false, supportsMute: false, current: 0),
            lastVolume: 0.2,
            lastMuted: true
        )
        XCTAssertEqual(bound.backend, .software)
        XCTAssertEqual(bound.current, 0.2, accuracy: 0.0001)
        XCTAssertTrue(bound.isMuted)
    }
}
