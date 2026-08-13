import AppKit

/// AppKit-only hot-plug / sleep observers. Kits stay AppKit-free.
final class HotPlugObserver {
    private var tokens: [NSObjectProtocol] = []
    private let onEvent: () -> Void

    init(onEvent: @escaping () -> Void) {
        self.onEvent = onEvent
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        tokens.append(
            appCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent()
            }
        )
        tokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent()
            }
        )
        tokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent()
            }
        )
    }

    func invalidate() {
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in tokens {
            appCenter.removeObserver(token)
            workspaceCenter.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit {
        invalidate()
    }
}