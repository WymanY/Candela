import ApplicationServices
import AppKit
import CoreGraphics
import DisplayCore

enum PictureInPictureEventInjector {
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if isSandboxed { return false }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }

    static func restoreCursor(toAppKit point: CGPoint) {
        _ = makeSource()
        CGWarpMouseCursorPosition(quartzPoint(fromAppKit: point))
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    static func postMouse(type: CGEventType, at quartzPoint: CGPoint, button: CGMouseButton, clickCount: Int) {
        let source = makeSource()
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: quartzPoint,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(max(clickCount, 1)))
        event.post(tap: .cghidEventTap)
    }

    static func postScroll(at quartzPoint: CGPoint, event: NSEvent) {
        let source = makeSource()
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let deltaX = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let units: CGScrollEventUnit = event.hasPreciseScrollingDeltas ? .pixel : .line
        guard let posted = CGEvent(
            scrollWheelEvent2Source: source,
            units: units,
            wheelCount: 2,
            wheel1: Int32(deltaY.rounded()),
            wheel2: Int32(deltaX.rounded()),
            wheel3: 0
        ) else { return }
        posted.location = quartzPoint
        posted.post(tap: .cghidEventTap)
    }

    static func postKey(_ event: NSEvent) {
        let source = makeSource()
        guard let posted = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(event.keyCode),
            keyDown: event.type == .keyDown
        ) else { return }
        posted.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
        posted.post(tap: .cghidEventTap)
    }

    private static func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        return source
    }

    static func shouldForwardKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if PictureInPictureInteraction.isExitControlShortcut(
            keyCode: event.keyCode,
            controlPressed: flags.contains(.control)
        ) {
            return false
        }
        if PictureInPictureInteraction.isBareEscapeKey(
            keyCode: event.keyCode,
            commandPressed: flags.contains(.command),
            optionPressed: flags.contains(.option),
            controlPressed: flags.contains(.control),
            shiftPressed: flags.contains(.shift)
        ) {
            return false
        }
        if flags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if key == "w" || key == "," || key == "tab" { return false }
        }
        return true
    }
}

/// Swallows Control-Esc while source control is on, including when another app is focused.
final class PictureInPictureControlExitTap {
    var onExit: (() -> Void)?
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: controlExitTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        runLoopSource = nil
    }

    fileprivate func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let controlPressed = event.flags.contains(.maskControl)
        guard PictureInPictureInteraction.isExitControlShortcut(keyCode: keyCode, controlPressed: controlPressed) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            DispatchQueue.main.async { [weak self] in
                self?.onExit?()
            }
        }
        return nil
    }

    deinit {
        stop()
    }
}

private func controlExitTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PictureInPictureControlExitTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handleTap(type: type, event: event)
}

/// Swallows bare Escape while Picture in Picture or Display Overview is open,
/// including when another app is focused.
final class OverlayEscapeTap {
    /// Written from the main actor; read from the event-tap callback.
    nonisolated(unsafe) var isArmed = false
    /// When Candela is active, the local monitor and key window keep Escape.
    nonisolated(unsafe) var candelaIsActive = true
    var onEscape: (() -> Void)?
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: overlayEscapeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        runLoopSource = nil
    }

    fileprivate func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard PictureInPictureInteraction.isBareEscapeKey(
            keyCode: keyCode,
            commandPressed: flags.contains(.maskCommand),
            optionPressed: flags.contains(.maskAlternate),
            controlPressed: flags.contains(.maskControl),
            shiftPressed: flags.contains(.maskShift)
        ) else {
            return Unmanaged.passUnretained(event)
        }
        guard isArmed, !candelaIsActive else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            DispatchQueue.main.async { [weak self] in
                self?.onEscape?()
            }
        }
        return nil
    }

    deinit {
        stop()
    }
}

private func overlayEscapeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<OverlayEscapeTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handleTap(type: type, event: event)
}
