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
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BootLog.write("didFinish")
        terminateExtraInstances()
        let session = DisplaySessionController.makeDefault()
        self.session = session
        statusItem = StatusItemController(session: session)
        installApplicationMenu()
        statusItem?.revealOnLaunch()
        session.start()
        controlServer = ControlServer { [weak session] request in
            guard let session else { return .failure("Candela is shutting down.") }
            var response: ControlResponse?
            DispatchQueue.main.sync {
                response = session.handleControl(request)
            }
            return response ?? .failure("Control request failed.")
        }
        controlServer?.start()
        log.info("launched; status item installed")
        BootLog.write("status item installed")
        #if !DEBUG
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.info("reopen hasVisibleWindows=\(flag, privacy: .public)")
        statusItem?.showMainUI()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) == false {
            statusItem?.showMainUI()
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(StatusItemController.openSettings),
            keyEquivalent: ""
        )
        settings.target = statusItem
        menu.addItem(settings)
        return menu
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
        let settings = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(StatusItemController.openSettings),
            keyEquivalent: ","
        )
        settings.target = statusItem
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(
            title: String(localized: "Hide Candela"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hide)
        let quit = NSMenuItem(
            title: String(localized: "Quit Candela"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func terminateExtraInstances() {
        // A later launch used to force-kill every other Candela, including the
        // instance Xcode was debugging. That shows up as SIGTERM on NSApplicationMain.
        if ProcessInfo.processInfo.isDebuggerAttached {
            BootLog.write("skip terminate extras; debugger attached")
            return
        }
        let mine = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "app.candela.macos")
        where app.processIdentifier != mine {
            if ProcessInfo.processInfo.isDebuggerAttached(to: app.processIdentifier) {
                log.info("leaving debugged instance pid=\(app.processIdentifier, privacy: .public)")
                BootLog.write("leave debugged pid=\(app.processIdentifier)")
                continue
            }
            log.info("terminating extra instance pid=\(app.processIdentifier, privacy: .public)")
            BootLog.write("terminate extra pid=\(app.processIdentifier)")
            app.forceTerminate()
        }
    }
}

private extension ProcessInfo {
    var isDebuggerAttached: Bool {
        isDebuggerAttached(to: processIdentifier)
    }

    func isDebuggerAttached(to pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size >= MemoryLayout<kinfo_proc>.stride else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

enum BootLog {
    static func write(_ line: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Candela", isDirectory: true)
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
