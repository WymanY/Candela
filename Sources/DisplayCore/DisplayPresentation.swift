import Foundation

/// Human-readable facts for Settings and agent dumps. No I/O.
public enum DisplayPresentation {
    public static func connectionTitle(for snapshot: DisplaySnapshot) -> String {
        switch snapshot.kind {
        case .builtIn:
            return localized("Built-in")
        case .appleExternal:
            return connectionKindTitle(snapshot.connection, fallback: localized("Apple"))
        case .virtualUnsupported:
            return localized("Unsupported")
        case .genericExternal:
            return connectionKindTitle(snapshot.connection, fallback: localized("External"))
        }
    }

    public static func connectionKindTitle(_ connection: ConnectionKind, fallback: String) -> String {
        switch connection {
        case .builtIn: return localized("Built-in")
        case .hdmi: return localized("HDMI")
        case .displayPort: return localized("DisplayPort")
        case .thunderbolt: return localized("Thunderbolt")
        case .usb: return localized("USB-C")
        case .unknown: return fallback
        }
    }

    public static func modeTitle(for snapshot: DisplaySnapshot) -> String? {
        guard snapshot.hasMode else { return nil }
        return "\(snapshot.pixelWidth) × \(snapshot.pixelHeight)"
    }

    public static func refreshTitle(for snapshot: DisplaySnapshot) -> String? {
        guard snapshot.refreshHz > 0.5 else { return nil }
        let rounded = snapshot.refreshHz.rounded()
        if abs(snapshot.refreshHz - rounded) < 0.05 {
            return "\(Int(rounded)) Hz"
        }
        return String(format: "%.2f Hz", snapshot.refreshHz)
    }

    public static func rotationTitle(for snapshot: DisplaySnapshot) -> String {
        "\(snapshot.rotation.current.title) · \(snapshot.rotation.current.orientationTitle)"
    }

    public static func scaleTitle(for snapshot: DisplaySnapshot) -> String? {
        guard snapshot.hasMode, snapshot.scaleFactor > 0.05 else { return nil }
        let value = snapshot.scaleFactor
        if abs(value - value.rounded()) < 0.05 {
            return "\(Int(value.rounded()))×"
        }
        return String(format: "%.1f×", value)
    }

    public static func brightnessBackendTitle(for snapshot: DisplaySnapshot) -> String {
        switch snapshot.brightness.backend {
        case .displayServices: return localized("DisplayServices")
        case .ddc: return localized("DDC")
        case .softwareGamma: return localized("Software")
        case .none:
            return snapshot.brightness.showsBrightnessSlider ? localized("Pending") : localized("None")
        }
    }

    public static func volumeBackendTitle(for snapshot: DisplaySnapshot) -> String {
        switch snapshot.volume.backend {
        case .coreAudio: return localized("Core Audio")
        case .ddc: return localized("DDC")
        case .software: return localized("Software")
        case .none:
            return snapshot.volume.supportsVolume ? localized("Pending") : localized("None")
        }
    }

    public static func vendorTitle(for snapshot: DisplaySnapshot) -> String? {
        let vendorID = snapshot.id.fields.inputs.vendorID
        if let token = AudioMatching.vendorToken(forVendorID: vendorID) {
            return token.capitalized
        }
        if let pnp = AudioMatching.pnpID(from: vendorID) {
            return pnp
        }
        return nil
    }

    public static func identityTitle(for snapshot: DisplaySnapshot) -> String {
        let inputs = snapshot.id.fields.inputs
        return String(format: "0x%04X / 0x%04X", inputs.vendorID, inputs.productID)
    }

    public static func serialTitle(for snapshot: DisplaySnapshot) -> String? {
        let inputs = snapshot.id.fields.inputs
        if let alpha = inputs.alphanumericSerial?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alpha.isEmpty
        {
            return alpha
        }
        if inputs.serial != 0 {
            return String(format: "0x%08X", inputs.serial)
        }
        return nil
    }
}
