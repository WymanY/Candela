import AppKit

@MainActor
final class SettingsGeneralView: NSView {
    private let session: DisplaySessionController
    private let softwareDimming: NSButton

    init(session: DisplaySessionController) {
        self.session = session
        softwareDimming = NSButton(
            checkboxWithTitle: String(localized: "Software dimming"),
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 260))
        softwareDimming.target = self
        softwareDimming.action = #selector(softwareDimmingChanged(_:))
        softwareDimming.state = session.settings.softwareDimmingEnabled ? .on : .off
        softwareDimming.translatesAutoresizingMaskIntoConstraints = false
        addSubview(softwareDimming)
        NSLayoutConstraint.activate([
            softwareDimming.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            softwareDimming.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            softwareDimming.topAnchor.constraint(equalTo: topAnchor, constant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func softwareDimmingChanged(_ sender: NSButton) {
        var next = session.settings
        next.softwareDimmingEnabled = sender.state == .on
        session.saveSettings(next)
    }
}
