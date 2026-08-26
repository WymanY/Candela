import Foundation

/// macOS 26 names this pane Menu Bar. The System Settings extension identifier
/// is still Control Center. Unknown `x-apple.systempreferences` identifiers
/// still open System Settings, usually on General, so they must not be listed.
public enum MenuBarSettings {
    public static let paneURLStrings = [
        "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
        "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?com.apple.controlcenter.settings",
    ]

    public static func firstOpenableURL(opening: (URL) -> Bool) -> URL? {
        for raw in paneURLStrings {
            guard let url = URL(string: raw) else { continue }
            if opening(url) {
                return url
            }
        }
        return nil
    }
}
