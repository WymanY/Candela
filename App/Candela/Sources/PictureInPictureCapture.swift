import AppKit
import CoreGraphics
import CoreMedia
import DisplayCore
import ScreenCaptureKit

enum PictureInPictureCapture {
    static let ownBundleIdentifier = "app.candela.macos"

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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
            let candidate = PictureInPictureWindowCandidate(
                windowID: UInt32(window.windowID),
                bundleIdentifier: bundle,
                title: title,
                ownerName: owner,
                displayID: displayIDContaining(window.frame, displays: content.displays),
                pixelWidth: UInt32(max(window.frame.width, 0).rounded()),
                pixelHeight: UInt32(max(window.frame.height, 0).rounded()),
                windowLayer: window.windowLayer
            )
            return PictureInPictureWindowMatching.shouldOffer(candidate) ? candidate : nil
        }
        let scoped = PictureInPictureWindowMatching.scopedToDisplay(mapped, displayID: displayID)
        return PictureInPictureWindowMatching.sorted(scoped, preferringDisplay: displayID)
    }

    static func window(id: UInt32, in content: SCShareableContent) -> SCWindow? {
        content.windows.first { UInt32($0.windowID) == id }
    }

    static func display(id: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
        if let match = content.displays.first(where: { $0.displayID == id }) {
            return match
        }
        let bounds = CGDisplayBounds(id)
        let matches = content.displays.filter { $0.frame.equalTo(bounds) }
        if matches.count == 1 {
            return matches[0]
        }
        return nil
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

    static func displayIDContaining(_ frame: CGRect, displays: [SCDisplay] = []) -> UInt32? {
        if let match = PictureInPictureWindowMatching.displayIDContaining(
            frame,
            displays: displays.map { (id: $0.displayID, bounds: $0.frame) }
        ) {
            return match
        }
        return PictureInPictureWindowMatching.displayIDContaining(frame, displays: onlineDisplayBounds())
    }

    private static func onlineDisplayBounds() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
        var allocated: UInt32 = 16
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
        var count: UInt32 = 0
        let error = CGGetOnlineDisplayList(allocated, &ids, &count)
        guard error == .success else { return [] }
        return ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
    }
}
