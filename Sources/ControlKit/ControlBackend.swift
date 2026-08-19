import DisplayCore
import Foundation

public struct ControlBackend {
    public var snapshots: () -> [DisplaySnapshot]
    public var setBrightness: (String, Double) -> Void
    public var setVolume: (String, Double) -> Void
    public var setMuted: (String, Bool) -> Void
    public var setContrast: (String, Double) -> Void
    public var setInput: (String, DisplayInputSource) -> Void
    public var setRotation: (String, DisplayRotation) -> Void
    public var setPictureInPicture: (String, Bool) -> Bool
    public var configurePictureInPicture: (String, PictureInPictureMode?, Bool?, PictureInPictureWindowIdentity?, Double?) -> Bool
    public var setPictureInPictureWall: (Bool) -> Bool
    public var isPictureInPictureWallOpen: () -> Bool
    public var rename: (String, String?) -> Bool
    public var applyPreset: (BrightnessPreset, String?) -> Void
    public var matchAll: (String) -> Void
    public var scenes: () -> [DisplayScene]
    public var applyScene: (String) -> DisplayScene?
    public var saveScene: (String) -> DisplayScene?
    public var renameScene: (String, String) -> DisplayScene?
    public var deleteScene: (String) -> Bool
    public var dump: (Bool) -> String

    public init(
        snapshots: @escaping () -> [DisplaySnapshot],
        setBrightness: @escaping (String, Double) -> Void,
        setVolume: @escaping (String, Double) -> Void,
        setMuted: @escaping (String, Bool) -> Void,
        setContrast: @escaping (String, Double) -> Void,
        setInput: @escaping (String, DisplayInputSource) -> Void,
        setRotation: @escaping (String, DisplayRotation) -> Void,
        setPictureInPicture: @escaping (String, Bool) -> Bool,
        configurePictureInPicture: @escaping (String, PictureInPictureMode?, Bool?, PictureInPictureWindowIdentity?, Double?) -> Bool = { _, _, _, _, _ in true },
        setPictureInPictureWall: @escaping (Bool) -> Bool = { _ in true },
        isPictureInPictureWallOpen: @escaping () -> Bool = { false },
        rename: @escaping (String, String?) -> Bool,
        applyPreset: @escaping (BrightnessPreset, String?) -> Void,
        matchAll: @escaping (String) -> Void,
        scenes: @escaping () -> [DisplayScene] = { [] },
        applyScene: @escaping (String) -> DisplayScene? = { _ in nil },
        saveScene: @escaping (String) -> DisplayScene? = { _ in nil },
        renameScene: @escaping (String, String) -> DisplayScene? = { _, _ in nil },
        deleteScene: @escaping (String) -> Bool = { _ in false },
        dump: @escaping (Bool) -> String
    ) {
        self.snapshots = snapshots
        self.setBrightness = setBrightness
        self.setVolume = setVolume
        self.setMuted = setMuted
        self.setContrast = setContrast
        self.setInput = setInput
        self.setRotation = setRotation
        self.setPictureInPicture = setPictureInPicture
        self.configurePictureInPicture = configurePictureInPicture
        self.setPictureInPictureWall = setPictureInPictureWall
        self.isPictureInPictureWallOpen = isPictureInPictureWallOpen
        self.rename = rename
        self.applyPreset = applyPreset
        self.matchAll = matchAll
        self.scenes = scenes
        self.applyScene = applyScene
        self.saveScene = saveScene
        self.renameScene = renameScene
        self.deleteScene = deleteScene
        self.dump = dump
    }
}

