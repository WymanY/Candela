import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import DisplayCore
import ScreenCaptureKit

@MainActor
final class PictureInPictureWallWindowController: NSWindowController, NSWindowDelegate {
    private let titleLabel = CandelaChrome.makeTitle(localizedText("Display Overview"), size: 12, weight: .semibold)
    private let opacitySlider = CandelaChrome.makeSlider()
    private let clickThroughButton: NSButton
    private let pinControl = PictureInPicturePinControl()
    private let closeButton = CandelaChrome.makeIconButton(symbolName: "xmark", help: localizedText("Close Display Overview"))
    private let restoreHiddenButton = CandelaChrome.makeQuietButton(
        title: localizedText("Show Hidden"),
        symbolName: "eye"
    )
    private let chrome = NSStackView()
    private let tilesHost = WallTilesHost()
    private var tiles: [WallTile] = []
    private var lastTileCount = 0
    private var hiddenKeys: [String]
    private var latestSnapshots: [DisplaySnapshot] = []
    private var placement: PictureInPicturePlacement
    private var isApplying = false
    private var clickThroughTimer: Timer?
    private var clickThroughScrollMonitor: Any?
    private var aspect: CGFloat = 16 / 9
    private let usePlaceholder: Bool
    var onClose: (() -> Void)?
    var onPlacementChange: ((PictureInPicturePlacement) -> Void)?
    var onHiddenKeysChange: (([String]) -> Void)?

