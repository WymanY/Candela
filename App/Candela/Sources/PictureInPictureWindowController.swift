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
    private let closeButton = CandelaChrome.makeIconButton(symbolName: "xmark", help: String(localized: "Close Picture in Picture"))
    private let preview = PictureInPicturePreviewView()
    private let placeholder = CandelaChrome.makeCaption(String(localized: "Waiting for display…"))
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "candela.pip.stream")
    private var aspect: CGFloat = 16 / 9
    var onClose: (() -> Void)?

    init(key: String, title: String, displayID: CGDirectDisplayID, pixelWidth: UInt32, pixelHeight: UInt32, usePlaceholder: Bool) {
        self.persistentKey = key
        let content = PictureInPictureLayout.contentSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        aspect = max(content.width / max(content.height, 1), 0.2)
        let windowSize = PictureInPictureLayout.windowSize(forContent: content)
        let origin = PictureInPictureLayout.origin(
            windowSize: windowSize,
            sourceDisplayID: displayID,
            screens: NSScreen.screens.map { ($0.candelaDisplayID, $0.visibleFrame) }
        )
        let panel = StatusPanel(
            contentRect: NSRect(origin: origin, size: windowSize),
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
        panel.contentView = makeContent(title: title, contentSize: content)
        if usePlaceholder {
            showPlaceholder(String(localized: "Preview only in fake-hardware mode."))
        } else {
            Task { await self.startCapture(displayID: displayID, content: content) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
        window?.title = title
    }

    func stop() {
        streamQueue.sync {
            try? stream?.stopCapture()
            stream = nil
        }
        preview.flush()
        window?.delegate = nil
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stop()
        onClose?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let width = min(max(frameSize.width, PictureInPictureLayout.minWidth), PictureInPictureLayout.maxWidth)
        return NSSize(width: width, height: width / aspect + PictureInPictureLayout.chromeHeight)
    }

    @objc private func closePictureInPicture() {
        window?.close()
    }

    private func makeContent(title: String, contentSize: CGSize) -> NSView {
        let root = NSView()
        CandelaChrome.applyPanelSurface(root)
        let backdrop = CandelaChrome.makeBackdrop()
        CandelaChrome.pin(backdrop, to: root, insets: .init(top: 0, left: 0, bottom: 0, right: 0))

        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        closeButton.target = self
        closeButton.action = #selector(closePictureInPicture)

        let chrome = NSStackView(views: [titleLabel, NSView(), closeButton])
        chrome.orientation = .horizontal
        chrome.alignment = .centerY
        chrome.spacing = 8
        chrome.translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
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

    private func showPlaceholder(_ text: String) {
        placeholder.stringValue = text
        placeholder.isHidden = false
    }

    private func startCapture(displayID: CGDirectDisplayID, content: CGSize) async {
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
            let configuration = SCStreamConfiguration()
            configuration.width = Int(content.width * 2)
            configuration.height = Int(content.height * 2)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 4
            configuration.showsCursor = true
            configuration.capturesAudio = false
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

final class PictureInPicturePreviewView: NSView, SCStreamOutput, SCStreamDelegate {
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = displayLayer
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
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
