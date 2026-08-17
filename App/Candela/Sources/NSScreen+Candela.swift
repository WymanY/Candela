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

    static func candelaScreen(containing point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
            ?? screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
    }

    /// Usable point on the screen under the pointer, including menu bar and dock hits.
    static var candelaPointerOnScreen: CGPoint {
        let mouse = NSEvent.mouseLocation
        guard let screen = candelaScreen(containing: mouse) else { return mouse }
        if screen.visibleFrame.contains(mouse) {
            return mouse
        }
        return CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
    }

    /// Fallback only when IOKit / CoreDisplay left the product name empty.
    static func candelaLocalizedName(for displayID: CGDirectDisplayID) -> String? {
        guard let name = candelaScreen(for: displayID)?.localizedName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
