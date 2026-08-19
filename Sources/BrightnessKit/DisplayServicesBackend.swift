import CoreGraphics
import Foundation

/// Hardware brightness get/set. Direct builds use DisplayServices via `dlsym`.
/// MAS builds skip this private-only tier and continue to DDC or software gamma.
enum HardwareBrightnessBackend {
    static var isAvailable: Bool {
        #if CANDELA_MAS
        false
        #else
        PrivateSymbols.displayServicesAvailable
        #endif
    }

    /// Probe success: Get returns 0 and brightness ≥ 0.
    static func get(_ displayID: CGDirectDisplayID) -> Float? {
        #if CANDELA_MAS
        nil
        #else
        guard let get = PrivateSymbols.displayServicesGetBrightness else { return nil }
        var value: Float = -1
        let status = get(displayID, &value)
        guard status == 0, value >= 0 else { return nil }
        return value
        #endif
    }

    static func set(_ displayID: CGDirectDisplayID, _ value: Float) -> Bool {
        #if CANDELA_MAS
        false
        #else
        guard let set = PrivateSymbols.displayServicesSetBrightness else { return false }
        return set(displayID, value) == 0
        #endif
    }
}
