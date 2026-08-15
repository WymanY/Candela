import AppKit
import DisplayCore

@MainActor
final class StatusPanelView: NSView {
    private let session: DisplaySessionController
    private let effectView = CandelaChrome.makeBackdrop()
    private let accentBar = CandelaChrome.makeAccentBar()
    private let content = NSView()
    private let header = NSView()
    private let titleLabel = CandelaChrome.makeTitle(String(localized: "Candela"), size: 14, weight: .semibold)
    private let markView = CandelaChrome.makeSymbol("sun.max.fill", size: 14)
    private let presets = NSSegmentedControl(
        labels: [
            String(localized: "Night"),
            String(localized: "Desk"),
            String(localized: "Max"),
        ],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let rowsStack = NSStackView()
    private let speakerRow = SpeakerRowView()
    private let speakerTop: NSLayoutConstraint
    private let speakerCollapsedHeight: NSLayoutConstraint
    private let footer = NSView()
    private var rows: [DisplayRowView] = []
    private var rowKeys: [String] = []
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init(session: DisplaySessionController) {
        self.session = session
        speakerTop = speakerRow.topAnchor.constraint(equalTo: rowsStack.bottomAnchor, constant: 8)
        speakerCollapsedHeight = speakerRow.heightAnchor.constraint(equalToConstant: 0)
        speakerCollapsedHeight.priority = .required
        super.init(frame: NSRect(x: 0, y: 0, width: CandelaChrome.panelWidth, height: 196))
        userInterfaceLayoutDirection = .leftToRight
        CandelaChrome.applyPanelSurface(self)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.userInterfaceLayoutDirection = .leftToRight
        effectView.addSubview(content)

        configureHeader()
        configurePresets()
        configureRows()
        configureFooter()

        let bottom = content.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: CandelaChrome.contentInsets.left),
            content.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -CandelaChrome.contentInsets.right),
            content.topAnchor.constraint(equalTo: accentBar.bottomAnchor, constant: CandelaChrome.contentInsets.top),
            content.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -CandelaChrome.contentInsets.bottom),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.topAnchor.constraint(equalTo: content.topAnchor),
            presets.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            presets.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            presets.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            rowsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: presets.bottomAnchor, constant: 8),
            speakerRow.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            speakerRow.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            speakerTop,
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.topAnchor.constraint(equalTo: speakerRow.bottomAnchor, constant: 8),
            bottom,
            widthAnchor.constraint(equalToConstant: CandelaChrome.panelWidth),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var fittingSize: NSSize {
        NSSize(width: CandelaChrome.panelWidth, height: measuredHeight)
    }

    private var measuredHeight: CGFloat {
        let rowsHeight = max(rowsStack.fittingSize.height, rows.isEmpty ? 20 : 56)
        let speakerHeight = speakerRow.isHidden ? 0 : max(speakerRow.fittingSize.height, 56) + 8
        return 3
            + CandelaChrome.contentInsets.top
            + 20
            + 8
            + 28
            + 8
            + rowsHeight
            + speakerHeight
            + 8
            + 28
            + CandelaChrome.contentInsets.bottom
    }

    func reload(_ snapshots: [DisplaySnapshot]) {
        let keys = snapshots.map(\.id.persistentKey)
        if keys == rowKeys, rows.count == snapshots.count, !rows.isEmpty {
            for (row, snapshot) in zip(rows, snapshots) {
                row.apply(snapshot, showPercent: session.settings.showPercentText, showMatchAll: snapshots.count > 1)
            }
            applySpeaker()
            syncPresetSelection(with: snapshots)
            return
        }
        rowKeys = keys
        rows.removeAll()
        rowsStack.arrangedSubviews.forEach { rowsStack.removeArrangedSubview($0); $0.removeFromSuperview() }

        if snapshots.isEmpty {
            let empty = CandelaChrome.makeCaption(String(localized: "No Displays"))
            empty.alignment = .left
            empty.font = .systemFont(ofSize: 13, weight: .medium)
            rowsStack.addArrangedSubview(empty)
            applySpeaker()
            syncPresetSelection(with: snapshots)
            return
        }

        for snapshot in snapshots {
            let row = DisplayRowView()
            let key = snapshot.id.persistentKey
            row.onBrightness = { [weak self] value in
                guard let self else { return }
                self.session.setBrightness(key: key, value: value)
                self.syncPresetSelection(with: self.session.snapshots)
            }
            row.onContrast = { [weak self] value in
                self?.session.setContrast(key: key, value: value)
            }
            row.onInput = { [weak self] source in
                self?.session.setInput(key: key, source: source)
            }
            row.onRotation = { [weak self] rotation in
                self?.session.setRotation(key: key, rotation: rotation)
            }
            row.onPictureInPicture = { [weak self] in
                self?.session.togglePictureInPicture(key: key)
            }
            row.onPreset = { [weak self] preset in
                self?.session.applyPreset(preset, key: key)
            }
            row.onMatchAll = { [weak self] in
                guard let self else { return }
                self.session.matchAll(to: key)
                self.syncPresetSelection(with: self.session.snapshots)
            }
            row.apply(snapshot, showPercent: session.settings.showPercentText, showMatchAll: snapshots.count > 1)
            row.translatesAutoresizingMaskIntoConstraints = false
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rows.append(row)
        }
        applySpeaker()
        syncPresetSelection(with: snapshots)
    }

    private func applySpeaker() {
        speakerRow.apply(session.speaker, choices: session.speakerChoices, showPercent: session.settings.showPercentText)
        speakerCollapsedHeight.isActive = speakerRow.isHidden
        speakerTop.constant = speakerRow.isHidden ? 0 : 8
    }

    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.userInterfaceLayoutDirection = .leftToRight
        content.addSubview(header)

        markView.contentTintColor = CandelaChrome.accent
        markView.setContentHuggingPriority(.required, for: .horizontal)
        markView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .natural
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(markView)
        header.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 20),
            markView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            markView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: markView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
        ])
    }

    private func configurePresets() {
        presets.translatesAutoresizingMaskIntoConstraints = false
        presets.segmentStyle = .rounded
        presets.controlSize = .regular
        presets.font = .systemFont(ofSize: 12, weight: .medium)
        presets.trackingMode = .selectOne
        presets.target = self
        presets.action = #selector(presetClicked(_:))
        presets.selectedSegment = -1
        if #available(macOS 11.0, *) {
            presets.segmentDistribution = .fillEqually
        }
        content.addSubview(presets)
        presets.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func configureRows() {
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.distribution = .fill
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.setContentHuggingPriority(.defaultLow, for: .vertical)
        rowsStack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        content.addSubview(rowsStack)

        speakerRow.translatesAutoresizingMaskIntoConstraints = false
        speakerRow.onVolume = { [weak self] value in
            self?.session.setSpeakerVolume(value)
        }
        speakerRow.onMute = { [weak self] muted in
            self?.session.setSpeakerMuted(muted)
        }
        speakerRow.onSelect = { [weak self] uid in
            self?.session.setDefaultSpeaker(uid: uid)
        }
        content.addSubview(speakerRow)
    }

    private func configureFooter() {
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        let line = CandelaChrome.makeHairline()
        let settingsButton = CandelaChrome.makeQuietButton(title: String(localized: "Settings…"), symbolName: "gearshape")
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        let quitButton = CandelaChrome.makeQuietButton(title: String(localized: "Quit"), symbolName: "power")
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(line)
        footer.addSubview(settingsButton)
        footer.addSubview(quitButton)

        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: 28),
            line.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            line.topAnchor.constraint(equalTo: footer.topAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 4),
            quitButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            quitButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
        ])
    }

    @objc private func presetClicked(_ sender: NSSegmentedControl) {
        let preset: BrightnessPreset
        switch sender.selectedSegment {
        case 0: preset = .night
        case 1: preset = .desk
        default: preset = .max
        }
        session.applyPreset(preset)
        syncPresetSelection(with: session.snapshots)
    }

    private func syncPresetSelection(with snapshots: [DisplaySnapshot]) {
        let values = snapshots.compactMap { snapshot -> Double? in
            guard snapshot.kind != .virtualUnsupported, snapshot.brightness.showsBrightnessSlider else {
                return nil
            }
            return snapshot.brightness.current
        }
        let index: Int
        if let first = values.first, values.allSatisfy({ abs($0 - first) < 0.02 }) {
            if abs(first - BrightnessPreset.night.value) < 0.02 {
                index = 0
            } else if abs(first - BrightnessPreset.desk.value) < 0.02 {
                index = 1
            } else if abs(first - BrightnessPreset.max.value) < 0.02 {
                index = 2
            } else {
                index = -1
            }
        } else {
            index = -1
        }
        highlightPreset(index)
    }

    private func highlightPreset(_ index: Int) {
        presets.selectedSegment = index
        for segment in 0..<presets.segmentCount {
            presets.setSelected(segment == index, forSegment: segment)
        }
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quitClicked() { onQuit?() }
}
