import CoreGraphics
import Foundation

public enum PictureInPictureLayout {
    public static let defaultWidth: CGFloat = 640
    public static let minWidth: CGFloat = 280
    public static let maxWidth: CGFloat = 1280
    public static let chromeHeight: CGFloat = 28
    public static let margin: CGFloat = 24
    public static let minimumCaptureWidth = 1280
    public static let minimumCaptureHeight = 720

    public static func supports(kind: DisplayKind) -> Bool {
        kind != .virtualUnsupported
    }

    public static func contentSize(
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        preferredWidth: CGFloat = defaultWidth
    ) -> CGSize {
        let sourceWidth = max(CGFloat(pixelWidth), 1)
        let sourceHeight = max(CGFloat(pixelHeight), 1)
        let width = min(max(preferredWidth, minWidth), maxWidth)
        return CGSize(width: width, height: max(width * (sourceHeight / sourceWidth), 80))
    }

    public static func windowSize(forContent content: CGSize) -> CGSize {
        CGSize(width: content.width, height: content.height + chromeHeight)
    }

    /// Capture at the source display's pixels so the floating window stays sharp.
    public static func captureSize(pixelWidth: UInt32, pixelHeight: UInt32) -> (width: Int, height: Int) {
        var width = max(Int(pixelWidth), minimumCaptureWidth)
        var height = max(Int(pixelHeight), minimumCaptureHeight)
        if pixelWidth > 0, pixelHeight > 0 {
            width = Int(pixelWidth)
            height = Int(pixelHeight)
        }
        width = max(width - width % 2, 2)
        height = max(height - height % 2, 2)
        return (width, height)
    }

    /// Prefer a screen that is not the mirrored source so the window is visible.
    public static func origin(
        windowSize: CGSize,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)]
    ) -> CGPoint {
        let target = screens.first(where: { $0.id != sourceDisplayID }) ?? screens.first
        guard let visible = target?.visible else { return .zero }
        return CGPoint(
            x: visible.maxX - windowSize.width - margin,
            y: visible.minY + margin
        )
    }
}
