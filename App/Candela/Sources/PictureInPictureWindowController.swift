import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import DisplayCore
import ScreenCaptureKit

@MainActor
final class PictureInPictureWindowController: NSWindowController, NSWindowDelegate {
    let persistentKey: String
    private let titleLabel = CandelaChrome.makeTitle("", size: 12, weight: .semibold)
    private let opacitySlider = CandelaChrome.makeSlider()
    private let clickThroughButton: NSButton
    private let pinPopup = NSPopUpButton()
    private let closeButton = CandelaChrome.makeIconButton(symbolName: "xmark", help: String(localized: "Close Picture in Picture"))
    private let preview = PictureInPicturePreviewView()
    private let placeholder = CandelaChrome.makeCaption(String(localized: "Waiting for display…"))
    private let chrome = NSStackView()
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "candela.pip.stream")
    private var aspect: CGFloat = 16 / 9
    private var placement: PictureInPicturePlacement
    private var isApplying = false
    private var clickThroughTimer: Timer?
    private var sourceDisplayID: CGDirectDisplayID
    var onClose: (() -> Void)?
    var onPlacementChange: ((PictureInPicturePlacement) -> Void)?

    private let sourcePixelWidth: UInt32
    private let sourcePixelHeight: UInt32

    init(
        key: String,
        title: String,
        displayID: CGDirectDisplayID,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        usePlaceholder: Bool,
        placement: PictureInPicturePlacement = .default
    ) {
        self.persistentKey = key
        self.sourceDisplayID = displayID
        self.sourcePixelWidth = pixelWidth
        self.sourcePixelHeight = pixelHeight
        self.placement = PictureInPicturePlacement(
            opacity: placement.opacity,
            clickThrough: placement.clickThrough,
            corner: placement.corner,
            frame: placement.frame,
            hostDisplayID: placement.hostDisplayID
        )
        clickThroughButton = CandelaChrome.makeIconButton(
            symbolName: "cursorarrow.slash",
            help: String(localized: "Click Through")
        )
        let preferredWidth = CGFloat(placement.frame?.width ?? PictureInPictureLayout.defaultWidth)
        let content = PictureInPictureLayout.contentSize(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            preferredWidth: preferredWidth
        )
        aspect = max(content.width / max(content.height, 1), 0.2)
        let windowSize = PictureInPictureLayout.windowSize(forContent: content)
        let frame = PictureInPictureLayout.windowFrame(
            windowSize: windowSize,
            sourceDisplayID: displayID,
            screens: Self.screenDescriptors(),
            placement: self.placement
        )
        let panel = StatusPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: PictureInPictureLayout.minWidth, height: 140)
        panel.maxSize = NSSize(width: PictureInPictureLayout.maxWidth, height: 900)
        super.init(window: panel)
        panel.delegate = self
        let root = makeContent(title: title, contentSize: content)
        root.onMagnify = { [weak self] event in
            self?.handleMagnify(event)
        }
        root.onScrollWheel = { [weak self] event in
            self?.handleScrollWheel(event)
        }
        panel.contentView = root
        applyPlacementToWindow()
        persistCurrentPlacement()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if usePlaceholder {
            showPlaceholder(String(localized: "Preview only in fake-hardware mode."))
        } else {
            Task { await self.startCapture(displayID: displayID) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clickThroughTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
        window?.title = title
    }

    func updateSourceDisplay(_ displayID: CGDirectDisplayID) {
        sourceDisplayID = displayID
    }

    func capturePlacement() {
        persistCurrentPlacement()
    }

    func stop() {
        clickThroughTimer?.invalidate()
        clickThroughTimer = nil
        persistCurrentPlacement()
        streamQueue.sync {
            try? stream?.stopCapture()
            stream = nil
        }
        preview.flush()
        window?.delegate = nil
        window?.ignoresMouseEvents = false
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stop()
        onClose?()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplying else { return }
        unpinIfDraggedAway()
        persistCurrentPlacement()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplying else { return }
        if placement.corner != nil {
            snapToPinnedCorner()
        }
        persistCurrentPlacement()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let width = min(max(frameSize.width, PictureInPictureLayout.minWidth), PictureInPictureLayout.maxWidth)
        return NSSize(width: width, height: width / aspect + PictureInPictureLayout.chromeHeight)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        let raw = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        guard raw != 0 else { return }
        applyZoom(factor: PictureInPictureLayout.zoomFactor(deltaY: raw, precise: event.hasPreciseScrollingDeltas), event: event)
    }

    private func handleMagnify(_ event: NSEvent) {
        applyZoom(factor: 1 + event.magnification, event: event)
    }

    private func applyZoom(factor: CGFloat, event: NSEvent) {
        guard let window, factor > 0, abs(factor - 1) > 0.001 else { return }
        let visible = hostVisibleFrame(for: window.frame) ?? window.screen?.visibleFrame
        let next = PictureInPictureLayout.zoomedFrame(
            current: window.frame,
            factor: factor,
            aspect: aspect,
            corner: placement.corner,
            visible: visible
        )
        guard next != window.frame else { return }
        isApplying = true
        window.setFrame(next, display: true, animate: false)
        isApplying = false
        persistCurrentPlacement()
    }

    @objc private func closePictureInPicture() {
        window?.close()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        placement.opacity = PictureInPictureLayout.clampedOpacity(sender.doubleValue / 100)
        applyOpacity()
        persistCurrentPlacement()
    }

    @objc private func toggleClickThrough() {
        placement.clickThrough.toggle()
        applyClickThrough()
        persistCurrentPlacement()
    }

    @objc private func pinChanged(_ sender: NSPopUpButton) {
        guard !isApplying else { return }
        if let raw = sender.selectedItem?.representedObject as? String,
           let corner = PictureInPictureCorner(rawValue: raw)
        {
            placement.corner = corner
            snapToPinnedCorner()
        } else {
            placement.corner = nil
        }
        persistCurrentPlacement()
    }

    @objc private func screensChanged() {
        if placement.corner != nil {
            snapToPinnedCorner()
        } else if let window {
            let visible = hostVisibleFrame(for: window.frame) ?? window.screen?.visibleFrame
            if let visible {
                isApplying = true
                window.setFrame(PictureInPictureLayout.clampedFrame(window.frame, in: visible), display: true)
                isApplying = false
            }
        }
        persistCurrentPlacement()
    }

    private func makeContent(title: String, contentSize: CGSize) -> PictureInPictureRootView {
        let root = PictureInPictureRootView()
        CandelaChrome.applyPanelSurface(root)
        let backdrop = CandelaChrome.makeBackdrop()
        CandelaChrome.pin(backdrop, to: root, insets: .init(top: 0, left: 0, bottom: 0, right: 0))

        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton.target = self
        closeButton.action = #selector(closePictureInPicture)

        opacitySlider.minValue = PictureInPictureLayout.minimumOpacity * 100
        opacitySlider.maxValue = 100
        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.setAccessibilityLabel(String(localized: "Opacity"))
        opacitySlider.toolTip = String(localized: "Opacity")
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 72).isActive = true

        clickThroughButton.setButtonType(.toggle)
        clickThroughButton.target = self
        clickThroughButton.action = #selector(toggleClickThrough)

        pinPopup.controlSize = .small
        pinPopup.font = .systemFont(ofSize: 11, weight: .medium)
        pinPopup.target = self
        pinPopup.action = #selector(pinChanged(_:))
        pinPopup.setAccessibilityLabel(String(localized: "Pin Corner"))
        pinPopup.removeAllItems()
        pinPopup.addItem(withTitle: String(localized: "Free"))
        pinPopup.lastItem?.representedObject = ""
        for corner in PictureInPictureCorner.allCases {
            pinPopup.addItem(withTitle: localizedCornerTitle(corner))
            pinPopup.lastItem?.representedObject = corner.rawValue
        }
        pinPopup.setContentHuggingPriority(.required, for: .horizontal)

        chrome.orientation = .horizontal
        chrome.alignment = .centerY
        chrome.spacing = 6
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.addArrangedSubview(titleLabel)
        chrome.addArrangedSubview(NSView())
        chrome.addArrangedSubview(opacitySlider)
        chrome.addArrangedSubview(clickThroughButton)
        chrome.addArrangedSubview(pinPopup)
        chrome.addArrangedSubview(closeButton)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layerContentsRedrawPolicy = .onSetNeedsDisplay
        preview.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        preview.layer?.backgroundColor = NSColor.black.cgColor
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true

        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isHidden = true

        root.addSubview(chrome)
        root.addSubview(preview)
        root.addSubview(placeholder)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            chrome.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            chrome.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            chrome.heightAnchor.constraint(equalToConstant: PictureInPictureLayout.chromeHeight - 4),
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 2),
            preview.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            preview.widthAnchor.constraint(equalTo: preview.heightAnchor, multiplier: aspect),
            placeholder.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: preview.leadingAnchor, constant: 12),
        ])
        return root
    }

    private func applyPlacementToWindow() {
        isApplying = true
        opacitySlider.doubleValue = placement.opacity * 100
        applyOpacity()
        applyClickThrough()
        syncPinPopup()
        isApplying = false
    }

    private func applyOpacity() {
        window?.alphaValue = CGFloat(placement.opacity)
        opacitySlider.toolTip = "\(String(localized: "Opacity")) \(Int((placement.opacity * 100).rounded()))%"
        opacitySlider.setAccessibilityValueDescription("\(Int((placement.opacity * 100).rounded()))%")
    }

    private func applyClickThrough() {
        clickThroughButton.state = placement.clickThrough ? .on : .off
        clickThroughButton.contentTintColor = placement.clickThrough ? CandelaChrome.accent : .secondaryLabelColor
        clickThroughButton.toolTip = placement.clickThrough
            ? String(localized: "Click through is on. Hover the title bar to adjust. Scroll still zooms.")
            : String(localized: "Click Through")
        clickThroughButton.setAccessibilityLabel(clickThroughButton.toolTip)
        if let root = window?.contentView as? PictureInPictureRootView {
            root.clickThroughEnabled = placement.clickThrough
        }
        updateClickThroughIgnoring()
        if placement.clickThrough {
            if clickThroughTimer == nil {
                let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.updateClickThroughIgnoring()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                clickThroughTimer = timer
            }
        } else {
            clickThroughTimer?.invalidate()
            clickThroughTimer = nil
            window?.ignoresMouseEvents = false
        }
    }

    private func updateClickThroughIgnoring() {
        guard placement.clickThrough, let window else {
            window?.ignoresMouseEvents = false
            return
        }
        let hoveringChrome = window.convertToScreen(chrome.convert(chrome.bounds, to: nil))
            .insetBy(dx: -10, dy: -10)
            .contains(NSEvent.mouseLocation)
        // Stay live over the preview so scroll/pinch still zoom. The root view
        // forwards clicks that miss chrome controls.
        window.ignoresMouseEvents = !hoveringChrome && !PictureInPictureLayout.isMouseOverWindow(
            mouse: NSEvent.mouseLocation,
            windowFrame: window.frame
        )
    }

    private func syncPinPopup() {
        let selected = placement.corner?.rawValue ?? ""
        if let index = pinPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) {
            pinPopup.selectItem(at: index)
        } else {
            pinPopup.selectItem(at: 0)
        }
    }

    private func snapToPinnedCorner() {
        guard let corner = placement.corner, let window else { return }
        let host = PictureInPictureLayout.hostScreen(
            preferredDisplayID: placement.hostDisplayID ?? currentHostDisplayID(),
            savedFrame: window.frame,
            sourceDisplayID: sourceDisplayID,
            screens: Self.screenDescriptors()
        )
        guard let visible = host?.visible else { return }
        let next = CGRect(
            origin: PictureInPictureLayout.snapOrigin(windowSize: window.frame.size, corner: corner, visible: visible),
            size: window.frame.size
        )
        isApplying = true
        window.setFrame(next, display: true)
        isApplying = false
        placement.hostDisplayID = host?.id
    }

    private func unpinIfDraggedAway() {
        guard let corner = placement.corner, let window else { return }
        let visible = hostVisibleFrame(for: window.frame) ?? window.screen?.visibleFrame
        guard let visible else { return }
        if PictureInPictureLayout.movedOffPinnedCorner(frame: window.frame, corner: corner, visible: visible) {
            placement.corner = nil
            syncPinPopup()
        } else {
            snapToPinnedCorner()
        }
    }

    private func persistCurrentPlacement() {
        guard let window else { return }
        placement.opacity = PictureInPictureLayout.clampedOpacity(Double(window.alphaValue))
        placement.frame = PictureInPictureFrame(rect: window.frame)
        placement.hostDisplayID = currentHostDisplayID() ?? placement.hostDisplayID
        onPlacementChange?(placement)
    }

    private func currentHostDisplayID() -> UInt32? {
        guard let window else { return nil }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return Self.screenDescriptors().first(where: { $0.visible.contains(center) })?.id
            ?? window.screen?.candelaDisplayID
    }

    private func hostVisibleFrame(for frame: CGRect) -> CGRect? {
        PictureInPictureLayout.hostScreen(
            preferredDisplayID: currentHostDisplayID(),
            savedFrame: frame,
            sourceDisplayID: sourceDisplayID,
            screens: Self.screenDescriptors()
        )?.visible
    }

    private func localizedCornerTitle(_ corner: PictureInPictureCorner) -> String {
        switch corner {
        case .topLeft: return String(localized: "Top Left")
        case .topRight: return String(localized: "Top Right")
        case .bottomLeft: return String(localized: "Bottom Left")
        case .bottomRight: return String(localized: "Bottom Right")
        }
    }

    private static func screenDescriptors() -> [(id: CGDirectDisplayID, visible: CGRect)] {
        NSScreen.screens.map { ($0.candelaDisplayID, $0.visibleFrame) }
    }

    private func showPlaceholder(_ text: String) {
        placeholder.stringValue = text
        placeholder.isHidden = false
    }

    private func startCapture(displayID: CGDirectDisplayID) async {
        guard displayID != 0 else {
            showPlaceholder(String(localized: "This display is not available."))
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        do {
            let contentList = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = contentList.displays.first(where: { $0.displayID == displayID }) else {
                showPlaceholder(String(localized: "Could not find this display for capture."))
                return
            }
            let ownWindows = contentList.windows.filter {
                $0.owningApplication?.bundleIdentifier == "app.candela.macos"
            }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let capture = PictureInPictureLayout.captureSize(
                pixelWidth: sourcePixelWidth > 0 ? sourcePixelWidth : UInt32(display.width),
                pixelHeight: sourcePixelHeight > 0 ? sourcePixelHeight : UInt32(display.height)
            )
            let configuration = SCStreamConfiguration()
            configuration.width = capture.width
            configuration.height = capture.height
            configuration.scalesToFit = false
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 8
            configuration.showsCursor = true
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            if #available(macOS 14.0, *) {
                configuration.captureResolution = .best
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: preview)
            try stream.addStreamOutput(preview, type: .screen, sampleHandlerQueue: streamQueue)
            try await stream.startCapture()
            self.stream = stream
            placeholder.isHidden = true
        } catch {
            showPlaceholder(String(localized: "Screen Recording permission is required for Picture in Picture."))
        }
    }
}

final class PictureInPictureRootView: NSView {
    var onScrollWheel: ((NSEvent) -> Void)?
    var onMagnify: ((NSEvent) -> Void)?
    var clickThroughEnabled = false

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if clickThroughEnabled, hit is PictureInPicturePreviewView || hit is NSTextField {
            return self
        }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        if clickThroughEnabled, shouldPassClick(event) {
            passClicksTemporarily()
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if clickThroughEnabled, shouldPassClick(event) {
            passClicksTemporarily()
            return
        }
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if clickThroughEnabled, shouldPassClick(event) {
            passClicksTemporarily()
            return
        }
        super.otherMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event)
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event)
    }

    private func shouldPassClick(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let hit = super.hitTest(point)
        return hit == nil || hit is PictureInPicturePreviewView || hit is NSTextField
    }

    private func passClicksTemporarily() {
        guard let window else { return }
        window.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            window.ignoresMouseEvents = false
        }
    }
}

final class PictureInPicturePreviewView: NSView, SCStreamOutput, SCStreamDelegate {
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = displayLayer
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.magnificationFilter = .linear
        displayLayer.minificationFilter = .trilinear
        displayLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func flush() {
        displayLayer.flushAndRemoveImage()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }
}
