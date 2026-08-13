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

    public init(
        schemaVersion: Int = 1,
        launchAtLogin: Bool = false,
        restoreOnReconnect: Bool = true,
        softwareDimmingEnabled: Bool = true,
        allowDimToBlack: Bool = false,
        showPercentText: Bool = true,
        hasShownGammaInterferenceAlert: Bool = false,
        hasOpenedPanelOnce: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.launchAtLogin = launchAtLogin
        self.restoreOnReconnect = restoreOnReconnect
        self.softwareDimmingEnabled = softwareDimmingEnabled
        self.allowDimToBlack = allowDimToBlack
        self.showPercentText = showPercentText
        self.hasShownGammaInterferenceAlert = hasShownGammaInterferenceAlert
        self.hasOpenedPanelOnce = hasOpenedPanelOnce
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
    public var brightnessBackend: BrightnessBackendKind?
    public var forceDDC: Bool
    public var softwareDimmingDisabled: Bool
    public var audioDeviceUIDOverride: String?
    public var useDDCMute: Bool
    public var customName: String?

    public init(
        persistentKey: String,
        portLocation: String? = nil,
        portSuffix: String? = nil,
        lastBrightness: Double? = nil,
        lastVolume: Double? = nil,
        lastMuted: Bool? = nil,
        brightnessBackend: BrightnessBackendKind? = nil,
        forceDDC: Bool = false,
        softwareDimmingDisabled: Bool = false,
        audioDeviceUIDOverride: String? = nil,
        useDDCMute: Bool = false,
        customName: String? = nil
    ) {
        self.persistentKey = persistentKey
        self.portLocation = portLocation
        self.portSuffix = portSuffix
        self.lastBrightness = lastBrightness
        self.lastVolume = lastVolume
        self.lastMuted = lastMuted
        self.brightnessBackend = brightnessBackend
        self.forceDDC = forceDDC
        self.softwareDimmingDisabled = softwareDimmingDisabled
        self.audioDeviceUIDOverride = audioDeviceUIDOverride
        self.useDDCMute = useDDCMute
        self.customName = customName
    }
}
