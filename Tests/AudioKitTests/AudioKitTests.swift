import AudioKit
import DisplayCore
import TestSupport
import XCTest

final class AudioKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(AudioKitModule.version.isEmpty)
        let snapshot = FakeSnapshots.builtIn()
        XCTAssertNil(AudioMatching.match(display: snapshot, overrideUID: nil, devices: []))
    }
}
