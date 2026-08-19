#if CANDELA_MAS
import CandelaPublicIO
#else
import CandelaPrivateIO
#endif
import CoreGraphics
import DisplayCore
import Foundation

/// Applies 0/90/180/270 rotation.
/// Direct builds use MonitorPanel.MPDisplay; the Mac App Store flavor uses public IOKit.
public enum DisplayRotationControl {
    public static func current(for displayID: CGDirectDisplayID) -> DisplayRotation {
        #if CANDELA_MAS
        DisplayRotation.from(degrees: Double(CandelaPublicDisplayGetOrientation(displayID)))
        #else
        DisplayRotation.from(degrees: Double(CandelaDisplayGetOrientation(displayID)))
        #endif
    }

    public static func canRotate(_ displayID: CGDirectDisplayID) -> Bool {
        guard displayID != 0 else { return false }
        guard CGDisplayIsBuiltin(displayID) == 0 else { return false }
        #if CANDELA_MAS
        return CandelaPublicDisplayCanChangeOrientation(displayID)
        #else
        return CandelaDisplayCanChangeOrientation(displayID)
        #endif
    }

    @discardableResult
    public static func set(_ rotation: DisplayRotation, displayID: CGDirectDisplayID) -> Bool {
        guard displayID != 0 else { return false }
        guard canRotate(displayID) else { return false }
        if current(for: displayID) == rotation {
            return true
        }
        // Return as soon as the display stack accepts the request. Waiting on
        // CGDisplayRotation here blocks the main run loop and the reconfigure
        // cannot finish, so the panel appears to snap back.
        #if CANDELA_MAS
        return CandelaPublicDisplaySetOrientation(displayID, Int32(rotation.degrees))
        #else
        return CandelaDisplaySetOrientation(displayID, Int32(rotation.degrees))
        #endif
    }

    static func probeOption(for rotation: DisplayRotation) -> UInt32 {
        // Kept for the existing encoding test; MonitorPanel uses degrees directly.
        let setTransform: UInt32 = 0x00000400
        return setTransform | (scaleRotate(for: rotation) << 16)
    }

    static func scaleRotate(for rotation: DisplayRotation) -> UInt32 {
        switch rotation {
        case .deg0: return 0x00000000
        case .deg90: return 0x00000030
        case .deg180: return 0x00000060
        case .deg270: return 0x00000050
        }
    }
}
