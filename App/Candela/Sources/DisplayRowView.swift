import AppKit
import DisplayCore

@MainActor
final class DisplayRowView: NSView {
    var onBrightness: ((Double) -> Void)?
    var onContrast: ((Double) -> Void)?
    var onInput: ((DisplayInputSource) -> Void)?
    var onRotation: ((DisplayRotation) -> Void)?
    var onPreset: ((BrightnessPreset) -> Void)?
    var onMatchAll: (() -> Void)?

    private let module = CandelaChrome.makeModule()
    private let nameLabel = CandelaChrome.makeTitle("")
    private let metaLabel = CandelaChrome.makeMeta()
    private let matchButton: NSButton
    private let inputPopup = NSPopUpButton()
    private let rotationControl = RotationSegmentControl()

    private let brightnessIcon = CandelaChrome.makeSymbol("sun.min")
    private let brightnessSlider: NSSlider
    private let brightnessPercent = CandelaChrome.makePercent()
    private let brightnessRow = NSStackView()

    private let contrastIcon = CandelaChrome.makeSymbol("circle.lefthalf.filled")
    private let contrastSlider: NSSlider
    private let contrastPercent = CandelaChrome.makePercent()
    private let contrastRow = NSStackView()

    private let hdrNote = CandelaChrome.makeCaption()
    private let column = NSStackView()
    private var rotationRow = NSStackView()

    private var isApplying = false
    private var showPercent = true
    private var currentKey = ""

    override init(frame frameRect: NSRect) {
        matchButton = CandelaChrome.makeQuietButton(title: String(localized: "Match All"), symbolName: "square.on.square")
        brightnessSlider = CandelaChrome.makeSlider()
        contrastSlider = CandelaChrome.makeSlider()
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged(_:))
        contrastSlider.target = self
        contrastSlider.action = #selector(contrastChanged(_:))
        matchButton.target = self
        matchButton.action = #selector(matchAll)

        inputPopup.controlSize = .small
        inputPopup.font = .systemFont(ofSize: 11, weight: .medium)
        inputPopup.target = self
        inputPopup.action = #selector(inputChanged(_:))
        inputPopup.removeAllItems()
        for source in DisplayInputSource.allCases {
            inputPopup.addItem(withTitle: source.title)
            inputPopup.lastItem?.representedObject = source.rawValue
        }
        inputPopup.setContentHuggingPriority(.required, for: .horizontal)

        rotationControl.target = self
        rotationControl.action = #selector(rotationChanged(_:))
        rotationControl.setContentHuggingPriority(.required, for: .horizontal)
        rotationControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        matchButton.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let identity = NSStackView(views: [nameLabel, metaLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2
        identity.setHuggingPriority(.defaultLow, for: .horizontal)
        identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [matchButton, inputPopup])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        actions.setHuggingPriority(.required, for: .horizontal)
        let header = NSStackView(views: [identity, actions])
        header.orientation = .horizontal
        header.alignment = .top
        header.distribution = .fill
        header.spacing = 8
        header.setHuggingPriority(.defaultHigh, for: .vertical)

        configureControlRow(brightnessRow, icon: brightnessIcon, slider: brightnessSlider, trailing: brightnessPercent)
        configureControlRow(contrastRow, icon: contrastIcon, slider: contrastSlider, trailing: contrastPercent)

        hdrNote.maximumNumberOfLines = 2
        hdrNote.isHidden = true

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        let rotateIcon = CandelaChrome.makeSymbol("rotate.right")
        let rotationLabel = CandelaChrome.makeCaption(String(localized: "Rotation"))
        rotationLabel.font = .systemFont(ofSize: 11, weight: .medium)
        let rotationLeading = NSStackView(views: [rotateIcon, rotationLabel])
        rotationLeading.orientation = .horizontal
        rotationLeading.alignment = .centerY
        rotationLeading.spacing = 6
        let rotationRow = NSStackView(views: [rotationLeading, rotationControl])
        rotationRow.orientation = .horizontal
        rotationRow.alignment = .centerY
        rotationRow.distribution = .fill
        rotationRow.spacing = 8
        rotationRow.setHuggingPriority(.defaultHigh, for: .vertical)
        self.rotationRow = rotationRow

        column.addArrangedSubview(header)
        column.addArrangedSubview(brightnessRow)
        column.addArrangedSubview(hdrNote)
        column.addArrangedSubview(rotationRow)
        column.addArrangedSubview(contrastRow)

        addSubview(module)
        CandelaChrome.pin(module, to: self, insets: .init(top: 0, left: 0, bottom: 0, right: 0))
        CandelaChrome.pin(column, to: module, insets: CandelaChrome.moduleInsets)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            brightnessRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            contrastRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            hdrNote.widthAnchor.constraint(equalTo: column.widthAnchor),
            rotationRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ snapshot: DisplaySnapshot, showPercent: Bool, showMatchAll: Bool = false) {
        isApplying = true
        self.showPercent = showPercent
        currentKey = snapshot.id.persistentKey
        nameLabel.stringValue = snapshot.name
        metaLabel.stringValue = badgeTitle(for: snapshot)
        let unsupported = snapshot.kind == .virtualUnsupported
        nameLabel.textColor = unsupported ? .tertiaryLabelColor : .labelColor
        metaLabel.textColor = unsupported ? .quaternaryLabelColor : .secondaryLabelColor
        module.layer?.opacity = unsupported ? 0.72 : 1

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

        let showsContrast = !unsupported && snapshot.contrast.supportsContrast
        contrastRow.isHidden = !showsContrast
        if showsContrast {
            contrastSlider.doubleValue = snapshot.contrast.current * 100
            updateContrastPercent(snapshot.contrast.current)
            contrastSlider.setAccessibilityLabel("\(String(localized: "Contrast")), \(snapshot.name)")
        }

        let showsInput = !unsupported && snapshot.input.supportsInputSelect
        inputPopup.isHidden = !showsInput
        if showsInput, let selected = snapshot.input.current?.rawValue,
           let index = DisplayInputSource.allCases.firstIndex(where: { $0.rawValue == selected })
        {
            inputPopup.selectItem(at: index)
        }
        let showsRotation = !unsupported && snapshot.rotation.supportsRotation
        rotationRow.isHidden = !showsRotation
        rotationControl.isHidden = !showsRotation
        if showsRotation {
            rotationControl.select(snapshot.rotation.current)
            rotationControl.setAccessibilityLabel("\(String(localized: "Rotation")), \(snapshot.name)")
        }
        matchButton.isHidden = unsupported || !showMatchAll
        isApplying = false
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        let width = CandelaChrome.panelWidth - CandelaChrome.contentInsets.left - CandelaChrome.contentInsets.right
        let height = max(column.fittingSize.height + CandelaChrome.moduleInsets.top + CandelaChrome.moduleInsets.bottom, 56)
        return NSSize(width: width, height: height)
    }

