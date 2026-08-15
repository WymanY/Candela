import DisplayCore
import TestSupport
import XCTest

final class DisplaySceneTests: XCTestCase {
    func testCaptureSkipsVirtualDisplays() {
        let snapshots = FakeSnapshots.standard()
        let speaker = SpeakerOutput(
            name: "MacBook Speakers",
            uid: "macbook",
            volume: VolumeCapabilities(backend: .coreAudio, supportsVolume: true, supportsMute: true, current: 0.43)
        )
        let scene = DisplaySceneCapture.scene(name: " Desk ", from: snapshots, speaker: speaker)
        XCTAssertEqual(scene.name, "Desk")
        XCTAssertEqual(scene.targets.count, 3)
        XCTAssertEqual(scene.speakerUID, "macbook")
        XCTAssertEqual(scene.speakerVolume ?? -1, 0.43, accuracy: 0.0001)
        XCTAssertEqual(scene.speakerMuted, false)
        XCTAssertFalse(scene.targets.contains(where: { $0.persistentKey == snapshots[3].id.persistentKey }))

        let dell = scene.targets.first(where: { $0.persistentKey == snapshots[1].id.persistentKey })
        XCTAssertEqual(dell?.brightness ?? -1, 0.50, accuracy: 0.0001)
        XCTAssertEqual(dell?.volume ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(dell?.muted, false)
        XCTAssertEqual(dell?.contrast ?? -1, 0.50, accuracy: 0.0001)
        XCTAssertEqual(dell?.inputCode, DisplayInputSource.displayPort1.code)
        XCTAssertEqual(dell?.rotationDegrees, 0)
        XCTAssertEqual(dell?.pictureInPicture, false)
    }

    func testPlannerAppliesSupportedFieldsAndReportsMissing() {
        var snapshots = FakeSnapshots.standard()
        let missingKey = "v1:gone"
        let scene = DisplayScene(
            name: "Night",
            targets: [
                DisplaySceneTarget(
                    persistentKey: snapshots[0].id.persistentKey,
                    brightness: 0.20
                ),
                DisplaySceneTarget(
                    persistentKey: snapshots[1].id.persistentKey,
                    brightness: 0.20,
                    volume: 0.10,
                    muted: true,
                    contrast: 0.40,
                    inputCode: DisplayInputSource.hdmi1.code,
                    rotationDegrees: 90,
                    pictureInPicture: true
                ),
                DisplaySceneTarget(
                    persistentKey: snapshots[3].id.persistentKey,
                    brightness: 0.10
                ),
                DisplaySceneTarget(persistentKey: missingKey, brightness: 0.3),
            ]
        )

        let plan = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots)
        XCTAssertEqual(plan.commands.count, 2)
        XCTAssertEqual(plan.missingKeys, [missingKey])
        XCTAssertTrue(plan.skippedKeys.contains(snapshots[3].id.persistentKey))

        let builtin = plan.commands.first(where: { $0.persistentKey == snapshots[0].id.persistentKey })
        XCTAssertEqual(builtin?.brightness ?? -1, 0.20, accuracy: 0.0001)
        XCTAssertNil(builtin?.rotation)

        let dell = plan.commands.first(where: { $0.persistentKey == snapshots[1].id.persistentKey })
        XCTAssertEqual(dell?.input, .hdmi1)
        XCTAssertEqual(dell?.rotation, .deg90)
        XCTAssertEqual(dell?.pictureInPicture, true)

        XCTAssertFalse(DisplayScenePlanner.matches(scene, snapshots: snapshots))
        snapshots[0].brightness.current = 0.20
        snapshots[1].brightness.current = 0.20
        snapshots[1].volume.current = 0.10
        snapshots[1].volume.isMuted = true
        snapshots[1].contrast.current = 0.40
        snapshots[1].input.current = .hdmi1
        snapshots[1].input.currentCode = DisplayInputSource.hdmi1.code
        snapshots[1].rotation.current = .deg90
        snapshots[1].pictureInPictureActive = true
        XCTAssertTrue(DisplayScenePlanner.matches(scene, snapshots: snapshots))
    }

    func testQueryResolvesNameSlugAndID() {
        let one = DisplayScene(id: "abc", name: "Night Writing", targets: [])
        let two = DisplayScene(id: "def", name: "Meeting", targets: [])
        XCTAssertEqual(DisplaySceneQuery.resolve("night-writing", in: [one, two])?.id, "abc")
        XCTAssertEqual(DisplaySceneQuery.resolve("Meeting", in: [one, two])?.id, "def")
        XCTAssertEqual(DisplaySceneQuery.resolve("ABC", in: [one, two])?.id, "abc")
        XCTAssertNil(DisplaySceneQuery.resolve("missing", in: [one, two]))
    }

