import DisplayCore
import Foundation

public enum ControlAction: String, Codable, Sendable {
    case list
    case get
    case setBrightness
    case setVolume
    case setMuted
    case setContrast
    case setInput
    case setRotation
    case setPictureInPicture
    case configurePictureInPicture
    case setPictureInPictureWall
    case rename
    case preset
    case matchAll
    case setBuiltInMirror
    case listScenes
    case applyScene
    case saveScene
    case renameScene
    case deleteScene
    case dump
}

public struct ControlRequest: Codable, Equatable, Sendable {
    public var action: ControlAction
    public var display: String?
    public var value: Double?
    public var muted: Bool?
    public var input: String?
    public var rotation: String?
    public var pictureInPicture: Bool?
    public var pictureInPictureMode: String?
    public var pictureInPictureMirrored: Bool?
    public var pictureInPictureWindow: String?
    public var pictureInPictureBundle: String?
    public var pictureInPictureZoom: Double?
    public var name: String?
    public var preset: String?
    public var scene: String?
    public var redact: Bool?

    public init(
        action: ControlAction,
        display: String? = nil,
        value: Double? = nil,
        muted: Bool? = nil,
        input: String? = nil,
        rotation: String? = nil,
        pictureInPicture: Bool? = nil,
        pictureInPictureMode: String? = nil,
        pictureInPictureMirrored: Bool? = nil,
        pictureInPictureWindow: String? = nil,
        pictureInPictureBundle: String? = nil,
        pictureInPictureZoom: Double? = nil,
        name: String? = nil,
        preset: String? = nil,
        scene: String? = nil,
        redact: Bool? = nil
    ) {
        self.action = action
        self.display = display
        self.value = value
        self.muted = muted
        self.input = input
        self.rotation = rotation
        self.pictureInPicture = pictureInPicture
        self.pictureInPictureMode = pictureInPictureMode
        self.pictureInPictureMirrored = pictureInPictureMirrored
        self.pictureInPictureWindow = pictureInPictureWindow
        self.pictureInPictureBundle = pictureInPictureBundle
        self.pictureInPictureZoom = pictureInPictureZoom
        self.name = name
        self.preset = preset
        self.scene = scene
        self.redact = redact
    }
}

public struct ControlDisplayDTO: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var hardwareName: String
    public var kind: String
    public var connection: String
    public var isMain: Bool
    public var isBuiltin: Bool
    public var brightness: Double?
    public var brightnessBackend: String?
    public var supportsBrightness: Bool
    public var volume: Double?
    public var muted: Bool?
    public var supportsVolume: Bool
    public var volumeBackend: String?
    public var contrast: Double?
    public var supportsContrast: Bool
    public var input: String?
    public var supportsInput: Bool
    public var rotation: String?
    public var supportsRotation: Bool
    public var supportsPictureInPicture: Bool
    public var pictureInPicture: Bool
    public var pictureInPictureMode: String?
    public var pictureInPictureMirrored: Bool?
    public var pictureInPictureWindow: String?
    public var pictureInPictureWall: Bool?
    public var isMirroringBuiltIn: Bool
    public var canMirrorBuiltIn: Bool
    public var resolution: String?
    public var refreshHz: Double?
    public var scale: Double?

    public init(snapshot: DisplaySnapshot) {
        key = snapshot.id.persistentKey
        name = snapshot.name
        hardwareName = snapshot.hardwareName
        kind = snapshot.kind.rawValue
        connection = snapshot.connection.rawValue
        isMain = snapshot.isMain
        isBuiltin = snapshot.isBuiltin
        supportsBrightness = snapshot.brightness.showsBrightnessSlider
        brightness = supportsBrightness ? snapshot.brightness.current : nil
        brightnessBackend = snapshot.brightness.backend.rawValue
        supportsVolume = snapshot.volume.supportsVolume
        volume = supportsVolume ? snapshot.volume.current : nil
        muted = snapshot.volume.supportsMute ? snapshot.volume.isMuted : nil
        volumeBackend = supportsVolume ? snapshot.volume.backend.rawValue : nil
        supportsContrast = snapshot.contrast.supportsContrast
        contrast = supportsContrast ? snapshot.contrast.current : nil
        supportsInput = snapshot.input.supportsInputSelect
        input = snapshot.input.current?.rawValue ?? snapshot.input.currentCode.map { String(format: "0x%02X", $0) }
        supportsRotation = snapshot.rotation.supportsRotation
        rotation = supportsRotation ? snapshot.rotation.current.rawValue.description : nil
        supportsPictureInPicture = PictureInPictureLayout.supports(kind: snapshot.kind)
        pictureInPicture = snapshot.pictureInPictureActive
        pictureInPictureMode = supportsPictureInPicture ? snapshot.pictureInPictureMode.rawValue : nil
        pictureInPictureMirrored = supportsPictureInPicture ? snapshot.pictureInPictureMirrored : nil
        pictureInPictureWindow = snapshot.pictureInPictureWindow?.displayTitle
        pictureInPictureWall = nil
        isMirroringBuiltIn = snapshot.isMirroringBuiltIn
        canMirrorBuiltIn = snapshot.canMirrorBuiltIn
        resolution = DisplayPresentation.modeTitle(for: snapshot)
        refreshHz = snapshot.refreshHz > 0.5 ? snapshot.refreshHz : nil
        scale = snapshot.hasMode ? snapshot.scaleFactor : nil
    }
}

public struct ControlSceneDTO: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var displayCount: Int
    public var missingCount: Int
    public var active: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(scene: DisplayScene, snapshots: [DisplaySnapshot] = []) {
        id = scene.id
        name = scene.displayName
        displayCount = scene.targets.count
        missingCount = DisplayScenePlanner.plan(scene: scene, snapshots: snapshots).missingKeys.count
        active = DisplayScenePlanner.matches(scene, snapshots: snapshots)
        createdAt = scene.createdAt
        updatedAt = scene.updatedAt
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    public var displays: [ControlDisplayDTO]?
    public var scenes: [ControlSceneDTO]?
    public var dump: String?
    public var pictureInPictureWall: Bool?
    public var isMirroringBuiltIn: Bool?

    public init(
        ok: Bool,
        error: String? = nil,
        displays: [ControlDisplayDTO]? = nil,
        scenes: [ControlSceneDTO]? = nil,
        dump: String? = nil,
        pictureInPictureWall: Bool? = nil,
        isMirroringBuiltIn: Bool? = nil
    ) {
        self.ok = ok
        self.error = error
        self.displays = displays
        self.scenes = scenes
        self.dump = dump
        self.pictureInPictureWall = pictureInPictureWall
        self.isMirroringBuiltIn = isMirroringBuiltIn
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message)
    }

    public static func success(displays: [ControlDisplayDTO], scenes: [ControlSceneDTO]? = nil) -> ControlResponse {
        ControlResponse(ok: true, displays: displays, scenes: scenes)
    }

    public static func success(scenes: [ControlSceneDTO], displays: [ControlDisplayDTO]? = nil) -> ControlResponse {
        ControlResponse(ok: true, displays: displays, scenes: scenes)
    }
}

public enum ControlSocket {
    public static var defaultPath: String {
        let root: URL
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = support.appendingPathComponent("Candela", isDirectory: true)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Candela", isDirectory: true)
        }
        return root.appendingPathComponent("control.sock").path
    }
}
