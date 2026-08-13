import AppKit

@MainActor
final class SettingsAboutView: NSView {
    private let session: DisplaySessionController
    private let versionLabel = NSTextField(labelWithString: "")

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 260))

        let name = NSTextField(labelWithString: String(localized: "Candela"))
        name.font = .systemFont(ofSize: 18, weight: .semibold)
        name.translatesAutoresizingMaskIntoConstraints = false

        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        versionLabel.stringValue = "\(short) (\(build))"
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.toolTip = String(localized: "Option-click to copy a debug dump")

        let notice = NSTextField(wrappingLabelWithString: String(localized: "Not affiliated with BetterDisplay."))
        notice.textColor = .tertiaryLabelColor
        notice.translatesAutoresizingMaskIntoConstraints = false

        addSubview(name)
        addSubview(versionLabel)
        addSubview(notice)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            versionLabel.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            versionLabel.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 6),
            notice.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            notice.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            notice.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(versionClicked(_:)))
        versionLabel.addGestureRecognizer(click)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func versionClicked(_ sender: NSClickGestureRecognizer) {
        let optionDown = NSEvent.modifierFlags.contains(.option)
            || NSApp.currentEvent?.modifierFlags.contains(.option) == true
        let debugEnv = ProcessInfo.processInfo.environment["CANDELA_DEBUG"] == "1"
        guard optionDown || debugEnv else { return }
        let redact = !debugEnv
        let dump = session.debugDump(redact: redact)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dump, forType: .string)
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Candela", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try? dump.write(to: logs.appendingPathComponent("last-dump.txt"), atomically: true, encoding: .utf8)
    }
}
