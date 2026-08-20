import AppKit
import DisplayCore

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
        session.sampleLiveBrightness()
        session.refreshPowerStatus()
        panelView.reload(session.snapshots)
        panelView.needsLayout = true
        panelView.layoutSubtreeIfNeeded()
        let height = StatusPanelLayout.clampedHeight(panelView.fittingSize.height)
        panel.setContentSize(NSSize(width: CandelaChrome.panelWidth, height: height))
        position(relativeTo: button, height: height)
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
        if isVisible, !panelView.isDraggingBrightness {
            panelView.needsLayout = true
            panelView.layoutSubtreeIfNeeded()
            let height = StatusPanelLayout.clampedHeight(panelView.fittingSize.height)
            var frame = panel.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            panel.setFrame(frame, display: true)
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
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let converted = button.window.map { window in
            window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let buttonScreen = StatusPanelLayout.resolvedButtonFrame(
            converted: converted,
            windowFrame: button.window?.frame,
            visible: visible
        )
        panel.setFrame(
            StatusPanelLayout.panelFrame(
                button: buttonScreen,
                height: height,
                visible: visible,
                width: CandelaChrome.panelWidth
            ),
            display: true
        )
    }
}
