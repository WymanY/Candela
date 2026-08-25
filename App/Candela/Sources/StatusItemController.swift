import AppKit
import DisplayCore
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
    private var launchAnchorTracker = StatusItemAnchorTracker()

    /// Poll quickly while StatusKit creates and restores the autosaved status-item position,
    /// then keep a few slower samples so a visible first-launch panel follows late menu-bar moves.
    private let launchRevealDelays: [TimeInterval] = Array(repeating: 0.2, count: 10) + [1, 2, 5]

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
        // Give StatusKit one stable identity so it can restore the same item
        // position across Developer ID installs and local builds.
        item.autosaveName = "CandelaStatusItem"

        // Candela's status item is its primary UI. Do not opt into interactive
        // removal; visibility remains controlled by the macOS 26 Menu Bar
        // setting and by showMainUI().
        item.behavior.remove(.removalAllowed)
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
        launchAnchorTracker.reset()
        scheduleMenuBarReveal(attempt: 0)
    }

    private func scheduleMenuBarReveal(attempt: Int) {
        guard attempt < launchRevealDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + launchRevealDelays[attempt]) { [weak self] in
            guard let self else { return }
            self.refreshStatusItemVisibility()

            if let anchor = self.statusItemAnchor() {
                let isStable = self.launchAnchorTracker.observe(anchor.frame)
                MenuBarGuideController.writeDiagnostic(
                    "launch anchor attempt=\(attempt) screen=\(NSStringFromRect(anchor.frame)) onBar=true stable=\(isStable)"
                )

                if self.panelController.isVisible {
                    self.panelController.reposition(relativeTo: anchor.button)
                } else if !self.session.settings.hasOpenedPanelOnce, isStable {
                    self.showPanel(relativeTo: anchor.button)
                }
                self.hideDockIfMenuBarReady()
            } else {
                self.launchAnchorTracker.reset()
                MenuBarGuideController.writeDiagnostic("launch anchor attempt=\(attempt) onBar=false")
            }

            let isLastAttempt = attempt == self.launchRevealDelays.count - 1
            if isLastAttempt, !self.session.settings.hasOpenedPanelOnce {
                self.showPanel(relativeTo: nil)
            }
            if isLastAttempt, !self.isStatusItemOnScreen() {
                self.presentGuideIfMissing()
            }
            self.scheduleMenuBarReveal(attempt: attempt + 1)
        }
    }

    private func refreshStatusItemVisibility() {
        configureButton()
        statusItem.isVisible = true
    }

    private func statusItemAnchor() -> (button: NSView, frame: NSRect)? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard NSScreen.screens.contains(where: {
            StatusPanelLayout.isUsableStatusButtonFrame(frame, visible: $0.visibleFrame)
        }) else {
            return nil
        }
        return (button, frame)
    }

    private func isStatusItemOnScreen() -> Bool {
        statusItemAnchor() != nil
    }

    private func hideDockIfMenuBarReady() {
        #if !DEBUG
        if isStatusItemOnScreen(), !panelController.panel.isKeyWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        #endif
    }

    /// Dock click, first launch, and reopen all go through here.
    func showMainUI() {
        refreshStatusItemVisibility()
        suppressDismissUntil = Date().addingTimeInterval(2)
        let button = statusItem.button
        let frame = button.map { NSStringFromRect($0.frame) } ?? "nil"
        let screenFrame: String
        if let button, let window = button.window {
            screenFrame = NSStringFromRect(window.convertToScreen(button.convert(button.bounds, to: nil)))
        } else {
            screenFrame = "nil"
        }
        MenuBarGuideController.writeDiagnostic(
            "visible=\(statusItem.isVisible) button=\(button != nil) frame=\(frame) screen=\(screenFrame) onBar=\(isStatusItemOnScreen())"
        )
        log.info("status visible=\(self.statusItem.isVisible, privacy: .public) onBar=\(self.isStatusItemOnScreen(), privacy: .public)")
    }

    private func presentGuideIfMissing() {
        let window = statusItem.button?.window
        let hasWindow = window != nil
        let onScreen = isStatusItemOnScreen()
        MenuBarGuideController.writeDiagnostic("post-launch window=\(hasWindow) onScreen=\(onScreen)")
        if !onScreen {
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
        if panelController.isVisible, !session.settings.hasOpenedPanelOnce {
            session.markPanelOpenedOnce()
            BootLog.write("first-launch panel visible frame=\(NSStringFromRect(panelController.panel.frame))")
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
