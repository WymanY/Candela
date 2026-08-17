import XCTest
import TestSupport
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
        XCTAssertEqual(zoomed.height, 257 * 1.08, accuracy: 0.001)
        XCTAssertEqual(zoomed.midX, current.midX, accuracy: 0.001)
        XCTAssertEqual(zoomed.midY, current.midY, accuracy: 0.001)

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

    func testScrollZoomInThenOutReturnsToTheSameFrame() {
        let current = CGRect(x: 180, y: 140, width: 400, height: 305)
        let zoomed = PictureInPictureLayout.zoomedFrame(
            current: current,
            factor: 1.08,
            aspect: 16 / 10
        )
        let restored = PictureInPictureLayout.zoomedFrame(
            current: zoomed,
            factor: 1 / 1.08,
            aspect: 16 / 10
        )
        XCTAssertEqual(zoomed.midX, current.midX, accuracy: 0.001)
        XCTAssertEqual(zoomed.midY, current.midY, accuracy: 0.001)
        XCTAssertEqual(restored.origin.x, current.origin.x, accuracy: 0.001)
        XCTAssertEqual(restored.origin.y, current.origin.y, accuracy: 0.001)
        XCTAssertEqual(restored.midX, current.midX, accuracy: 0.001)
        XCTAssertEqual(restored.midY, current.midY, accuracy: 0.001)
        XCTAssertEqual(restored.width, current.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, current.height, accuracy: 0.001)
    }

    func testCenteredFrameFixesHeightChangedByLayout() {
        let current = CGRect(x: 180, y: 140, width: 400, height: 305)
        let zoomed = PictureInPictureLayout.zoomedFrame(
            current: current,
            factor: 1.08,
            aspect: 16 / 10
        )
        var settled = zoomed
        settled.size.height = current.height * 1.08 + 18
        let recentered = PictureInPictureLayout.centeredFrame(settled, around: current)
        XCTAssertEqual(recentered.midX, current.midX, accuracy: 0.001)
        XCTAssertEqual(recentered.midY, current.midY, accuracy: 0.001)
        XCTAssertEqual(recentered.width, settled.width, accuracy: 0.001)
        XCTAssertEqual(recentered.height, settled.height, accuracy: 0.001)
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

    func testMonitorWallZoomCanExceedSinglePiPWidth() {
        let current = CGRect(x: 80, y: 60, width: 1280, height: 760)
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let grown = PictureInPictureLayout.zoomedFrame(
            current: current,
            factor: 1.5,
            aspect: 16 / 9,
            visible: visible,
            minWidth: PictureInPictureWallLayout.minWidth,
            maxWidth: visible.width
        )
        XCTAssertGreaterThan(grown.width, PictureInPictureLayout.maxWidth)
        XCTAssertEqual(grown.width, 1920, accuracy: 0.001)
        XCTAssertLessThanOrEqual(grown.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(grown.maxY, visible.maxY)
    }

    func testMouseOverWindowDetectsHoverForClickThroughZoom() {
        let frame = CGRect(x: 200, y: 120, width: 400, height: 260)
        XCTAssertTrue(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 250, y: 180), windowFrame: frame))
        XCTAssertFalse(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 20, y: 20), windowFrame: frame))
        XCTAssertTrue(PictureInPictureLayout.isMouseOverWindow(mouse: CGPoint(x: 198, y: 180), windowFrame: frame, inset: 4))
    }

    func testCommandWClosesOnlyTheHoveredWindow() {
        let frame = CGRect(x: 200, y: 120, width: 400, height: 260)
        XCTAssertTrue(
            PictureInPictureLayout.shouldCloseOnCommandW(
                mouse: CGPoint(x: 250, y: 180),
                windowFrame: frame,
                commandPressed: true,
                key: "w"
            )
        )
        XCTAssertFalse(
            PictureInPictureLayout.shouldCloseOnCommandW(
                mouse: CGPoint(x: 20, y: 20),
                windowFrame: frame,
                commandPressed: true,
                key: "w"
            )
        )
        XCTAssertFalse(
            PictureInPictureLayout.shouldCloseOnCommandW(
                mouse: CGPoint(x: 250, y: 180),
                windowFrame: frame,
                commandPressed: false,
                key: "w"
            )
        )
    }

    func testWindowMatchingPrefersSameAppAndTitle() {
        let slackA = PictureInPictureWindowCandidate(
            windowID: 11,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "#design",
            ownerName: "Slack",
            displayID: 2
        )
        let slackB = PictureInPictureWindowCandidate(
            windowID: 12,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "#general",
            ownerName: "Slack",
            displayID: 1
        )
        let safari = PictureInPictureWindowCandidate(
            windowID: 21,
            bundleIdentifier: "com.apple.Safari",
            title: "Reference",
            ownerName: "Safari",
            displayID: 2
        )
        let identity = PictureInPictureWindowIdentity(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "#design",
            ownerName: "Slack"
        )
        let match = PictureInPictureWindowMatching.match(
            identity: identity,
            candidates: [safari, slackB, slackA]
        )
        XCTAssertEqual(match?.windowID, 11)

        let retitled = PictureInPictureWindowMatching.match(
            identity: PictureInPictureWindowIdentity(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                title: "design review",
                ownerName: "Slack"
            ),
            candidates: [slackB, slackA]
        )
        XCTAssertEqual(retitled?.windowID, 11)

        let query = PictureInPictureWindowMatching.query(
            "safari",
            preferringDisplay: 2,
            in: [slackA, safari]
        )
        XCTAssertEqual(query?.bundleIdentifier, "com.apple.Safari")
    }

    func testWindowMenuHidesDesktopBackstopLayers() {
        let slack = PictureInPictureWindowCandidate(
            windowID: 11,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "#design",
            ownerName: "Slack"
        )
        let backstop = PictureInPictureWindowCandidate(
            windowID: 31,
            bundleIdentifier: "com.apple.WindowServer",
            title: "Display 1 Backstop",
            ownerName: ""
        )
        let otherBackstop = PictureInPictureWindowCandidate(
            windowID: 32,
            bundleIdentifier: "",
            title: "Display 2 Backstop",
            ownerName: "WindowServer"
        )
        XCTAssertTrue(PictureInPictureWindowMatching.shouldOffer(slack))
        XCTAssertFalse(PictureInPictureWindowMatching.shouldOffer(backstop))
        XCTAssertFalse(PictureInPictureWindowMatching.shouldOffer(otherBackstop))
    }

    func testWindowMenuHidesBlackCaptureOverlays() {
        let slack = PictureInPictureWindowCandidate(
            windowID: 11,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "#design",
            ownerName: "Slack"
        )
        let highlighter = PictureInPictureWindowCandidate(
            windowID: 41,
            bundleIdentifier: "com.timpler.screenstudio",
            title: "Screen Studio Display Window Picker Highlighter",
            ownerName: "Screen Studio"
        )
        let untitledOverlay = PictureInPictureWindowCandidate(
            windowID: 42,
            bundleIdentifier: "com.timpler.screenstudio",
            title: "",
            ownerName: "Screen Studio",
            windowLayer: 3
        )
        XCTAssertTrue(PictureInPictureWindowMatching.shouldOffer(slack))
        XCTAssertFalse(PictureInPictureWindowMatching.shouldOffer(highlighter))
        XCTAssertFalse(PictureInPictureWindowMatching.shouldOffer(untitledOverlay))
    }

    func testMagnifierCropsAroundCursorAndStaysOnScreen() {
        let crop = PictureInPictureMagnifier.cropRect(
            sourceWidth: 1920,
            sourceHeight: 1080,
            cursor: CGPoint(x: 960, y: 540),
            zoom: 2
        )
        XCTAssertEqual(crop.width, 960, accuracy: 0.001)
        XCTAssertEqual(crop.height, 540, accuracy: 0.001)
        XCTAssertEqual(crop.midX, 960, accuracy: 0.001)
        XCTAssertEqual(crop.midY, 540, accuracy: 0.001)

        let edge = PictureInPictureMagnifier.cropRect(
            sourceWidth: 1920,
            sourceHeight: 1080,
            cursor: CGPoint(x: 10, y: 10),
            zoom: 2
        )
        XCTAssertEqual(edge.minX, 0, accuracy: 0.001)
        XCTAssertEqual(edge.minY, 0, accuracy: 0.001)
        XCTAssertEqual(PictureInPictureMagnifier.clampedZoom(8), 4, accuracy: 0.0001)
        XCTAssertEqual(PictureInPictureMagnifier.nearestStop(2.4), 2, accuracy: 0.0001)

        let screen = CGRect(x: 1920, y: 0, width: 1512, height: 982)
        let cursor = PictureInPictureMagnifier.cursorInSourcePixels(
            mouse: CGPoint(x: 1920 + 756, y: 491),
            screenFrame: screen,
            pixelWidth: 3024,
            pixelHeight: 1964
        )
        XCTAssertEqual(cursor?.x ?? -1, 1512, accuracy: 1)
        XCTAssertEqual(cursor?.y ?? -1, 982, accuracy: 1)
        XCTAssertNil(
            PictureInPictureMagnifier.cursorInSourcePixels(
                mouse: CGPoint(x: 10, y: 10),
                screenFrame: screen,
                pixelWidth: 3024,
                pixelHeight: 1964
            )
        )
    }

    func testMagnifierSpaceDragPansTheCropAndStaysOnScreen() {
        let start = PictureInPictureMagnifier.clampedFocus(
            CGPoint(x: 960, y: 540),
            sourceWidth: 1920,
            sourceHeight: 1080,
            zoom: 2
        )
        XCTAssertEqual(start.x, 960, accuracy: 0.001)
        XCTAssertEqual(start.y, 540, accuracy: 0.001)

        let panned = PictureInPictureMagnifier.pannedFocus(
            current: start,
            deltaX: 100,
            deltaY: 50,
            previewWidth: 400,
            previewHeight: 225,
            sourceWidth: 1920,
            sourceHeight: 1080,
            zoom: 2
        )
        XCTAssertEqual(panned.x, 720, accuracy: 0.001)
        XCTAssertEqual(panned.y, 420, accuracy: 0.001)

        let upward = PictureInPictureMagnifier.pannedFocus(
            current: start,
            deltaX: 0,
            deltaY: 50,
            previewWidth: 400,
            previewHeight: 225,
            sourceWidth: 1920,
            sourceHeight: 1080,
            zoom: 2
        )
        XCTAssertLessThan(upward.y, start.y)

        let edge = PictureInPictureMagnifier.pannedFocus(
            current: CGPoint(x: 100, y: 100),
            deltaX: 400,
            deltaY: 400,
            previewWidth: 400,
            previewHeight: 225,
            sourceWidth: 1920,
            sourceHeight: 1080,
            zoom: 2
        )
        XCTAssertEqual(edge.x, 480, accuracy: 0.001)
        XCTAssertEqual(edge.y, 270, accuracy: 0.001)
        XCTAssertFalse(PictureInPictureLayout.shouldResizeWindow(forMagnifierPan: true, mode: .magnifier))
        XCTAssertTrue(PictureInPictureLayout.shouldResizeWindow(forMagnifierPan: false, mode: .magnifier))
        XCTAssertTrue(PictureInPictureLayout.shouldResizeWindow(forMagnifierPan: true, mode: .window))

        XCTAssertFalse(PictureInPictureLayout.shouldMoveWindow(forMagnifierPan: true, mode: .magnifier))
        XCTAssertTrue(PictureInPictureLayout.shouldMoveWindow(forMagnifierPan: false, mode: .magnifier))
        XCTAssertTrue(PictureInPictureLayout.shouldMoveWindow(forMagnifierPan: true, mode: .display))

        XCTAssertTrue(PictureInPictureLayout.shouldFallBackToDisplay(mode: .window, hasResolvedWindow: false))
        XCTAssertFalse(PictureInPictureLayout.shouldFallBackToDisplay(mode: .window, hasResolvedWindow: true))
        XCTAssertFalse(PictureInPictureLayout.shouldFallBackToDisplay(mode: .display, hasResolvedWindow: false))
        XCTAssertFalse(PictureInPictureLayout.shouldFallBackToDisplay(mode: .magnifier, hasResolvedWindow: false))
    }

    func testMonitorWallSkipsVirtualScreensAndTilesFromTopLeft() {
        let snapshots = FakeSnapshots.standard()
        let wall = PictureInPictureWallLayout.snapshots(snapshots)
        XCTAssertEqual(wall.map(\.name), [FakeSnapshots.builtInName, FakeSnapshots.dellName, FakeSnapshots.hdmiTVName])
        XCTAssertEqual(PictureInPictureWallLayout.grid(for: 2).columns, 2)
        XCTAssertEqual(PictureInPictureWallLayout.grid(for: 2).rows, 1)
        XCTAssertEqual(PictureInPictureWallLayout.grid(for: 3).columns, 2)
        XCTAssertEqual(PictureInPictureWallLayout.grid(for: 3).rows, 2)

        let frames = PictureInPictureWallLayout.tileFrames(
            count: 3,
            in: CGRect(x: 0, y: 0, width: 200, height: 200),
            gap: 0
        )
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(frames[0].maxY, 200, accuracy: 0.001)
        XCTAssertEqual(frames[1].origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(frames[2].origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(frames[2].origin.x, 0, accuracy: 0.001)

        let grown = PictureInPictureWallLayout.tileFrames(
            count: 2,
            in: CGRect(x: 0, y: 0, width: 1280, height: 400),
            gap: 8
        )
        XCTAssertEqual(grown.count, 2)
        XCTAssertEqual(grown[0].width, 636, accuracy: 0.001)
        XCTAssertEqual(grown[0].height, 400, accuracy: 0.001)
        XCTAssertEqual(grown[0].minY, 0, accuracy: 0.001)
        XCTAssertEqual(grown[0].maxY, 400, accuracy: 0.001)
        XCTAssertEqual(grown[1].minX, 644, accuracy: 0.001)
        XCTAssertEqual(grown[1].maxX, 1280, accuracy: 0.001)
    }

    func testLegacyPlacementDecodesAsDisplayMode() throws {
        let data = Data(#"{"opacity":0.4,"clickThrough":true,"corner":"topLeft"}"#.utf8)
        let placement = try JSONDecoder().decode(PictureInPicturePlacement.self, from: data)
        XCTAssertEqual(placement.opacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(placement.mode, .display)
        XCTAssertFalse(placement.mirrored)
        XCTAssertEqual(placement.magnifierZoom, 2, accuracy: 0.0001)
        XCTAssertEqual(PictureInPictureMode.from(query: "loupe"), .magnifier)
    }

    func testMirrorKeepsThePreviewCentered() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 360)
        XCTAssertEqual(PictureInPictureMirror.affineTransform(mirrored: false, bounds: bounds), .identity)
        XCTAssertEqual(PictureInPictureMirror.centeredAffineTransform(mirrored: false), .identity)

        let flipped = PictureInPictureMirror.affineTransform(mirrored: true, bounds: bounds)
        let left = CGPoint(x: 0, y: 180).applying(flipped)
        let right = CGPoint(x: 640, y: 180).applying(flipped)
        let center = CGPoint(x: 320, y: 180).applying(flipped)
        XCTAssertEqual(left.x, 640, accuracy: 0.001)
        XCTAssertEqual(right.x, 0, accuracy: 0.001)
        XCTAssertEqual(center.x, 320, accuracy: 0.001)
        XCTAssertEqual(center.y, 180, accuracy: 0.001)

        let centered = PictureInPictureMirror.centeredAffineTransform(mirrored: true)
        XCTAssertEqual(CGPoint(x: -160, y: 20).applying(centered), CGPoint(x: 160, y: 20))
        XCTAssertEqual(centered.a, -1, accuracy: 0.0001)
        XCTAssertEqual(centered.d, 1, accuracy: 0.0001)
        XCTAssertEqual(centered.tx, 0, accuracy: 0.0001)
        XCTAssertEqual(centered.ty, 0, accuracy: 0.0001)
    }
}
