import XCTest
@testable import DisplayCore

final class PictureInPictureTests: XCTestCase {
    func testVirtualDisplaysCannotMirror() {
        XCTAssertFalse(PictureInPictureLayout.supports(kind: .virtualUnsupported))
        XCTAssertTrue(PictureInPictureLayout.supports(kind: .builtIn))
        XCTAssertTrue(PictureInPictureLayout.supports(kind: .genericExternal))
    }

    func testContentKeepsAspectAndClampsWidth() {
        let size = PictureInPictureLayout.contentSize(pixelWidth: 3840, pixelHeight: 2160, preferredWidth: 640)
        XCTAssertEqual(size.width, 640, accuracy: 0.001)
        XCTAssertEqual(size.height, 360, accuracy: 0.01)

        let narrow = PictureInPictureLayout.contentSize(pixelWidth: 1920, pixelHeight: 1080, preferredWidth: 100)
        XCTAssertEqual(narrow.width, PictureInPictureLayout.minWidth, accuracy: 0.001)

        let wide = PictureInPictureLayout.contentSize(pixelWidth: 1920, pixelHeight: 1080, preferredWidth: 2000)
        XCTAssertEqual(wide.width, PictureInPictureLayout.maxWidth, accuracy: 0.001)
    }

    func testWindowAddsChromeAndPrefersAnotherScreen() {
        let content = CGSize(width: 420, height: 236)
        let window = PictureInPictureLayout.windowSize(forContent: content)
        XCTAssertEqual(window.height, content.height + PictureInPictureLayout.chromeHeight, accuracy: 0.001)

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

    func testCaptureUsesSourcePixels() {
        let fourK = PictureInPictureLayout.captureSize(pixelWidth: 3840, pixelHeight: 2160)
        XCTAssertEqual(fourK.width, 3840)
        XCTAssertEqual(fourK.height, 2160)

        let missing = PictureInPictureLayout.captureSize(pixelWidth: 0, pixelHeight: 0)
        XCTAssertEqual(missing.width, PictureInPictureLayout.minimumCaptureWidth)
        XCTAssertEqual(missing.height, PictureInPictureLayout.minimumCaptureHeight)
    }

    func testOpacityClampsAndPinnedCornersSnap() {
        XCTAssertEqual(PictureInPictureLayout.clampedOpacity(0.01), 0.25, accuracy: 0.0001)
        XCTAssertEqual(PictureInPictureLayout.clampedOpacity(1.4), 1, accuracy: 0.0001)

        let visible = CGRect(x: 1920, y: 0, width: 1512, height: 982)
        let size = CGSize(width: 420, height: 264)
        let topLeft = PictureInPictureLayout.snapOrigin(windowSize: size, corner: .topLeft, visible: visible)
        XCTAssertEqual(topLeft.x, 1944, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 982 - 264 - 24, accuracy: 0.001)

        let screens: [(id: UInt32, visible: CGRect)] = [
            (id: 2, visible: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            (id: 1, visible: CGRect(x: 1920, y: 0, width: 1512, height: 982)),
        ]
        let pinned = PictureInPictureLayout.windowFrame(
            windowSize: size,
            sourceDisplayID: 2,
            screens: screens,
            placement: PictureInPicturePlacement(corner: .topRight, hostDisplayID: 1)
        )
        XCTAssertEqual(pinned.origin.x, 1920 + 1512 - size.width - 24, accuracy: 0.001)
        XCTAssertEqual(pinned.origin.y, 982 - size.height - 24, accuracy: 0.001)
    }

    func testSavedFrameRestoresOnTheSameScreenAndClamps() {
        let screens: [(id: UInt32, visible: CGRect)] = [
            (id: 2, visible: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            (id: 1, visible: CGRect(x: 1920, y: 0, width: 1512, height: 982)),
        ]
        let saved = PictureInPictureFrame(x: 2100, y: 120, width: 480, height: 300)
        let frame = PictureInPictureLayout.windowFrame(
            windowSize: CGSize(width: 480, height: 300),
            sourceDisplayID: 2,
            screens: screens,
            placement: PictureInPicturePlacement(frame: saved)
        )
        XCTAssertEqual(frame.origin.x, 2100, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 120, accuracy: 0.001)

        let overflow = PictureInPictureLayout.windowFrame(
            windowSize: CGSize(width: 480, height: 300),
            sourceDisplayID: 2,
            screens: screens,
            placement: PictureInPicturePlacement(frame: PictureInPictureFrame(x: 3400, y: 900, width: 480, height: 300))
        )
        XCTAssertEqual(overflow.maxX, 1920 + 1512, accuracy: 0.001)
        XCTAssertEqual(overflow.maxY, 982, accuracy: 0.001)
    }

    func testDraggingOffAPinnedCornerUnpins() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let size = CGSize(width: 400, height: 250)
        let pinned = CGRect(origin: PictureInPictureLayout.snapOrigin(windowSize: size, corner: .bottomRight, visible: visible), size: size)
        XCTAssertFalse(PictureInPictureLayout.movedOffPinnedCorner(frame: pinned, corner: .bottomRight, visible: visible))

        var dragged = pinned
        dragged.origin.x -= 40
        XCTAssertTrue(PictureInPictureLayout.movedOffPinnedCorner(frame: dragged, corner: .bottomRight, visible: visible))
    }

    func testScrollWheelZoomsAndKeepsPinnedCorner() {
        XCTAssertEqual(PictureInPictureLayout.zoomFactor(deltaY: 1, precise: false), 1.08, accuracy: 0.0001)
        XCTAssertEqual(PictureInPictureLayout.zoomFactor(deltaY: -1, precise: false), 1 / 1.08, accuracy: 0.0001)
        XCTAssertEqual(PictureInPictureLayout.zoomFactor(deltaY: 25, precise: true), 1.10, accuracy: 0.0001)

        let current = CGRect(x: 100, y: 80, width: 400, height: 257)
        let zoomed = PictureInPictureLayout.zoomedFrame(
            current: current,
            factor: 1.08,
            aspect: 400 / 225
        )
        XCTAssertEqual(zoomed.width, 432, accuracy: 0.001)
        XCTAssertEqual(zoomed.height, 432 / (400 / 225) + PictureInPictureLayout.chromeHeight, accuracy: 0.001)
        XCTAssertEqual(zoomed.origin.x, 84, accuracy: 0.001)
        XCTAssertEqual(zoomed.origin.y, 80 + (257 - zoomed.height) / 2, accuracy: 0.001)

        let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pinned = CGRect(
            origin: PictureInPictureLayout.snapOrigin(windowSize: current.size, corner: .bottomRight, visible: visible),
            size: current.size
        )
        let grown = PictureInPictureLayout.zoomedFrame(
            current: pinned,
            factor: 1.08,
            aspect: 400 / 225,
            corner: .bottomRight,
            visible: visible
        )
        XCTAssertEqual(grown.maxX, visible.maxX - PictureInPictureLayout.margin, accuracy: 0.001)
        XCTAssertEqual(grown.minY, visible.minY + PictureInPictureLayout.margin, accuracy: 0.001)
        XCTAssertGreaterThan(grown.width, pinned.width)
    }

    func testZoomStopsAtWidthLimits() {
        let tiny = PictureInPictureLayout.zoomedFrame(
            current: CGRect(x: 40, y: 40, width: PictureInPictureLayout.minWidth, height: 200),
            factor: 0.5,
            aspect: 16 / 9
        )
        XCTAssertEqual(tiny.width, PictureInPictureLayout.minWidth, accuracy: 0.001)

        let huge = PictureInPictureLayout.zoomedFrame(
            current: CGRect(x: 40, y: 40, width: PictureInPictureLayout.maxWidth, height: 752),
            factor: 1.5,
            aspect: 16 / 9
        )
        XCTAssertEqual(huge.width, PictureInPictureLayout.maxWidth, accuracy: 0.001)
    }

    func testMouseOverWindowDetectsHoverForClickThroughZoom() {
        let frame = CGRect(x: 200, y: 120, width: 400, height: 260)
        XCTAssertTrue(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 250, y: 180), windowFrame: frame))
        XCTAssertFalse(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 20, y: 20), windowFrame: frame))
        XCTAssertTrue(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 198, y: 180), windowFrame: frame, inset: 4))
    }
}
