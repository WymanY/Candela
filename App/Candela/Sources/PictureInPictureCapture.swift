import AppKit
import CoreGraphics
import CoreMedia
import DisplayCore
import ScreenCaptureKit

enum PictureInPictureCapture {
    static let ownBundleIdentifier = "app.candela.macos"

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleIdentifier }
    }

    static func candidates(
        in content: SCShareableContent,
        preferringDisplay displayID: CGDirectDisplayID?
    ) -> [PictureInPictureWindowCandidate] {
        let mapped = content.windows.compactMap { window -> PictureInPictureWindowCandidate? in
            guard window.windowID != 0 else { return nil }
            let bundle = window.owningApplication?.bundleIdentifier ?? ""
            if bundle == ownBundleIdentifier { return nil }
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let owner = window.owningApplication?.applicationName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty && owner.isEmpty { return nil }
            if window.frame.width < 80 || window.frame.height < 80 { return nil }
            return PictureInPictureWindowCandidate(
                windowID: UInt32(window.windowID),
                bundleIdentifier: bundle,
                title: title,
                ownerName: owner,
                displayID: displayIDContaining(window.frame),
                pixelWidth: UInt32(max(window.frame.width, 0).rounded()),
                pixelHeight: UInt32(max(window.frame.height, 0).rounded())
            )
        }
        return PictureInPictureWindowMatching.sorted(mapped, preferringDisplay: displayID)
    }

    static func window(id: UInt32, in content: SCShareableContent) -> SCWindow? {
        content.windows.first { UInt32($0.windowID) == id }
    }

    static func display(id: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == id }
    }

    static func fakeCandidates(displayID: CGDirectDisplayID) -> [PictureInPictureWindowCandidate] {
        [
            PictureInPictureWindowCandidate(
                windowID: 101,
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                title: "#design",
                ownerName: "Slack",
                displayID: displayID,
                pixelWidth: 1280,
                pixelHeight: 800
            ),
            PictureInPictureWindowCandidate(
                windowID: 102,
                bundleIdentifier: "com.apple.Safari",
                title: "Reference",
                ownerName: "Safari",
                displayID: displayID,
                pixelWidth: 1440,
                pixelHeight: 900
            ),
            PictureInPictureWindowCandidate(
                windowID: 103,
                bundleIdentifier: "com.apple.finder",
                title: "Downloads",
                ownerName: "Finder",
                displayID: displayID,
                pixelWidth: 980,
                pixelHeight: 640
            ),
        ]
    }

    static func streamConfiguration(
        width: Int,
        height: Int,
        sourceRect: CGRect? = nil,
        showsCursor: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(width - width % 2, 2)
        configuration.height = max(height - height % 2, 2)
        configuration.scalesToFit = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        if let sourceRect, sourceRect.width > 1, sourceRect.height > 1 {
            configuration.sourceRect = sourceRect
        }
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }
        return configuration
    }

    static func sourceRect(
        crop: CGRect,
        pixelWidth: Double,
        pixelHeight: Double,
        pointWidth: Double,
        pointHeight: Double
    ) -> CGRect {
        guard pixelWidth > 1, pixelHeight > 1, pointWidth > 1, pointHeight > 1 else { return crop }
        return CGRect(
            x: crop.minX * pointWidth / pixelWidth,
            y: crop.minY * pointHeight / pixelHeight,
            width: crop.width * pointWidth / pixelWidth,
            height: crop.height * pointHeight / pixelHeight
        )
    }

    static func displayIDContaining(_ frame: CGRect) -> UInt32? {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(point) })?.candelaDisplayID
    }
}
