import AppKit

@MainActor
final class StatusPanel: NSPanel {
    var canvasPanActive = false
    var onCommandW: (() -> Void)?
    var onCommandComma: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCommandShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        if isCommandW(event) {
            onCommandW?()
            return true
        }
        if isCommandComma(event) {
            onCommandComma?()
            return true
        }
        return false
    }

    private func isCommandW(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }

    private func isCommandComma(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers == ","
    }

    override func scrollWheel(with event: NSEvent) {
        if canvasPanActive {
            contentView?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if canvasPanActive {
            contentView?.mouseDragged(with: event)
            return
        }
        super.mouseDragged(with: event)
    }
}

@MainActor
final class StatusPanelController {
    let panel: StatusPanel
    private let session: DisplaySessionController
    private var panelView: StatusPanelView

    var isVisible: Bool {
        panel.isVisible
    }

    init(session: DisplaySessionController) {
        self.session = session
        let panelView = StatusPanelView(session: session)
        self.panelView = panelView
        let panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: CandelaChrome.panelWidth, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // Do not use `.transient`: an accessory/debug launch never stays "active",
        // so AppKit would immediately hide the panel.
        panel.collectionBehavior = [.ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = panelView
        self.panel = panel
        panelView.reload(session.snapshots)
    }

    func bindActions(openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        panelView.onOpenSettings = openSettings
        panelView.onQuit = quit
        panel.onCommandComma = openSettings
    }

    func show(relativeTo button: NSView) {
        session.sampleLiveSpeakerVolume()
        panelView.reload(session.snapshots)
        panelView.needsLayout = true
        panelView.layoutSubtreeIfNeeded()
        let measured = panelView.fittingSize.height
        let height = min(max(measured.isFinite ? measured : 196, 176), 640)
        panel.setContentSize(NSSize(width: CandelaChrome.panelWidth, height: height))
        position(relativeTo: button, height: height)
        if !isOnscreen() {
            snapBelowMenuBar(height: height)
        }
        panel.orderFront(nil)
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func rebuild() {
        let next = StatusPanelView(session: session)
        next.onOpenSettings = panelView.onOpenSettings
        next.onQuit = panelView.onQuit
        panelView = next
        panel.contentView = next
        reload()
    }

    func reload() {
        panelView.reload(session.snapshots)
        if isVisible {
            panelView.needsLayout = true
            panelView.layoutSubtreeIfNeeded()
            let measured = panelView.fittingSize.height
            let height = min(max(measured.isFinite ? measured : 196, 176), 640)
            panel.setContentSize(NSSize(width: CandelaChrome.panelWidth, height: height))
        }
    }

    func noteMouseDown() {
        panel.makeKey()
    }

    func containsMouse() -> Bool {
        panel.frame.contains(NSEvent.mouseLocation)
    }

    func isOnscreen() -> Bool {
        guard let screen = panel.screen ?? NSScreen.main else { return false }
        return screen.visibleFrame.intersects(panel.frame.insetBy(dx: 8, dy: 8))
    }

    private func position(relativeTo button: NSView, height: CGFloat) {
        let width = CandelaChrome.panelWidth
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let buttonScreen = resolvedButtonFrame(button, visible: visible)
        var x = buttonScreen.midX - width / 2
        var y = buttonScreen.minY - height - 8
        x = min(max(x, visible.minX + 8), max(visible.minX + 8, visible.maxX - width - 8))
        if y < visible.minY + 8 || (y + height) > visible.maxY {
            y = visible.maxY - height - 8
        }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func resolvedButtonFrame(_ button: NSView, visible: NSRect) -> NSRect {
        let padded = visible.insetBy(dx: -48, dy: -48)
        if let window = button.window {
            let converted = window.convertToScreen(button.convert(button.bounds, to: nil))
            if converted.width > 4, converted.height > 4, padded.intersects(converted) {
                return converted
            }
            if padded.intersects(window.frame) {
                return window.frame
            }
        }
        return NSRect(x: visible.maxX - 72, y: visible.maxY, width: 36, height: 24)
    }

    private func snapBelowMenuBar(height: CGFloat) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let width = CandelaChrome.panelWidth
        let x = min(max(visible.maxX - width - 16, visible.minX + 8), visible.maxX - width - 8)
        let y = visible.maxY - height - 8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
