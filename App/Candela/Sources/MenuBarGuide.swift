import AppKit
import os

/// macOS 26+ gates third-party `NSStatusItem`s behind
/// System Settings → Menu Bar → Allow in the Menu Bar.
/// There is no public API to flip that switch.
enum MenuBarSettings {
    static let paneURLs = [
        "x-apple.systempreferences:com.apple.MenuBar-Settings.extension",
        "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
    ]

    @discardableResult
    static func openPane() -> Bool {
        for raw in paneURLs {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return true
            }
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            return NSWorkspace.shared.open(url)
        }
        return false
    }
}

@MainActor
final class MenuBarGuideController: NSWindowController {
    private let log = Logger(subsystem: "app.candela.macos", category: "ui")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedText("Candela")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isRestorable = false
        self.init(window: window)
        window.contentView = Self.makeContent(target: self)
    }

    func present() {
        guard let window else { return }
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
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        log.info("presented menu-bar guide")
        Self.writeDiagnostic("presented guide")
    }

    static func writeDiagnostic(_ line: String) {
        let dir = (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true))
            .appendingPathComponent("Logs/Candela", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("status-item.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    @objc private func openSettingsPane() {
        MenuBarSettings.openPane()
    }

    private static func makeContent(target: MenuBarGuideController) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 340))
        let title = NSTextField(labelWithString: localizedText("The menu bar icon is hidden by macOS 26."))
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: localizedText("""
        Candela does not need Accessibility, Screen Recording, or other privacy permissions.

        macOS 26 added a switch that hides third-party status items by default. Open:

        System Settings → Menu Bar → Allow in the Menu Bar → enable Candela

        The icon then appears on the right side of the built-in display menu bar. External-display menu bars usually do not show third-party icons.

        If you use Ice, Bartender, or BetterTouchTool, their menu-bar buttons can also reveal a hidden Candela item.
        """))
        body.font = .systemFont(ofSize: 13)
        body.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(
            title: localizedText("Open System Settings · Menu Bar"),
            target: target,
            action: #selector(MenuBarGuideController.openSettingsPane)
        )
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(body)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            button.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 20),
            button.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
        ])
        return view
    }
}
