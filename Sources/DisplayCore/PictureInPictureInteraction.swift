import CoreGraphics
import Foundation

/// Maps clicks on the Picture in Picture preview onto the captured source.
///
/// Preview coordinates are AppKit view space (origin at the bottom-left).
/// Captured-image and Quartz coordinates have origin at the top-left.
/// `AVSampleBufferDisplayLayer.videoGravity = .resizeAspect` letterboxes the
/// picture inside the preview; clicks on the bars do not hit the source.
public enum PictureInPictureInteraction {
    /// Aspect-fit `sourceSize` inside `previewBounds`.
    public static func letterboxedContentRect(previewBounds: CGRect, sourceSize: CGSize) -> CGRect {
        guard previewBounds.width > 1, previewBounds.height > 1, sourceSize.width > 1, sourceSize.height > 1 else {
            return .null
        }
        let scale = min(previewBounds.width / sourceSize.width, previewBounds.height / sourceSize.height)
        let fitted = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: previewBounds.midX - fitted.width / 2,
            y: previewBounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Normalized point in the captured image (origin top-left, y down). `nil` on the letterbox.
    public static func normalizedPoint(
        previewPoint: CGPoint,
        previewBounds: CGRect,
        sourceSize: CGSize,
        mirrored: Bool
    ) -> CGPoint? {
        let content = letterboxedContentRect(previewBounds: previewBounds, sourceSize: sourceSize)
        guard content.width > 1, content.height > 1 else { return nil }
        let inside =
            previewPoint.x >= content.minX && previewPoint.x <= content.maxX
            && previewPoint.y >= content.minY && previewPoint.y <= content.maxY
        guard inside else { return nil }
        var nx = (previewPoint.x - content.minX) / content.width
        let nyFromBottom = (previewPoint.y - content.minY) / content.height
        var nyTop = 1 - nyFromBottom
        if mirrored { nx = 1 - nx }
        nx = min(max(nx, 0), 1)
        nyTop = min(max(nyTop, 0), 1)
        return CGPoint(x: nx, y: nyTop)
    }

    /// Preview click mapped into `sourceBounds` (Quartz global, origin top-left of the main display).
    public static func quartzPoint(
        previewPoint: CGPoint,
        previewBounds: CGRect,
        sourceBounds: CGRect,
        mirrored: Bool
    ) -> CGPoint? {
        guard sourceBounds.width > 1, sourceBounds.height > 1, !sourceBounds.isNull else { return nil }
        guard let normalized = normalizedPoint(
            previewPoint: previewPoint,
            previewBounds: previewBounds,
            sourceSize: sourceBounds.size,
            mirrored: mirrored
        ) else { return nil }
        return CGPoint(
            x: sourceBounds.minX + normalized.x * sourceBounds.width,
            y: sourceBounds.minY + normalized.y * sourceBounds.height
        )
    }

    /// `cropInDisplayPoints` is local to the display (origin top-left of that display).
    public static func quartzBounds(displayBounds: CGRect, cropInDisplayPoints: CGRect?) -> CGRect {
        guard let crop = cropInDisplayPoints, crop.width > 1, crop.height > 1 else {
            return displayBounds
        }
        return CGRect(
            x: displayBounds.minX + crop.minX,
            y: displayBounds.minY + crop.minY,
            width: crop.width,
            height: crop.height
        )
    }

    public static func showsControlSource(mode: PictureInPictureMode) -> Bool {
        mode == .display
    }

    public static func canControlSource(
        hostDisplayID: UInt32?,
        sourceDisplayID: UInt32,
        mode: PictureInPictureMode = .display
    ) -> Bool {
        guard showsControlSource(mode: mode) else { return false }
        guard sourceDisplayID != 0 else { return false }
        guard let hostDisplayID, hostDisplayID != 0 else { return false }
        return hostDisplayID != sourceDisplayID
    }

    /// Control and click-through cannot both be on. Control wins.
    public static func resolvedClickThrough(clickThrough: Bool, controlSource: Bool) -> Bool {
        clickThrough && !controlSource
    }

    /// Hardware Escape. Matches `kVK_Escape`.
    public static let escapeKeyCode: UInt16 = 53

    /// Control-Esc leaves source-control mode. Works even when the source app has focus.
    public static func isExitControlShortcut(keyCode: UInt16, controlPressed: Bool) -> Bool {
        controlPressed && keyCode == escapeKeyCode
    }
}
