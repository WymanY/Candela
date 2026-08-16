import CoreAudio
import Foundation

/// Watches the default output, HAL device list, and the active device volume/mute.
public final class HALAudioRouteObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "candela.audio.route")
    private let onChange: @Sendable () -> Void
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID = kAudioObjectUnknown

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        install()
    }

    public func invalidate() {
        removeSystemListeners()
        unobserveDevice()
    }

    deinit {
        invalidate()
    }

    public func observeVolume(uid: String?) {
        queue.async { [weak self] in
            self?.observeVolumeLocked(uid: uid)
        }
    }

    private func install() {
        let callback: AudioObjectPropertyListenerBlock = { [onChange] _, _ in
            DispatchQueue.main.async(execute: onChange)
        }
        systemListener = callback
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = HALDeviceEnumerator.defaultOutputDeviceAddress
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, queue, callback)
        var devicesAddress = HALDeviceEnumerator.devicesAddress
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, queue, callback)
    }

    private func removeSystemListeners() {
        guard let systemListener else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = HALDeviceEnumerator.defaultOutputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(system, &defaultAddress, queue, systemListener)
        var devicesAddress = HALDeviceEnumerator.devicesAddress
        AudioObjectRemovePropertyListenerBlock(system, &devicesAddress, queue, systemListener)
        self.systemListener = nil
    }

    private func observeVolumeLocked(uid: String?) {
        let nextID = uid.flatMap(HALDeviceEnumerator.deviceID(forUID:)) ?? kAudioObjectUnknown
        if nextID == observedDeviceID {
            return
        }
        unobserveDeviceLocked()
        guard nextID != kAudioObjectUnknown else { return }

        let callback: AudioObjectPropertyListenerBlock = { [onChange] _, _ in
            DispatchQueue.main.async(execute: onChange)
        }
        deviceListener = callback
        for var address in Self.volumeAddresses {
            AudioObjectAddPropertyListenerBlock(nextID, &address, queue, callback)
        }
        observedDeviceID = nextID
    }

    private func unobserveDevice() {
        queue.sync { unobserveDeviceLocked() }
    }

    private func unobserveDeviceLocked() {
        guard let deviceListener, observedDeviceID != kAudioObjectUnknown else {
            self.deviceListener = nil
            observedDeviceID = kAudioObjectUnknown
            return
        }
        for var address in Self.volumeAddresses {
            AudioObjectRemovePropertyListenerBlock(observedDeviceID, &address, queue, deviceListener)
        }
        self.deviceListener = nil
        observedDeviceID = kAudioObjectUnknown
    }

    private static var volumeAddresses: [AudioObjectPropertyAddress] {
        [
            HALVolumeControl.virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeOutput),
            HALVolumeControl.virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeGlobal),
            HALVolumeControl.volumeScalarAddress(element: kAudioObjectPropertyElementMain),
            HALVolumeControl.volumeScalarAddress(element: 1),
            HALVolumeControl.volumeScalarAddress(element: 2),
            HALVolumeControl.muteAddress(element: kAudioObjectPropertyElementMain),
            HALVolumeControl.muteAddress(element: 1),
            HALVolumeControl.muteAddress(element: 2),
        ]
    }
}
