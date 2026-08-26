import AppKit
import DisplayCore
import os
import ApplicationServices

enum MenuBarSettingsOpener {
    @discardableResult
    static func openPane() -> Bool {
        let opened = MenuBarSettings.firstOpenableURL { url in
            NSWorkspace.shared.open(url)
        } != nil
        if opened {
            MenuBarAppRowRevealer.revealIfPossible()
        }
        return opened
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

    nonisolated static func writeDiagnostic(_ line: String) {
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

private enum MenuBarAppRowRevealer {
    private static let maxAttempts = 24
    private static let retryInterval: TimeInterval = 0.25

    static func revealIfPossible() {
        if PictureInPictureEventInjector.isSandboxed { return }
        guard AXIsProcessTrusted() else {
            MenuBarGuideController.writeDiagnostic("skip Candela row reveal: accessibility not trusted")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            attempt(remaining: maxAttempts)
        }
    }

    private static func attempt(remaining: Int) {
        if revealNow() {
            MenuBarGuideController.writeDiagnostic("revealed Candela row in Menu Bar settings")
            return
        }
        guard remaining > 1 else {
            MenuBarGuideController.writeDiagnostic("could not reveal Candela row in Menu Bar settings")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) {
            attempt(remaining: remaining - 1)
        }
    }

    @discardableResult
    private static func revealNow() -> Bool {
        guard let app = settingsApp(),
              let window = firstWindow(of: app.processIdentifier),
              let row = preferredRow(in: window)
        else { return false }
        if let scrollArea = nearestContentScrollArea(from: row) {
            jump(row, in: scrollArea)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        AXUIElementSetAttributeValue(row, kAXFocusedAttribute as CFString, kCFBooleanTrue as CFTypeRef)
        let visible = isVisible(row, in: window)
        if let rowFrame = frame(of: row), let windowFrame = frame(of: window) {
            MenuBarGuideController.writeDiagnostic(
                "Candela row visible=\(visible) row=\(NSStringFromRect(rowFrame)) window=\(NSStringFromRect(windowFrame))"
            )
        }
        return visible
    }

    private static func settingsApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
            ?? NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "System Settings" })
    }

    private static func appRowNames() -> Set<String> {
        var names = Set<String>(["Candela"])
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
            names.insert(displayName)
        }
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
            names.insert(bundleName)
        }
        return names
    }

    private static func firstWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = attributeValue(app, kAXWindowsAttribute as String) as? [AXUIElement] else { return nil }
        let titles = ["Menu Bar", "菜单栏"]
        return windows.first { window in
            titles.contains(stringValue(window, kAXTitleAttribute as String) ?? "")
        } ?? windows.first
    }

    private static func preferredRow(in root: AXUIElement) -> AXUIElement? {
        let names = appRowNames()
        var labels: [AXUIElement] = []
        var stack = [root]
        while let current = stack.popLast() {
            if stringValue(current, kAXRoleAttribute as String) == "AXStaticText",
               let value = stringValue(current, kAXValueAttribute as String),
               names.contains(value)
            {
                labels.append(current)
            }
            stack.append(contentsOf: children(of: current))
        }
        labels.sort { lhs, rhs in
            (frame(of: lhs)?.minY ?? 0) < (frame(of: rhs)?.minY ?? 0)
        }
        guard !labels.isEmpty else { return nil }

        func checkbox(for label: AXUIElement) -> AXUIElement? {
            if let linked = attributeValue(label, "AXServesAsTitleForUIElements") as? [AXUIElement],
               let checkbox = linked.first
            {
                return checkbox
            }
            guard let parent = parent(of: label) else { return nil }
            let siblings = children(of: parent)
            if let index = siblings.firstIndex(where: { CFEqual($0, label) }),
               index + 1 < siblings.count,
               stringValue(siblings[index + 1], kAXRoleAttribute as String) == "AXCheckBox"
            {
                return siblings[index + 1]
            }
            return nil
        }

        let labeled = labels.map { label in (label, checkbox(for: label)) }
        if let off = labeled.first(where: { numberValue($0.1) == 0 }) {
            return off.1 ?? off.0
        }
        return labeled.first?.1 ?? labeled.first?.0
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attributeValue(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private static func attributeValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        attributeValue(element, attribute) as? String
    }

    private static func numberValue(_ element: AXUIElement?) -> Int? {
        guard let element else { return nil }
        if let number = attributeValue(element, kAXValueAttribute as String) as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        attributeValue(element, kAXParentAttribute as String) as! AXUIElement?
    }

    private static func frame(of element: AXUIElement) -> NSRect? {
        guard let positionValue = attributeValue(element, kAXPositionAttribute as String),
              let sizeValue = attributeValue(element, kAXSizeAttribute as String)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return NSRect(origin: position, size: size)
    }

    private static func sizeValue(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = attributeValue(element, attribute) else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    private static func isVisible(_ row: AXUIElement, in window: AXUIElement) -> Bool {
        guard let rowFrame = frame(of: row), let windowFrame = frame(of: window) else { return false }
        return windowFrame.insetBy(dx: 8, dy: 36).intersects(rowFrame)
    }

    private static func nearestContentScrollArea(from row: AXUIElement) -> AXUIElement? {
        var current = parent(of: row)
        while let element = current {
            if stringValue(element, kAXRoleAttribute as String) == "AXScrollArea",
               (frame(of: element)?.size.width ?? 0) > 300
            {
                return element
            }
            current = parent(of: element)
        }
        return nil
    }

    private static func verticalScrollBar(in scrollArea: AXUIElement) -> AXUIElement? {
        if let bar = attributeValue(scrollArea, "AXVerticalScrollBar") as! AXUIElement? {
            return bar
        }
        return children(of: scrollArea).first { child in
            stringValue(child, kAXRoleAttribute as String) == "AXScrollBar"
                && (frame(of: child)?.size.height ?? 0) > 100
        }
    }

    private static func scrollBarValue(_ scrollBar: AXUIElement) -> CGFloat {
        if let number = attributeValue(scrollBar, kAXValueAttribute as String) as? NSNumber {
            return CGFloat(truncating: number)
        }
        return 0
    }

    private static func jump(_ row: AXUIElement, in scrollArea: AXUIElement) {
        guard let bar = verticalScrollBar(in: scrollArea),
              let areaFrame = frame(of: scrollArea),
              let rowFrame = frame(of: row)
        else { return }
        let contentHeight = sizeValue(scrollArea, "AXContentSize")?.height ?? areaFrame.height
        let travel = max(contentHeight - areaFrame.height, 1)
        let current = scrollBarValue(bar)
        let rowAtZero = rowFrame.minY + current * travel
        let targetY = areaFrame.minY + min(220, areaFrame.height * 0.32)
        let value = min(max((rowAtZero - targetY) / travel, 0), 1)
        AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: Double(value)))
    }
}
