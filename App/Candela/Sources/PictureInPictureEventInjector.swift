import ApplicationServices
import AppKit
import CoreGraphics

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
        if flags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if key == "w" || key == "," || key == "tab" { return false }
        }
        return true
    }
}