    private func configureControlRow(_ row: NSStackView, icon: NSView, slider: NSSlider, trailing: NSView) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(icon)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(trailing)
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        let value = sender.doubleValue / 100
        updateBrightnessPercent(value)
        sender.setAccessibilityValueDescription(percentPhrase(value))
        onBrightness?(value)
    }

    @objc private func contrastChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        let value = sender.doubleValue / 100
        updateContrastPercent(value)
        onContrast?(value)
    }

    @objc private func inputChanged(_ sender: NSPopUpButton) {
        guard !isApplying, let raw = sender.selectedItem?.representedObject as? String,
              let source = DisplayInputSource(rawValue: raw)
        else { return }
        onInput?(source)
    }

    @objc private func rotationChanged(_ sender: RotationSegmentControl) {
        guard !isApplying else { return }
        onRotation?(sender.selectedRotation)
    }

    @objc private func matchAll() { onMatchAll?() }

    private func updateContrastPercent(_ value: Double) {
        contrastPercent.isHidden = !showPercent
        contrastPercent.stringValue = "\(Int((value * 100).rounded()))%"
    }

    private func updateBrightnessPercent(_ value: Double) {
        brightnessPercent.isHidden = !showPercent
        brightnessPercent.stringValue = "\(Int((value * 100).rounded()))%"
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


@MainActor
final class RotationSegmentControl: NSStackView {
    weak var target: AnyObject?
    var action: Selector?

    private var buttons: [NSButton] = []
    private(set) var selectedRotation: DisplayRotation = .deg0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 2
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        for rotation in DisplayRotation.allCases {
            let button = NSButton(title: "", target: self, action: #selector(selectRotation(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.image = Self.symbol(for: rotation)
            button.controlSize = .small
            button.tag = rotation.rawValue
            button.toolTip = "\(rotation.orientationTitle) (\(rotation.title))"
            button.setAccessibilityLabel(rotation.orientationTitle)
            button.setButtonType(.momentaryChange)
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.cornerCurve = .continuous
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            addArrangedSubview(button)
            buttons.append(button)
        }
        edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        select(.deg0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ rotation: DisplayRotation) {
        selectedRotation = rotation
        for button in buttons {
            let selected = button.tag == rotation.rawValue
            button.contentTintColor = selected ? .white : .secondaryLabelColor
            button.layer?.backgroundColor = selected
                ? CandelaChrome.accent.cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func selectRotation(_ sender: NSButton) {
        guard let rotation = DisplayRotation(rawValue: sender.tag) else { return }
        select(rotation)
        if let action {
            _ = target?.perform(action, with: self)
        }
    }

    private static func symbol(for rotation: DisplayRotation) -> NSImage? {
        let name = rotation.isPortrait ? "rectangle.portrait" : "rectangle"
        guard let image = CandelaChrome.symbol(name, size: 11) else {
            return CandelaChrome.symbol("rectangle", size: 11)
        }
        switch rotation {
        case .deg0, .deg90:
            return image
        case .deg180, .deg270:
            return image.rotated(byDegrees: 180) ?? image
        }
    }
}

private extension NSImage {
    func rotated(byDegrees degrees: CGFloat) -> NSImage? {
        guard degrees != 0 else { return self }
        let radians = degrees * .pi / 180
        let bounds = NSRect(origin: .zero, size: size)
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byRadians: radians)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        let rotated = NSImage(size: size)
        rotated.lockFocus()
        transform.concat()
        draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        rotated.unlockFocus()
        rotated.isTemplate = isTemplate
        return rotated
    }
}
