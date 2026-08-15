import CoreAudio
import Foundation

/// Watches the default output device and the HAL device list.
public final class HALAudioRouteObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "candela.audio.route")
    private let onChange: @Sendable () -> Void
    private var listener: AudioObjectPropertyListenerBlock?

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        install()
    }

    public func invalidate() {
        guard let listener else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = HALDeviceEnumerator.defaultOutputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(system, &defaultAddress, queue, listener)
        var devicesAddress = HALDeviceEnumerator.devicesAddress
        AudioObjectRemovePropertyListenerBlock(system, &devicesAddress, queue, listener)
        self.listener = nil
    }

    deinit {
        invalidate()
    }

    private func install() {
        let callback: AudioObjectPropertyListenerBlock = { [onChange] _, _ in
            DispatchQueue.main.async(execute: onChange)
        }
        listener = callback
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = HALDeviceEnumerator.defaultOutputDeviceAddress
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, queue, callback)
        var devicesAddress = HALDeviceEnumerator.devicesAddress
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, queue, callback)
    }
}
