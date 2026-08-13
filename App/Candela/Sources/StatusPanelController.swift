import AppKit

@MainActor
final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

@MainActor
final class StatusPanelController {
    let panel: StatusPanel
    private let session: DisplaySessionController
    private let panelView: StatusPanelView

    var isVisible: Bool {
        panel.isVisible
    }

    init(session: DisplaySessionController) {
        self.session = session
        let panelView = StatusPanelView(session: session)
        self.panelView = panelView
        let panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
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

    func show(relativeTo button: NSView) {
        panelView.reload(session.snapshots)
        panelView.layoutSubtreeIfNeeded()
        let height = max(panelView.fittingSize.height, 48)
        panel.setContentSize(NSSize(width: 300, height: height))
        position(relativeTo: button, height: height)
        panel.orderFront(nil)
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func reload() {
        panelView.reload(session.snapshots)
        if isVisible {
            panelView.layoutSubtreeIfNeeded()
            let height = max(panelView.fittingSize.height, 48)
            panel.setContentSize(NSSize(width: 300, height: height))
        }
    }

    func noteMouseDown() {
        panel.makeKey()
    }

    func containsMouse() -> Bool {
        panel.frame.contains(NSEvent.mouseLocation)
    }

    private func position(relativeTo button: NSView, height: CGFloat) {
        guard let window = button.window else { return }
        let buttonScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonScreen.maxX - 300
        let y = buttonScreen.minY - height - 6
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - 300 - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
