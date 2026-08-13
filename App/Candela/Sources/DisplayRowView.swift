import AppKit
import DisplayCore

@MainActor
final class DisplayRowView: NSView {
    var onBrightness: ((Double) -> Void)?
    var onVolume: ((Double) -> Void)?
    var onMute: ((Bool) -> Void)?

    private let nameLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let brightnessSlider = NSSlider()
    private let brightnessPercent = NSTextField(labelWithString: "")
    private let volumeSlider = NSSlider()
    private let muteButton = NSButton()
    private let brightnessRow = NSStackView()
    private let volumeRow = NSStackView()
    private let hdrNote = NSTextField(labelWithString: "")
    private var isApplying = false
    private var showPercent = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.alignment = .right

        configureSlider(brightnessSlider, action: #selector(brightnessChanged(_:)))
        configureSlider(volumeSlider, action: #selector(volumeChanged(_:)))

        brightnessPercent.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        brightnessPercent.textColor = .secondaryLabelColor
        brightnessPercent.alignment = .right
        brightnessPercent.translatesAutoresizingMaskIntoConstraints = false
        brightnessPercent.widthAnchor.constraint(equalToConstant: 36).isActive = true

        muteButton.bezelStyle = .inline
        muteButton.setButtonType(.toggle)
        muteButton.isBordered = false
        muteButton.imagePosition = .imageOnly
        muteButton.target = self
        muteButton.action = #selector(muteClicked(_:))
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let header = NSStackView(views: [nameLabel, badgeLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.distribution = .fill

        brightnessRow.orientation = .horizontal
        brightnessRow.alignment = .centerY
        brightnessRow.spacing = 8
        brightnessRow.addArrangedSubview(brightnessSlider)
        brightnessRow.addArrangedSubview(brightnessPercent)

        volumeRow.orientation = .horizontal
        volumeRow.alignment = .centerY
        volumeRow.spacing = 8
        volumeRow.addArrangedSubview(volumeSlider)
        volumeRow.addArrangedSubview(muteButton)

        hdrNote.font = .systemFont(ofSize: 10)
        hdrNote.textColor = .secondaryLabelColor
        hdrNote.lineBreakMode = .byWordWrapping
        hdrNote.maximumNumberOfLines = 2
        hdrNote.isHidden = true

        let column = NSStackView(views: [header, brightnessRow, hdrNote, volumeRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            brightnessRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            hdrNote.widthAnchor.constraint(equalTo: column.widthAnchor),
            volumeRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ snapshot: DisplaySnapshot, showPercent: Bool) {
        isApplying = true
        self.showPercent = showPercent
        nameLabel.stringValue = snapshot.name
        badgeLabel.stringValue = badgeTitle(for: snapshot)
        let unsupported = snapshot.kind == .virtualUnsupported
        nameLabel.textColor = unsupported ? .tertiaryLabelColor : .labelColor
        badgeLabel.textColor = unsupported ? .quaternaryLabelColor : .secondaryLabelColor

        let showsBrightness = !unsupported && snapshot.brightness.showsBrightnessSlider
        brightnessRow.isHidden = !showsBrightness
        if showsBrightness {
            brightnessSlider.doubleValue = snapshot.brightness.current * 100
            updateBrightnessPercent(snapshot.brightness.current)
            brightnessSlider.setAccessibilityLabel("\(String(localized: "Brightness")), \(snapshot.name)")
            brightnessSlider.setAccessibilityValueDescription(percentPhrase(snapshot.brightness.current))
        }

        let showHDR = showsBrightness && snapshot.brightness.hdrWashes
        hdrNote.isHidden = !showHDR
        if showHDR {
            hdrNote.stringValue = String(localized: "Software dimming reduces HDR contrast.")
        }

        let showsVolume = !unsupported && snapshot.volume.supportsVolume
        volumeRow.isHidden = !showsVolume
        if showsVolume {
            volumeSlider.doubleValue = snapshot.volume.current * 100
            updateMuteButton(isMuted: snapshot.volume.isMuted, name: snapshot.name)
            volumeSlider.setAccessibilityLabel("\(String(localized: "Volume")), \(snapshot.name)")
            volumeSlider.setAccessibilityValueDescription(percentPhrase(snapshot.volume.current))
        }
        isApplying = false
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        var height: CGFloat = 18
        if !brightnessRow.isHidden { height += 26 }
        if !hdrNote.isHidden { height += 16 }
        if !volumeRow.isHidden { height += 26 }
        return NSSize(width: 276, height: height)
    }

    private func configureSlider(_ slider: NSSlider, action: Selector) {
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = 50
        slider.isContinuous = true
        slider.target = self
        slider.action = action
        slider.altIncrementValue = 1
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        let value = sender.doubleValue / 100
        updateBrightnessPercent(value)
        sender.setAccessibilityValueDescription(percentPhrase(value))
        onBrightness?(value)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        let value = sender.doubleValue / 100
        sender.setAccessibilityValueDescription(percentPhrase(value))
        onVolume?(value)
    }

    @objc private func muteClicked(_ sender: NSButton) {
        let muted = sender.state == .on
        updateMuteSymbol(isMuted: muted)
        onMute?(muted)
    }

    private func updateBrightnessPercent(_ value: Double) {
        brightnessPercent.isHidden = !showPercent
        brightnessPercent.stringValue = "\(Int((value * 100).rounded()))%"
    }

    private func updateMuteButton(isMuted: Bool, name: String) {
        muteButton.state = isMuted ? .on : .off
        muteButton.setAccessibilityLabel(String(localized: "Mute"))
        muteButton.setAccessibilityHelp(name)
        updateMuteSymbol(isMuted: isMuted)
    }

    private func updateMuteSymbol(isMuted: Bool) {
        let symbol = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: String(localized: "Mute"))
    }

    private func percentPhrase(_ value: Double) -> String {
        String(format: String(localized: "%d percent"), Int((value * 100).rounded()))
    }

    private func badgeTitle(for snapshot: DisplaySnapshot) -> String {
        var title: String
        switch snapshot.kind {
        case .builtIn:
            title = String(localized: "Built-in")
        case .appleExternal:
            title = String(localized: "Apple")
        case .genericExternal:
            switch snapshot.connection {
            case .hdmi:
                title = String(localized: "HDMI")
            case .displayPort:
                title = String(localized: "DisplayPort")
            case .thunderbolt:
                title = String(localized: "Thunderbolt")
            case .usb:
                title = String(localized: "USB-C")
            default:
                title = String(localized: "External")
            }
        case .virtualUnsupported:
            title = String(localized: "Unsupported")
        }
        if snapshot.brightness.notes == "!" {
            title += " !"
        }
        return title
    }
}
