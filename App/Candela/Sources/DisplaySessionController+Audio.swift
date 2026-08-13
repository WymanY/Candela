import AudioKit
import DisplayCore
import Foundation

extension DisplaySessionController {
    /// Match HAL output devices after a catalog apply. Skips built-in / virtual.
    /// Does not probe DDC volume or rewrite `DisplayIOBox`.
    func refreshAudioBindings() {
        guard !Self.shouldUseFakeHardware else { return }
        let devices = HALDeviceEnumerator.outputDevices()
        for index in snapshots.indices {
            let snapshot = snapshots[index]
            switch snapshot.kind {
            case .builtIn, .virtualUnsupported:
                continue
            case .appleExternal, .genericExternal:
                break
            }

            let key = snapshot.id.persistentKey
            let override = persistence.record(for: key)?.audioDeviceUIDOverride
            let uid = AudioMatching.match(display: snapshot, overrideUID: override, devices: devices)
            boxes[key]?.bindAudio(uid: uid)

            var volume = snapshot.volume
            if let override, !override.isEmpty,
               devices.contains(where: { $0.uid == override }) == false
            {
                volume.notes = "Saved audio device missing — rematched"
            }
            if let uid, let device = devices.first(where: { $0.uid == uid }) {
                volume.audioDeviceUID = uid
                volume.supportsVolume = device.hasVolume
                volume.supportsMute = device.hasMute
                if device.hasVolume || device.hasMute {
                    volume.backend = .coreAudio
                }
                if device.hasVolume, let current = HALVolumeControl.volume(uid: uid) {
                    volume.current = current
                }
                if device.hasMute, let muted = HALVolumeControl.isMuted(uid: uid) {
                    volume.isMuted = muted
                }
            }
            snapshots[index].volume = volume
        }
    }
}
