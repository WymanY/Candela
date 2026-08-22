import AppKit
import ControlKit
import Darwin
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var session: DisplaySessionController?
    private var controlServer: ControlServer?
    private let log = Logger(subsystem: "app.candela.macos", category: "ui")

    func applicationWillFinishLaunching(_ notification: Notification) {
        BootLog.write("willFinish pid=\(ProcessInfo.processInfo.processIdentifier)")
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            log.error("Candela must run natively; aborting Rosetta process.")
            BootLog.write("abort rosetta")
            NSApp.terminate(nil)
            return
        }
        // Stay a regular app until the status item is actually on the menu bar.
        // Going accessory first makes macOS 26 StatusKit treat this as a background
        // process and hide the extra without listing it under Allow in the Menu Bar.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BootLog.write("didFinish")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let session = DisplaySessionController.makeDefault()
        self.session = session
        statusItem = StatusItemController(session: session)
        installApplicationMenu()
        statusItem?.revealOnLaunch()
        session.start()
        // Hop to the main actor asynchronously; a sync hop can deadlock
        // against applicationWillTerminate stopping the server.
        controlServer = ControlServer { [weak session] request, respond in
            DispatchQueue.main.async {
                guard let session else {
                    respond(.failure("Candela is shutting down."))
                    return
                }
                respond(session.handleControl(request))
            }
        }
        controlServer?.start()
        log.info("launched; status item installed")
        BootLog.write("status item installed")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.info("reopen hasVisibleWindows=\(flag, privacy: .public)")
        statusItem?.showMainUI()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.mainMenu == nil {
            installApplicationMenu()
        }
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) == false {
            statusItem?.showMainUI()
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: localizedText("Settings"),
            action: #selector(StatusItemController.openSettings),
            keyEquivalent: ""
        )
        settings.target = statusItem
        menu.addItem(settings)
        return menu
    }

    func reloadApplicationMenu() {
        installApplicationMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
        controlServer = nil
        session?.prepareToQuit()
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let about = NSMenuItem(
            title: localizedText("About Candela"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(
            title: localizedText("Settings"),
            action: #selector(StatusItemController.openSettings),
            keyEquivalent: ","
        )
        settings.target = statusItem
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(
            title: localizedText("Hide Candela"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(
            title: localizedText("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        let showAll = NSMenuItem(
            title: localizedText("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(
            title: localizedText("Quit Candela"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = menu
    }
}

enum BootLog {
    static func write(_ line: String) {
        let dir = (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true))
            .appendingPathComponent("Logs/Candela", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("boot.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url)
        {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
