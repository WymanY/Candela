import AppKit
import DisplayCore

@MainActor
final class SpeakerRowView: NSView {
    var onVolume: ((Double) -> Void)?
    var onMute: ((Bool) -> Void)?
    var onSelect: ((String) -> Void)?

    private let module = CandelaChrome.makeModule()
    private let nameLabel = CandelaChrome.makeTitle("")
    private let metaLabel = CandelaChrome.makeMeta()
    private let outputPopup = NSPopUpButton()
    private let volumeIcon = CandelaChrome.makeSymbol("speaker.wave.2")
    private let volumeSlider: CandelaSlider
    private let volumePercent = CandelaChrome.makePercent()
    private let muteButton: NSButton
    private let volumeRow = NSStackView()
    private let volumeNote = CandelaChrome.makeCaption()
    private let column = NSStackView()
    private var isApplying = false
    private var showPercent = true
    private var isMuted = false

    override init(frame frameRect: NSRect) {
        volumeSlider = CandelaChrome.makeSlider()
        muteButton = CandelaChrome.makeIconButton(
            symbolName: "speaker.slash",
            help: String(localized: "Mute")
        )
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        muteButton.setButtonType(.pushOnPushOff)

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        muteButton.target = self
        muteButton.action = #selector(muteClicked(_:))

        outputPopup.controlSize = .small
        outputPopup.font = .systemFont(ofSize: 11, weight: .medium)
        outputPopup.target = self
        outputPopup.action = #selector(outputChanged(_:))
        outputPopup.setContentHuggingPriority(.required, for: .horizontal)
        outputPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        outputPopup.setAccessibilityLabel(String(localized: "Output"))

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let identity = NSStackView(views: [nameLabel, metaLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2
        identity.setHuggingPriority(.defaultLow, for: .horizontal)
        identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [identity, outputPopup])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8
        header.setHuggingPriority(.defaultHigh, for: .vertical)

        let trailing = NSStackView(views: [volumePercent, muteButton])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 4
        configureControlRow(volumeRow, icon: volumeIcon, slider: volumeSlider, trailing: trailing)

        volumeNote.maximumNumberOfLines = 2
        volumeNote.isHidden = true

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.addArrangedSubview(header)
        column.addArrangedSubview(volumeRow)
        column.addArrangedSubview(volumeNote)

        addSubview(module)
        CandelaChrome.pin(module, to: self, insets: .init(top: 0, left: 0, bottom: 0, right: 0))
        CandelaChrome.pin(column, to: module, insets: CandelaChrome.moduleInsets)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            volumeRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            volumeNote.widthAnchor.constraint(equalTo: column.widthAnchor),
            outputPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 168),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ speaker: SpeakerOutput?, choices: [SpeakerChoice], showPercent: Bool) {
        isApplying = true
        self.showPercent = showPercent
        guard let speaker else {
            isHidden = true
            isApplying = false
            invalidateIntrinsicContentSize()
            return
        }

        isHidden = false
        nameLabel.stringValue = speaker.name
        metaLabel.stringValue = String(localized: "Current output")
        reloadChoices(choices, selectedUID: speaker.uid)

        let showsVolume = speaker.volume.supportsVolume
        volumeRow.isHidden = !showsVolume
        muteButton.isHidden = !showsVolume
        volumePercent.isHidden = !showsVolume
        if showsVolume {
            volumeSlider.doubleValue = speaker.volume.current * 100
            updateVolumePercent(speaker.volume.current)
            applyMutedAppearance(isMuted: speaker.volume.isMuted, name: speaker.name)
            volumeSlider.setAccessibilityLabel("\(String(localized: "Volume")), \(speaker.name)")
            volumeSlider.setAccessibilityValueDescription(percentPhrase(speaker.volume.current))
        } else {
            applyMutedAppearance(isMuted: false, name: speaker.name)
        }

        let showSoftwareVolume = showsVolume && speaker.volume.backend == .software
        volumeNote.isHidden = !showSoftwareVolume
        if showSoftwareVolume {
            volumeNote.stringValue = String(localized: "Software volume for the current output.")
        }
        isApplying = false
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        let width = CandelaChrome.panelWidth - CandelaChrome.contentInsets.left - CandelaChrome.contentInsets.right
        let height = max(column.fittingSize.height + CandelaChrome.moduleInsets.top + CandelaChrome.moduleInsets.bottom, 56)
        return NSSize(width: width, height: height)
    }

