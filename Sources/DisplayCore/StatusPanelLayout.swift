import CoreGraphics
import Foundation

public enum StatusPanelLayout {
    public static let defaultWidth: CGFloat = 392
    public static let minHeight: CGFloat = 176
    public static let maxHeight: CGFloat = 640
    public static let margin: CGFloat = 8
    public static let maxButtonWidth: CGFloat = 64
    public static let maxButtonHeight: CGFloat = 40
    public static let fallbackTrailingInset: CGFloat = 16
    public static let fallbackButtonWidth: CGFloat = 36
    public static let fallbackButtonHeight: CGFloat = 24

    public static func clampedHeight(_ value: CGFloat) -> CGFloat {
        let measured = value.isFinite ? value : minHeight
        return min(max(measured, minHeight), maxHeight)
    }

    /// Status items live in a thin band just above `visibleFrame`.
    /// Full-width menu-bar windows and content-area frames are not usable anchors.
    public static func isUsableStatusButtonFrame(_ frame: CGRect, visible: CGRect) -> Bool {
        guard frame.width > 4, frame.height > 4 else { return false }
        guard frame.width <= maxButtonWidth, frame.height <= maxButtonHeight else { return false }
        let band = CGRect(
            x: visible.minX - margin,
            y: visible.maxY - 4,
            width: visible.width + margin * 2,
            height: maxButtonHeight + margin * 3
        )
        return band.intersects(frame)
    }

    public static func resolvedButtonFrame(
        converted: CGRect?,
        windowFrame: CGRect?,
        visible: CGRect
    ) -> CGRect {
        if let converted, isUsableStatusButtonFrame(converted, visible: visible) {
            return converted
        }
        if let windowFrame, isUsableStatusButtonFrame(windowFrame, visible: visible) {
            return windowFrame
        }
        return fallbackButtonFrame(in: visible)
    }

    public static func fallbackButtonFrame(in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.maxX - fallbackTrailingInset - fallbackButtonWidth,
            y: visible.maxY,
            width: fallbackButtonWidth,
            height: fallbackButtonHeight
        )
    }

    public static func panelFrame(
        button: CGRect,
        height: CGFloat,
        visible: CGRect,
        width: CGFloat = defaultWidth
    ) -> CGRect {
        let size = CGSize(width: width, height: clampedHeight(height))
        var x = button.midX - size.width / 2
        var y = button.minY - size.height - margin
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - size.width - margin)
        x = min(max(x, minX), maxX)
        if y < visible.minY + margin || (y + size.height) > visible.maxY {
            y = visible.maxY - size.height - margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
