import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import DisplayCore
import ScreenCaptureKit

@MainActor
final class PictureInPictureWallWindowController: NSWindowController, NSWindowDelegate {
    private let titleLabel = CandelaChrome.makeTitle(String(localized: "Monitor Wall"), size: 12, weight: .semibold)
    private let opacitySlider = CandelaChrome.makeSlider()
    private let clickThroughButton: NSButton
    private let pinPopup = NSPopUpButton()
    private let closeButton = CandelaChrome.makeIconButton(symbolName: "xmark", help: String(localized: "Close Monitor Wall"))
    private let chrome = NSStackView()
    private let tilesHost = WallTilesHost()
    private var tiles: [WallTile] = []
    private var lastTileCount = 0
    private var placement: PictureInPicturePlacement
    private var isApplying = false
    private var clickThroughTimer: Timer?
    private var clickThroughScrollMonitor: Any?
    private var aspect: CGFloat = 16 / 9
    private let usePlaceholder: Bool
    var onClose: (() -> Void)?
    var onPlacementChange: ((PictureInPicturePlacement) -> Void)?

    init(usePlaceholder: Bool, placement: PictureInPicturePlacement = .default) {
        self.usePlaceholder = usePlaceholder
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
        let preferredWidth = CGFloat(placement.frame?.width ?? PictureInPictureWallLayout.defaultWidth)
        let content = PictureInPictureWallLayout.contentSize(displayCount: 2, preferredWidth: preferredWidth)
        aspect = max(content.width / max(content.height, 1), 0.2)
        let windowSize = PictureInPictureLayout.windowSize(forContent: content)
        let frame = PictureInPictureLayout.windowFrame(
            windowSize: windowSize,
            sourceDisplayID: 0,
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
        panel.minSize = NSSize(width: PictureInPictureWallLayout.minWidth, height: 180)
        panel.maxSize = NSSize(width: 20_000, height: 20_000)
        super.init(window: panel)
        panel.delegate = self
        panel.onCommandW = { [weak self] in
            self?.closeIfHovered()
        }
        let root = makeContent()
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clickThroughTimer?.invalidate()
        if let clickThroughScrollMonitor {
            NSEvent.removeMonitor(clickThroughScrollMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func update(snapshots: [DisplaySnapshot]) {
        let sources = PictureInPictureWallLayout.snapshots(snapshots)
        if sources.count != lastTileCount {
            resize(for: max(sources.count, 1))
            lastTileCount = sources.count
        }
        rebuildTiles(sources)
        persistCurrentPlacement()
    }

    func capturePlacement() {
        persistCurrentPlacement()
    }

    var currentPlacement: PictureInPicturePlacement { placement }

    func stop() {
        clickThroughTimer?.invalidate()
        clickThroughTimer = nil
        removeClickThroughScrollMonitor()
        persistCurrentPlacement()
        tiles.forEach { $0.stop() }
        tiles.removeAll()
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
        window?.layoutIfNeeded()
        layoutTiles()
        guard !isApplying else { return }
        if placement.corner != nil {
            snapToPinnedCorner()
        }
        persistCurrentPlacement()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let limits = currentSizeLimits(for: sender.frame)
        let width = min(max(frameSize.width, limits.minWidth), limits.maxWidth)
        let height = min(max(width / aspect + PictureInPictureLayout.chromeHeight, limits.minHeight), limits.maxHeight)
        return NSSize(width: width, height: height)
    }

    private func makeContent() -> PictureInPictureRootView {
        let root = PictureInPictureRootView()
        CandelaChrome.applyPanelSurface(root)
        let backdrop = CandelaChrome.makeBackdrop()
        CandelaChrome.pin(backdrop, to: root, insets: .init(top: 0, left: 0, bottom: 0, right: 0))

        closeButton.target = self
        closeButton.action = #selector(closeWall)
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

        titleLabel.lineBreakMode = .byTruncatingTail
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

        tilesHost.translatesAutoresizingMaskIntoConstraints = false
        tilesHost.wantsLayer = true
        tilesHost.postsFrameChangedNotifications = true

        root.addSubview(chrome)
        root.addSubview(tilesHost)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            chrome.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            chrome.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            chrome.heightAnchor.constraint(equalToConstant: PictureInPictureLayout.chromeHeight - 8),
            tilesHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            tilesHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            tilesHost.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 2),
            tilesHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        return root
    }

    private func resize(for count: Int) {
        guard let window else { return }
        let preferredWidth = window.frame.width
        let content = PictureInPictureWallLayout.contentSize(
            displayCount: count,
            preferredWidth: preferredWidth,
            maxWidth: currentSizeLimits(for: window.frame).maxWidth
        )
        aspect = max(content.width / max(content.height, 1), 0.2)
        let nextSize = PictureInPictureLayout.windowSize(forContent: content)
        var next = window.frame
        next.size = nextSize
        if let visible = hostVisibleFrame(for: next) {
            next = PictureInPictureLayout.clampedFrame(next, in: visible)
        }
        isApplying = true
        window.setFrame(next, display: true)
        isApplying = false
    }

    private func rebuildTiles(_ snapshots: [DisplaySnapshot]) {
        tiles.forEach { $0.stop(); $0.view.removeFromSuperview() }
        tiles = snapshots.map { snapshot in
            let tile = WallTile(snapshot: snapshot, usePlaceholder: usePlaceholder)
            tilesHost.addSubview(tile.view)
            return tile
        }
        tilesHost.tileViews = tiles.map(\.view)
        layoutTiles()
        if snapshots.isEmpty {
            titleLabel.stringValue = String(localized: "Monitor Wall")
        } else {
            titleLabel.stringValue = String(localized: "Monitor Wall") + " · \(snapshots.count)"
        }
    }

    private func layoutTiles() {
        tilesHost.layoutTiles()
    }

    @objc private func closeWall() {
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
        } else if let window, let visible = hostVisibleFrame(for: window.frame) {
            isApplying = true
            window.setFrame(PictureInPictureLayout.clampedFrame(window.frame, in: visible), display: true)
            isApplying = false
        }
        persistCurrentPlacement()
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
    }

    private func applyClickThrough() {
        clickThroughButton.state = placement.clickThrough ? .on : .off
        clickThroughButton.contentTintColor = placement.clickThrough ? CandelaChrome.accent : .secondaryLabelColor
        clickThroughButton.toolTip = placement.clickThrough
            ? String(localized: "Click through is on. Hover the title bar to adjust. Scroll still zooms.")
            : String(localized: "Click Through")
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

    private func updateClickThroughIgnoring() {
        guard placement.clickThrough, let window else {
            window?.ignoresMouseEvents = false
            return
        }
        let hoveringChrome = window.convertToScreen(chrome.convert(chrome.bounds, to: nil))
            .insetBy(dx: -10, dy: -10)
            .contains(NSEvent.mouseLocation)
        window.ignoresMouseEvents = !hoveringChrome
    }

    private func installClickThroughScrollMonitor() {
        guard clickThroughScrollMonitor == nil else { return }
        clickThroughScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard let window = self.window,
                      PictureInPictureLayout.isMouseOverWindow(mouse: NSEvent.mouseLocation, windowFrame: window.frame)
                else { return }
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

    private func handleScrollWheel(_ event: NSEvent) {
        let raw = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        guard raw != 0 else { return }
        applyZoom(factor: PictureInPictureLayout.zoomFactor(deltaY: raw, precise: event.hasPreciseScrollingDeltas))
    }

    private func handleMagnify(_ event: NSEvent) {
        applyZoom(factor: 1 + event.magnification)
    }

    private func applyZoom(factor: CGFloat) {
        guard let window, factor > 0, abs(factor - 1) > 0.001 else { return }
        let visible = hostVisibleFrame(for: window.frame) ?? window.screen?.visibleFrame
        let limits = currentSizeLimits(for: window.frame, visible: visible)
        let next = PictureInPictureLayout.zoomedFrame(
            current: window.frame,
            factor: factor,
            aspect: aspect,
            corner: placement.corner,
            visible: visible,
            minWidth: limits.minWidth,
            maxWidth: limits.maxWidth
        )
        isApplying = true
        window.setFrame(next, display: true, animate: false)
        window.layoutIfNeeded()
        layoutTiles()
        isApplying = false
        persistCurrentPlacement()
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
            sourceDisplayID: 0,
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

    private func currentSizeLimits(for frame: CGRect, visible: CGRect? = nil) -> (minWidth: CGFloat, maxWidth: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) {
        let host = visible ?? hostVisibleFrame(for: frame)
        let maxWidth = max(host?.width ?? PictureInPictureWallLayout.maxWidth, PictureInPictureWallLayout.minWidth)
        let maxHeight = max(host?.height ?? 980, 180)
        return (
            PictureInPictureWallLayout.minWidth,
            maxWidth,
            180,
            maxHeight
        )
    }

    private func hostVisibleFrame(for frame: CGRect) -> CGRect? {
        PictureInPictureLayout.hostScreen(
            preferredDisplayID: currentHostDisplayID(),
            savedFrame: frame,
            sourceDisplayID: 0,
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
}

private final class WallTilesHost: NSView {
    var tileViews: [NSView] = [] {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        layoutTiles()
    }

    func layoutTiles() {
        let frames = PictureInPictureWallLayout.tileFrames(count: tileViews.count, in: bounds)
        for (view, frame) in zip(tileViews, frames) {
            view.frame = frame
        }
    }
}

@MainActor
private final class WallTile {
    let view = NSView()
    private let preview = PictureInPicturePreviewView()
    private let label = CandelaChrome.makeCaption()
    private let placeholder = CandelaChrome.makeCaption()
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "candela.pip.wall.tile")
    private let snapshot: DisplaySnapshot
    private let usePlaceholder: Bool

    init(snapshot: DisplaySnapshot, usePlaceholder: Bool) {
        self.snapshot = snapshot
        self.usePlaceholder = usePlaceholder
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = snapshot.name
        label.textColor = .white
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.alignment = .center
        placeholder.stringValue = usePlaceholder
            ? String(localized: "Preview only in fake-hardware mode.")
            : String(localized: "Waiting for display…")
        placeholder.isHidden = !usePlaceholder
        view.addSubview(preview)
        view.addSubview(placeholder)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        if !usePlaceholder {
            Task { await startCapture() }
        }
    }

    func stop() {
        streamQueue.sync {
            try? stream?.stopCapture()
            stream = nil
        }
        preview.flush()
    }

    private func startCapture() async {
        guard snapshot.sessionDisplayID != 0 else {
            placeholder.isHidden = false
            placeholder.stringValue = String(localized: "This display is not available.")
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        do {
            let content = try await PictureInPictureCapture.shareableContent()
            guard let display = PictureInPictureCapture.display(id: snapshot.sessionDisplayID, in: content) else {
                placeholder.isHidden = false
                placeholder.stringValue = String(localized: "Could not find this display for capture.")
                return
            }
            let filter = SCContentFilter(
                display: display,
                excludingWindows: PictureInPictureCapture.ownWindows(in: content)
            )
            let capture = PictureInPictureLayout.captureSize(
                pixelWidth: snapshot.pixelWidth > 0 ? snapshot.pixelWidth : UInt32(display.width),
                pixelHeight: snapshot.pixelHeight > 0 ? snapshot.pixelHeight : UInt32(display.height)
            )
            let configuration = PictureInPictureCapture.streamConfiguration(
                width: min(capture.width, 1600),
                height: min(capture.height, 900),
                showsCursor: false
            )
            let stream = SCStream(filter: filter, configuration: configuration, delegate: preview)
            try stream.addStreamOutput(preview, type: .screen, sampleHandlerQueue: streamQueue)
            try await stream.startCapture()
            self.stream = stream
            placeholder.isHidden = true
        } catch {
            placeholder.isHidden = false
            placeholder.stringValue = String(localized: "Screen Recording permission is required for Picture in Picture.")
        }
    }
}
