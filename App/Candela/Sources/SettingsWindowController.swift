import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?
    private let session: DisplaySessionController
    private let tabView = NSTabView()
    private var generalView: SettingsGeneralView?
    private var displaysView: SettingsDisplaysView?

    private enum Tab: String {
        case general
        case displays
        case about
    }

    init(session: DisplaySessionController) {
        self.session = session
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Candela")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self

        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let generalView = SettingsGeneralView(session: session)
        self.generalView = generalView
        let general = NSTabViewItem(identifier: Tab.general.rawValue)
        general.label = String(localized: "General")
        general.view = generalView

        let displaysView = SettingsDisplaysView(session: session)
        self.displaysView = displaysView
        let displays = NSTabViewItem(identifier: Tab.displays.rawValue)
        displays.label = String(localized: "Displays")
        displays.view = displaysView

        let about = NSTabViewItem(identifier: Tab.about.rawValue)
        about.label = String(localized: "About")
        about.view = SettingsAboutView(session: session)

        tabView.addTabViewItem(general)
        tabView.addTabViewItem(displays)
        tabView.addTabViewItem(about)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = root
        root.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: root.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let toolbar = NSToolbar(identifier: "CandelaSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(Tab.general.rawValue)
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 640, height: 500))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func reload() {
        generalView?.reload()
        displaysView?.reload()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            NSToolbarItem.Identifier(Tab.general.rawValue),
            NSToolbarItem.Identifier(Tab.displays.rawValue),
            NSToolbarItem.Identifier(Tab.about.rawValue),
        ]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(selectTab(_:))
        switch itemIdentifier.rawValue {
        case Tab.general.rawValue:
            item.label = String(localized: "General")
            item.image = CandelaChrome.symbol("slider.horizontal.3", size: 16)
        case Tab.displays.rawValue:
            item.label = String(localized: "Displays")
            item.image = CandelaChrome.symbol("display", size: 16)
        case Tab.about.rawValue:
            item.label = String(localized: "About")
            item.image = CandelaChrome.symbol("info.circle", size: 16)
        default:
            return nil
        }
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        tabView.selectTabViewItem(withIdentifier: sender.itemIdentifier.rawValue)
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
    }
}