public enum ControlRouter {
    public static func apply(_ request: ControlRequest, backend: ControlBackend) -> ControlResponse {
        let all = backend.snapshots()
        switch request.action {
        case .list:
            return .success(displays: all.map(ControlDisplayDTO.init(snapshot:)))
        case .dump:
            return ControlResponse(ok: true, dump: backend.dump(request.redact ?? true))
        case .listScenes:
            return .success(scenes: backend.scenes().map { ControlSceneDTO(scene: $0, snapshots: all) })
        case .setPictureInPictureWall:
            guard let enabled = request.pictureInPicture else {
                return .failure("pictureInPicture true/false is required.")
            }
            guard backend.setPictureInPictureWall(enabled) else {
                return .failure("Could not update the monitor wall.")
            }
            return ControlResponse(
                ok: true,
                displays: backend.snapshots().map(ControlDisplayDTO.init(snapshot:)),
                pictureInPictureWall: backend.isPictureInPictureWallOpen()
            )
        case .applyScene:
            guard let query = sceneQuery(request) else {
                return .failure("Scene name or id is required.")
            }
            guard let scene = backend.applyScene(query) else {
                return .failure("No scene matched '\(query)'.")
            }
            return sceneResponse(scene, backend: backend)
        case .saveScene:
            guard let name = request.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return .failure("Scene name is required.")
            }
            guard let scene = backend.saveScene(name) else {
                return .failure("Could not save scene '\(name)'.")
            }
            return sceneResponse(scene, backend: backend)
        case .renameScene:
            guard let query = sceneQuery(request) else {
                return .failure("Scene name or id is required.")
            }
            guard let name = request.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return .failure("New scene name is required.")
            }
            guard let scene = backend.renameScene(query, name) else {
                return .failure("No scene matched '\(query)'.")
            }
            return sceneResponse(scene, backend: backend)
        case .deleteScene:
            guard let query = sceneQuery(request) else {
                return .failure("Scene name or id is required.")
            }
            guard backend.deleteScene(query) else {
                return .failure("No scene matched '\(query)'.")
            }
            return .success(scenes: backend.scenes().map { ControlSceneDTO(scene: $0, snapshots: backend.snapshots()) })
        case .preset:
            return applyPreset(request, all: all, backend: backend)
        case .get, .setBrightness, .setVolume, .setMuted, .setContrast, .setInput, .setRotation,
             .setPictureInPicture, .configurePictureInPicture, .rename, .matchAll:
            switch resolveDisplay(request.display, in: all) {
            case .failure(let failure):
                return failure
            case .success(let display):
                return applyDisplayAction(request, display: display, backend: backend)
            }
        }
    }

    private static func applyPreset(_ request: ControlRequest, all: [DisplaySnapshot], backend: ControlBackend) -> ControlResponse {
        let query = request.display?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var target: DisplaySnapshot?
        if !query.isEmpty, query.lowercased() != "all" {
            switch resolveDisplay(request.display, in: all) {
            case .failure(let failure):
                return failure
            case .success(let display):
                target = display
            }
        }
        guard let raw = request.preset, let preset = BrightnessPreset(rawValue: raw.lowercased()) else {
            return .failure("Preset must be night, desk, or max.")
        }
        backend.applyPreset(preset, target?.id.persistentKey)
        return summary(displayKey: target?.id.persistentKey, backend: backend)
    }

    private static func applyDisplayAction(_ request: ControlRequest, display: DisplaySnapshot, backend: ControlBackend) -> ControlResponse {
        let key = display.id.persistentKey
        switch request.action {
        case .get:
            return .success(displays: [ControlDisplayDTO(snapshot: display)])
        case .setBrightness:
            guard let value = request.value else { return .failure("Brightness value 0...1 is required.") }
            guard display.brightness.showsBrightnessSlider else {
                return .failure("\(display.name) has no brightness control.")
            }
            backend.setBrightness(key, value)
        case .setVolume:
            guard let value = request.value else { return .failure("Volume value 0...1 is required.") }
            guard display.volume.supportsVolume else {
                return .failure("\(display.name) has no volume control.")
            }
            backend.setVolume(key, value)
        case .setMuted:
            guard let muted = request.muted else { return .failure("muted true/false is required.") }
            guard display.volume.supportsMute || display.volume.supportsVolume else {
                return .failure("\(display.name) has no mute control.")
            }
            backend.setMuted(key, muted)
        case .setContrast:
            guard let value = request.value else { return .failure("Contrast value 0...1 is required.") }
            guard display.contrast.supportsContrast else {
                return .failure("\(display.name) has no contrast control.")
            }
            backend.setContrast(key, value)
        case .setInput:
            guard let raw = request.input, let source = DisplayInputSource.from(query: raw) else {
                return .failure("Input must be hdmi1, hdmi2, dp, dp2, usbc, or a VCP 0x60 code.")
            }
            guard display.input.supportsInputSelect else {
                return .failure("\(display.name) has no DDC input select.")
            }
            backend.setInput(key, source)
        case .setRotation:
            guard let raw = request.rotation, let rotation = DisplayRotation.from(query: raw) else {
                return .failure("Rotation must be 0, 90, 180, 270, landscape, or portrait.")
            }
            guard !display.isBuiltin, display.rotation.supportsRotation else {
                return .failure("\(display.name) cannot rotate.")
            }
            backend.setRotation(key, rotation)
        case .setPictureInPicture:
            guard let enabled = request.pictureInPicture else {
                return .failure("pictureInPicture true/false is required.")
            }
            guard PictureInPictureLayout.supports(kind: display.kind) else {
                return .failure("\(display.name) cannot open Picture in Picture.")
            }
            guard backend.setPictureInPicture(key, enabled) else {
                return .failure("Could not update Picture in Picture for \(display.name).")
            }
        case .configurePictureInPicture:
            guard PictureInPictureLayout.supports(kind: display.kind) else {
                return .failure("\(display.name) cannot open Picture in Picture.")
            }
            let mode: PictureInPictureMode?
            if let raw = request.pictureInPictureMode {
                guard let parsed = PictureInPictureMode.from(query: raw) else {
                    return .failure("Picture in Picture mode must be display, window, or magnifier.")
                }
                mode = parsed
            } else {
                mode = nil
            }
            let window: PictureInPictureWindowIdentity?
            if let raw = request.pictureInPictureWindow?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                window = PictureInPictureWindowIdentity(
                    bundleIdentifier: request.pictureInPictureBundle ?? "",
                    title: raw,
                    ownerName: raw
                )
            } else {
                window = nil
            }
            if mode == .window, window == nil {
                return .failure("Window name or bundle is required for window Picture in Picture.")
            }
            if request.pictureInPicture == true {
                _ = backend.setPictureInPicture(key, true)
            }
            guard backend.configurePictureInPicture(
                key,
                mode,
                request.pictureInPictureMirrored,
                window,
                request.pictureInPictureZoom
            ) else {
                return .failure("Could not configure Picture in Picture for \(display.name).")
            }
        case .rename:
            guard backend.rename(key, request.name) else {
                return .failure("Could not rename \(display.name).")
            }
        case .matchAll:
            backend.matchAll(key)
        case .list, .dump, .listScenes, .setPictureInPictureWall, .preset,
             .applyScene, .saveScene, .renameScene, .deleteScene:
            return .failure("unreachable")
        }
        return summary(displayKey: key, backend: backend)
    }

    private enum DisplayResolution {
        case success(DisplaySnapshot)
        case failure(ControlResponse)
    }

    private static func resolveDisplay(_ rawQuery: String?, in all: [DisplaySnapshot]) -> DisplayResolution {
        let query = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return .failure(.failure("Display query required. Use a name, persistentKey, main, builtin, or external."))
        }
        guard let match = DisplayQuery.resolve(query, in: all) else {
            return .failure(.failure("No display matched '\(query)'."))
        }
        return .success(match)
    }

    private static func summary(displayKey: String?, backend: ControlBackend) -> ControlResponse {
        let latest = backend.snapshots()
        let wall = backend.isPictureInPictureWallOpen()
        if let displayKey, let current = latest.first(where: { $0.id.persistentKey == displayKey }) {
            return ControlResponse(ok: true, displays: [ControlDisplayDTO(snapshot: current)], pictureInPictureWall: wall)
        }
        return ControlResponse(ok: true, displays: latest.map(ControlDisplayDTO.init(snapshot:)), pictureInPictureWall: wall)
    }

    private static func sceneQuery(_ request: ControlRequest) -> String? {
        let raw = request.scene ?? request.name ?? request.display
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sceneResponse(_ scene: DisplayScene, backend: ControlBackend) -> ControlResponse {
        let snapshots = backend.snapshots()
        return .success(
            displays: snapshots.map(ControlDisplayDTO.init(snapshot:)),
            scenes: [ControlSceneDTO(scene: scene, snapshots: snapshots)]
        )
    }
}
