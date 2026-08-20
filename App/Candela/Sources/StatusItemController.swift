import AppKit
import os

@MainActor
final class StatusItemController: NSObject {
    private let session: DisplaySessionController
    private let statusItem: NSStatusItem
    private let panelController: StatusPanelController
    private var settingsController: SettingsWindowController
    private let guideController = MenuBarGuideController()
    private let log = Logger(subsystem: "app.candela.macos", category: "ui")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var suppressDismissUntil: Date?
    private var appliedLanguage: String

    init(session: DisplaySessionController) {
        self.session = session
        self.statusItem = Self.makeStatusItem()
        self.panelController = StatusPanelController(session: session)
        self.settingsController = SettingsWindowController(session: session)
        self.appliedLanguage = session.settings.preferredLanguage
        super.init()
        bindSettingsController()
        session.onChange = { [weak self] in
            self?.handleSessionChange()
        }
        panelController.bindActions(
            openSettings: { [weak self] in self?.openSettings() },
            quit: { [weak self] in self?.quit() }
        )
        configureButton()
        statusItem.isVisible = true
        installMonitors()
        log.info("status item created visible=\(self.statusItem.isVisible, privacy: .public)")
    }

    private static func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = false
        return item
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func revealOnLaunch() {
        showMainUI()
        presentFirstLaunchPanelIfPossible(attempt: 0)
    }

    private func presentFirstLaunchPanelIfPossible(attempt: Int) {
        guard !session.settings.hasOpenedPanelOnce else { return }
        if let button = statusItem.button, button.window != nil {
            showPanel(relativeTo: button)
            return
        }
        guard attempt < 16 else {
            showPanel(relativeTo: statusItem.button)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.presentFirstLaunchPanelIfPossible(attempt: attempt + 1)
        }
    }

    /// Dock click, first launch, and reopen all go through here.
    func showMainUI() {
        configureButton()
        statusItem.isVisible = true
        suppressDismissUntil = Date().addingTimeInterval(2)
        let button = statusItem.button
        let frame = button.map { NSStringFromRect($0.frame) } ?? "nil"
        let hasWindow = button?.window != nil
        MenuBarGuideController.writeDiagnostic(
            "visible=\(statusItem.isVisible) button=\(button != nil) frame=\(frame) window=\(hasWindow)"
        )
        log.info("status visible=\(self.statusItem.isVisible, privacy: .public) buttonWindow=\(hasWindow, privacy: .public)")
    }

    private func presentGuideIfMissing() {
        let hasWindow = statusItem.button?.window != nil
        MenuBarGuideController.writeDiagnostic("post-launch window=\(hasWindow)")
        if !hasWindow {
            guideController.present()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            log.error("configureButton: NSStatusItem.button is nil")
            return
        }
        let image = statusImage(filled: false)
        button.image = image
        button.image?.isTemplate = true
        button.title = ""
        button.imagePosition = image == nil ? .noImage : .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Candela"
        button.setAccessibilityLabel("Candela")
        button.setAccessibilityTitle("Candela")
        button.target = self
        button.action = #selector(statusButtonActivated(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.length = NSStatusItem.squareLength
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
        if panelController.isVisible, panelController.isOnscreen() {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        showPanel(relativeTo: statusItem.button)
    }

    private func showPanel(relativeTo button: NSView?) {
        panelController.show(relativeTo: button)
        statusItem.button?.image = statusImage(filled: true)
        if !session.settings.hasOpenedPanelOnce {
            session.markPanelOpenedOnce()
        }
    }

    private func hidePanel() {
        panelController.hide()
        statusItem.button?.image = statusImage(filled: false)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: localizedText("Settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: localizedText("Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func bindSettingsController() {
        settingsController.onClose = { [weak self] in
            self?.settingsDidClose()
        }
    }

    private func handleSessionChange() {
        let language = session.settings.preferredLanguage
        if language != appliedLanguage {
            appliedLanguage = language
            panelController.rebuild()
            rebuildSettingsWindow()
            session.reloadLocalizedChrome()
            (NSApp.delegate as? AppDelegate)?.reloadApplicationMenu()
        } else {
            panelController.reload()
            settingsController.reload()
        }
    }

    private func rebuildSettingsWindow() {
        let wasVisible = settingsController.window?.isVisible == true
        let selected = settingsController.window?.toolbar?.selectedItemIdentifier
        let frame = settingsController.window?.frame
        settingsController.onClose = nil
        let previous = settingsController
        let replacement = SettingsWindowController(session: session)
        settingsController = replacement
        bindSettingsController()
        if wasVisible, let frame {
            replacement.showWindow(nil)
            if let next = replacement.window {
                next.setFrame(frame, display: true)
                if let selected {
                    replacement.selectTab(identifier: selected)
                }
                next.level = .floating
                next.makeKeyAndOrderFront(nil)
                next.orderFrontRegardless()
            }
        }
        previous.window?.close()
    }

    @objc func openSettings() {
        hidePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        presentSettingsWindow()
    }

    private func presentSettingsWindow() {
        settingsController.showWindow(nil)
        guard let window = settingsController.window else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.midY - size.height / 2
                )
            )
        } else {
            window.center()
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func settingsDidClose() {
        #if !DEBUG
        if !panelController.panel.isKeyWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        #endif
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
                    if !self.shouldSuppressDismiss(),
                       !self.isEventOnStatusButton(),
                       !self.panelController.containsMouse()
                    {
                        self.hidePanel()
                    }
                }
            } else if event.type == .keyDown {
                if self.panelController.isVisible, event.keyCode == 53 {
                    self.hidePanel()
                    return nil
                }
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.charactersIgnoringModifiers == ","
                {
                    self.openSettings()
                    return nil
                }
            }
            return event
        }
    }

    private func shouldSuppressDismiss() -> Bool {
        guard let until = suppressDismissUntil else { return false }
        if Date() < until { return true }
        suppressDismissUntil = nil
        return false
    }

    private func dismissIfOutside() {
        guard panelController.isVisible else { return }
        if shouldSuppressDismiss() { return }
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
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: localizedText("Candela")
        )?.withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