    private func reloadChoices(_ choices: [SpeakerChoice], selectedUID: String?) {
        outputPopup.removeAllItems()
        let canSwitch = choices.count > 1
        outputPopup.isHidden = !canSwitch
        outputPopup.isEnabled = canSwitch
        guard canSwitch else { return }

        for choice in choices {
            outputPopup.addItem(withTitle: choice.name)
            outputPopup.lastItem?.representedObject = choice.uid
            outputPopup.lastItem?.toolTip = choice.name
        }
        if let selectedUID,
           let index = choices.firstIndex(where: { $0.uid == selectedUID })
        {
            outputPopup.selectItem(at: index)
        } else if let selectedUID {
            outputPopup.addItem(withTitle: nameLabel.stringValue)
            outputPopup.lastItem?.representedObject = selectedUID
            outputPopup.select(outputPopup.lastItem)
        }
    }

    private func configureControlRow(_ row: NSStackView, icon: NSView, slider: NSSlider, trailing: NSView) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(icon)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(trailing)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        let value = sender.doubleValue / 100
        updateVolumePercent(value)
        sender.setAccessibilityValueDescription(percentPhrase(value))
        if isMuted {
            applyMutedAppearance(isMuted: false, name: nameLabel.stringValue)
            onMute?(false)
        }
        onVolume?(value)
    }

    @objc private func muteClicked(_ sender: NSButton) {
        applyMutedAppearance(isMuted: sender.state == .on, name: nameLabel.stringValue)
        onMute?(isMuted)
    }

    @objc private func outputChanged(_ sender: NSPopUpButton) {
        guard !isApplying, let uid = sender.selectedItem?.representedObject as? String else { return }
        onSelect?(uid)
    }

    private func updateVolumePercent(_ value: Double) {
        volumePercent.isHidden = false
        volumePercent.stringValue = "\(Int((value * 100).rounded()))%"
    }

    private func applyMutedAppearance(isMuted: Bool, name: String) {
        self.isMuted = isMuted
        muteButton.state = isMuted ? .on : .off
        muteButton.toolTip = isMuted ? String(localized: "Unmute") : String(localized: "Mute")
        muteButton.setAccessibilityLabel(isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
        muteButton.setAccessibilityHelp(name)
        muteButton.wantsLayer = true
        muteButton.layer?.cornerRadius = 7
        muteButton.layer?.cornerCurve = .continuous
        muteButton.layer?.backgroundColor = isMuted
            ? CandelaChrome.accentSoft.cgColor
            : NSColor.clear.cgColor
        muteButton.contentTintColor = isMuted ? CandelaChrome.accent : .secondaryLabelColor
        muteButton.image = CandelaChrome.symbol(isMuted ? "speaker.slash.fill" : "speaker.slash", size: 13)
        volumeIcon.image = CandelaChrome.symbol("speaker.wave.2", size: CandelaChrome.iconSize)
        volumeIcon.contentTintColor = isMuted ? .tertiaryLabelColor : .secondaryLabelColor
        volumeSlider.appearsMuted = isMuted
        volumeSlider.alphaValue = 1
        volumePercent.textColor = isMuted ? .tertiaryLabelColor : .secondaryLabelColor
        metaLabel.textColor = isMuted ? CandelaChrome.accent : .secondaryLabelColor
        metaLabel.stringValue = isMuted
            ? String(localized: "Muted · Current output")
            : String(localized: "Current output")
    }

    private func percentPhrase(_ value: Double) -> String {
        String(format: String(localized: "%d percent"), Int((value * 100).rounded()))
    }
}
