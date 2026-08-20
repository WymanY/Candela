import CoreGraphics
import Foundation

/// After Control-Esc, warp the pointer onto the PiP and pulse it to 2× then back.
public enum PictureInPictureCursorPulse {
    public static let scale: CGFloat = 2
    public static let growDuration: TimeInterval = 0.14
    public static let shrinkDuration: TimeInterval = 0.22

    public static func warpPoint(previewFrameInScreen: CGRect) -> CGPoint {
        CGPoint(x: previewFrameInScreen.midX, y: previewFrameInScreen.midY)
    }

    /// Overlay in AppKit screen space, large enough for the 2× cursor. The hotspot sits on `mouse`.
    public static func overlayFrame(
        mouse: CGPoint,
        cursorSize: CGSize,
        scale: CGFloat = scale
    ) -> CGRect {
        let width = max(cursorSize.width * scale, 1)
        let height = max(cursorSize.height * scale, 1)
        return CGRect(x: mouse.x - width / 2, y: mouse.y - height / 2, width: width, height: height)
    }

    /// Place the 1× cursor image so its hotspot sits on the overlay midpoint (`mouse`).
    /// `hotSpot` uses NSCursor's top-left origin.
    public static func cursorOrigin(
        overlaySize: CGSize,
        cursorSize: CGSize,
        hotSpot: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: overlaySize.width / 2 - hotSpot.x,
            y: overlaySize.height / 2 - (cursorSize.height - hotSpot.y)
        )
    }

    /// Layer `anchorPoint` for a non-flipped AppKit view, so scale grows around the hotspot.
    public static func layerAnchorPoint(cursorSize: CGSize, hotSpot: CGPoint) -> CGPoint {
        let width = max(cursorSize.width, 1)
        let height = max(cursorSize.height, 1)
        return CGPoint(
            x: min(max(hotSpot.x / width, 0), 1),
            y: min(max((height - hotSpot.y) / height, 0), 1)
        )
    }
}
