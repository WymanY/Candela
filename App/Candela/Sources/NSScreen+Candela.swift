import AppKit
import CoreGraphics

extension NSScreen {
    var candelaDisplayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    static func candelaScreen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.candelaDisplayID == displayID }
    }

    /// Fallback only when IOKit / CoreDisplay left the product name empty.
    static func candelaLocalizedName(for displayID: CGDirectDisplayID) -> String? {
        guard let name = candelaScreen(for: displayID)?.localizedName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
