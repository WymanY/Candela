import XCTest
@testable import DisplayCore
import TestSupport

final class CandelaTextTests: XCTestCase {
    override func tearDown() {
        CandelaText.locale = .autoupdatingCurrent
        super.tearDown()
    }

    func testExplicitEnglishAndChineseLocales() {
        XCTAssertEqual(CandelaText.locale(forPreferredLanguage: "en").identifier, "en")
        XCTAssertEqual(CandelaText.locale(forPreferredLanguage: "zh-Hans").identifier, "zh-Hans")
    }

    func testSystemPreferenceMapsToSupportedLocale() {
        let locale = CandelaText.locale(forPreferredLanguage: "")
        XCTAssertTrue(["en", "zh-Hans"].contains(locale.identifier))
    }

    func testBuiltInTitleFollowsRuntimeLocale() {
        CandelaText.applyPreferredLanguage("en")
        XCTAssertEqual(DisplayPresentation.connectionTitle(for: FakeSnapshots.builtIn()), "Built-in")

        CandelaText.applyPreferredLanguage("zh-Hans")
        XCTAssertEqual(DisplayPresentation.connectionTitle(for: FakeSnapshots.builtIn()), "内置")
    }

    func testUntitledSceneFollowsRuntimeLocale() {
        let scene = DisplayScene(name: "  ", targets: [])
        CandelaText.applyPreferredLanguage("en")
        XCTAssertEqual(scene.displayName, "Untitled Scene")
        CandelaText.applyPreferredLanguage("zh-Hans")
        XCTAssertEqual(scene.displayName, "未命名场景")
    }

    func testFormattedBatteryCopyFollowsRuntimeLocale() {
        CandelaText.applyPreferredLanguage("en")
        XCTAssertEqual(PowerStatusPresentation.remainingTitle(for: PowerStatus(source: .battery, isPresent: true, percent: 37, minutesToEmpty: 148)), "2h 28m left")
        CandelaText.applyPreferredLanguage("zh-Hans")
        XCTAssertEqual(PowerStatusPresentation.remainingTitle(for: PowerStatus(source: .battery, isPresent: true, percent: 37, minutesToEmpty: 148)), "剩余 2 小时 28 分钟")
    }
}
