import CoreGraphics
import Foundation

/// Reuses `PrivateSymbols` so CoreDisplay is `dlsym`'d once.
enum CoreDisplayInfo {
    static func dictionary(for displayID: CGDirectDisplayID) -> [String: Any]? {
        #if CANDELA_MAS
        _ = displayID
        return nil
        #else
        guard let create = PrivateSymbols.coreDisplayCreateInfoDictionary,
              let unmanaged = create(displayID)
        else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? [String: Any]
        #endif
    }
}
