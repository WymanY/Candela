import CoreAudio
import DisplayCore
import XCTest

@testable import AudioKit

final class HALVolumeControlTests: XCTestCase {
    func testVirtualMainVolumeFourCC() {
        XCTAssertEqual(kCandelaVirtualMainVolume, 0x766D_7663)
        XCTAssertEqual(kCandelaVirtualMainVolume, HALFourCC.make("vmvc"))
        XCTAssertEqual(HALFourCC.string(kCandelaVirtualMainVolume), "vmvc")
    }

    func testTransportFourCCsMatchCoreAudio() {
        XCTAssertEqual(AudioMatching.transportHDMI, kAudioDeviceTransportTypeHDMI)
        XCTAssertEqual(AudioMatching.transportDisplayPort, kAudioDeviceTransportTypeDisplayPort)
        XCTAssertEqual(AudioMatching.transportThunderbolt, kAudioDeviceTransportTypeThunderbolt)
        XCTAssertEqual(AudioMatching.transportUSB, kAudioDeviceTransportTypeUSB)
        XCTAssertEqual(AudioMatching.transportHDMI, HALFourCC.make("hdmi"))
        XCTAssertEqual(AudioMatching.transportDisplayPort, HALFourCC.make("dprt"))
        XCTAssertEqual(AudioMatching.transportThunderbolt, HALFourCC.make("thun"))
        XCTAssertEqual(AudioMatching.transportUSB, HALFourCC.make("usb "))
    }

    func testVolumeAndMuteSelectorsMatchCoreAudio() {
        XCTAssertEqual(kAudioDevicePropertyVolumeScalar, HALFourCC.make("volm"))
        XCTAssertEqual(kAudioDevicePropertyMute, HALFourCC.make("mute"))
        XCTAssertEqual(
            HALVolumeControl.volumeScalarAddress(element: 0).mSelector,
            kAudioDevicePropertyVolumeScalar
        )
        XCTAssertEqual(HALVolumeControl.muteAddress(element: 0).mSelector, kAudioDevicePropertyMute)
        XCTAssertEqual(
            HALVolumeControl.streamConfigurationAddress().mSelector,
            kAudioDevicePropertyStreamConfiguration
        )
    }

    func testPropertyAddressBuilders() {
        let vmvcOut = HALVolumeControl.virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeOutput)
        XCTAssertEqual(vmvcOut.mSelector, kCandelaVirtualMainVolume)
        XCTAssertEqual(vmvcOut.mScope, kAudioObjectPropertyScopeOutput)
        XCTAssertEqual(vmvcOut.mElement, kAudioObjectPropertyElementMain)

