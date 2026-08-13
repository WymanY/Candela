import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let session: DisplaySessionController
    private let statusItem: NSStatusItem
    private let panelController: StatusPanelController
    private let settingsController: SettingsWindowController
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(session: DisplaySessionController) {
        self.session = session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panelController = StatusPanelController(session: session)
        self.settingsController = SettingsWindowController(session: session)
        super.init()
        settingsController.onClose = { [weak self] in
            self?.settingsDidClose()
        }
        session.onChange = { [weak self] in
            self?.panelController.reload()
        }
        configureButton()
        installMonitors()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func revealPanelIfNeeded() {
        if !session.settings.hasOpenedPanelOnce {
            showPanel()
            session.markPanelOpenedOnce()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = statusImage(filled: false)
        button.image?.isTemplate = true
        button.toolTip = String(localized: "Candela")
        button.target = self
        button.action = #selector(statusButtonActivated(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonActivated(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        if type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePanel()
    }

    private func togglePanel() {
        if panelController.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        panelController.show(relativeTo: button)
        statusItem.button?.image = statusImage(filled: true)
    }

    private func hidePanel() {
        panelController.hide()
        statusItem.button?.image = statusImage(filled: false)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        hidePanel()
        NSApp.setActivationPolicy(.regular)
        settingsController.showWindow(nil)
        settingsController.window?.center()
        settingsController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func settingsDidClose() {
        if !panelController.panel.isKeyWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dismissIfOutside()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                if self.panelController.isVisible {
                    self.panelController.noteMouseDown()
                    if !self.isEventOnStatusButton() && !self.panelController.containsMouse() {
                        self.hidePanel()
                    }
                }
            } else if event.type == .keyDown,
                      event.keyCode == 53,
                      self.panelController.isVisible
            {
                self.hidePanel()
                return nil
            }
            return event
        }
    }

    private func dismissIfOutside() {
        guard panelController.isVisible else { return }
        if isEventOnStatusButton() || panelController.containsMouse() {
            return
        }
        hidePanel()
    }

    private func isEventOnStatusButton() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let buttonScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonScreen.contains(NSEvent.mouseLocation)
    }

    private func statusImage(filled: Bool) -> NSImage? {
        let name = filled ? "sun.max.fill" : "sun.max"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: String(localized: "Candela"))
        image?.isTemplate = true
        return image
    }
}
