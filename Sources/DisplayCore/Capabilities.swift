import Foundation

public struct BrightnessCapabilities: Equatable, Sendable {
    public var backend: BrightnessBackendKind
    public var supportsHardware: Bool
    public var supportsSoftware: Bool
    public var range: ClosedRange<Double>
    public var current: Double
    public var ddcMax: UInt16
    public var hdrWashes: Bool
    public var notes: String?

    public init(
        backend: BrightnessBackendKind,
        supportsHardware: Bool,
        supportsSoftware: Bool,
        range: ClosedRange<Double> = 0...1,
        current: Double,
        ddcMax: UInt16 = 0,
        hdrWashes: Bool = false,
        notes: String? = nil
    ) {
        self.backend = backend
        self.supportsHardware = supportsHardware
        self.supportsSoftware = supportsSoftware
        self.range = range
        self.current = current
        self.ddcMax = ddcMax
        self.hdrWashes = hdrWashes
        self.notes = notes
    }

    public var showsBrightnessSlider: Bool {
        supportsHardware || supportsSoftware
    }
}

public struct VolumeCapabilities: Equatable, Sendable {
    public var backend: VolumeBackendKind
    public var supportsVolume: Bool
    public var supportsMute: Bool
    public var range: ClosedRange<Double>
    public var current: Double
    public var isMuted: Bool
    public var audioDeviceUID: String?
    public var notes: String?

    public init(
        backend: VolumeBackendKind,
        supportsVolume: Bool,
        supportsMute: Bool,
        range: ClosedRange<Double> = 0...1,
        current: Double,
        isMuted: Bool = false,
        audioDeviceUID: String? = nil,
        notes: String? = nil
    ) {
        self.backend = backend
        self.supportsVolume = supportsVolume
        self.supportsMute = supportsMute
        self.range = range
        self.current = current
        self.isMuted = isMuted
        self.audioDeviceUID = audioDeviceUID
        self.notes = notes
    }
}
