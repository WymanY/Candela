import AppKit
import Darwin
import os

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var session: DisplaySessionController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            Logger(subsystem: "app.candela.macos", category: "ui")
                .error("Candela must run natively; aborting Rosetta process.")
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let session = DisplaySessionController.makeDefault()
        self.session = session
        statusItem = StatusItemController(session: session)
        session.start()
        statusItem?.revealPanelIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.prepareToQuit()
    }
}
