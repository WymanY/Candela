import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let session: DisplaySessionController

    init(session: DisplaySessionController) {
        self.session = session
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Candela")
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeContent() -> NSView {
        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let general = NSTabViewItem(identifier: "general")
        general.label = String(localized: "General")
        general.view = SettingsGeneralView(session: session)

        let displays = NSTabViewItem(identifier: "displays")
        displays.label = String(localized: "Displays")
        displays.view = SettingsDisplaysView(session: session)

        let about = NSTabViewItem(identifier: "about")
        about.label = String(localized: "About")
        about.view = SettingsAboutView(session: session)

        tabView.addTabViewItem(general)
        tabView.addTabViewItem(displays)
        tabView.addTabViewItem(about)
        return tabView
    }
}