        let vmvcGlobal = HALVolumeControl.virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeGlobal)
        XCTAssertEqual(vmvcGlobal.mScope, kAudioObjectPropertyScopeGlobal)

        let scalar = HALVolumeControl.volumeScalarAddress(element: 3)
        XCTAssertEqual(scalar.mSelector, kAudioDevicePropertyVolumeScalar)
        XCTAssertEqual(scalar.mScope, kAudioObjectPropertyScopeOutput)
        XCTAssertEqual(scalar.mElement, 3)

        let mute = HALVolumeControl.muteAddress(element: kAudioObjectPropertyElementMain)
        XCTAssertEqual(mute.mSelector, kAudioDevicePropertyMute)
        XCTAssertEqual(mute.mScope, kAudioObjectPropertyScopeOutput)
        XCTAssertEqual(mute.mElement, kAudioObjectPropertyElementMain)

        let streams = HALVolumeControl.streamConfigurationAddress()
        XCTAssertEqual(streams.mScope, kAudioObjectPropertyScopeOutput)
        XCTAssertEqual(streams.mElement, kAudioObjectPropertyElementMain)
    }

    func testEnumeratorPropertyAddresses() {
        XCTAssertEqual(
            HALDeviceEnumerator.devicesAddress.mSelector,
            kAudioHardwarePropertyDevices
        )
        XCTAssertEqual(
            HALDeviceEnumerator.defaultOutputDeviceAddress.mSelector,
            kAudioHardwarePropertyDefaultOutputDevice
        )
        XCTAssertEqual(
            HALDeviceEnumerator.transportAddress.mSelector,
            kAudioDevicePropertyTransportType
        )
        XCTAssertEqual(HALDeviceEnumerator.nameAddress.mSelector, kAudioObjectPropertyName)
        XCTAssertEqual(
            HALDeviceEnumerator.manufacturerAddress.mSelector,
            kAudioObjectPropertyManufacturer
        )
        XCTAssertEqual(HALDeviceEnumerator.uidAddress.mSelector, kAudioDevicePropertyDeviceUID)
        XCTAssertEqual(
            HALDeviceEnumerator.streamDirectionAddress.mSelector,
            kAudioStreamPropertyDirection
        )
        XCTAssertEqual(HALDeviceEnumerator.outputStreamDirection, 0)
        XCTAssertEqual(
            HALDeviceEnumerator.outputStreamsAddress.mScope,
            kAudioObjectPropertyScopeOutput
        )
    }

    func testChannelElementsWalkEveryBufferChannel() {
        XCTAssertEqual(HALVolumeControl.channelElements(bufferChannelCounts: []), [])
        XCTAssertEqual(HALVolumeControl.channelElements(bufferChannelCounts: [0, 0]), [])
        XCTAssertEqual(HALVolumeControl.channelElements(bufferChannelCounts: [2]), [1, 2])
        XCTAssertEqual(HALVolumeControl.channelElements(bufferChannelCounts: [8]), Array(1...8))
        XCTAssertEqual(
            HALVolumeControl.channelElements(bufferChannelCounts: [2, 2]),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            HALVolumeControl.channelElements(bufferChannelCounts: [6, 6]),
            Array(1...12)
        )
        XCTAssertNotEqual(
            HALVolumeControl.channelElements(bufferChannelCounts: [6, 6]).count,
            2
        )
    }

    func testClampedScalar() {
        XCTAssertEqual(HALVolumeControl.clampedScalar(0), 0)
        XCTAssertEqual(HALVolumeControl.clampedScalar(1), 1)
        XCTAssertEqual(HALVolumeControl.clampedScalar(0.25), 0.25)
        XCTAssertEqual(HALVolumeControl.clampedScalar(-4), 0)
        XCTAssertEqual(HALVolumeControl.clampedScalar(4), 1)
        XCTAssertEqual(HALVolumeControl.clampedScalar(.nan), 0)
        XCTAssertEqual(HALVolumeControl.clampedScalar(.infinity), 1)
        XCTAssertEqual(HALVolumeControl.clampedScalar(-.infinity), 0)
    }

    func testVirtualMainVolumeOutputWins() {
        let path = HALVolumeControl.volumeWritePath(
            hasProperty: { $0.mSelector == kCandelaVirtualMainVolume },
            isSettable: { _ in true },
            channelElements: [1, 2]
        )
        XCTAssertEqual(path, .virtualMainVolume(kAudioObjectPropertyScopeOutput))
    }

    func testVirtualMainVolumeGlobalOnlyIfOutputHasPropertyIsFalse() {
        let path = HALVolumeControl.volumeWritePath(
            hasProperty: {
                $0.mSelector == kCandelaVirtualMainVolume
                    && $0.mScope == kAudioObjectPropertyScopeGlobal
            },
            isSettable: { _ in true },
            channelElements: []
        )
        XCTAssertEqual(path, .virtualMainVolume(kAudioObjectPropertyScopeGlobal))
    }

    func testVirtualMainVolumeDoesNotUseGlobalWhenOutputExistsButIsNotSettable() {
        let path = HALVolumeControl.volumeWritePath(
            hasProperty: {
                $0.mSelector == kCandelaVirtualMainVolume
                    && $0.mScope == kAudioObjectPropertyScopeOutput
            },
            isSettable: { _ in false },
            channelElements: [1, 2]
        )
        XCTAssertEqual(path, .unavailable)
    }

    func testVolumeScalarMainAfterSkippingUnsettableVirtual() {
        let path = HALVolumeControl.volumeWritePath(
            hasProperty: { address in
                if address.mSelector == kCandelaVirtualMainVolume,
                   address.mScope == kAudioObjectPropertyScopeOutput
                {
                    return true
                }
                return address.mSelector == kAudioDevicePropertyVolumeScalar
                    && address.mElement == kAudioObjectPropertyElementMain
            },
            isSettable: { $0.mSelector == kAudioDevicePropertyVolumeScalar },
            channelElements: [1, 2]
        )
        XCTAssertEqual(path, .volumeScalarMain)
    }

    func testVolumeFallsThroughToEveryStreamChannel() {
        let path = HALVolumeControl.volumeWritePath(
            hasProperty: {
                $0.mSelector == kAudioDevicePropertyVolumeScalar && $0.mElement >= 1
            },
            isSettable: { _ in true },
            channelElements: [1, 2, 3, 4, 5, 6]
        )
        XCTAssertEqual(path, .volumeScalarChannels)
    }

    func testMuteMainThenChannelWalk() {
        XCTAssertEqual(
            HALVolumeControl.muteWritePath(
                hasProperty: { $0.mSelector == kAudioDevicePropertyMute && $0.mElement == 0 },
                isSettable: { _ in true },
                channelElements: [1, 2]
            ),
            .muteMain
        )
        XCTAssertEqual(
            HALVolumeControl.muteWritePath(
                hasProperty: { $0.mSelector == kAudioDevicePropertyMute && $0.mElement >= 1 },
                isSettable: { _ in true },
                channelElements: [1, 2, 3]
            ),
            .muteChannels
        )
        XCTAssertEqual(
            HALVolumeControl.muteWritePath(
                hasProperty: { _ in false },
                isSettable: { _ in true },
                channelElements: [1, 2]
            ),
            .unavailable
        )
    }

    func testHasVolumeAndMuteUseHasPropertyOnly() {
        XCTAssertTrue(
            HALVolumeControl.hasVolumeProperty(
                hasProperty: { $0.mSelector == kCandelaVirtualMainVolume },
                channelElements: []
            )
        )
        XCTAssertTrue(
            HALVolumeControl.hasVolumeProperty(
                hasProperty: {
                    $0.mSelector == kAudioDevicePropertyVolumeScalar && $0.mElement == 4
                },
                channelElements: [1, 2, 3, 4]
            )
        )
        XCTAssertFalse(
            HALVolumeControl.hasVolumeProperty(
                hasProperty: { _ in false },
                channelElements: [1, 2]
            )
        )
        XCTAssertTrue(
            HALVolumeControl.hasMuteProperty(
                hasProperty: { $0.mSelector == kAudioDevicePropertyMute && $0.mElement == 0 },
                channelElements: []
            )
        )
        XCTAssertTrue(
            HALVolumeControl.hasMuteProperty(
                hasProperty: { $0.mSelector == kAudioDevicePropertyMute && $0.mElement == 2 },
                channelElements: [1, 2]
            )
        )
        XCTAssertFalse(
            HALVolumeControl.hasMuteProperty(
                hasProperty: { _ in false },
                channelElements: [1]
            )
        )
    }

    func testUnknownUIDDoesNotSetDefaultOutput() {
        XCTAssertFalse(HALDeviceEnumerator.setDefaultOutputUID("candela-no-such-device"))
    }

    func testDefaultOutputSwitchAcceptsAsynchronousHALChange() {
        var writes: [AudioDeviceID] = []
        let switched = HALDeviceEnumerator.switchDefaultOutput(
            uid: "target",
            resolveDeviceID: { $0 == "target" ? 42 : nil },
            writeDefault: {
                writes.append($0)
                return true
            },
            readDefaultUID: { "previous" }
        )

        XCTAssertTrue(switched)
        XCTAssertEqual(writes, [42])
    }

    func testDefaultOutputSwitchReportsWriteFailure() {
        let switched = HALDeviceEnumerator.switchDefaultOutput(
            uid: "target",
            resolveDeviceID: { $0 == "target" ? 42 : nil },
            writeDefault: { _ in false },
            readDefaultUID: { "previous" }
        )

        XCTAssertFalse(switched)
    }

    func testDefaultOutputSwitchTrimsUID() {
        var currentUID = "previous"
        let switched = HALDeviceEnumerator.switchDefaultOutput(
            uid: " target ",
            resolveDeviceID: { $0 == "target" ? 42 : nil },
            writeDefault: { _ in
                currentUID = "target"
                return true
            },
            readDefaultUID: { currentUID }
        )

        XCTAssertTrue(switched)
    }

    func testDefaultOutputSwitchSkipsWriteWhenAlreadySelected() {
        var didWrite = false
        let switched = HALDeviceEnumerator.switchDefaultOutput(
            uid: "target",
            resolveDeviceID: { _ in 42 },
            writeDefault: { _ in
                didWrite = true
                return true
            },
            readDefaultUID: { "target" }
        )

        XCTAssertTrue(switched)
        XCTAssertFalse(didWrite)
    }

    func testPlaybackContinuityRequiresCapturedPlayback() {
        XCTAssertFalse(
            PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: [],
                runningProcessIDs: [],
                expectedOutputUID: "target",
                currentOutputUID: "target"
            )
        )
    }

    func testPlaybackContinuityDoesNotResumeWhileCapturedProcessIsRunning() {
        XCTAssertFalse(
            PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: [101, 202],
                runningProcessIDs: [202, 303],
                expectedOutputUID: "target",
                currentOutputUID: "target"
            )
        )
    }

    func testPlaybackContinuityRequiresExpectedOutputRoute() {
        XCTAssertFalse(
            PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: [101],
                runningProcessIDs: [],
                expectedOutputUID: "target",
                currentOutputUID: "other"
            )
        )
    }

    func testPlaybackContinuityResumesStoppedPlaybackOnExpectedRoute() {
        XCTAssertTrue(
            PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: [101],
                runningProcessIDs: [303],
                expectedOutputUID: "target",
                currentOutputUID: "target"
            )
        )
    }

    func testUnknownUIDDoesNotThrow() {
        XCTAssertNil(HALDeviceEnumerator.deviceID(forUID: "candela-no-such-device"))
        XCTAssertFalse(HALVolumeControl.setVolume(uid: "candela-no-such-device", value: 0.5))
        XCTAssertNil(HALVolumeControl.volume(uid: "candela-no-such-device"))
        XCTAssertFalse(HALVolumeControl.setMuted(uid: "candela-no-such-device", muted: true))
        XCTAssertNil(HALVolumeControl.isMuted(uid: "candela-no-such-device"))
    }

    func testEnumerateOutputDevicesAndReadDefaultWithoutMutation() throws {
        let devices = HALDeviceEnumerator.outputDevices()
        var seen = Set<String>()
        for device in devices {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertTrue(seen.insert(device.uid).inserted, "duplicate UID \(device.uid)")
            if let deviceID = HALDeviceEnumerator.deviceID(forUID: device.uid) {
                XCTAssertTrue(HALDeviceEnumerator.hasOutputStream(deviceID))
            }
        }

        guard let uid = HALDeviceEnumerator.defaultOutputUID() else {
            throw XCTSkip("No default output device")
        }
        XCTAssertTrue(devices.contains(where: { $0.uid == uid }))

        let first = HALVolumeControl.volume(uid: uid)
        let second = HALVolumeControl.volume(uid: uid)
        XCTAssertEqual(first, second)
        let mutedFirst = HALVolumeControl.isMuted(uid: uid)
        let mutedSecond = HALVolumeControl.isMuted(uid: uid)
        XCTAssertEqual(mutedFirst, mutedSecond)
    }
}
