import AppKit
import DisplayCore
import os

enum MenuBarSettingsOpener {
    @discardableResult
    static func openPane() -> Bool {
        MenuBarSettings.firstOpenableURL { url in
            NSWorkspace.shared.open(url)
        } != nil
    }
}

@MainActor
final class MenuBarGuideController: NSWindowController {
    private let log = Logger(subsystem: "app.candela.macos", category: "ui")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedText("Menu Bar")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isRestorable = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.init(window: window)
        window.contentView = Self.makeContent(target: self)
        window.contentView?.layoutSubtreeIfNeeded()
        let fitting = window.contentView?.fittingSize ?? NSSize(width: 480, height: 500)
        window.setContentSize(NSSize(width: 480, height: max(fitting.height, 1)))
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
        MenuBarSettingsOpener.openPane()
    }

    private static func makeContent(target: MenuBarGuideController) -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconWell = NSView()
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 16
        iconWell.layer?.cornerCurve = .continuous
        iconWell.layer?.backgroundColor = CandelaChrome.accentSoft.cgColor
        iconWell.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = CandelaChrome.symbol("menubar.rectangle", size: 22, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = CandelaChrome.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(iconView)

        let title = wrappingLabel(
            localizedText("The menu bar icon is hidden by macOS 26."),
            font: .systemFont(ofSize: 20, weight: .semibold),
            color: .labelColor
        )
        let subtitle = wrappingLabel(
            localizedText("macOS hid Candela in Menu Bar settings. This is not a signing or privacy-permission issue."),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .secondaryLabelColor
        )

        let header = NSStackView(views: [iconWell, title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.setCustomSpacing(12, after: iconWell)
        header.translatesAutoresizingMaskIntoConstraints = false

        let pathCard = makeInfoCard(
            heading: localizedText("Turn Candela on"),
            body: localizedText("System Settings → Menu Bar → Allow in the Menu Bar → enable Candela"),
            symbolName: "checkmark.circle"
        )
        let retryCard = makeInfoCard(
            heading: localizedText("If it is already on"),
            body: localizedText("Quit Candela and open it again. If the icon is still missing, use Reset Control Center at the bottom of that page. Resetting restores every Control Center and menu bar layout."),
            symbolName: "arrow.triangle.2.circlepath"
        )
        let extrasCard = makeInfoCard(
            heading: localizedText("Menu bar managers"),
            body: localizedText("Ice, Bartender, and BetterTouchTool can also hide Candela behind their menu-bar buttons."),
            symbolName: "rectangle.3.group"
        )

        let button = NSButton(
            title: localizedText("Open Menu Bar Settings"),
            target: target,
            action: #selector(MenuBarGuideController.openSettingsPane)
        )
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.image = CandelaChrome.symbol("gearshape", size: 12, weight: .semibold)
        button.imagePosition = .imageLeading
        if #available(macOS 11.0, *) {
            button.imageHugsTitle = true
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .vertical)

        let stack = NSStackView(views: [header, pathCard, retryCard, extrasCard, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: header)
        stack.setCustomSpacing(18, after: extrasCard)
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            iconWell.widthAnchor.constraint(equalToConstant: 44),
            iconWell.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            retryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            extrasCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return root
    }

    private static func makeInfoCard(heading: String, body: String, symbolName: String) -> NSView {
        let card = CandelaChrome.makeModule()
        let icon = CandelaChrome.makeSymbol(symbolName, size: 13)
        icon.contentTintColor = CandelaChrome.accent
        let headingField = wrappingLabel(
            heading,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .labelColor
        )
        let bodyField = wrappingLabel(
            body,
            font: .systemFont(ofSize: 12, weight: .medium),
            color: .secondaryLabelColor
        )
        let texts = NSStackView(views: [headingField, bodyField])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        texts.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [icon, texts])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        CandelaChrome.pin(row, to: card, insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        return card
    }

    private static func wrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.isSelectable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}