    func testPlannerResolvesAliasedKeys() {
        var snapshots = FakeSnapshots.standard()
        let liveKey = snapshots[1].id.persistentKey
        let oldKey = "v1:old-dell"
        let scene = DisplayScene(
            name: "Code",
            targets: [DisplaySceneTarget(persistentKey: oldKey, brightness: 0.22, volume: 0.31)]
        )
        let missing = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots)
        XCTAssertTrue(missing.commands.isEmpty)
        XCTAssertEqual(missing.missingKeys, [oldKey])

        let plan = DisplayScenePlanner.plan(
            scene: scene,
            snapshots: snapshots,
            aliases: [oldKey: liveKey]
        )
        XCTAssertEqual(plan.commands.count, 1)
        XCTAssertEqual(plan.commands.first?.persistentKey, liveKey)
        XCTAssertEqual(plan.commands.first?.brightness ?? -1, 0.22, accuracy: 0.0001)
        XCTAssertEqual(plan.commands.first?.volume ?? -1, 0.31, accuracy: 0.0001)

        snapshots[1].brightness.current = 0.22
        snapshots[1].volume.current = 0.31
        XCTAssertTrue(DisplayScenePlanner.matches(scene, snapshots: snapshots, aliases: [oldKey: liveKey]))
    }

    func testPlannerAppliesPreviewBrightness() {
        var snapshots = FakeSnapshots.standard()
        snapshots[0].brightness.backend = .none
        snapshots[0].brightness.supportsHardware = false
        snapshots[0].brightness.supportsSoftware = false
        snapshots[0].brightness.current = 1
        let scene = DisplayScene(
            name: "Code",
            targets: [DisplaySceneTarget(persistentKey: snapshots[0].id.persistentKey, brightness: 0.17)]
        )
        let plan = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots)
        XCTAssertEqual(plan.commands.first?.brightness ?? -1, 0.17, accuracy: 0.0001)
    }

    func testSpeakerRestoreUsesSavedOutput() {
        var snapshots = FakeSnapshots.standard()
        snapshots[1].volume.current = 0.90
        let scene = DisplayScene(
            name: "Code",
            targets: [
                DisplaySceneTarget(persistentKey: snapshots[1].id.persistentKey, brightness: 1, volume: 0.43, muted: false)
            ],
            speakerUID: "macbook",
            speakerVolume: 0.43,
            speakerMuted: false
        )
        let speaker = SpeakerOutput(
            name: "MacBook Speakers",
            uid: "macbook",
            volume: VolumeCapabilities(backend: .coreAudio, supportsVolume: true, supportsMute: true, current: 0.90)
        )
        let restore = DisplaySceneSpeakerRestore.resolve(
            scene: scene,
            speaker: speaker,
            commands: DisplayScenePlanner.plan(scene: scene, snapshots: snapshots).commands
        )
        XCTAssertEqual(restore?.uid, "macbook")
        XCTAssertEqual(restore?.volume ?? -1, 0.43, accuracy: 0.0001)
        XCTAssertEqual(restore?.muted, false)
        XCTAssertFalse(DisplayScenePlanner.matches(scene, snapshots: snapshots, aliases: [:], speaker: speaker))

        var restored = speaker
        restored.volume.current = 0.43
        restored.volume.isMuted = false
        snapshots[1].brightness.current = 1
        snapshots[1].volume.current = 0.43
        snapshots[1].volume.isMuted = false
        XCTAssertTrue(DisplayScenePlanner.matches(scene, snapshots: snapshots, aliases: [:], speaker: restored))
    }

    func testLegacySceneInfersSpeakerVolumeFromSingleDisplay() {
        let snapshots = FakeSnapshots.standard()
        let scene = DisplayScene(
            name: "Code",
            targets: [
                DisplaySceneTarget(persistentKey: snapshots[1].id.persistentKey, volume: 0.43, muted: false)
            ]
        )
        let speaker = SpeakerOutput(
            name: "MacBook Speakers",
            uid: "macbook",
            volume: VolumeCapabilities(backend: .coreAudio, supportsVolume: true, supportsMute: true, current: 1)
        )
        let restore = DisplaySceneSpeakerRestore.resolve(
            scene: scene,
            speaker: speaker,
            commands: DisplayScenePlanner.plan(scene: scene, snapshots: snapshots).commands
        )
        XCTAssertNil(restore?.uid)
        XCTAssertEqual(restore?.volume ?? -1, 0.43, accuracy: 0.0001)
        XCTAssertEqual(restore?.muted, false)
    }

    func testPlannerRestoresVolumeBeforeProbeFinishes() {
        var snapshots = FakeSnapshots.standard()
        snapshots[1].volume.backend = .none
        snapshots[1].volume.supportsVolume = false
        snapshots[1].volume.supportsMute = false
        snapshots[1].volume.current = 1
        let scene = DisplayScene(
            name: "Code",
            targets: [DisplaySceneTarget(persistentKey: snapshots[1].id.persistentKey, volume: 0.43, muted: false)]
        )
        let plan = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots)
        XCTAssertEqual(plan.commands.first?.volume ?? -1, 0.43, accuracy: 0.0001)
        XCTAssertEqual(plan.commands.first?.muted, false)
    }
}
