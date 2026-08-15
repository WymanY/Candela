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

public struct ContrastCapabilities: Equatable, Sendable {
    public var supportsContrast: Bool
    public var current: Double
    public var ddcMax: UInt16

    public init(supportsContrast: Bool = false, current: Double = 0.5, ddcMax: UInt16 = 0) {
        self.supportsContrast = supportsContrast
        self.current = current
        self.ddcMax = ddcMax
    }

    public static let unsupported = ContrastCapabilities()
}

public enum DisplayInputSource: String, Codable, Sendable, CaseIterable {
    case vga1
    case dvi1
    case displayPort1
    case displayPort2
    case hdmi1
    case hdmi2
    case usbC

    public var code: UInt16 {
        switch self {
        case .vga1: return 0x01
        case .dvi1: return 0x03
        case .displayPort1: return 0x0F
        case .displayPort2: return 0x10
        case .hdmi1: return 0x11
        case .hdmi2: return 0x12
        case .usbC: return 0x1B
        }
    }

    public var title: String {
        switch self {
        case .vga1: return "VGA"
        case .dvi1: return "DVI"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .usbC: return "USB-C"
        }
    }

    public static func from(code: UInt16) -> DisplayInputSource? {
        allCases.first { $0.code == code }
    }

    public static func from(query: String) -> DisplayInputSource? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "vga", "vga1":
            return .vga1
        case "dvi", "dvi1":
            return .dvi1
        case "dp", "displayport", "displayport1", "dp1":
            return .displayPort1
        case "dp2", "displayport2":
            return .displayPort2
        case "hdmi", "hdmi1":
            return .hdmi1
        case "hdmi2":
            return .hdmi2
        case "usbc", "usb-c", "usb_c", "thunderbolt", "tb":
            return .usbC
        default:
            let hex = trimmed.hasPrefix("0x")
            if let raw = UInt16(hex ? String(trimmed.dropFirst(2)) : trimmed, radix: hex ? 16 : 10) {
                return from(code: raw)
            }
            return allCases.first { $0.rawValue.lowercased() == trimmed }
        }
    }
}

public struct InputCapabilities: Equatable, Sendable {
    public var supportsInputSelect: Bool
    public var currentCode: UInt16?
    public var current: DisplayInputSource?

    public init(
        supportsInputSelect: Bool = false,
        currentCode: UInt16? = nil,
        current: DisplayInputSource? = nil
    ) {
        self.supportsInputSelect = supportsInputSelect
        self.currentCode = currentCode
        self.current = current ?? currentCode.flatMap(DisplayInputSource.from(code:))
    }

    public static let unsupported = InputCapabilities()
}

public enum DisplayRotation: Int, Codable, Sendable, CaseIterable {
    case deg0 = 0
    case deg90 = 90
    case deg180 = 180
    case deg270 = 270

    public var degrees: Int { rawValue }

    public var isPortrait: Bool {
        self == .deg90 || self == .deg270
    }

    public var title: String {
        switch self {
        case .deg0: return "0°"
        case .deg90: return "90°"
        case .deg180: return "180°"
        case .deg270: return "270°"
        }
    }

    public var orientationTitle: String {
        switch self {
        case .deg0: return "Landscape"
        case .deg90: return "Portrait"
        case .deg180: return "Landscape flipped"
        case .deg270: return "Portrait flipped"
        }
    }

    public static func from(degrees: Double) -> DisplayRotation {
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        switch normalized {
        case 45..<135: return .deg90
        case 135..<225: return .deg180
        case 225..<315: return .deg270
        default: return .deg0
        }
    }

    public static func from(query: String) -> DisplayRotation? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "0", "0°", "landscape", "normal":
            return .deg0
        case "90", "90°", "portrait":
            return .deg90
        case "180", "180°", "landscape-flipped", "landscape_flipped", "inverted":
            return .deg180
        case "270", "270°", "portrait-flipped", "portrait_flipped":
            return .deg270
        default:
            if let value = Double(trimmed) {
                return from(degrees: value)
            }
            return nil
        }
    }
}

public struct RotationCapabilities: Equatable, Sendable {
    public var supportsRotation: Bool
    public var current: DisplayRotation

    public init(supportsRotation: Bool = false, current: DisplayRotation = .deg0) {
        self.supportsRotation = supportsRotation
        self.current = current
    }

    public static let unsupported = RotationCapabilities()

    public static func supported(_ current: DisplayRotation = .deg0) -> RotationCapabilities {
        RotationCapabilities(supportsRotation: true, current: current)
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

    public var showsVolumeSlider: Bool {
        supportsVolume
    }
}
