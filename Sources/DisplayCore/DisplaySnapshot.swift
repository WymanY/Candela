import CoreGraphics
import Foundation

public struct DisplaySnapshot: Identifiable, Equatable, Sendable {
    public var id: DisplayIdentity
    public var sessionDisplayID: CGDirectDisplayID
    public var name: String
    public var kind: DisplayKind
    public var isMain: Bool
    public var isBuiltin: Bool
    public var connection: ConnectionKind
    public var brightness: BrightnessCapabilities
    public var volume: VolumeCapabilities
    public var contrast: ContrastCapabilities
    public var input: InputCapabilities
    public var rotation: RotationCapabilities
    public var hardwareName: String
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    public var refreshHz: Double
    public var scaleFactor: Double
    public var pictureInPictureActive: Bool
    public var pictureInPictureMode: PictureInPictureMode
    public var pictureInPictureMirrored: Bool
    public var pictureInPictureWindow: PictureInPictureWindowIdentity?
    public var isMirroringBuiltIn: Bool
    public var canMirrorBuiltIn: Bool

    public init(
        id: DisplayIdentity,
        sessionDisplayID: CGDirectDisplayID,
        name: String,
        kind: DisplayKind,
        isMain: Bool,
        isBuiltin: Bool,
        connection: ConnectionKind,
        brightness: BrightnessCapabilities,
        volume: VolumeCapabilities,
        contrast: ContrastCapabilities = .unsupported,
        input: InputCapabilities = .unsupported,
        rotation: RotationCapabilities = .unsupported,
        hardwareName: String? = nil,
        pixelWidth: UInt32 = 0,
        pixelHeight: UInt32 = 0,
        refreshHz: Double = 0,
        scaleFactor: Double = 1,
        pictureInPictureActive: Bool = false,
        pictureInPictureMode: PictureInPictureMode = .display,
        pictureInPictureMirrored: Bool = false,
        pictureInPictureWindow: PictureInPictureWindowIdentity? = nil,
        isMirroringBuiltIn: Bool = false,
        canMirrorBuiltIn: Bool = false
    ) {
        self.id = id
        self.sessionDisplayID = sessionDisplayID
        self.name = name
        self.kind = kind
        self.isMain = isMain
        self.isBuiltin = isBuiltin
        self.connection = connection
        self.brightness = brightness
        self.volume = volume
        self.contrast = contrast
        self.input = input
        self.rotation = rotation
        self.hardwareName = hardwareName ?? name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.scaleFactor = scaleFactor
        self.pictureInPictureActive = pictureInPictureActive
        self.pictureInPictureMode = pictureInPictureMode
        self.pictureInPictureMirrored = pictureInPictureMirrored
        self.pictureInPictureWindow = pictureInPictureWindow
        self.isMirroringBuiltIn = isMirroringBuiltIn
        self.canMirrorBuiltIn = canMirrorBuiltIn
    }

    public var displayName: String { name }

    public var hasMode: Bool {
        pixelWidth > 0 && pixelHeight > 0
    }
}
