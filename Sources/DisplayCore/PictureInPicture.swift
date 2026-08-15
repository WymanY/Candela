import CoreGraphics
import Foundation

public enum PictureInPictureCorner: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

public struct PictureInPictureFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct PictureInPicturePlacement: Codable, Equatable, Sendable {
    public var opacity: Double
    public var clickThrough: Bool
    public var corner: PictureInPictureCorner?
    public var frame: PictureInPictureFrame?
    public var hostDisplayID: UInt32?

    public init(
        opacity: Double = 1,
        clickThrough: Bool = false,
        corner: PictureInPictureCorner? = nil,
        frame: PictureInPictureFrame? = nil,
        hostDisplayID: UInt32? = nil
    ) {
        self.opacity = PictureInPictureLayout.clampedOpacity(opacity)
        self.clickThrough = clickThrough
        self.corner = corner
        self.frame = frame
        self.hostDisplayID = hostDisplayID
    }

    public static let `default` = PictureInPicturePlacement()
}

public enum PictureInPictureLayout {
    public static let defaultWidth: CGFloat = 640
    public static let minWidth: CGFloat = 280
    public static let maxWidth: CGFloat = 1280
    public static let chromeHeight: CGFloat = 32
    public static let margin: CGFloat = 24
    public static let minimumCaptureWidth = 1280
    public static let minimumCaptureHeight = 720
    public static let minimumOpacity: Double = 0.25
    public static let snapTolerance: CGFloat = 12

    public static func supports(kind: DisplayKind) -> Bool {
        kind != .virtualUnsupported
    }

    public static func clampedOpacity(_ value: Double) -> Double {
        min(1, max(minimumOpacity, value))
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
        windowFrame(
            windowSize: windowSize,
            sourceDisplayID: sourceDisplayID,
            screens: screens,
            placement: .default
        ).origin
    }

    public static func windowFrame(
        windowSize: CGSize,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)],
        placement: PictureInPicturePlacement = .default
    ) -> CGRect {
        let size = clampedWindowSize(windowSize)
        let host = hostScreen(
            preferredDisplayID: placement.hostDisplayID,
            savedFrame: placement.frame?.rect,
            sourceDisplayID: sourceDisplayID,
            screens: screens
        )
        guard let host else {
            return CGRect(origin: .zero, size: size)
        }
        if let corner = placement.corner {
            return CGRect(origin: snapOrigin(windowSize: size, corner: corner, visible: host.visible), size: size)
        }
        if let saved = placement.frame?.rect, saved.width > 1, saved.height > 1 {
            return clampedFrame(CGRect(origin: saved.origin, size: size), in: host.visible)
        }
        return CGRect(
            origin: snapOrigin(windowSize: size, corner: .bottomRight, visible: host.visible),
            size: size
        )
    }

    public static func snapOrigin(windowSize: CGSize, corner: PictureInPictureCorner, visible: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: visible.minX + margin, y: visible.maxY - windowSize.height - margin)
        case .topRight:
            return CGPoint(x: visible.maxX - windowSize.width - margin, y: visible.maxY - windowSize.height - margin)
        case .bottomLeft:
            return CGPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            return CGPoint(x: visible.maxX - windowSize.width - margin, y: visible.minY + margin)
        }
    }

    public static func clampedFrame(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var next = frame
        if next.width > visible.width {
            next.size.width = visible.width
        }
        if next.height > visible.height {
            next.size.height = visible.height
        }
        if next.maxX > visible.maxX {
            next.origin.x = visible.maxX - next.width
        }
        if next.maxY > visible.maxY {
            next.origin.y = visible.maxY - next.height
        }
        if next.minX < visible.minX {
            next.origin.x = visible.minX
        }
        if next.minY < visible.minY {
            next.origin.y = visible.minY
        }
        return next
    }

    public static func hostScreen(
        preferredDisplayID: UInt32?,
        savedFrame: CGRect?,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)]
    ) -> (id: CGDirectDisplayID, visible: CGRect)? {
        if let savedFrame {
            let ranked = screens
                .map { screen -> (screen: (id: CGDirectDisplayID, visible: CGRect), area: CGFloat) in
                    (screen, screen.visible.intersection(savedFrame).width * screen.visible.intersection(savedFrame).height)
                }
                .filter { $0.area > 1 }
                .sorted { $0.area > $1.area }
            if let best = ranked.first {
                return best.screen
            }
        }
        if let preferredDisplayID,
           let match = screens.first(where: { $0.id == preferredDisplayID })
        {
            return match
        }
        return screens.first(where: { $0.id != sourceDisplayID }) ?? screens.first
    }

    public static func clampedWindowSize(_ size: CGSize) -> CGSize {
        let width = min(max(size.width, minWidth), maxWidth)
        let height = max(size.height, chromeHeight + 80)
        return CGSize(width: width, height: height)
    }

    public static func movedOffPinnedCorner(
        frame: CGRect,
        corner: PictureInPictureCorner,
        visible: CGRect
    ) -> Bool {
        let snap = snapOrigin(windowSize: frame.size, corner: corner, visible: visible)
        let dx = frame.origin.x - snap.x
        let dy = frame.origin.y - snap.y
        return (dx * dx + dy * dy).squareRoot() > snapTolerance
    }
}
