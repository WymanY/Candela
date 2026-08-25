import Foundation

public enum ScreenRecordingSettings {
    public static let paneURLStrings = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
        "x-apple.systempreferences:",
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
