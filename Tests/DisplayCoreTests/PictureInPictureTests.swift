import XCTest
@testable import DisplayCore

final class PictureInPictureTests: XCTestCase {
    func testVirtualDisplaysCannotMirror() {
        XCTAssertFalse(PictureInPictureLayout.supports(kind: .virtualUnsupported))
        XCTAssertTrue(PictureInPictureLayout.supports(kind: .builtIn))
        XCTAssertTrue(PictureInPictureLayout.supports(kind: .genericExternal))
    }

    func testContentKeepsAspectAndClampsWidth() {
        let size = PictureInPictureLayout.contentSize(pixelWidth: 3840, pixelHeight: 2160, preferredWidth: 420)
        XCTAssertEqual(size.width, 420, accuracy: 0.001)
        XCTAssertEqual(size.height, 236.25, accuracy: 0.01)

        let narrow = PictureInPictureLayout.contentSize(pixelWidth: 1920, pixelHeight: 1080, preferredWidth: 100)
        XCTAssertEqual(narrow.width, PictureInPictureLayout.minWidth, accuracy: 0.001)

        let wide = PictureInPictureLayout.contentSize(pixelWidth: 1920, pixelHeight: 1080, preferredWidth: 2000)
        XCTAssertEqual(wide.width, PictureInPictureLayout.maxWidth, accuracy: 0.001)
    }

    func testWindowAddsChromeAndPrefersAnotherScreen() {
        let content = CGSize(width: 420, height: 236)
        let window = PictureInPictureLayout.windowSize(forContent: content)
        XCTAssertEqual(window.height, 264, accuracy: 0.001)

        let origin = PictureInPictureLayout.origin(
            windowSize: window,
            sourceDisplayID: 2,
            screens: [
                (id: 2, visible: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                (id: 1, visible: CGRect(x: 1920, y: 0, width: 1512, height: 982)),
            ]
        )
        XCTAssertEqual(origin.x, 1920 + 1512 - window.width - 24, accuracy: 0.001)
        XCTAssertEqual(origin.y, 24, accuracy: 0.001)
    }
}
