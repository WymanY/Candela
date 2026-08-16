import AppKit

enum CandelaChrome {
    static let panelWidth: CGFloat = 392
    static let panelCorner: CGFloat = 18
    static let moduleCorner: CGFloat = 12
    static let iconSize: CGFloat = 14
    static let percentWidth: CGFloat = 36
    static let contentInsets = NSEdgeInsets(top: 10, left: 14, bottom: 8, right: 14)
    static let moduleInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    static let stackSpacing: CGFloat = 8

    static var accent: NSColor {
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.20, alpha: 1)
    }

    static var accentSoft: NSColor {
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.20, alpha: 0.16)
    }

    static func applyPanelSurface(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = panelCorner
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    }

    static func makeBackdrop() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.wantsLayer = true
        return effect
    }

    static func makeWindowBackdrop() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        return effect
    }

    static func makeAccentBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = accent.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        return bar
    }

    static func makeModule() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = moduleCorner
        box.layer?.cornerCurve = .continuous
        box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    static func makeTitle(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .semibold) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func makeCaption(_ text: String = "") -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11, weight: .medium)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func makePercent() -> NSTextField {
        let field = NSTextField(labelWithString: "50%")
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: percentWidth).isActive = true
        return field
    }

    static func makeSymbol(_ name: String, size: CGFloat = iconSize) -> NSImageView {
        let view = NSImageView()
        view.image = symbol(name, size: size)
        view.imageScaling = .scaleProportionallyDown
        view.contentTintColor = .secondaryLabelColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    static func symbol(_ name: String, size: CGFloat = iconSize, weight: NSFont.Weight = .medium) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    static func makeSlider() -> CandelaSlider {
        let slider = CandelaSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = 50
        slider.isContinuous = true
        slider.altIncrementValue = 1
        slider.controlSize = .regular
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    static func makeHairline() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    static func makeIconButton(symbolName: String, help: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = symbol(symbolName, size: 13)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    static func makeQuietButton(title: String, symbolName: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.imagePosition = symbolName == nil ? .noImage : .imageLeading
        if let symbolName {
            button.image = symbol(symbolName, size: 11)
        }
        if #available(macOS 11.0, *) {
            button.imageHugsTitle = true
        }
        button.lineBreakMode = .byClipping
        button.setButtonType(.momentaryChange)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    static func makePresetButton(title: String, symbolName: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.image = symbol(symbolName, size: 12, weight: .semibold)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .labelColor
        button.tag = tag
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    @MainActor
    static func makeCapsule(_ text: String) -> CandelaBadge {
        CandelaBadge(text, tone: .muted)
    }

    static func makeMeta(_ text: String = "") -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11, weight: .medium)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }
}


final class CandelaSlider: NSSlider {
    var appearsMuted = false {
        didSet {
            (cell as? CandelaSliderCell)?.appearsMuted = appearsMuted
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        cell = CandelaSliderCell()
        sliderType = .linear
    }
}

private final class CandelaSliderCell: NSSliderCell {
    var appearsMuted = false

    override func barRect(flipped: Bool) -> NSRect {
        var rect = super.barRect(flipped: flipped)
        rect.origin.y += (rect.height - trackHeight) / 2
        rect.size.height = trackHeight
        return rect
    }

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        let track = NSBezierPath(roundedRect: aRect, xRadius: aRect.height / 2, yRadius: aRect.height / 2)
        NSColor.labelColor.withAlphaComponent(0.26).setFill()
        track.fill()

        let span = max(maxValue - minValue, 0.0001)
        let fraction = CGFloat((doubleValue - minValue) / span)
        guard fraction > 0 else { return }
        var fillRect = aRect
        fillRect.size.width = max(aRect.height, aRect.width * fraction)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: aRect.height / 2, yRadius: aRect.height / 2)
        (appearsMuted ? NSColor.labelColor.withAlphaComponent(0.42) : CandelaChrome.accent).setFill()
        fill.fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let size = knobDiameter
        let rect = NSRect(
            x: knobRect.midX - size / 2,
            y: knobRect.midY - size / 2,
            width: size,
            height: size
        )
        let knob = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        knob.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.10).setStroke()
        knob.lineWidth = 0.5
        knob.stroke()
    }

    private var trackHeight: CGFloat {
        switch controlSize {
        case .mini, .small: return 3
        default: return 4
        }
    }

    private var knobDiameter: CGFloat {
        switch controlSize {
        case .mini, .small: return 12
        default: return 14
        }
    }
}

@MainActor
final class CandelaBadge: NSView {
    enum Tone {
        case muted
        case accent
    }

    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    var textColor: NSColor {
        get { label.textColor ?? .secondaryLabelColor }
        set { label.textColor = newValue }
    }

    init(_ text: String = "", tone: Tone = .muted) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        CandelaChrome.pin(label, to: self, insets: NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 7))
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        apply(text, tone: tone)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ text: String, tone: Tone = .muted) {
        label.stringValue = text
        isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch tone {
        case .muted:
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            label.textColor = .secondaryLabelColor
        case .accent:
            layer?.backgroundColor = CandelaChrome.accentSoft.cgColor
            label.textColor = CandelaChrome.accent
        }
    }
}
