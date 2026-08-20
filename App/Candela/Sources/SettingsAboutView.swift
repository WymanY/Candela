import AppKit

@MainActor
final class SettingsAboutView: NSView {
    private let session: DisplaySessionController
    private let versionLabel = CandelaChrome.makeCaption()

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 480))

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 14
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let name = CandelaChrome.makeTitle(localizedText("Candela"), size: 26, weight: .semibold)
        name.alignment = .center
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        versionLabel.stringValue = "\(short) (\(build))"
        versionLabel.alignment = .center
        versionLabel.toolTip = localizedText("Option-click to copy a debug dump")

        let blurb = CandelaChrome.makeCaption(localizedText("Menu-bar brightness for every display."))
        blurb.alignment = .center
        blurb.font = .systemFont(ofSize: 13, weight: .medium)

        let column = NSStackView(views: [icon, name, versionLabel, blurb])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 8
        column.setCustomSpacing(14, after: icon)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
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
        let dump = session.debugDump(redact: !debugEnv)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dump, forType: .string)
        let logs = (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true))
            .appendingPathComponent("Logs/Candela", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try? dump.write(to: logs.appendingPathComponent("last-dump.txt"), atomically: true, encoding: .utf8)
    }
}