    init(
        usePlaceholder: Bool,
        placement: PictureInPicturePlacement = .default,
        hiddenKeys: [String] = []
    ) {
        self.usePlaceholder = usePlaceholder
        self.hiddenKeys = hiddenKeys
        self.placement = PictureInPicturePlacement(
            opacity: placement.opacity,
            clickThrough: placement.clickThrough,
            corner: placement.corner,
            frame: placement.frame,
            hostDisplayID: placement.hostDisplayID
        )
        clickThroughButton = CandelaChrome.makeIconButton(
            symbolName: "cursorarrow.slash",
            help: localizedText("Click Through")
        )
        let preferredWidth = CGFloat(placement.frame?.width ?? PictureInPictureWallLayout.defaultWidth)
        let content = PictureInPictureWallLayout.contentSize(displayCount: 2, preferredWidth: preferredWidth)
        aspect = max(content.width / max(content.height, 1), 0.2)
        let windowSize = PictureInPictureLayout.windowSize(forContent: content)
        let frame = PictureInPictureLayout.windowFrame(
            windowSize: windowSize,
            sourceDisplayID: 0,
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

    func reloadLocalizedChrome() {
        closeButton.toolTip = localizedText("Close Display Overview")
        closeButton.setAccessibilityLabel(localizedText("Close Display Overview"))
        restoreHiddenButton.title = localizedText("Show Hidden")
        restoreHiddenButton.toolTip = localizedText("Show Hidden Displays")
        restoreHiddenButton.setAccessibilityLabel(localizedText("Show Hidden Displays"))
        opacitySlider.setAccessibilityLabel(localizedText("Opacity"))
        pinControl.reloadLocalizedChrome()
        applyOpacity()
        applyClickThrough()
        applyTitle()
        tiles.forEach { $0.reloadLocalizedChrome() }
    }

    func update(snapshots: [DisplaySnapshot]) {
        latestSnapshots = snapshots
        hiddenKeys = PictureInPictureWallLayout.sanitizedHiddenKeys(hiddenKeys)
        let sources = PictureInPictureWallLayout.visibleSnapshots(snapshots, hiddenKeys: hiddenKeys)
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
        restoreHiddenButton.target = self
        restoreHiddenButton.action = #selector(restoreHiddenTiles)
        restoreHiddenButton.toolTip = localizedText("Show Hidden Displays")
        restoreHiddenButton.setAccessibilityLabel(localizedText("Show Hidden Displays"))
        restoreHiddenButton.isHidden = true
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

        pinControl.onChange = { [weak self] corner in
            self?.pinChanged(corner)
        }

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        restoreHiddenButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        chrome.orientation = .horizontal
        chrome.alignment = .centerY
        chrome.spacing = 6
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.addArrangedSubview(titleLabel)
        chrome.addArrangedSubview(restoreHiddenButton)
        chrome.addArrangedSubview(NSView())
        chrome.addArrangedSubview(opacitySlider)
        chrome.addArrangedSubview(clickThroughButton)
        chrome.addArrangedSubview(pinControl)
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
        let existing = Dictionary(uniqueKeysWithValues: tiles.map { ($0.persistentKey, $0) })
        var next: [WallTile] = []
        var reused = Set<String>()
        for snapshot in snapshots {
            let key = snapshot.id.persistentKey
            if let tile = existing[key] {
                tile.update(snapshot: snapshot)
                reused.insert(key)
                next.append(tile)
            } else {
                let tile = WallTile(snapshot: snapshot, usePlaceholder: usePlaceholder)
                tile.onHide = { [weak self] in
                    self?.hideTile(key: key)
                }
                tilesHost.addSubview(tile.view)
                next.append(tile)
            }
        }
        for tile in tiles where !reused.contains(tile.persistentKey) {
            tile.stop()
            tile.view.removeFromSuperview()
        }
        tiles = next
        tilesHost.tileViews = tiles.map(\.view)
        layoutTiles()
        applyTitle()
    }

    private func applyTitle() {
        restoreHiddenButton.isHidden = !PictureInPictureWallLayout.hasHiddenTiles(
            stored: hiddenKeys,
            snapshots: latestSnapshots
        )
        if tiles.isEmpty {
            titleLabel.stringValue = localizedText("Display Overview")
        } else {
            titleLabel.stringValue = localizedText("Display Overview") + " · \(tiles.count)"
        }
    }

    @objc private func restoreHiddenTiles() {
        hiddenKeys = []
        onHiddenKeysChange?(hiddenKeys)
        update(snapshots: latestSnapshots)
    }

    private func hideTile(key: String) {
        hiddenKeys = PictureInPictureWallLayout.hiding(key, in: hiddenKeys, among: latestSnapshots)
        onHiddenKeysChange?(hiddenKeys)
        update(snapshots: latestSnapshots)
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

    private func pinChanged(_ corner: PictureInPictureCorner?) {
        guard !isApplying else { return }
        placement.corner = corner
        if corner != nil {
            snapToPinnedCorner()
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
        opacitySlider.toolTip = "\(localizedText("Opacity")) \(Int((placement.opacity * 100).rounded()))%"
    }

    private func applyClickThrough() {
        clickThroughButton.state = placement.clickThrough ? .on : .off
        clickThroughButton.contentTintColor = placement.clickThrough ? CandelaChrome.accent : .secondaryLabelColor
        clickThroughButton.toolTip = placement.clickThrough
            ? localizedText("Click through is on. Hover the title bar to adjust. Scroll still zooms.")
            : localizedText("Click Through")
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
        let mouse = NSEvent.mouseLocation
        let hoveringChrome = window.convertToScreen(chrome.convert(chrome.bounds, to: nil))
            .insetBy(dx: -10, dy: -10)
            .contains(mouse)
        let hoveringHide = tiles.contains { tile in
            window.convertToScreen(tile.hideButton.convert(tile.hideButton.bounds, to: nil))
                .insetBy(dx: -6, dy: -6)
                .contains(mouse)
        }
        window.ignoresMouseEvents = !(hoveringChrome || hoveringHide)
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
        pinControl.select(corner: placement.corner)
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
private final class WallTile: NSObject {
    let view = NSView()
    var persistentKey: String { snapshot.id.persistentKey }
    var onHide: (() -> Void)?
    private let preview = PictureInPicturePreviewView()
    private let label = CandelaChrome.makeCaption()
    private let placeholder = CandelaChrome.makeCaption()
    let hideButton = CandelaChrome.makeIconButton(
        symbolName: "xmark",
        help: localizedText("Hide Display")
    )
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "candela.pip.wall.tile")
    private var snapshot: DisplaySnapshot
    private let usePlaceholder: Bool

    init(snapshot: DisplaySnapshot, usePlaceholder: Bool) {
        self.snapshot = snapshot
        self.usePlaceholder = usePlaceholder
        super.init()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.allowsWindowDrag = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = snapshot.name
        label.textColor = .white
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.alignment = .center
        placeholder.stringValue = usePlaceholder
            ? localizedText("Preview only in fake-hardware mode.")
            : localizedText("Waiting for display…")
        placeholder.isHidden = !usePlaceholder
        hideButton.target = self
        hideButton.action = #selector(hideTile)
        hideButton.contentTintColor = .white
        hideButton.wantsLayer = true
        hideButton.layer?.cornerRadius = 13
        hideButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        view.addSubview(preview)
        view.addSubview(placeholder)
        view.addSubview(label)
        view.addSubview(hideButton)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: hideButton.leadingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hideButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            hideButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
        ])
        applyHideHelp()
        if !usePlaceholder {
            Task { await startCapture() }
        }
    }

    func update(snapshot: DisplaySnapshot) {
        let displayChanged = self.snapshot.sessionDisplayID != snapshot.sessionDisplayID
            || self.snapshot.pixelWidth != snapshot.pixelWidth
            || self.snapshot.pixelHeight != snapshot.pixelHeight
        self.snapshot = snapshot
        label.stringValue = snapshot.name
        applyHideHelp()
        if displayChanged, !usePlaceholder {
            stop()
            Task { await startCapture() }
        }
    }

    func reloadLocalizedChrome() {
        applyHideHelp()
        if usePlaceholder {
            placeholder.stringValue = localizedText("Preview only in fake-hardware mode.")
        }
    }

    @objc private func hideTile() {
        onHide?()
    }

    private func applyHideHelp() {
        let help = String(format: localizedText("Hide %@"), snapshot.name)
        hideButton.toolTip = help
        hideButton.setAccessibilityLabel(help)
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
            placeholder.stringValue = localizedText("This display is not available.")
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        do {
            let content = try await PictureInPictureCapture.shareableContent()
            guard let display = PictureInPictureCapture.display(id: snapshot.sessionDisplayID, in: content) else {
                placeholder.isHidden = false
                placeholder.stringValue = localizedText("Could not find this display for capture.")
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
            placeholder.stringValue = localizedText("Screen Recording permission is required for Picture in Picture.")
        }
    }
}
