import AppKit
import CoreGraphics
import DisplayCore

@MainActor
enum PictureInPictureCursorPulseOverlay {
    private static var panel: NSPanel?
    private static var imageView: NSImageView?
    private static var hideDisplayID: CGDirectDisplayID?

    static func play(at screenPoint: CGPoint) {
        cancel()
        PictureInPictureEventInjector.restoreCursor(toAppKit: screenPoint)

        let (image, hotSpot) = arrowCursor()
        let cursorSize = image.size
        guard cursorSize.width > 1, cursorSize.height > 1 else { return }

        let frame = PictureInPictureCursorPulse.overlayFrame(mouse: screenPoint, cursorSize: cursorSize)
        let origin = PictureInPictureCursorPulse.cursorOrigin(
            overlaySize: frame.size,
            cursorSize: cursorSize,
            hotSpot: hotSpot
        )
        let view = NSImageView(frame: CGRect(origin: origin, size: cursorSize))
        view.image = image
        view.imageScaling = .scaleNone
        view.wantsLayer = true
        view.layer?.anchorPoint = PictureInPictureCursorPulse.layerAnchorPoint(
            cursorSize: cursorSize,
            hotSpot: hotSpot
        )
        view.layer?.position = CGPoint(
            x: origin.x + cursorSize.width * (view.layer?.anchorPoint.x ?? 0.5),
            y: origin.y + cursorSize.height * (view.layer?.anchorPoint.y ?? 0.5)
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.addSubview(view)
        panel.contentView = root
        panel.orderFrontRegardless()

        Self.panel = panel
        Self.imageView = view
        hideCursor(at: screenPoint)

        animate(layer: view.layer, to: PictureInPictureCursorPulse.scale, duration: PictureInPictureCursorPulse.growDuration, timing: .easeOut) {
            animate(layer: view.layer, to: 1, duration: PictureInPictureCursorPulse.shrinkDuration, timing: .easeIn) {
                finish()
            }
        }
    }

    private static func animate(
        layer: CALayer?,
        to scale: CGFloat,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        completion: @escaping () -> Void
    ) {
        guard let layer else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.transform
        animation.toValue = CATransform3DMakeScale(scale, scale, 1)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "pulse")
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    static func cancel() {
        finish()
    }

    private static func hideCursor(at screenPoint: CGPoint) {
        NSCursor.hide()
        let id = NSScreen.candelaScreen(containing: screenPoint)?.candelaDisplayID ?? CGMainDisplayID()
        CGDisplayHideCursor(id)
        hideDisplayID = id
    }

    private static func finish() {
        imageView?.layer?.removeAllAnimations()
        imageView = nil
        panel?.orderOut(nil)
        panel = nil
        if hideDisplayID != nil {
            NSCursor.unhide()
            if let id = hideDisplayID {
                CGDisplayShowCursor(id)
            }
            hideDisplayID = nil
        }
    }

    private static func arrowCursor() -> (NSImage, CGPoint) {
        let arrow = NSCursor.arrow
        if arrow.image.size.width >= 8 {
            return (arrow.image, arrow.hotSpot)
        }
        let size = CGSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 1, y: 22))
        path.line(to: CGPoint(x: 1, y: 4))
        path.line(to: CGPoint(x: 6, y: 9))
        path.line(to: CGPoint(x: 10, y: 2))
        path.line(to: CGPoint(x: 13, y: 3))
        path.line(to: CGPoint(x: 9, y: 10))
        path.line(to: CGPoint(x: 16, y: 10))
        path.close()
        path.lineWidth = 1
        path.fill()
        path.stroke()
        image.unlockFocus()
        return (image, CGPoint(x: 1, y: 2))
    }
}
