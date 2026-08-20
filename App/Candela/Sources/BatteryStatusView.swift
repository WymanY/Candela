import AppKit
import DisplayCore

@MainActor
final class BatteryStatusView: NSView {
    private let icon = CandelaChrome.makeSymbol("battery.100percent", size: 12)
    private let percentLabel = CandelaChrome.makeTitle("100%", size: 11, weight: .semibold)
    private let remainingLabel = CandelaChrome.makeCaption()
    private let stack = NSStackView()
    private var collapsedWidth: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor

        icon.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        remainingLabel.font = .systemFont(ofSize: 10, weight: .medium)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(percentLabel)
        stack.addArrangedSubview(remainingLabel)
        addSubview(stack)

        let width = widthAnchor.constraint(equalToConstant: 0)
        collapsedWidth = width

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        identifier = NSUserInterfaceItemIdentifier("battery-status")
        isHidden = true
        collapsedWidth?.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ status: PowerStatus) {
        guard status.showsInPanel else {
            isHidden = true
            collapsedWidth?.isActive = true
            toolTip = nil
            setAccessibilityElement(false)
            return
        }

        isHidden = false
        collapsedWidth?.isActive = false
        let title = PowerStatusPresentation.title(for: status)
        percentLabel.stringValue = title ?? ""
        percentLabel.isHidden = title == nil
        icon.image = CandelaChrome.symbol(PowerStatusPresentation.symbolName(for: status), size: 12)
        remainingLabel.stringValue = PowerStatusPresentation.remainingTitle(for: status) ?? ""
        remainingLabel.isHidden = remainingLabel.stringValue.isEmpty

        let low = status.showsOnBattery && (status.percent ?? 100) <= 20
        if low {
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.16).cgColor
            icon.contentTintColor = .systemRed
            percentLabel.textColor = .systemRed
            remainingLabel.textColor = .systemRed
        } else if status.showsOnPower {
            layer?.backgroundColor = CandelaChrome.accentSoft.cgColor
            icon.contentTintColor = CandelaChrome.accent
            percentLabel.textColor = CandelaChrome.accent
            remainingLabel.textColor = CandelaChrome.accent
        } else if status.isLowPowerModeEnabled {
            layer?.backgroundColor = CandelaChrome.accentSoft.cgColor
            icon.contentTintColor = CandelaChrome.accent
            percentLabel.textColor = CandelaChrome.accent
            remainingLabel.textColor = CandelaChrome.accent
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            icon.contentTintColor = .secondaryLabelColor
            percentLabel.textColor = .labelColor
            remainingLabel.textColor = .secondaryLabelColor
        }

        let help = PowerStatusPresentation.accessibilityTitle(for: status)
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(localizedText("Battery"))
        setAccessibilityValue(help)
    }
}
