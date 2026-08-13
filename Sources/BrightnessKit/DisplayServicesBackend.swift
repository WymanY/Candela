import CoreGraphics
import Foundation

/// DisplayServices get/set via `dlsym` only. Return `0` is success.
enum DisplayServicesBackend {
    static var isAvailable: Bool {
        PrivateSymbols.displayServicesAvailable
    }

    /// Probe success: Get returns 0 and brightness ≥ 0.
    static func get(_ displayID: CGDirectDisplayID) -> Float? {
        guard let get = PrivateSymbols.displayServicesGetBrightness else { return nil }
        var value: Float = -1
        let status = get(displayID, &value)
        guard status == 0, value >= 0 else { return nil }
        return value
    }

    static func set(_ displayID: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let set = PrivateSymbols.displayServicesSetBrightness else { return false }
        return set(displayID, value) == 0
    }
}
