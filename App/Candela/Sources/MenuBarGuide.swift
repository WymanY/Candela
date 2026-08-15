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
        window.title = "Candela"
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
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Candela", isDirectory: true)
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
        let title = NSTextField(labelWithString: "菜单栏图标被 macOS 26 挡住了")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: """
        Candela 不需要辅助功能、屏幕录制或任何隐私权限。

        macOS 26 新增了一道开关：第三方状态栏图标默认不允许显示。请打开：

        系统设置 → 菜单栏 → 允许出现在菜单栏 → 打开 Candela

        打开后图标会出现在主显示器（笔记本屏幕）菜单栏右侧。外接屏菜单栏通常不会出现第三方图标。

        如果你装了 Ice / Bartender / BetterTouchTool，点它们的菜单栏按钮也能看到被收纳的 Candela。
        """)
        body.font = .systemFont(ofSize: 13)
        body.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(
            title: "打开系统设置 · 菜单栏",
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
