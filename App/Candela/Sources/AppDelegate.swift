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
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BootLog.write("didFinish")
        let session = DisplaySessionController.makeDefault()
        self.session = session
        statusItem = StatusItemController(session: session)
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
