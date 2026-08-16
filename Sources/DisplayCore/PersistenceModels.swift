import Foundation

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var launchAtLogin: Bool
    public var restoreOnReconnect: Bool
    public var softwareDimmingEnabled: Bool
    public var allowDimToBlack: Bool
    public var showPercentText: Bool
    public var hasShownGammaInterferenceAlert: Bool
    public var hasOpenedPanelOnce: Bool
    public var pictureInPictureWall: PictureInPicturePlacement?
    /// Empty string follows the system language. Otherwise a language identifier such as `en` or `zh-Hans`.
    public var preferredLanguage: String

    public init(
        schemaVersion: Int = 1,
        launchAtLogin: Bool = false,
        restoreOnReconnect: Bool = true,
        softwareDimmingEnabled: Bool = true,
        allowDimToBlack: Bool = false,
        showPercentText: Bool = true,
        hasShownGammaInterferenceAlert: Bool = false,
        hasOpenedPanelOnce: Bool = false,
        pictureInPictureWall: PictureInPicturePlacement? = nil,
        preferredLanguage: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.launchAtLogin = launchAtLogin
        self.restoreOnReconnect = restoreOnReconnect
        self.softwareDimmingEnabled = softwareDimmingEnabled
        self.allowDimToBlack = allowDimToBlack
        self.showPercentText = showPercentText
        self.hasShownGammaInterferenceAlert = hasShownGammaInterferenceAlert
        self.hasOpenedPanelOnce = hasOpenedPanelOnce
        self.pictureInPictureWall = pictureInPictureWall
        self.preferredLanguage = preferredLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        restoreOnReconnect = try container.decodeIfPresent(Bool.self, forKey: .restoreOnReconnect) ?? true
        softwareDimmingEnabled = try container.decodeIfPresent(Bool.self, forKey: .softwareDimmingEnabled) ?? true
        allowDimToBlack = try container.decodeIfPresent(Bool.self, forKey: .allowDimToBlack) ?? false
        showPercentText = try container.decodeIfPresent(Bool.self, forKey: .showPercentText) ?? true
        hasShownGammaInterferenceAlert = try container.decodeIfPresent(Bool.self, forKey: .hasShownGammaInterferenceAlert) ?? false
        hasOpenedPanelOnce = try container.decodeIfPresent(Bool.self, forKey: .hasOpenedPanelOnce) ?? false
        pictureInPictureWall = try container.decodeIfPresent(PictureInPicturePlacement.self, forKey: .pictureInPictureWall)
        preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? ""
    }
}

public struct DisplayRecord: Codable, Equatable, Sendable {
    public var persistentKey: String
    /// Diagnostic only. Never a resolve or lookup key.
    public var portLocation: String?
    /// Diagnostic; `"port-<8 hex>"` when the live key is suffixed.
    public var portSuffix: String?
    public var lastBrightness: Double?
    public var lastVolume: Double?
    public var lastMuted: Bool?
    public var lastContrast: Double?
    public var lastInputCode: UInt16?
    public var lastRotationDegrees: Int?
    public var brightnessBackend: BrightnessBackendKind?
    public var forceDDC: Bool
    public var softwareDimmingDisabled: Bool
    public var audioDeviceUIDOverride: String?
    public var useDDCMute: Bool
    public var customName: String?
    public var pictureInPicture: PictureInPicturePlacement?

    public init(
        persistentKey: String,
        portLocation: String? = nil,
        portSuffix: String? = nil,
        lastBrightness: Double? = nil,
        lastVolume: Double? = nil,
        lastMuted: Bool? = nil,
        lastContrast: Double? = nil,
        lastInputCode: UInt16? = nil,
        lastRotationDegrees: Int? = nil,
        brightnessBackend: BrightnessBackendKind? = nil,
        forceDDC: Bool = false,
        softwareDimmingDisabled: Bool = false,
        audioDeviceUIDOverride: String? = nil,
        useDDCMute: Bool = false,
        customName: String? = nil,
        pictureInPicture: PictureInPicturePlacement? = nil
    ) {
        self.persistentKey = persistentKey
        self.portLocation = portLocation
        self.portSuffix = portSuffix
        self.lastBrightness = lastBrightness
        self.lastVolume = lastVolume
        self.lastMuted = lastMuted
        self.lastContrast = lastContrast
        self.lastInputCode = lastInputCode
        self.lastRotationDegrees = lastRotationDegrees
        self.brightnessBackend = brightnessBackend
        self.forceDDC = forceDDC
        self.softwareDimmingDisabled = softwareDimmingDisabled
        self.audioDeviceUIDOverride = audioDeviceUIDOverride
        self.useDDCMute = useDDCMute
        self.customName = customName
        self.pictureInPicture = pictureInPicture
    }
}

public enum BrightnessPreset: String, CaseIterable, Sendable {
    case night
    case desk
    case max

    public var value: Double {
        switch self {
        case .night: return 0.20
        case .desk: return 0.50
        case .max: return 1.0
        }
    }

    public var title: String {
        switch self {
        case .night: return "Night"
        case .desk: return "Desk"
        case .max: return "Max"
        }
    }
}

public enum DisplayNameResolver {
    public static func displayName(hardwareName: String, customName: String?) -> String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? hardwareName : trimmed
    }
}
