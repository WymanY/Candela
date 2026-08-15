import XCTest
@testable import DisplayCore
import TestSupport

final class SpeakerResolutionTests: XCTestCase {
    func testDefaultOutputWinsEvenWhenAnotherDisplayHasVolume() {
        var dell = FakeSnapshots.dellUSBC()
        dell.volume.audioDeviceUID = "hdmi-dell"
        let snapshots = [FakeSnapshots.builtIn(), dell, FakeSnapshots.hdmiTV()]
        let devices = [
            HALOutputDevice(
                uid: "macbook",
                name: "MacBook Speakers",
                manufacturer: "Apple",
                transport: 0,
                hasVolume: true,
                hasMute: true
            ),
            HALOutputDevice(
                uid: "hdmi-dell",
                name: "DELL",
                manufacturer: "Dell",
                transport: AudioMatching.transportHDMI,
                hasVolume: true,
                hasMute: true
            ),
        ]

        let speaker = SpeakerResolution.resolve(
            snapshots: snapshots,
            defaultUID: "macbook",
            devices: devices
        )

        XCTAssertEqual(speaker?.name, "MacBook Speakers")
        XCTAssertEqual(speaker?.uid, "macbook")
        XCTAssertNil(speaker?.displayKey)
        XCTAssertEqual(speaker?.volume.backend, .coreAudio)
        XCTAssertTrue(speaker?.volume.supportsVolume ?? false)
    }

    func testMatchedDisplayUsesDisplayName() {
        var dell = FakeSnapshots.dellUSBC()
        dell.volume.audioDeviceUID = "hdmi-dell"
        dell.volume.current = 0.4
        let speaker = SpeakerResolution.resolve(
            snapshots: [dell],
            defaultUID: "hdmi-dell",
            devices: [
                HALOutputDevice(
                    uid: "hdmi-dell",
                    name: "DELL HDMI",
                    manufacturer: "Dell",
                    transport: AudioMatching.transportHDMI,
                    hasVolume: true,
                    hasMute: true
                ),
            ]
        )

        XCTAssertEqual(speaker?.name, FakeSnapshots.dellName)
        XCTAssertEqual(speaker?.displayKey, dell.id.persistentKey)
        XCTAssertEqual(speaker?.volume.current ?? -1, 0.4, accuracy: 0.0001)
    }

    func testFallsBackToFirstControllableDisplay() {
        let speaker = SpeakerResolution.resolve(
            snapshots: FakeSnapshots.standard(),
            defaultUID: nil,
            devices: []
        )
        XCTAssertEqual(speaker?.name, FakeSnapshots.dellName)
        XCTAssertEqual(speaker?.volume.backend, .ddc)
    }

    func testChoicesSkipSoftwareAggregatesAndPreferDisplayNames() {
        var dell = FakeSnapshots.dellUSBC()
        dell.volume.audioDeviceUID = "hdmi-dell"
        let devices = [
            HALOutputDevice(
                uid: "macbook",
                name: "MacBook Speakers",
                manufacturer: "Apple",
                transport: 0,
                hasVolume: true,
                hasMute: true
            ),
            HALOutputDevice(
                uid: "hdmi-dell",
                name: "DELL HDMI",
                manufacturer: "Dell",
                transport: AudioMatching.transportHDMI,
                hasVolume: true,
                hasMute: true
            ),
            HALOutputDevice(
                uid: "candela.software-volume.hidden",
                name: "Candela Volume",
                manufacturer: "Candela",
                transport: 0,
                hasVolume: false,
                hasMute: false
            ),
        ]

        let choices = SpeakerResolution.choices(snapshots: [dell], devices: devices)
        XCTAssertEqual(choices.map(\.uid), ["macbook", "hdmi-dell"])
        XCTAssertEqual(choices.map(\.name), ["MacBook Speakers", FakeSnapshots.dellName])
    }
}
