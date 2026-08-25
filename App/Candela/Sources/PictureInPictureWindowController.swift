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
    private let modePopup = NSPopUpButton()
    private let windowPopup = NSPopUpButton()
    private let mirrorButton: NSButton
    private let zoomPopup = NSPopUpButton()
    private let opacitySlider = CandelaChrome.makeSlider()
    private let clickThroughButton: NSButton
    private let controlButton: NSButton
    private let pinControl = PictureInPicturePinControl()
    private let closeButton = CandelaChrome.makeIconButton(symbolName: "xmark", help: localizedText("Close Picture in Picture"))
    private let preview = PictureInPicturePreviewView()
    private let placeholder = CandelaChrome.makeCaption(localizedText("Waiting for display…"))
    private let permissionOverlay = ScreenRecordingPermissionOverlay()
    private let chrome = NSStackView()
    private let sourceRow = NSStackView()
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "candela.pip.stream")
    private var aspect: CGFloat = 16 / 9
    private var placement: PictureInPicturePlacement
    private var isApplying = false
    private var clickThroughTimer: Timer?
    private var magnifierTimer: Timer?
    private var clickThroughScrollMonitor: Any?
    private var spaceKeyMonitor: Any?
    private var localSpaceKeyMonitor: Any?
    private var commandWMonitor: Any?
    private var controlKeyMonitor: Any?
    private var controlExitTap: PictureInPictureControlExitTap?
    private var controlExitGlobalMonitor: Any?
    private var sourceDisplayID: CGDirectDisplayID
    private var sourceQuartzBounds: CGRect = .null
    private var windowCandidates: [PictureInPictureWindowCandidate] = []
    private var lastMagnifierRect: CGRect = .null
    private var magnifierFocus: CGPoint?
    private var isPanningMagnifier = false
    private var spaceHeld = false
    private var dragStateBeforeMagnifierCanvasPan: MagnifierCanvasPanDragState?
    var onClose: (() -> Void)?
    var onPlacementChange: ((PictureInPicturePlacement) -> Void)?

    private struct MagnifierCanvasPanDragState {
        let windowIsMovable: Bool
        let windowIsMovableByBackground: Bool
        let panelCanvasPanActive: Bool
        let rootAllowsWindowDrag: Bool
        let rootSwallowsScroll: Bool
        let previewAllowsWindowDrag: Bool
    }

    private var sourcePixelWidth: UInt32
    private var sourcePixelHeight: UInt32
    private var displayTitle: String
    private let usePlaceholder: Bool

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
        self.displayTitle = title
        self.usePlaceholder = usePlaceholder
        self.placement = PictureInPicturePlacement(
            opacity: placement.opacity,
            clickThrough: placement.clickThrough,
            corner: placement.corner,
            frame: placement.frame,
            hostDisplayID: placement.hostDisplayID,
            mirrored: placement.mirrored,
            mode: placement.mode,
            window: placement.window,
            magnifierZoom: placement.magnifierZoom,
            controlSource: placement.controlSource
        )
        clickThroughButton = CandelaChrome.makeIconButton(
            symbolName: "cursorarrow.slash",
            help: localizedText("Click Through")
        )
        controlButton = CandelaChrome.makeIconButton(
            symbolName: "cursorarrow.click",
            help: localizedText("Control Source")
        )
        mirrorButton = CandelaChrome.makeIconButton(
            symbolName: "arrow.left.and.right.righttriangle.left.righttriangle.right",
            help: localizedText("Mirror")
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
            placement: self.placement,
            pointer: NSScreen.candelaPointerOnScreen
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
        panel.minSize = NSSize(width: PictureInPictureLayout.minWidth, height: 180)
        panel.maxSize = NSSize(width: PictureInPictureLayout.maxWidth, height: 980)
        super.init(window: panel)
        panel.delegate = self
        panel.onCommandW = { [weak self] in
            self?.closeIfHovered()
        }
        let root = makeContent(title: title, contentSize: content)
        root.onMagnify = { [weak self] event in
            self?.handleMagnify(event)
        }
        root.onScrollWheel = { [weak self] event in
            self?.handleScrollWheel(event)
        }
        root.onMouseDown = { [weak self] event in
            self?.handlePreviewMouseDown(event) ?? false
        }
        root.onMouseDragged = { [weak self] event in
            self?.handlePreviewMouseDragged(event) ?? false
        }
        root.onMouseUp = { [weak self] event in
            self?.handlePreviewMouseUp(event) ?? false
        }
        preview.onControlEvent = { [weak self] event in
            self?.handleControlEvent(event) ?? false
        }
        preview.onControlCursorMove = { [weak self] point in
            self?.handleControlCursorMove(point)
        }
        panel.contentView = root
        applyPlacementToWindow()
        persistCurrentPlacement()
        installSpaceMonitor()
        installCommandWMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        if usePlaceholder {
            showPlaceholder(localizedText("Preview only in fake-hardware mode."))
            windowCandidates = PictureInPictureCapture.fakeCandidates(displayID: displayID)
            reloadWindowMenu()
            applyMirror()
        } else {
            Task { await self.startCapture() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clickThroughTimer?.invalidate()
        magnifierTimer?.invalidate()
        if let clickThroughScrollMonitor {
            NSEvent.removeMonitor(clickThroughScrollMonitor)
        }
        if let spaceKeyMonitor {
            NSEvent.removeMonitor(spaceKeyMonitor)
        }
        if let localSpaceKeyMonitor {
            NSEvent.removeMonitor(localSpaceKeyMonitor)
        }
        if let commandWMonitor {
            NSEvent.removeMonitor(commandWMonitor)
        }
        if let controlKeyMonitor {
            NSEvent.removeMonitor(controlKeyMonitor)
        }
        controlExitTap?.stop()
        if let controlExitGlobalMonitor {
            NSEvent.removeMonitor(controlExitGlobalMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func updateTitle(_ title: String) {
        displayTitle = title
        applyCurrentTitle()
    }

    func reloadLocalizedChrome() {
        closeButton.toolTip = localizedText("Close Picture in Picture")
        closeButton.setAccessibilityLabel(localizedText("Close Picture in Picture"))
        configurePopup(modePopup, label: localizedText("Source"))
        let selectedMode = modePopup.selectedItem?.representedObject as? String
        modePopup.removeAllItems()
        for mode in PictureInPictureMode.allCases {
            modePopup.addItem(withTitle: localizedModeTitle(mode))
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        if let selectedMode,
           let index = modePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selectedMode })
        {
            modePopup.selectItem(at: index)
        }
        configurePopup(windowPopup, label: localizedText("Window"))
        configurePopup(zoomPopup, label: localizedText("Magnifier Zoom"))
        opacitySlider.setAccessibilityLabel(localizedText("Opacity"))
        pinControl.reloadLocalizedChrome()
        applyOpacity()
        applyClickThrough()
        applyControlSource()
        applyMirror()
        applyCurrentTitle()
        reloadWindowMenu()
        permissionOverlay.reloadLocalizedChrome()
    }

    private func applyCurrentTitle() {
        let title = currentChromeTitle()
        titleLabel.stringValue = title
        window?.title = title
    }

    private func currentChromeTitle(windowSource: PictureInPictureWindowIdentity? = nil) -> String {
        if placement.mode == .window, let source = windowSource ?? placement.window {
            return composedTitle(composedWindowName(source), hint: localizedText("Scroll to zoom"))
        }
        if placement.mode == .magnifier {
            return composedTitle(displayTitle, hint: localizedText("Space-drag to pan"))
        }
        return composedTitle(displayTitle, hint: localizedText("Scroll to zoom"))
    }

    private func composedWindowName(_ source: PictureInPictureWindowIdentity) -> String {
        let windowName = source.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty { return windowName }
        if windowName.isEmpty { return displayName }
        if windowName == displayName { return displayName }
        return "\(displayName) · \(windowName)"
    }

    private func composedTitle(_ name: String, hint: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return trimmedHint }
        if trimmedHint.isEmpty { return trimmedName }
        return "\(trimmedName) · \(trimmedHint)"
    }

    func updateSourceDisplay(_ displayID: CGDirectDisplayID) {
        guard sourceDisplayID != displayID else { return }
        sourceDisplayID = displayID
        Task { await self.startCapture() }
    }

    func updateSourcePixels(width: UInt32, height: UInt32) {
        if width > 0 { sourcePixelWidth = width }
        if height > 0 { sourcePixelHeight = height }
    }

    func applyConfiguration(
        mode: PictureInPictureMode? = nil,
        mirrored: Bool? = nil,
        window: PictureInPictureWindowIdentity? = nil,
        magnifierZoom: Double? = nil
    ) {
        if let mode { placement.mode = mode }
        if let mirrored { placement.mirrored = mirrored }
        if window != nil || mode == .display || mode == .magnifier {
            placement.window = window
        }
        if let magnifierZoom {
            placement.magnifierZoom = PictureInPictureMagnifier.clampedZoom(magnifierZoom)
        }
        applyPlacementToWindow()
        persistCurrentPlacement()
        Task { await startCapture() }
    }

    var currentPlacement: PictureInPicturePlacement { placement }

    func capturePlacement() {
        persistCurrentPlacement()
    }

    func stop() {
        clickThroughTimer?.invalidate()
        clickThroughTimer = nil
        magnifierTimer?.invalidate()
        magnifierTimer = nil
        removeClickThroughScrollMonitor()
        removeControlKeyMonitor()
        endMagnifierPan(force: true)
        persistCurrentPlacement()
        stopStream()
        preview.flush()
        window?.delegate = nil
        window?.ignoresMouseEvents = false
        preview.setControlCursor(visible: false, at: nil)
        PictureInPictureCursorPulseOverlay.cancel()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stop()
        onClose?()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplying else { return }
        if shouldPanMagnifierCanvas {
            return
        }
        unpinIfDraggedAway()
        disableControlIfHostIsSource()
        persistCurrentPlacement()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplying else { return }
        if placement.corner != nil {
            snapToPinnedCorner()
        }
        disableControlIfHostIsSource()
        persistCurrentPlacement()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let width = min(max(frameSize.width, PictureInPictureLayout.minWidth), PictureInPictureLayout.maxWidth)
        return NSSize(width: width, height: width / aspect + PictureInPictureLayout.chromeHeight)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        if shouldPanMagnifierCanvas {
            beginMagnifierPanSession()
            panMagnifier(deltaX: event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX,
                         deltaY: event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY)
            return
        }
        if placement.controlSource, handleControlEvent(event) {
            return
        }
        let raw = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        guard raw != 0 else { return }
        applyZoom(factor: PictureInPictureLayout.zoomFactor(deltaY: raw, precise: event.hasPreciseScrollingDeltas), event: event)
    }

    private func handleMagnify(_ event: NSEvent) {
        if shouldPanMagnifierCanvas { return }
        applyZoom(factor: 1 + event.magnification, event: event)
    }

    private func applyZoom(factor: CGFloat, event: NSEvent) {
        guard let window, factor > 0, abs(factor - 1) > 0.001 else { return }
        let current = window.frame
        let visible = hostVisibleFrame(for: current) ?? window.screen?.visibleFrame
        let next = PictureInPictureLayout.zoomedFrame(
            current: current,
            factor: factor,
            aspect: aspect,
            corner: placement.corner,
            visible: visible
        )
        guard next != current else { return }
        let wasMovable = window.isMovableByWindowBackground
        isApplying = true
        window.isMovableByWindowBackground = false
        window.setFrame(next, display: true, animate: false)
        window.layoutIfNeeded()
        if placement.corner == nil {
            let settled = PictureInPictureLayout.centeredFrame(window.frame, around: current, visible: visible)
            if settled != window.frame {
                window.setFrame(settled, display: true, animate: false)
            }
        }
        window.isMovableByWindowBackground = wasMovable
        isApplying = false
        persistCurrentPlacement()
    }

    @objc private func closePictureInPicture() {
        window?.close()
    }

    private func closeIfHovered() {
        guard let window, PictureInPictureLayout.isMouseOverWindow(mouse: NSEvent.mouseLocation, windowFrame: window.frame) else {
            return
        }
        window.close()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        guard !isApplying else { return }
        placement.opacity = PictureInPictureLayout.clampedOpacity(sender.doubleValue / 100)
        applyOpacity()
        persistCurrentPlacement()
    }

    @objc private func toggleClickThrough() {
        placement.clickThrough.toggle()
        if placement.clickThrough {
            placement.controlSource = false
            applyControlSource()
        }
        applyClickThrough()
        persistCurrentPlacement()
    }

    @objc private func toggleMirror() {
        placement.mirrored.toggle()
        applyMirror()
        persistCurrentPlacement()
    }

    private func pinChanged(_ corner: PictureInPictureCorner?) {
        guard !isApplying else { return }
        placement.corner = corner
        if corner != nil {
            snapToPinnedCorner()
        }
        persistCurrentPlacement()
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard !isApplying else { return }
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = PictureInPictureMode(rawValue: raw)
        else { return }
        placement.mode = mode
        if mode != .window {
            placement.window = nil
        }
        applySourceChrome()
        applyControlSource()
        persistCurrentPlacement()
        applyCurrentTitle()
        Task { await startCapture() }
    }

    @objc private func toggleControlSource() {
        guard !isApplying else { return }
        if placement.controlSource {
            exitControlSource()
            return
        }
        guard PictureInPictureInteraction.showsControlSource(mode: placement.mode) else {
            applyControlSource()
            return
        }
        guard canControlSourceNow else {
            applyControlSource()
            return
        }
        guard PictureInPictureEventInjector.isTrusted(prompt: true) else {
            applyControlSource()
            return
        }
        placement.controlSource = true
        placement.clickThrough = false
        applyClickThrough()
        applyControlSource()
        persistCurrentPlacement()
    }

    @objc private func windowChanged(_ sender: NSPopUpButton) {
        guard !isApplying else { return }
        guard let raw = sender.selectedItem?.representedObject as? String, !raw.isEmpty else {
            placement.window = nil
            persistCurrentPlacement()
            Task { await startCapture() }
            return
        }
        let parts = raw.split(separator: "\u{1e}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let identity = PictureInPictureWindowIdentity(
            bundleIdentifier: parts.count > 0 ? parts[0] : "",
            title: parts.count > 1 ? parts[1] : "",
            ownerName: parts.count > 2 ? parts[2] : ""
        )
        placement.window = identity
        persistCurrentPlacement()
        Task { await startCapture() }
    }

    @objc private func zoomChanged(_ sender: NSPopUpButton) {
        guard !isApplying else { return }
        if let raw = sender.selectedItem?.representedObject as? String, let value = Double(raw) {
            placement.magnifierZoom = PictureInPictureMagnifier.clampedZoom(value)
            persistCurrentPlacement()
            Task { await startCapture() }
        }
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
        disableControlIfHostIsSource()
        persistCurrentPlacement()
    }

    @objc private func appDidBecomeActive() {
        guard !usePlaceholder, !permissionOverlay.isHidden || !ScreenRecordingPermission.isGranted else { return }
        Task { await startCapture() }
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
        opacitySlider.setAccessibilityLabel(localizedText("Opacity"))
        opacitySlider.toolTip = localizedText("Opacity")
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 72).isActive = true

        clickThroughButton.setButtonType(.toggle)
        clickThroughButton.target = self
        clickThroughButton.action = #selector(toggleClickThrough)

        controlButton.setButtonType(.toggle)
        controlButton.target = self
        controlButton.action = #selector(toggleControlSource)

        mirrorButton.setButtonType(.toggle)
        mirrorButton.target = self
        mirrorButton.action = #selector(toggleMirror)

        configurePopup(modePopup, label: localizedText("Source"))
        modePopup.removeAllItems()
        for mode in PictureInPictureMode.allCases {
            modePopup.addItem(withTitle: localizedModeTitle(mode))
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))

        configurePopup(windowPopup, label: localizedText("Window"))
        windowPopup.target = self
        windowPopup.action = #selector(windowChanged(_:))

        configurePopup(zoomPopup, label: localizedText("Magnifier Zoom"))
        zoomPopup.removeAllItems()
        for stop in PictureInPictureMagnifier.zoomStops {
            let title = stop == stop.rounded() ? String(format: "%.0fx", stop) : String(format: "%.1fx", stop)
            zoomPopup.addItem(withTitle: title)
            zoomPopup.lastItem?.representedObject = String(stop)
        }
        zoomPopup.target = self
        zoomPopup.action = #selector(zoomChanged(_:))

        pinControl.onChange = { [weak self] corner in
            self?.pinChanged(corner)
        }

        chrome.orientation = .horizontal
        chrome.alignment = .centerY
        chrome.spacing = 6
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.addArrangedSubview(titleLabel)
        chrome.addArrangedSubview(NSView())
        chrome.addArrangedSubview(opacitySlider)
        chrome.addArrangedSubview(clickThroughButton)
        chrome.addArrangedSubview(controlButton)
        chrome.addArrangedSubview(pinControl)
        chrome.addArrangedSubview(closeButton)

        sourceRow.orientation = .horizontal
        sourceRow.alignment = .centerY
        sourceRow.spacing = 6
        sourceRow.translatesAutoresizingMaskIntoConstraints = false
        sourceRow.addArrangedSubview(modePopup)
        sourceRow.addArrangedSubview(windowPopup)
        sourceRow.addArrangedSubview(zoomPopup)
        sourceRow.addArrangedSubview(mirrorButton)
        sourceRow.addArrangedSubview(NSView())

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
        root.addSubview(sourceRow)
        root.addSubview(preview)
        root.addSubview(placeholder)
        permissionOverlay.translatesAutoresizingMaskIntoConstraints = false
        permissionOverlay.isHidden = true
        permissionOverlay.onOpenSettings = { [weak self] in
            self?.openScreenRecordingSettings()
        }
        root.addSubview(permissionOverlay)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            chrome.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            chrome.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            chrome.heightAnchor.constraint(equalToConstant: 26),
            sourceRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            sourceRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            sourceRow.topAnchor.constraint(equalTo: chrome.bottomAnchor),
            sourceRow.heightAnchor.constraint(equalToConstant: 24),
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: sourceRow.bottomAnchor, constant: 4),
            preview.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            preview.widthAnchor.constraint(equalTo: preview.heightAnchor, multiplier: aspect),
            placeholder.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: preview.leadingAnchor, constant: 12),
            permissionOverlay.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            permissionOverlay.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            permissionOverlay.topAnchor.constraint(equalTo: preview.topAnchor),
            permissionOverlay.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
        ])
        return root
    }

    private func configurePopup(_ popup: NSPopUpButton, label: String) {
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11, weight: .medium)
        popup.setAccessibilityLabel(label)
        popup.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func applyPlacementToWindow() {
        isApplying = true
        opacitySlider.doubleValue = placement.opacity * 100
        applyOpacity()
        applyClickThrough()
        applyControlSource()
        applyMirror()
        applySourceChrome()
        applyCurrentTitle()
        syncPinPopup()
        syncModePopup()
        syncZoomPopup()
        reloadWindowMenu()
        isApplying = false
    }

    private func applyOpacity() {
        window?.alphaValue = CGFloat(placement.opacity)
        opacitySlider.toolTip = "\(localizedText("Opacity")) \(Int((placement.opacity * 100).rounded()))%"
        opacitySlider.setAccessibilityValueDescription("\(Int((placement.opacity * 100).rounded()))%")
    }

    private func applyMirror() {
        mirrorButton.state = placement.mirrored ? .on : .off
        mirrorButton.contentTintColor = placement.mirrored ? CandelaChrome.accent : .secondaryLabelColor
        mirrorButton.toolTip = placement.mirrored
            ? localizedText("Mirrored. Flip back to the original view.")
            : localizedText("Mirror")
        mirrorButton.setAccessibilityLabel(mirrorButton.toolTip)
        preview.setMirrored(placement.mirrored)
    }

    private func applySourceChrome() {
        windowPopup.isHidden = placement.mode != .window
        zoomPopup.isHidden = placement.mode != .magnifier
        if placement.mode == .magnifier {
            startMagnifierTimer()
        } else {
            magnifierTimer?.invalidate()
            magnifierTimer = nil
            magnifierFocus = nil
            isPanningMagnifier = false
        }
        syncMagnifierCanvasPanState()
    }

    private func applyClickThrough() {
        clickThroughButton.state = placement.clickThrough ? .on : .off
        clickThroughButton.contentTintColor = placement.clickThrough ? CandelaChrome.accent : .secondaryLabelColor
        clickThroughButton.toolTip = placement.clickThrough
            ? localizedText("Click through is on. Hover the title bar to adjust. Scroll still zooms.")
            : localizedText("Click Through")
        clickThroughButton.setAccessibilityLabel(clickThroughButton.toolTip)
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
            installClickThroughScrollMonitor()
        } else {
            clickThroughTimer?.invalidate()
            clickThroughTimer = nil
            removeClickThroughScrollMonitor()
            window?.ignoresMouseEvents = false
        }
    }

    private var canControlSourceNow: Bool {
        !PictureInPictureEventInjector.isSandboxed
            && PictureInPictureInteraction.canControlSource(
                hostDisplayID: currentHostDisplayID(),
                sourceDisplayID: sourceDisplayID,
                mode: placement.mode
            )
    }

    private func applyControlSource() {
        let showsButton = !PictureInPictureEventInjector.isSandboxed
            && PictureInPictureInteraction.showsControlSource(mode: placement.mode)
        let active = placement.controlSource && canControlSourceNow
        if placement.controlSource && !active {
            placement.controlSource = false
        }
        controlButton.isHidden = !showsButton
        controlButton.state = active ? .on : .off
        controlButton.isEnabled = canControlSourceNow
        controlButton.contentTintColor = active ? CandelaChrome.accent : .secondaryLabelColor
        controlButton.toolTip = controlTooltip(active: active)
        controlButton.setAccessibilityLabel(controlButton.toolTip)
        preview.controlActive = active
        preview.allowsWindowDrag = !active && !shouldPanMagnifierCanvas
        if active {
            installControlKeyMonitor()
        } else {
            removeControlKeyMonitor()
            preview.setControlCursor(visible: false, at: nil)
        }
    }

    private func controlTooltip(active: Bool) -> String {
        if PictureInPictureEventInjector.isSandboxed {
            return localizedText("Control is unavailable in the Mac App Store build.")
        }
        if !canControlSourceNow {
            return localizedText("Move Picture in Picture to another display to control the source.")
        }
        if !PictureInPictureEventInjector.isTrusted(prompt: false) {
            return localizedText("Accessibility permission is required to control the source display.")
        }
        if active {
            return localizedText("Control is on. Clicks and scrolls go to the other display. Press Control-Esc to exit. Hover the title bar to move this window.")
        }
        return localizedText("Control Source")
    }

    private func disableControlIfHostIsSource() {
        guard placement.controlSource else { return }
        guard !canControlSourceNow else { return }
        placement.controlSource = false
        applyControlSource()
    }

    private func exitControlSource(revealCursor: Bool = false) {
        guard placement.controlSource else { return }
        placement.controlSource = false
        applyControlSource()
        persistCurrentPlacement()
        if revealCursor {
            revealCursorInPictureInPicture()
        }
    }

    private func revealCursorInPictureInPicture() {
        guard let window else { return }
        let previewScreen = window.convertToScreen(preview.convert(preview.bounds, to: nil))
        let point = PictureInPictureCursorPulse.warpPoint(previewFrameInScreen: previewScreen)
        PictureInPictureCursorPulseOverlay.play(at: point)
    }

    private func installControlKeyMonitor() {
        if controlKeyMonitor == nil {
            controlKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                return self.handleControlKey(event)
            }
        }
        if controlExitTap == nil {
            let tap = PictureInPictureControlExitTap()
            tap.onExit = { [weak self] in
                self?.exitControlSource(revealCursor: true)
            }
            if tap.start() {
                controlExitTap = tap
            } else {
                installControlExitGlobalMonitor()
            }
        }
    }

    private func installControlExitGlobalMonitor() {
        guard controlExitGlobalMonitor == nil else { return }
        controlExitGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard PictureInPictureInteraction.isExitControlShortcut(
                keyCode: event.keyCode,
                controlPressed: flags.contains(.control)
            ) else { return }
            Task { @MainActor in
                self.exitControlSource(revealCursor: true)
            }
        }
    }

    private func removeControlKeyMonitor() {
        if let controlKeyMonitor {
            NSEvent.removeMonitor(controlKeyMonitor)
            self.controlKeyMonitor = nil
        }
        controlExitTap?.stop()
        controlExitTap = nil
        if let controlExitGlobalMonitor {
            NSEvent.removeMonitor(controlExitGlobalMonitor)
            self.controlExitGlobalMonitor = nil
        }
    }

    private func handleControlKey(_ event: NSEvent) -> NSEvent? {
        guard placement.controlSource else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if PictureInPictureInteraction.isExitControlShortcut(
            keyCode: event.keyCode,
            controlPressed: flags.contains(.control)
        ) {
            if event.type == .keyDown {
                exitControlSource(revealCursor: true)
            }
            return nil
        }
        guard isPointerOverPreview else { return event }
        if event.keyCode == 49 && shouldPanMagnifierCanvas { return event }
        guard PictureInPictureEventInjector.shouldForwardKey(event) else { return event }
        if usePlaceholder { return nil }
        PictureInPictureEventInjector.postKey(event)
        return nil
    }

    private var isPointerOverPreview: Bool {
        guard let window else { return false }
        let rect = window.convertToScreen(preview.convert(preview.bounds, to: nil))
        return rect.contains(NSEvent.mouseLocation)
    }

    private func handleControlCursorMove(_ point: CGPoint?) {
        guard placement.controlSource else {
            preview.setControlCursor(visible: false, at: nil)
            return
        }
        guard let point, preview.bounds.contains(point) else {
            preview.setControlCursor(visible: false, at: nil)
            return
        }
        preview.setControlCursor(visible: true, at: point)
    }

    private func handleControlEvent(_ event: NSEvent) -> Bool {
        guard placement.controlSource else { return false }
        if shouldPanMagnifierCanvas { return false }
        switch event.type {
        case .scrollWheel:
            return injectControlScroll(event)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return injectControlMouse(event, type: cgEventType(for: event), button: .left)
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return injectControlMouse(event, type: cgEventType(for: event), button: .right)
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return injectControlMouse(event, type: cgEventType(for: event), button: .center)
        default:
            return true
        }
    }

    private func cgEventType(for event: NSEvent) -> CGEventType {
        switch event.type {
        case .leftMouseDown: return .leftMouseDown
        case .leftMouseUp: return .leftMouseUp
        case .leftMouseDragged: return .leftMouseDragged
        case .rightMouseDown: return .rightMouseDown
        case .rightMouseUp: return .rightMouseUp
        case .rightMouseDragged: return .rightMouseDragged
        case .otherMouseDown: return .otherMouseDown
        case .otherMouseUp: return .otherMouseUp
        case .otherMouseDragged: return .otherMouseDragged
        default: return .null
        }
    }

    private func injectControlMouse(_ event: NSEvent, type: CGEventType, button: CGMouseButton) -> Bool {
        guard type != .null else { return true }
        guard let quartz = mappedQuartzPoint(from: event) else { return true }
        if usePlaceholder { return true }
        guard PictureInPictureEventInjector.isTrusted(prompt: false) else { return true }
        let pointer = NSEvent.mouseLocation
        PictureInPictureEventInjector.postMouse(
            type: type,
            at: quartz,
            button: button,
            clickCount: event.clickCount
        )
        PictureInPictureEventInjector.restoreCursor(toAppKit: pointer)
        return true
    }

    private func injectControlScroll(_ event: NSEvent) -> Bool {
        guard let quartz = mappedQuartzPoint(from: event) else { return true }
        if usePlaceholder { return true }
        guard PictureInPictureEventInjector.isTrusted(prompt: false) else { return true }
        let pointer = NSEvent.mouseLocation
        PictureInPictureEventInjector.postScroll(at: quartz, event: event)
        PictureInPictureEventInjector.restoreCursor(toAppKit: pointer)
        return true
    }

    private func mappedQuartzPoint(from event: NSEvent) -> CGPoint? {
        let local = preview.convert(event.locationInWindow, from: nil)
        return PictureInPictureInteraction.quartzPoint(
            previewPoint: local,
            previewBounds: preview.bounds,
            sourceBounds: sourceQuartzBounds,
            mirrored: placement.mirrored
        )
    }

    private func updateClickThroughIgnoring() {
        guard placement.clickThrough, let window else {
            window?.ignoresMouseEvents = false
            return
        }
        let chromeRect = window.convertToScreen(chrome.convert(chrome.bounds, to: nil))
            .insetBy(dx: -10, dy: -10)
        let sourceRect = window.convertToScreen(sourceRow.convert(sourceRow.bounds, to: nil))
            .insetBy(dx: -10, dy: -10)
        let hoveringChrome = chromeRect.contains(NSEvent.mouseLocation) || sourceRect.contains(NSEvent.mouseLocation)
        let hoveringPermission = !permissionOverlay.isHidden && window.convertToScreen(
            permissionOverlay.convert(permissionOverlay.bounds, to: nil)
        ).contains(NSEvent.mouseLocation)
        window.ignoresMouseEvents = !(hoveringChrome || hoveringPermission)
    }

    private func installClickThroughScrollMonitor() {
        guard clickThroughScrollMonitor == nil else { return }
        clickThroughScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard self.shouldZoomThroughClickThrough() else { return }
                switch event.type {
                case .scrollWheel:
                    self.handleScrollWheel(event)
                case .magnify:
                    self.handleMagnify(event)
                default:
                    break
                }
            }
        }
    }

    private func removeClickThroughScrollMonitor() {
        if let clickThroughScrollMonitor {
            NSEvent.removeMonitor(clickThroughScrollMonitor)
            self.clickThroughScrollMonitor = nil
        }
    }

    private func shouldZoomThroughClickThrough() -> Bool {
        guard placement.clickThrough, let window else { return false }
        return PictureInPictureLayout.isMouseOverWindow(mouse: NSEvent.mouseLocation, windowFrame: window.frame)
    }

    private func syncPinPopup() {
        pinControl.select(corner: placement.corner)
    }

    private func syncModePopup() {
        if let index = modePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == placement.mode.rawValue }) {
            modePopup.selectItem(at: index)
        }
    }

    private func syncZoomPopup() {
        let selected = String(PictureInPictureMagnifier.nearestStop(placement.magnifierZoom))
        if let index = zoomPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) {
            zoomPopup.selectItem(at: index)
        }
    }

    private func reloadWindowMenu() {
        let previous = windowPopup.selectedItem?.representedObject as? String
        windowPopup.removeAllItems()
        windowPopup.addItem(withTitle: localizedText("Choose Window"))
        windowPopup.lastItem?.representedObject = ""
        for candidate in windowCandidates {
            windowPopup.addItem(withTitle: candidate.identity.displayTitle)
            windowPopup.lastItem?.representedObject = token(for: candidate.identity)
        }
        if let identity = placement.window {
            let token = token(for: identity)
            if let index = windowPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == token }) {
                windowPopup.selectItem(at: index)
            } else if windowCandidates.isEmpty == false {
                windowPopup.addItem(withTitle: identity.displayTitle)
                windowPopup.lastItem?.representedObject = token
                windowPopup.selectItem(at: windowPopup.numberOfItems - 1)
            } else {
                windowPopup.selectItem(at: 0)
            }
        } else if let previous, let index = windowPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == previous }) {
            windowPopup.selectItem(at: index)
        } else {
            windowPopup.selectItem(at: 0)
        }
    }

    private func token(for identity: PictureInPictureWindowIdentity) -> String {
        "\(identity.bundleIdentifier)\u{1e}\(identity.title)\u{1e}\(identity.ownerName)"
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

    private func localizedModeTitle(_ mode: PictureInPictureMode) -> String {
        switch mode {
        case .display: return localizedText("Display")
        case .window: return localizedText("Window")
        case .magnifier: return localizedText("Magnifier")
        }
    }

    private static func screenDescriptors() -> [(id: CGDirectDisplayID, visible: CGRect)] {
        NSScreen.screens.map { ($0.candelaDisplayID, $0.visibleFrame) }
    }

    private func showPlaceholder(_ text: String) {
        placeholder.stringValue = text
        placeholder.isHidden = false
        permissionOverlay.isHidden = true
    }

    private func startMagnifierTimer() {
        guard magnifierTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshMagnifierIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        magnifierTimer = timer
    }

    private func stopStream() {
        streamQueue.sync {
            try? stream?.stopCapture()
            stream = nil
        }
        lastMagnifierRect = .null
    }

    private func startCapture() async {
        if usePlaceholder {
            applySourceChrome()
            applyCurrentTitle()
            return
        }
        guard sourceDisplayID != 0 else {
            showPlaceholder(localizedText("This display is not available."))
            return
        }
        if !ScreenRecordingPermission.isGranted {
            showScreenRecordingPermissionPrompt()
            return
        }
        do {
            let contentList = try await PictureInPictureCapture.shareableContent()
            windowCandidates = PictureInPictureCapture.candidates(in: contentList, preferringDisplay: sourceDisplayID)
            reloadWindowMenu()
            let ownWindows = PictureInPictureCapture.ownWindows(in: contentList)
            let filter: SCContentFilter
            let captureWidth: Int
            let captureHeight: Int
            var sourceRect: CGRect?
            var showsCursor = true
            let resolvedWindow: PictureInPictureWindowCandidate? = {
                guard placement.mode == .window, let identity = placement.window else { return nil }
                return Self.resolveWindow(identity, in: windowCandidates, displayID: sourceDisplayID)
            }()
            if placement.mode == .window,
               let match = resolvedWindow,
               let window = PictureInPictureCapture.window(id: match.windowID, in: contentList)
            {
                placement.window = match.identity
                filter = SCContentFilter(desktopIndependentWindow: window)
                let size = PictureInPictureLayout.captureSize(
                    pixelWidth: match.pixelWidth,
                    pixelHeight: match.pixelHeight
                )
                captureWidth = size.width
                captureHeight = size.height
                showsCursor = false
                titleLabel.stringValue = currentChromeTitle(windowSource: match.identity)
                self.window?.title = titleLabel.stringValue
                sourceQuartzBounds = window.frame
            } else if placement.mode == .magnifier {
                guard let display = PictureInPictureCapture.display(id: sourceDisplayID, in: contentList) else {
                    showPlaceholder(localizedText("Could not find this display for capture."))
                    return
                }
                filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let crop = currentMagnifierCrop(display: display)
                lastMagnifierRect = crop
                sourceRect = PictureInPictureCapture.sourceRect(
                    crop: crop,
                    pixelWidth: Double(sourcePixelWidth > 0 ? sourcePixelWidth : UInt32(display.width)),
                    pixelHeight: Double(sourcePixelHeight > 0 ? sourcePixelHeight : UInt32(display.height)),
                    pointWidth: Double(display.width),
                    pointHeight: Double(display.height)
                )
                let size = PictureInPictureLayout.captureSize(
                    pixelWidth: UInt32(crop.width.rounded()),
                    pixelHeight: UInt32(crop.height.rounded())
                )
                captureWidth = size.width
                captureHeight = size.height
                sourceQuartzBounds = PictureInPictureInteraction.quartzBounds(
                    displayBounds: display.frame,
                    cropInDisplayPoints: sourceRect
                )
            } else {
                if PictureInPictureLayout.shouldFallBackToDisplay(mode: placement.mode, hasResolvedWindow: resolvedWindow != nil) {
                    applyCurrentTitle()
                }
                guard let display = PictureInPictureCapture.display(id: sourceDisplayID, in: contentList) else {
                    showPlaceholder(localizedText("Could not find this display for capture."))
                    return
                }
                filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let size = PictureInPictureLayout.captureSize(
                    pixelWidth: sourcePixelWidth > 0 ? sourcePixelWidth : UInt32(display.width),
                    pixelHeight: sourcePixelHeight > 0 ? sourcePixelHeight : UInt32(display.height)
                )
                captureWidth = size.width
                captureHeight = size.height
                sourceQuartzBounds = display.frame
            }
            let configuration = PictureInPictureCapture.streamConfiguration(
                width: captureWidth,
                height: captureHeight,
                sourceRect: sourceRect,
                showsCursor: showsCursor
            )
            stopStream()
            let stream = SCStream(filter: filter, configuration: configuration, delegate: preview)
            try stream.addStreamOutput(preview, type: .screen, sampleHandlerQueue: streamQueue)
            try await stream.startCapture()
            self.stream = stream
            placeholder.isHidden = true
            permissionOverlay.isHidden = true
            applyMirror()
            applySourceChrome()
            applyCurrentTitle()
        } catch {
            if !ScreenRecordingPermission.isGranted {
                showScreenRecordingPermissionPrompt()
            } else {
                showPlaceholder(localizedText("Screen Recording permission is required for Picture in Picture."))
            }
        }
    }

    private func showScreenRecordingPermissionPrompt() {
        placeholder.isHidden = true
        permissionOverlay.reloadLocalizedChrome()
        permissionOverlay.isHidden = false
        ScreenRecordingPermission.prepareForCapturePrompt()
        window?.makeKeyAndOrderFront(nil)
        _ = ScreenRecordingPermission.requestSystemPrompt()
    }

    private func openScreenRecordingSettings() {
        ScreenRecordingPermission.prepareForCapturePrompt()
        window?.makeKeyAndOrderFront(nil)
        _ = ScreenRecordingPermission.requestSystemPrompt()
        _ = ScreenRecordingPermission.openSystemSettings()
    }


    private static func resolveWindow(
        _ identity: PictureInPictureWindowIdentity,
        in candidates: [PictureInPictureWindowCandidate],
        displayID: CGDirectDisplayID
    ) -> PictureInPictureWindowCandidate? {
        if let match = PictureInPictureWindowMatching.match(
            identity: identity,
            candidates: candidates,
            preferringDisplay: displayID
        ) {
            return match
        }
        let query = identity.title.isEmpty ? identity.ownerName : identity.title
        let bundle = identity.bundleIdentifier.isEmpty ? nil : identity.bundleIdentifier
        return PictureInPictureWindowMatching.query(
            query,
            bundleIdentifier: bundle,
            preferringDisplay: displayID,
            in: candidates
        )
    }

    private func currentMagnifierCrop(display: SCDisplay) -> CGRect {
        let pixelWidth = Double(sourcePixelWidth > 0 ? sourcePixelWidth : UInt32(display.width))
        let pixelHeight = Double(sourcePixelHeight > 0 ? sourcePixelHeight : UInt32(display.height))
        let focus = currentMagnifierFocus(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        return PictureInPictureMagnifier.cropRect(
            sourceWidth: pixelWidth,
            sourceHeight: pixelHeight,
            cursor: focus,
            zoom: placement.magnifierZoom
        )
    }

    private func currentMagnifierFocus(pixelWidth: Double, pixelHeight: Double) -> CGPoint {
        if isPanningMagnifier || spaceHeld, let focus = magnifierFocus {
            return PictureInPictureMagnifier.clampedFocus(
                focus,
                sourceWidth: pixelWidth,
                sourceHeight: pixelHeight,
                zoom: placement.magnifierZoom
            )
        }
        let screen = NSScreen.candelaScreen(for: sourceDisplayID)?.frame
            ?? CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let cursor = PictureInPictureMagnifier.cursorInSourcePixels(
            mouse: NSEvent.mouseLocation,
            screenFrame: screen,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ) ?? magnifierFocus ?? CGPoint(x: pixelWidth / 2, y: pixelHeight / 2)
        let focus = PictureInPictureMagnifier.clampedFocus(
            cursor,
            sourceWidth: pixelWidth,
            sourceHeight: pixelHeight,
            zoom: placement.magnifierZoom
        )
        magnifierFocus = focus
        return focus
    }

    private func handlePreviewMouseDown(_ event: NSEvent) -> Bool {
        guard shouldPanMagnifier(with: event) else { return false }
        beginMagnifierPanSession()
        return true
    }

    private func handlePreviewMouseDragged(_ event: NSEvent) -> Bool {
        guard isPanningMagnifier, shouldPanMagnifierCanvas else { return false }
        panMagnifier(deltaX: event.deltaX, deltaY: event.deltaY)
        return true
    }

    private func handlePreviewMouseUp(_ event: NSEvent) -> Bool {
        guard isPanningMagnifier else { return false }
        endMagnifierPan()
        return true
    }

    private func shouldPanMagnifier(with event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown else { return false }
        return shouldPanMagnifierCanvas
    }

    private var shouldPanMagnifierCanvas: Bool {
        !PictureInPictureLayout.shouldMoveWindow(
            forMagnifierPan: spaceHeld,
            mode: placement.mode
        )
    }

    private func beginMagnifierPanSession() {
        guard shouldPanMagnifierCanvas else { return }
        isPanningMagnifier = true
        setMagnifierCanvasPanActive(true)
        updateMagnifierCursor()
    }

    private func panMagnifier(deltaX: CGFloat, deltaY: CGFloat) {
        guard placement.mode == .magnifier else { return }
        let pixelWidth = Double(sourcePixelWidth > 0 ? sourcePixelWidth : 1)
        let pixelHeight = Double(sourcePixelHeight > 0 ? sourcePixelHeight : 1)
        let current = magnifierFocus ?? CGPoint(x: pixelWidth / 2, y: pixelHeight / 2)
        magnifierFocus = PictureInPictureMagnifier.pannedFocus(
            current: current,
            deltaX: deltaX,
            deltaY: deltaY,
            previewWidth: Double(max(preview.bounds.width, 1)),
            previewHeight: Double(max(preview.bounds.height, 1)),
            sourceWidth: pixelWidth,
            sourceHeight: pixelHeight,
            zoom: placement.magnifierZoom
        )
        Task { await refreshMagnifierIfNeeded() }
    }

    private func endMagnifierPan(force: Bool = false) {
        isPanningMagnifier = false
        if force {
            setMagnifierCanvasPanActive(false)
            preview.updatePanCursor(false)
        } else {
            syncMagnifierCanvasPanState()
        }
    }

    private func syncMagnifierCanvasPanState() {
        let active = shouldPanMagnifierCanvas
        isPanningMagnifier = active
        setMagnifierCanvasPanActive(active)
        if placement.controlSource {
            preview.allowsWindowDrag = false
        }
        updateMagnifierCursor()
    }

    private func setMagnifierCanvasPanActive(_ active: Bool) {
        if active {
            guard dragStateBeforeMagnifierCanvasPan == nil,
                  let window,
                  let panel = window as? StatusPanel,
                  let root = window.contentView as? PictureInPictureRootView
            else { return }
            dragStateBeforeMagnifierCanvasPan = MagnifierCanvasPanDragState(
                windowIsMovable: window.isMovable,
                windowIsMovableByBackground: window.isMovableByWindowBackground,
                panelCanvasPanActive: panel.canvasPanActive,
                rootAllowsWindowDrag: root.allowsWindowDrag,
                rootSwallowsScroll: root.swallowScrollForCanvasPan,
                previewAllowsWindowDrag: preview.allowsWindowDrag
            )
            window.isMovable = false
            window.isMovableByWindowBackground = false
            panel.canvasPanActive = true
            root.allowsWindowDrag = false
            root.swallowScrollForCanvasPan = true
            preview.allowsWindowDrag = false
            return
        }

        guard let previous = dragStateBeforeMagnifierCanvasPan else { return }
        dragStateBeforeMagnifierCanvasPan = nil
        window?.isMovable = previous.windowIsMovable
        window?.isMovableByWindowBackground = previous.windowIsMovableByBackground
        (window as? StatusPanel)?.canvasPanActive = previous.panelCanvasPanActive
        if let root = window?.contentView as? PictureInPictureRootView {
            root.allowsWindowDrag = previous.rootAllowsWindowDrag
            root.swallowScrollForCanvasPan = previous.rootSwallowsScroll
        }
        preview.allowsWindowDrag = previous.previewAllowsWindowDrag
    }

    private func updateMagnifierCursor() {
        preview.updatePanCursor(shouldPanMagnifierCanvas)
    }

    private func installSpaceMonitor() {
        guard spaceKeyMonitor == nil, localSpaceKeyMonitor == nil else { return }
        spaceKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.noteSpaceKey(event)
        }
        localSpaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 {
                self.setSpaceHeld(event.type == .keyDown)
                if self.placement.mode == .magnifier {
                    return nil
                }
            }
            return event
        }
    }

    private func installCommandWMonitor() {
        guard commandWMonitor == nil else { return }
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "w"
            else { return event }
            guard let window = self.window,
                  PictureInPictureLayout.isMouseOverWindow(mouse: NSEvent.mouseLocation, windowFrame: window.frame)
            else { return event }
            self.closePictureInPicture()
            return nil
        }
    }

    private func noteSpaceKey(_ event: NSEvent) {
        if event.keyCode == 49 {
            setSpaceHeld(event.type != .keyUp)
        }
    }

    private func setSpaceHeld(_ held: Bool) {
        guard spaceHeld != held else {
            updateMagnifierCursor()
            return
        }
        spaceHeld = held
        syncMagnifierCanvasPanState()
    }

    private func refreshMagnifierIfNeeded() async {
        guard placement.mode == .magnifier, !usePlaceholder else { return }
        do {
            let contentList = try await PictureInPictureCapture.shareableContent()
            guard let display = PictureInPictureCapture.display(id: sourceDisplayID, in: contentList) else { return }
            let crop = currentMagnifierCrop(display: display)
            guard crop.integral != lastMagnifierRect.integral else { return }
            lastMagnifierRect = crop
            let sourceRect = PictureInPictureCapture.sourceRect(
                crop: crop,
                pixelWidth: Double(sourcePixelWidth > 0 ? sourcePixelWidth : UInt32(display.width)),
                pixelHeight: Double(sourcePixelHeight > 0 ? sourcePixelHeight : UInt32(display.height)),
                pointWidth: Double(display.width),
                pointHeight: Double(display.height)
            )
            let size = PictureInPictureLayout.captureSize(
                pixelWidth: UInt32(crop.width.rounded()),
                pixelHeight: UInt32(crop.height.rounded())
            )
            let configuration = PictureInPictureCapture.streamConfiguration(
                width: size.width,
                height: size.height,
                sourceRect: sourceRect,
                showsCursor: true
            )
            try await stream?.updateConfiguration(configuration)
            sourceQuartzBounds = PictureInPictureInteraction.quartzBounds(
                displayBounds: display.frame,
                cropInDisplayPoints: sourceRect
            )
        } catch {
            return
        }
    }
}

