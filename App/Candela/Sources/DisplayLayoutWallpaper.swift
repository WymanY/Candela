import AppKit
import CoreGraphics
import DisplayCore

enum DisplayLayoutWallpaper {
    static let fallbackFill = NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.78, alpha: 1)

    private static let cache = NSCache<NSString, NSImage>()

    static func images(
        for slots: [DisplayLayoutSlot],
        displayIDsByKey: [String: CGDirectDisplayID]
    ) -> [String: NSImage] {
        var images: [String: NSImage] = [:]
        for slot in slots {
            images[slot.persistentKey] = image(
                for: slot,
                displayID: displayIDsByKey[slot.persistentKey]
            )
        }
        return images
    }

    static func image(
        for slot: DisplayLayoutSlot,
        displayID: CGDirectDisplayID?
    ) -> NSImage {
        if let displayID,
           let screen = NSScreen.candelaScreen(for: displayID),
           let image = image(for: screen) {
            return image
        }
        if let screen = matchingScreen(for: slot),
           let image = image(for: screen) {
            return image
        }
        if let image = image(at: defaultDesktopURL) {
            return image
        }
        return solidFallback
    }

    private static func matchingScreen(for slot: DisplayLayoutSlot) -> NSScreen? {
        let screens = NSScreen.screens
        if slot.isMain, let main = screens.first(where: { CGDisplayIsMain($0.candelaDisplayID) != 0 }) {
            return main
        }
        if slot.isBuiltin, let builtin = screens.first(where: { CGDisplayIsBuiltin($0.candelaDisplayID) != 0 }) {
            return builtin
        }
        let matches = screens.filter {
            abs($0.frame.width - slot.size.width) < 1 && abs($0.frame.height - slot.size.height) < 1
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func image(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        return image(at: url)
    }

    private static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let loaded = NSImage(contentsOf: url), loaded.size.width > 0, loaded.size.height > 0 else {
            return nil
        }
        let thumbnail = downsampled(loaded, maxDimension: 720)
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    private static func downsampled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = NSImage(size: target)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.medium.rawValue)]
        )
        thumbnail.unlockFocus()
        return thumbnail
    }

    private static var defaultDesktopURL: URL {
        URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
    }

    private static var solidFallback: NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        fallbackFill.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 8, height: 8))
        image.unlockFocus()
        return image
    }
}
