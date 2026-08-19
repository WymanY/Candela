import ControlKit
import DisplayCore
import TestSupport
import XCTest

final class ControlRouterTests: XCTestCase {
    func testListAndSetBrightness() {
        var snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { key, value in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].brightness.current = value
                }
            },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            setPictureInPicture: { _, _ in true },
            rename: { _, _ in true },
            applyPreset: { preset, key in
                for index in snapshots.indices where key == nil || snapshots[index].id.persistentKey == key {
                    if snapshots[index].brightness.showsBrightnessSlider {
                        snapshots[index].brightness.current = preset.value
                    }
                }
            },
            matchAll: { key in
                guard let source = snapshots.first(where: { $0.id.persistentKey == key }) else { return }
                for index in snapshots.indices where snapshots[index].id.persistentKey != key {
                    if snapshots[index].brightness.showsBrightnessSlider {
                        snapshots[index].brightness.current = source.brightness.current
                    }
                }
            },
            dump: { _ in "dump" }
        )

        let listed = ControlRouter.apply(ControlRequest(action: .list), backend: backend)
        XCTAssertTrue(listed.ok)
        XCTAssertEqual(listed.displays?.count, 4)

        let set = ControlRouter.apply(
            ControlRequest(action: .setBrightness, display: "Built-in", value: 0.2),
            backend: backend
        )
        XCTAssertTrue(set.ok)
        XCTAssertEqual(set.displays?.first?.brightness ?? 0, 0.2, accuracy: 0.0001)

        let preset = ControlRouter.apply(
            ControlRequest(action: .preset, preset: "max"),
            backend: backend
        )
        XCTAssertTrue(preset.ok)
        XCTAssertEqual(snapshots[0].brightness.current, 1.0, accuracy: 0.0001)
    }

    func testUnknownDisplayFails() {
        let snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            setPictureInPicture: { _, _ in true },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let response = ControlRouter.apply(
            ControlRequest(action: .get, display: "No Such Panel"),
            backend: backend
        )
        XCTAssertFalse(response.ok)
    }

    func testSetRotation() {
        var snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { key, rotation in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].rotation.current = rotation
                }
            },
            setPictureInPicture: { key, enabled in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].pictureInPictureActive = enabled
                }
                return PictureInPictureLayout.supports(kind: snapshots.first(where: { $0.id.persistentKey == key })?.kind ?? .genericExternal)
            },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let builtin = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: "Built-in", rotation: "portrait"),
            backend: backend
        )
        XCTAssertFalse(builtin.ok)
        XCTAssertEqual(snapshots[0].rotation.current, .deg0)

        let response = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: FakeSnapshots.dellName, rotation: "portrait"),
            backend: backend
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.displays?.first?.rotation, "90")
        XCTAssertEqual(snapshots[1].rotation.current, .deg90)

        let sidecar = ControlRouter.apply(
            ControlRequest(action: .setRotation, display: "Sidecar", rotation: "90"),
            backend: backend
        )
        XCTAssertFalse(sidecar.ok)
    }

    func testSetPictureInPicture() {
        var snapshots = FakeSnapshots.standard()
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            setPictureInPicture: { key, enabled in
                guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return false }
                guard PictureInPictureLayout.supports(kind: snapshots[index].kind) else { return false }
                snapshots[index].pictureInPictureActive = enabled
                return true
            },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let opened = ControlRouter.apply(
            ControlRequest(action: .setPictureInPicture, display: FakeSnapshots.dellName, pictureInPicture: true),
            backend: backend
        )
        XCTAssertTrue(opened.ok)
        XCTAssertEqual(opened.displays?.first?.pictureInPicture, true)
        XCTAssertTrue(snapshots[1].pictureInPictureActive)

        let sidecar = ControlRouter.apply(
            ControlRequest(action: .setPictureInPicture, display: "Sidecar", pictureInPicture: true),
            backend: backend
        )
        XCTAssertFalse(sidecar.ok)
        XCTAssertFalse(snapshots[3].pictureInPictureActive)
    }

    func testSaveAndApplyScene() {
        var snapshots = FakeSnapshots.standard()
        var scenes: [DisplayScene] = []
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { key, value in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].brightness.current = value
                }
            },
            setVolume: { key, value in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].volume.current = value
                }
            },
            setMuted: { key, muted in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].volume.isMuted = muted
                }
            },
            setContrast: { key, value in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].contrast.current = value
                }
            },
            setInput: { key, source in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].input.current = source
                    snapshots[index].input.currentCode = source.code
                }
            },
            setRotation: { key, rotation in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].rotation.current = rotation
                }
            },
            setPictureInPicture: { key, enabled in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].pictureInPictureActive = enabled
                }
                return true
            },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            scenes: { scenes },
            applyScene: { query in
                guard let scene = DisplaySceneQuery.resolve(query, in: scenes) else { return nil }
                let plan = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots)
                for command in plan.commands {
                    if let brightness = command.brightness,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].brightness.current = brightness
                    }
                    if let volume = command.volume,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].volume.current = volume
                    }
                    if let muted = command.muted,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].volume.isMuted = muted
                    }
                    if let contrast = command.contrast,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].contrast.current = contrast
                    }
                    if let input = command.input,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].input.current = input
                        snapshots[index].input.currentCode = input.code
                    }
                    if let rotation = command.rotation,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].rotation.current = rotation
                    }
                    if let pictureInPicture = command.pictureInPicture,
                       let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) {
                        snapshots[index].pictureInPictureActive = pictureInPicture
                    }
                }
                return scene
            },
            saveScene: { name in
                let scene = DisplaySceneCapture.scene(name: name, from: snapshots)
                if let index = scenes.firstIndex(where: { DisplaySceneName.slug($0.name) == DisplaySceneName.slug(name) }) {
                    scenes[index] = DisplayScene(
                        id: scenes[index].id,
                        name: name,
                        createdAt: scenes[index].createdAt,
                        targets: scene.targets,
                        speakerUID: scene.speakerUID,
                        speakerVolume: scene.speakerVolume,
                        speakerMuted: scene.speakerMuted
                    )
                    return scenes[index]
                }
                scenes.append(scene)
                return scene
            },
            renameScene: { query, name in
                guard let current = DisplaySceneQuery.resolve(query, in: scenes),
                      let index = scenes.firstIndex(where: { $0.id == current.id }) else {
                    return nil
                }
                scenes[index].name = name
                return scenes[index]
            },
            deleteScene: { query in
                guard let current = DisplaySceneQuery.resolve(query, in: scenes),
                      let index = scenes.firstIndex(where: { $0.id == current.id }) else {
                    return false
                }
                scenes.remove(at: index)
                return true
            },
            dump: { _ in "" }
        )

        let saved = ControlRouter.apply(ControlRequest(action: .saveScene, name: "Night"), backend: backend)
        XCTAssertTrue(saved.ok)
        XCTAssertEqual(saved.scenes?.first?.name, "Night")
        XCTAssertEqual(scenes.count, 1)

        snapshots[0].brightness.current = 1
        snapshots[1].brightness.current = 1
        snapshots[1].volume.current = 1
        snapshots[1].rotation.current = .deg90

        let applied = ControlRouter.apply(ControlRequest(action: .applyScene, scene: "night"), backend: backend)
        XCTAssertTrue(applied.ok)
        XCTAssertEqual(snapshots[0].brightness.current, 0.80, accuracy: 0.0001)
        XCTAssertEqual(snapshots[1].brightness.current, 0.50, accuracy: 0.0001)
        XCTAssertEqual(snapshots[1].volume.current, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshots[1].rotation.current, .deg0)

        let listed = ControlRouter.apply(ControlRequest(action: .listScenes), backend: backend)
        XCTAssertEqual(listed.scenes?.count, 1)
        XCTAssertEqual(listed.scenes?.first?.active, true)

        let renamed = ControlRouter.apply(ControlRequest(action: .renameScene, name: "Late", scene: "Night"), backend: backend)
        XCTAssertTrue(renamed.ok)
        XCTAssertEqual(scenes.first?.name, "Late")

        let deleted = ControlRouter.apply(ControlRequest(action: .deleteScene, scene: "Late"), backend: backend)
        XCTAssertTrue(deleted.ok)
        XCTAssertTrue(scenes.isEmpty)
    }

    func testConfigurePictureInPictureAndWall() {
        var snapshots = FakeSnapshots.standard()
        var wallOpen = false
        var configured: (String, PictureInPictureMode?, Bool?, String?)?
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            setPictureInPicture: { key, enabled in
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    snapshots[index].pictureInPictureActive = enabled
                }
                return true
            },
            configurePictureInPicture: { key, mode, mirrored, window, zoom in
                configured = (key, mode, mirrored, window?.title)
                if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
                    if let mode { snapshots[index].pictureInPictureMode = mode }
                    if let mirrored { snapshots[index].pictureInPictureMirrored = mirrored }
                    snapshots[index].pictureInPictureWindow = window
                    snapshots[index].pictureInPictureActive = true
                }
                return true
            },
            setPictureInPictureWall: { enabled in
                wallOpen = enabled
                return true
            },
            isPictureInPictureWallOpen: { wallOpen },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            dump: { _ in "" }
        )
        let configuredResponse = ControlRouter.apply(
            ControlRequest(
                action: .configurePictureInPicture,
                display: FakeSnapshots.dellName,
                pictureInPicture: true,
                pictureInPictureMode: "window",
                pictureInPictureMirrored: true,
                pictureInPictureWindow: "Slack"
            ),
            backend: backend
        )
        XCTAssertTrue(configuredResponse.ok)
        XCTAssertEqual(configured?.1, .window)
        XCTAssertEqual(configured?.2, true)
        XCTAssertEqual(configured?.3, "Slack")
        XCTAssertEqual(snapshots[1].pictureInPictureMode, .window)
        XCTAssertEqual(snapshots[1].pictureInPictureMirrored, true)

        let wall = ControlRouter.apply(
            ControlRequest(action: .setPictureInPictureWall, pictureInPicture: true),
            backend: backend
        )
        XCTAssertTrue(wall.ok)
        XCTAssertEqual(wall.pictureInPictureWall, true)
        XCTAssertTrue(wallOpen)
    }

    func testToggleBuiltInMirror() {
        var snapshots = FakeSnapshots.standard()
        var mirrored = false
        let backend = ControlBackend(
            snapshots: { snapshots },
            setBrightness: { _, _ in },
            setVolume: { _, _ in },
            setMuted: { _, _ in },
            setContrast: { _, _ in },
            setInput: { _, _ in },
            setRotation: { _, _ in },
            setPictureInPicture: { _, _ in true },
            rename: { _, _ in true },
            applyPreset: { _, _ in },
            matchAll: { _ in },
            toggleBuiltInMirror: {
                mirrored.toggle()
                for index in snapshots.indices {
                    snapshots[index].isMirroringBuiltIn = mirrored
                    snapshots[index].canMirrorBuiltIn = true
                }
                return true
            },
            isMirroringBuiltIn: { mirrored },
            dump: { _ in "" }
        )
        let response = ControlRouter.apply(
            ControlRequest(action: .setBuiltInMirror),
            backend: backend
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.isMirroringBuiltIn, true)
        XCTAssertTrue(snapshots[0].isMirroringBuiltIn)
    }
}

final class DisplayQueryTests: XCTestCase {
    func testResolvesAliasesAndCustomNames() {
        var snapshots = FakeSnapshots.standard()
        snapshots[1].name = "Desk Dell"
        XCTAssertEqual(DisplayQuery.resolve("main", in: snapshots)?.isMain, true)
        XCTAssertEqual(DisplayQuery.resolve("builtin", in: snapshots)?.isBuiltin, true)
        XCTAssertEqual(DisplayQuery.resolve("Desk Dell", in: snapshots)?.hardwareName, FakeSnapshots.dellName)
        XCTAssertEqual(DisplayQuery.resolve("DELL", in: snapshots)?.kind, .genericExternal)
        XCTAssertNil(DisplayQuery.resolve("Display", in: snapshots))
    }
}

final class DisplayNameResolverTests: XCTestCase {
    func testCustomNameWinsUntilCleared() {
        XCTAssertEqual(DisplayNameResolver.displayName(hardwareName: "DELL", customName: " Desk "), "Desk")
        XCTAssertEqual(DisplayNameResolver.displayName(hardwareName: "DELL", customName: "  "), "DELL")
    }
}
