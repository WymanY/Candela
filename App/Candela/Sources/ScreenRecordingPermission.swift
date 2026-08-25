import AppKit
import CoreGraphics
import DisplayCore

enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestSystemPrompt() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func openSystemSettings() -> Bool {
        ScreenRecordingSettings.firstOpenableURL { url in
            NSWorkspace.shared.open(url)
        } != nil
    }

    static func prepareForCapturePrompt() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ScreenRecordingPermissionOverlay: NSView {
    var onOpenSettings: (() -> Void)?

    private let titleLabel = CandelaChrome.makeTitle(
        localizedText("Screen Recording is required"),
        size: 13,
        weight: .semibold
    )
    private let bodyLabel = NSTextField(wrappingLabelWithString: localizedText(
        "Candela needs Screen Recording to show Picture in Picture and Display Overview. Enable Candela in System Settings, then click the feature again."
    ))
    private let openButton = NSButton(
        title: localizedText("Open System Settings · Screen Recording"),
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.86)
        bodyLabel.alignment = .center
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.font = .systemFont(ofSize: 11, weight: .semibold)
        openButton.target = self
        openButton.action = #selector(openSettings)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(titleLabel)
        addSubview(bodyLabel)
        addSubview(openButton)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bodyLabel.topAnchor, constant: -8),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            openButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 12),
            openButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            openButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            openButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            openButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadLocalizedChrome() {
        titleLabel.stringValue = localizedText("Screen Recording is required")
        bodyLabel.stringValue = localizedText(
            "Candela needs Screen Recording to show Picture in Picture and Display Overview. Enable Candela in System Settings, then click the feature again."
        )
        openButton.title = localizedText("Open System Settings · Screen Recording")
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