final class PictureInPictureRootView: NSView {
    var onScrollWheel: ((NSEvent) -> Void)?
    var onMagnify: ((NSEvent) -> Void)?
    var onMouseDown: ((NSEvent) -> Bool)?
    var onMouseDragged: ((NSEvent) -> Bool)?
    var onMouseUp: ((NSEvent) -> Bool)?
    var allowsWindowDrag = true

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { allowsWindowDrag }

    var swallowScrollForCanvasPan = false

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event)
        if !swallowScrollForCanvasPan {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event)
    }

    override func mouseDown(with event: NSEvent) {
        if onMouseDown?(event) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if onMouseDragged?(event) == true { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if onMouseUp?(event) == true { return }
        super.mouseUp(with: event)
    }

    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        true
    }
}

final class PictureInPicturePreviewView: NSView, SCStreamOutput, SCStreamDelegate {
    private let hostLayer = CALayer()
    private var displayLayer = AVSampleBufferDisplayLayer()
    private let controlCursor = CALayer()
    private var mirrored = false
    var allowsWindowDrag = true
    var controlActive = false
    var onControlEvent: ((NSEvent) -> Bool)?
    var onControlCursorMove: ((CGPoint?) -> Void)?

    override var mouseDownCanMoveWindow: Bool { allowsWindowDrag }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        controlActive
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        hostLayer.masksToBounds = true
        hostLayer.backgroundColor = NSColor.black.cgColor
        hostLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(hostLayer)
        controlCursor.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        controlCursor.cornerRadius = 5
        controlCursor.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        controlCursor.borderColor = NSColor.black.withAlphaComponent(0.85).cgColor
        controlCursor.borderWidth = 1.5
        controlCursor.isHidden = true
        controlCursor.zPosition = 50
        layer?.addSublayer(controlCursor)
        configureDisplayLayer(displayLayer)
        hostLayer.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyPreviewGeometry()
    }

    func setMirrored(_ mirrored: Bool) {
        self.mirrored = mirrored
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func updatePanCursor(_ panning: Bool) {
        if panning {
            NSCursor.openHand.set()
        } else if controlActive {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func setControlCursor(visible: Bool, at point: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controlCursor.isHidden = !visible
        if let point {
            controlCursor.position = point
        }
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        onControlCursorMove?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        onControlCursorMove?(convert(event.locationInWindow, from: nil))
        if controlActive { NSCursor.crosshair.set() }
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onControlCursorMove?(nil)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        onControlCursorMove?(convert(event.locationInWindow, from: nil))
        if onControlEvent?(event) == true { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if onControlEvent?(event) == true { return }
        super.scrollWheel(with: event)
    }

    func flush() {
        displayLayer.flushAndRemoveImage()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if displayLayer.status == .failed {
            recreateDisplayLayer()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func applyPreviewGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        hostLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        hostLayer.setAffineTransform(PictureInPictureMirror.centeredAffineTransform(mirrored: mirrored))
        displayLayer.frame = hostLayer.bounds
        displayLayer.setAffineTransform(.identity)
        CATransaction.commit()
    }

    private func recreateDisplayLayer() {
        displayLayer.flushAndRemoveImage()
        displayLayer.removeFromSuperlayer()
        let replacement = AVSampleBufferDisplayLayer()
        configureDisplayLayer(replacement)
        replacement.frame = hostLayer.bounds
        hostLayer.addSublayer(replacement)
        displayLayer = replacement
    }

    private func configureDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.anchorPoint = CGPoint(x: 0, y: 0)
        layer.setAffineTransform(.identity)
    }
}
