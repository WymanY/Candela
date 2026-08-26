import XCTest
@testable import DisplayCore

final class MenuBarSettingsTests: XCTestCase {
    func testMenuBarSettingsOpensControlCenterPaneFirst() {
        XCTAssertEqual(
            MenuBarSettings.paneURLStrings.first,
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        )
        XCTAssertFalse(
            MenuBarSettings.paneURLStrings.contains {
                $0.contains("MenuBar-Settings") || $0.contains("PrivacySecurity") || $0.hasSuffix("systempreferences:")
            }
        )

        var attempted: [String] = []
        let opened = MenuBarSettings.firstOpenableURL { url in
            attempted.append(url.absoluteString)
            return url.absoluteString.contains("ControlCenter-Settings.extension")
        }
        XCTAssertEqual(opened?.absoluteString, MenuBarSettings.paneURLStrings[0])
        XCTAssertEqual(attempted, [MenuBarSettings.paneURLStrings[0]])

        attempted.removeAll()
        let fallback = MenuBarSettings.firstOpenableURL { url in
            attempted.append(url.absoluteString)
            return url.absoluteString.contains("com.apple.controlcenter.settings")
        }
        XCTAssertEqual(fallback?.absoluteString, MenuBarSettings.paneURLStrings[1])
        XCTAssertEqual(attempted, MenuBarSettings.paneURLStrings)
    }
}
