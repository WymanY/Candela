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

    private let card = NSView()
    private let iconView = NSImageView()
    private let titleLabel = CandelaChrome.makeTitle(
        localizedText("Screen Recording is required"),
        size: 15,
        weight: .semibold
    )
    private let bodyLabel = NSTextField(wrappingLabelWithString: localizedText(
        "Enable Candela in System Settings to use Picture in Picture and Display Overview."
    ))
    private let pathLabel = NSTextField(wrappingLabelWithString: localizedText(
        "System Settings → Privacy & Security → Screen Recording"
    ))
    private let openButton = NSButton(
        title: localizedText("Open System Settings"),
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        configureCard()
        addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            card.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 20),
            card.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadLocalizedChrome() {
        titleLabel.stringValue = localizedText("Screen Recording is required")
        bodyLabel.stringValue = localizedText(
            "Enable Candela in System Settings to use Picture in Picture and Display Overview."
        )
        pathLabel.stringValue = localizedText(
            "System Settings → Privacy & Security → Screen Recording"
        )
        openButton.title = localizedText("Open System Settings")
        openButton.toolTip = localizedText("Open System Settings · Screen Recording")
        openButton.setAccessibilityLabel(openButton.toolTip)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    override func mouseDown(with event: NSEvent) {
        openSettings()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func configureCard() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 0.96).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = CandelaChrome.symbol("record.circle", size: 22, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = CandelaChrome.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureWrappingLabel(
            bodyLabel,
            font: .systemFont(ofSize: 12, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.82)
        )
        configureWrappingLabel(
            pathLabel,
            font: .systemFont(ofSize: 11, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.58)
        )

        openButton.bezelStyle = .rounded
        openButton.isBordered = false
        openButton.font = .systemFont(ofSize: 13, weight: .semibold)
        openButton.contentTintColor = .black
        openButton.image = CandelaChrome.symbol("gearshape", size: 12, weight: .semibold)
        openButton.imagePosition = .imageLeading
        if #available(macOS 11.0, *) {
            openButton.imageHugsTitle = true
        }
        openButton.wantsLayer = true
        openButton.layer?.cornerRadius = 8
        openButton.layer?.cornerCurve = .continuous
        openButton.layer?.backgroundColor = CandelaChrome.accent.cgColor
        openButton.target = self
        openButton.action = #selector(openSettings)
        openButton.toolTip = localizedText("Open System Settings · Screen Recording")
        openButton.setAccessibilityLabel(openButton.toolTip)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconView)
        card.addSubview(titleLabel)
        card.addSubview(bodyLabel)
        card.addSubview(pathLabel)
        card.addSubview(openButton)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            openButton.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 16),
            openButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            openButton.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 20),
            openButton.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -20),
            openButton.heightAnchor.constraint(equalToConstant: 32),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 188),
            openButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
    }

    private func configureWrappingLabel(_ field: NSTextField, font: NSFont, color: NSColor) {
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 3
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}
