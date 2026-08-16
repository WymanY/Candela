import AppKit
import os

@MainActor
final class StatusItemController: NSObject {
    static let autosaveName = "CandelaMain"

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
        Self.forceSystemVisible()
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
        installMonitors()
        log.info("status item created visible=\(self.statusItem.isVisible, privacy: .public)")
    }

    /// macOS 26 stores unnamed extras as Item-N and Control Center hides them.
    /// Pin a named extra next to the clock before NSStatusItem reads autosave state.
    private static func makeStatusItem() -> NSStatusItem {
        forceSystemVisible()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.isVisible = true
        return item
    }

    private static func forceSystemVisible() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(autosaveName)")
        if defaults.object(forKey: "NSStatusItem Preferred Position \(autosaveName)") == nil {
            defaults.set(48.0, forKey: "NSStatusItem Preferred Position \(autosaveName)")
        }
        // Stale unnamed extras are stored as Item-N and Control Center hides them.
        for (key, _) in defaults.dictionaryRepresentation() {
            if key.hasPrefix("NSStatusItem Visible Item-") || key.hasPrefix("NSStatusItem VisibleCC Item-") {
                defaults.set(true, forKey: key)
            }
        }
        defaults.synchronize()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showPanelIfReady()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.presentGuideIfMissing()
        }
    }

    private func showPanelIfReady() {
        guard statusItem.button?.window != nil else { return }
        showPanel()
    }

    /// Dock click, first launch, and reopen all go through here.
    func showMainUI() {
        Self.forceSystemVisible()
        statusItem.isVisible = true
        configureButton()
        suppressDismissUntil = Date().addingTimeInterval(2)
        if !session.settings.hasOpenedPanelOnce {
            session.markPanelOpenedOnce()
        }
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
        statusItem.autosaveName = Self.autosaveName
        statusItem.isVisible = true
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
            title: String(localized: "Settings"),
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
            if settingsController.window?.isVisible == true {
                rebuildSettingsWindow()
            }
        } else {
            panelController.reload()
            settingsController.reload()
        }
    }

    private func rebuildSettingsWindow() {
        guard let window = settingsController.window, window.isVisible else { return }
        let selected = window.toolbar?.selectedItemIdentifier
        let frame = window.frame
        settingsController.onClose = nil
        let replacement = SettingsWindowController(session: session)
        settingsController = replacement
        bindSettingsController()
        replacement.showWindow(nil)
        if let next = replacement.window {
            next.setFrame(frame, display: true)
            if let selected {
                replacement.selectTab(identifier: selected)
            }
            next.makeKeyAndOrderFront(nil)
        }
        window.close()
    }

    @objc func openSettings() {
        hidePanel()
        NSApp.setActivationPolicy(.regular)
        settingsController.showWindow(nil)
        if let window = settingsController.window {
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
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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
            accessibilityDescription: String(localized: "Candela")
        )?.withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
