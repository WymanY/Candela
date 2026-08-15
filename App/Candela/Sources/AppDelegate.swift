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
            title: String(localized: "Settings…"),
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

    private func terminateExtraInstances() {
        let mine = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "app.candela.macos")
        where app.processIdentifier != mine {
            log.info("terminating extra instance pid=\(app.processIdentifier, privacy: .public)")
            BootLog.write("terminate extra pid=\(app.processIdentifier)")
            app.forceTerminate()
        }
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
