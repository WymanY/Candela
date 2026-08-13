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

    public init(
        id: DisplayIdentity,
        sessionDisplayID: CGDirectDisplayID,
        name: String,
        kind: DisplayKind,
        isMain: Bool,
        isBuiltin: Bool,
        connection: ConnectionKind,
        brightness: BrightnessCapabilities,
        volume: VolumeCapabilities
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
    }
}
