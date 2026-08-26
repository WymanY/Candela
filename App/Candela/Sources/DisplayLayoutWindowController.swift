import AppKit
#if !CANDELA_MAS
import BrightnessKit
#endif
import DisplayCore

@MainActor
final class DisplayLayoutWindowController: NSWindowController, NSWindowDelegate {
    private let session: DisplaySessionController
    private let canvas = DisplayLayoutCanvasView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let instructionsLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: "", target: nil, action: nil)
    private let reloadButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private var workspace: DisplayLayoutWorkspace?
    private var draftIsStale = false
    private var screenObserver: NSObjectProtocol?
    private var ignoreScreenChangesUntil: Date?

    init(session: DisplaySessionController) {
        self.session = session
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 600, height: 400)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        configureView()
        reloadLocalizedChrome()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersChanged()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        reloadFromHardware(successMessage: nil)
        ensureWindowVisible()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func reloadLocalizedChrome() {
        window?.title = localizedText("Display Layout")
        titleLabel.stringValue = localizedText("Display Layout")
        instructionsLabel.stringValue = localizedText(
            "Drag displays to arrange them. Edges snap automatically. The main display stays fixed."
        )
        applyButton.title = localizedText("Apply")
        reloadButton.title = localizedText("Reload")
        cancelButton.title = localizedText("Cancel")
        canvas.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        workspace = nil
        canvas.setDraft(nil)
        draftIsStale = false
    }

    private func configureView() {
        guard let window else { return }
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = root

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        instructionsLabel.font = .systemFont(ofSize: 12)
        instructionsLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.group)
        canvas.setAccessibilityLabel(localizedText("Display Layout"))
        canvas.onDraftChange = { [weak self] draft in
            guard let self, var workspace = self.workspace else { return }
            workspace.draft = draft
            self.workspace = workspace
            self.refreshValidationMessage()
        }
        canvas.onMainDisplayAttempt = { [weak self] in
            self?.setStatus(localizedText("The main display is fixed as the anchor."), error: true)
        }

        for view in [titleLabel, instructionsLabel, statusLabel, applyButton, reloadButton, cancelButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(applyClicked)
        reloadButton.bezelStyle = .rounded
        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        root.addSubview(titleLabel)
        root.addSubview(instructionsLabel)
        root.addSubview(canvas)
        root.addSubview(statusLabel)
        root.addSubview(applyButton)
        root.addSubview(reloadButton)
        root.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            instructionsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            instructionsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            instructionsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            canvas.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 14),
            canvas.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),
            statusLabel.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: reloadButton.leadingAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            cancelButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            reloadButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            reloadButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            applyButton.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -8),
            applyButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            reloadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    @objc private func applyClicked() {
        guard let workspace, !draftIsStale else {
            setStaleStatus()
            return
        }
        do {
            ignoreScreenChangesUntil = Date().addingTimeInterval(1.5)
            let verified = try session.applyDisplayLayout(
                workspace.draft,
                revision: workspace.revision
            )
            self.workspace = verified
            canvas.setDraft(verified.draft)
            draftIsStale = false
            applyButton.isEnabled = true
            setStatus(localizedText("Display layout applied."), error: false)
        } catch {
            ignoreScreenChangesUntil = nil
            handle(error)
        }
    }

    @objc private func reloadClicked() {
        reloadFromHardware(successMessage: localizedText("Reloaded the current display layout."))
    }

    @objc private func cancelClicked() {
        window?.performClose(nil)
    }

    private func reloadFromHardware(successMessage: String?) {
        do {
            let workspace = try session.loadDisplayLayout()
            self.workspace = workspace
            canvas.setDraft(workspace.draft)
            draftIsStale = false
            applyButton.isEnabled = true
            setStatus(successMessage ?? localizedText("Layout is ready."), error: false)
        } catch {
            workspace = nil
            canvas.setDraft(nil)
            applyButton.isEnabled = false
            handle(error)
        }
    }

    private func refreshValidationMessage() {
        guard let workspace else {
            applyButton.isEnabled = false
            return
        }
        guard !draftIsStale else {
            setStaleStatus()
            return
        }
        do {
            try workspace.draft.validated()
            applyButton.isEnabled = true
            setStatus(localizedText("Layout is ready."), error: false)
        } catch let error as DisplayLayoutValidationError {
            applyButton.isEnabled = false
            setStatus(validationMessage(error), error: true)
        } catch {
            applyButton.isEnabled = false
            setStatus(localizedText("Could not validate the display layout."), error: true)
        }
    }

    private func screenParametersChanged() {
        ensureWindowVisible()
        session.requestDisplayLayoutRescan()
        if let until = ignoreScreenChangesUntil, Date() < until {
            return
        }
        ignoreScreenChangesUntil = nil
        guard window?.isVisible == true, workspace != nil else { return }
        draftIsStale = true
        setStaleStatus()
    }

    private func ensureWindowVisible() {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        var frame = window.frame
        frame.size.width = min(frame.size.width, visible.width)
        frame.size.height = min(frame.size.height, visible.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
        if window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func setStaleStatus() {
        applyButton.isEnabled = false
        setStatus(
            localizedText("Display configuration changed. Reload before applying."),
            error: true
        )
    }

    private func handle(_ error: Error) {
        guard let error = error as? DisplayLayoutSessionError else {
            applyButton.isEnabled = false
            setStatus(localizedText("Could not apply the display layout."), error: true)
            return
        }
        switch error {
        case .unavailable(.mirroring):
            applyButton.isEnabled = false
            setStatus(localizedText("Stop mirroring before editing the display layout."), error: true)
        case .unavailable(.insufficientDisplays):
            applyButton.isEnabled = false
            setStatus(localizedText("Connect at least two real displays in extended desktop mode."), error: true)
        case .unavailable(.available):
            applyButton.isEnabled = false
            setStatus(localizedText("Could not read the current display layout."), error: true)
        case .staleDraft:
            draftIsStale = true
            setStaleStatus()
        case let .validation(validation):
            applyButton.isEnabled = false
            setStatus(validationMessage(validation), error: true)
        case let .hardware(hardware):
            handleHardwareError(hardware)
        }
    }

    private func handleHardwareError(_ error: DisplayLayoutHardwareError) {
        applyButton.isEnabled = false
        switch error {
        case .mirroringActive:
            setStatus(localizedText("Stop mirroring before editing the display layout."), error: true)
        case .insufficientDisplays:
            setStatus(localizedText("Connect at least two real displays in extended desktop mode."), error: true)
        case let .invalidDraft(validation):
            if case .deviceSetChanged = validation {
                draftIsStale = true
                setStaleStatus()
            } else {
                setStatus(validationMessage(validation), error: true)
            }
        case .displayGeometryChanged, .verificationFailed:
            draftIsStale = true
            setStaleStatus()
        case .displayQueryFailed, .unresolvedDisplay, .unresolvedPersistentKey, .ambiguousPersistentKey:
            setStatus(localizedText("Could not read the current display layout."), error: true)
        case .beginConfigurationFailed, .configureOriginFailed, .completeConfigurationFailed:
            setStatus(localizedText("Could not apply the display layout."), error: true)
        }
    }

    private func validationMessage(_ error: DisplayLayoutValidationError) -> String {
        switch error {
        case .overlappingDisplays:
            return localizedText("Displays overlap. Move them apart before applying.")
        case .disconnectedDisplays:
            return localizedText("Every display must touch another display.")
        case .deviceSetChanged, .displayGeometryChanged:
            return localizedText("Display configuration changed. Reload before applying.")
        case .mainDisplayIsAnchored:
            return localizedText("The main display is fixed as the anchor.")
        case .missingMainDisplay, .multipleMainDisplays, .unknownDisplay, .invalidGeometry:
            return localizedText("Could not validate the display layout.")
        }
    }

    private func setStatus(_ text: String, error: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
    }
}

@MainActor
private final class DisplayLayoutCanvasView: NSView {
    var onDraftChange: ((DisplayLayoutDraft) -> Void)?
    var onMainDisplayAttempt: (() -> Void)?

    private var draft: DisplayLayoutDraft?
    private var viewport: CGRect?
    private var draggedKey: String?
    private var dragStartPoint = CGPoint.zero
    private var dragStartOrigin = DisplayLayoutPoint(x: 0, y: 0)
    private var dragScale: CGFloat = 1

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDraft(_ draft: DisplayLayoutDraft?) {
        self.draft = draft
        viewport = draft.map(makeViewport)
        draggedKey = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let draft, let transform = transform() else {
            let text = localizedText("No editable display layout is available.") as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attributes
            )
            return
        }

        for slot in draft.slots {
            let rect = displayRect(for: slot, transform: transform)
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            let selected = draggedKey == slot.persistentKey
            let fill = slot.isMain
                ? NSColor.controlAccentColor.withAlphaComponent(selected ? 0.34 : 0.22)
                : NSColor.selectedControlColor.withAlphaComponent(selected ? 0.25 : 0.12)
            fill.setFill()
            path.fill()
            (slot.isMain ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = slot.isMain ? 2 : 1.5
            path.stroke()

            let name = slot.name as NSString
            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            name.draw(
                in: rect.insetBy(dx: 10, dy: 10),
                withAttributes: nameAttributes
            )
            let detail = "\(Int(slot.size.width.rounded())) × \(Int(slot.size.height.rounded()))" as NSString
            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            detail.draw(
                at: NSPoint(x: rect.minX + 10, y: rect.maxY - 24),
                withAttributes: detailAttributes
            )
            if slot.isMain {
                let badge = localizedText("Main Display") as NSString
                let badgeAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor.controlAccentColor,
                ]
                badge.draw(
                    at: NSPoint(x: rect.minX + 10, y: rect.maxY - 40),
                    withAttributes: badgeAttributes
                )
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let draft, let transform = transform() else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let slot = draft.slots.reversed().first(where: {
            displayRect(for: $0, transform: transform).contains(point)
        }) else { return }
        guard !slot.isMain else {
            onMainDisplayAttempt?()
            return
        }
        draggedKey = slot.persistentKey
        dragStartPoint = point
        dragStartOrigin = slot.origin
        dragScale = transform.scale
        NSCursor.closedHand.set()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draft, let draggedKey, dragScale > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let proposed = DisplayLayoutPoint(
            x: dragStartOrigin.x + Double((point.x - dragStartPoint.x) / dragScale),
            y: dragStartOrigin.y + Double((point.y - dragStartPoint.y) / dragScale)
        )
        do {
            let next = try draft.moving(
                persistentKey: draggedKey,
                to: proposed,
                snapDistance: Double(12 / dragScale)
            )
            self.draft = next
            needsDisplay = true
            onDraftChange?(next)
        } catch {
            NSSound.beep()
        }
    }

    override func mouseUp(with event: NSEvent) {
        draggedKey = nil
        NSCursor.openHand.set()
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let draft, let transform = transform() else { return }
        for slot in draft.slots {
            addCursorRect(
                displayRect(for: slot, transform: transform),
                cursor: slot.isMain ? .arrow : .openHand
            )
        }
    }

    private func makeViewport(_ draft: DisplayLayoutDraft) -> CGRect {
        let frames = draft.slots.map { slot in
            CGRect(
                x: slot.origin.x,
                y: slot.origin.y,
                width: slot.size.width,
                height: slot.size.height
            )
        }
        guard var union = frames.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        for frame in frames.dropFirst() {
            union = union.union(frame)
        }
        let margin = max(180, max(union.width, union.height) * 0.18)
        return union.insetBy(dx: -margin, dy: -margin)
    }

    private func transform() -> (viewport: CGRect, scale: CGFloat, offset: CGPoint)? {
        guard let viewport, viewport.width > 0, viewport.height > 0 else { return nil }
        let drawable = bounds.insetBy(dx: 20, dy: 20)
        guard drawable.width > 0, drawable.height > 0 else { return nil }
        let scale = min(drawable.width / viewport.width, drawable.height / viewport.height)
        let rendered = CGSize(width: viewport.width * scale, height: viewport.height * scale)
        return (
            viewport,
            scale,
            CGPoint(x: drawable.midX - rendered.width / 2, y: drawable.midY - rendered.height / 2)
        )
    }

    private func displayRect(
        for slot: DisplayLayoutSlot,
        transform: (viewport: CGRect, scale: CGFloat, offset: CGPoint)
    ) -> CGRect {
        CGRect(
            x: transform.offset.x + (CGFloat(slot.origin.x) - transform.viewport.minX) * transform.scale,
            y: transform.offset.y + (CGFloat(slot.origin.y) - transform.viewport.minY) * transform.scale,
            width: CGFloat(slot.size.width) * transform.scale,
            height: CGFloat(slot.size.height) * transform.scale
        )
    }
}
