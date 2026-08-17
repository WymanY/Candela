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
        XCTAssertEqual(bound.current, 0, accuracy: 0.0001)
        XCTAssertFalse(bound.isMuted)
    }

    func testHALBindKeepsExistingVolumeUntilLiveRead() {
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
            existing: VolumeCapabilities(backend: .none, supportsVolume: false, supportsMute: false, current: 0.87),
            lastVolume: 0.4,
            lastMuted: true
        )
        XCTAssertEqual(bound.current, 0.87, accuracy: 0.0001)
        XCTAssertFalse(bound.isMuted)
        let live = VolumeResolution.adoptingHAL(bound, current: 0.87, muted: false)
        XCTAssertEqual(live.current, 0.87, accuracy: 0.0001)
        XCTAssertFalse(live.isMuted)
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

    func testAdoptingHALIgnoresMissingReads() {
        let existing = VolumeCapabilities(
            backend: .coreAudio,
            supportsVolume: true,
            supportsMute: true,
            current: 0.43,
            isMuted: true
        )
        let unchanged = VolumeResolution.adoptingHAL(existing, current: nil, muted: nil)
        XCTAssertEqual(unchanged.current, 0.43, accuracy: 0.0001)
        XCTAssertTrue(unchanged.isMuted)

        let clamped = VolumeResolution.adoptingHAL(existing, current: 1.4, muted: false)
        XCTAssertEqual(clamped.current, 1, accuracy: 0.0001)
        XCTAssertFalse(clamped.isMuted)
    }

    func testPreferringExistingHALKeepsCoreAudioOverDDC() {
        let existing = VolumeCapabilities(
            backend: .coreAudio,
            supportsVolume: true,
            supportsMute: true,
            current: 0.47,
            isMuted: false,
            audioDeviceUID: "BuiltInSpeakerDevice"
        )
        let probed = VolumeCapabilities(
            backend: .ddc,
            supportsVolume: true,
            supportsMute: true,
            current: 0.25,
            isMuted: false
        )
        let kept = VolumeResolution.preferringExistingHAL(existing: existing, probed: probed)
        XCTAssertEqual(kept.backend, .coreAudio)
        XCTAssertEqual(kept.current, 0.47, accuracy: 0.0001)
        XCTAssertEqual(kept.audioDeviceUID, "BuiltInSpeakerDevice")
    }

    func testAdoptingLiveOutputPromotesReadableHALOverDDC() {
        let existing = VolumeCapabilities(
            backend: .ddc,
            supportsVolume: true,
            supportsMute: true,
            current: 0.25,
            isMuted: true
        )
        let live = VolumeResolution.adoptingLiveOutput(
            existing,
            deviceUID: "BuiltInSpeakerDevice",
            hasHALVolume: true,
            current: 0.47,
            muted: false
        )
        XCTAssertEqual(live.backend, .coreAudio)
        XCTAssertEqual(live.current, 0.47, accuracy: 0.0001)
        XCTAssertFalse(live.isMuted)
        XCTAssertEqual(live.audioDeviceUID, "BuiltInSpeakerDevice")
    }

    func testAdoptingLiveOutputLeavesDDCWhenHALIsUnavailable() {
        let existing = VolumeCapabilities(
            backend: .ddc,
            supportsVolume: true,
            supportsMute: true,
            current: 0.25,
            isMuted: false
        )
        let unchanged = VolumeResolution.adoptingLiveOutput(
            existing,
            deviceUID: "hdmi-dell",
            hasHALVolume: false,
            current: nil,
            muted: nil
        )
        XCTAssertEqual(unchanged.backend, .ddc)
        XCTAssertEqual(unchanged.current, 0.25, accuracy: 0.0001)
        XCTAssertNil(unchanged.audioDeviceUID)
    }
}
