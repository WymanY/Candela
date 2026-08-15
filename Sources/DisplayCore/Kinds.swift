import Foundation

public enum DisplayKind: String, Codable, Sendable {
    case builtIn
    case appleExternal
    case genericExternal
    case virtualUnsupported
}

public enum ConnectionKind: String, Codable, Sendable {
    case builtIn
    case displayPort
    case hdmi
    case thunderbolt
    case usb
    case unknown
}

public enum BrightnessBackendKind: String, Codable, Sendable {
    case displayServices
    case ddc
    case softwareGamma
    case none
}

public enum VolumeBackendKind: String, Codable, Sendable {
    case coreAudio
    case ddc
    case software
    case none
}
