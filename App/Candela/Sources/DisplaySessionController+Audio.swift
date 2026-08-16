import AudioKit
import DisplayCore
import Foundation

extension DisplaySessionController {
    /// Match HAL output devices after a catalog apply. Skips built-in / virtual.
    /// Does not probe DDC volume or rewrite `DisplayIOBox`.
    func refreshAudioBindings() {
        guard !Self.shouldUseFakeHardware else {
            refreshSpeaker()
            return
        }
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

            var notes = snapshot.volume.notes
            if let override, !override.isEmpty,
               devices.contains(where: { $0.uid == override }) == false
            {
                notes = "Saved audio device missing — rematched"
            }

            let device = uid.flatMap { match in devices.first(where: { $0.uid == match }) }
            let record = persistence.record(for: key)
            var volume = VolumeResolution.bind(
                device: device,
                existing: snapshot.volume,
                lastVolume: record?.lastVolume,
                lastMuted: record?.lastMuted
            )
            if let notes {
                volume.notes = notes
            }
            if volume.backend == .coreAudio, let uid {
                volume = VolumeResolution.adoptingHAL(
                    volume,
                    current: HALVolumeControl.volume(uid: uid),
                    muted: HALVolumeControl.isMuted(uid: uid)
                )
            }
            snapshots[index].volume = volume
        }
        refreshSpeaker()
    }

    func refreshSpeaker() {
        if Self.shouldUseFakeHardware {
            speakerChoices = []
            speaker = SpeakerResolution.resolve(snapshots: snapshots, defaultUID: nil, devices: [])
            return
        }

        let devices = HALDeviceEnumerator.outputDevices()
        let defaultUID = HALDeviceEnumerator.defaultOutputUID()
        speakerChoices = SpeakerResolution.choices(snapshots: snapshots, devices: devices)
        var next = SpeakerResolution.resolve(
            snapshots: snapshots,
            defaultUID: defaultUID,
            devices: devices
        )
        if var resolved = next, let uid = resolved.uid, resolved.volume.backend == .coreAudio {
            resolved.volume = VolumeResolution.adoptingHAL(
                resolved.volume,
                current: HALVolumeControl.volume(uid: uid),
                muted: HALVolumeControl.isMuted(uid: uid)
            )
            if let key = resolved.displayKey,
               let index = snapshots.firstIndex(where: { $0.id.persistentKey == key })
            {
                snapshots[index].volume = VolumeResolution.adoptingHAL(
                    snapshots[index].volume,
                    current: resolved.volume.current,
                    muted: resolved.volume.isMuted
                )
            }
            next = resolved
        }
        speaker = next
        observeActiveSpeakerVolume()
    }

    func setSpeakerVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        if let key = speaker?.displayKey {
            setVolume(key: key, value: clamped)
            return
        }
        applyStandaloneSpeaker(volume: clamped, muted: speaker?.volume.isMuted)
    }

    func setSpeakerMuted(_ muted: Bool) {
        if let key = speaker?.displayKey {
            setMuted(key: key, muted: muted)
            return
        }
        applyStandaloneSpeaker(volume: speaker?.volume.current, muted: muted)
    }

    private func applyStandaloneSpeaker(volume: Double?, muted: Bool?) {
        guard var current = speaker, let uid = current.uid else { return }
        if let volume {
            current.volume.current = min(1, max(0, volume))
        }
        if let muted {
            current.volume.isMuted = muted
        }
        speaker = current
        switch current.volume.backend {
        case .coreAudio:
            HALVolumeControl.setVolume(uid: uid, value: current.volume.current)
            if current.volume.supportsMute {
                HALVolumeControl.setMuted(uid: uid, muted: current.volume.isMuted)
            }
        case .software:
            SoftwareVolumeControl.shared.apply(
                uid: uid,
                volume: current.volume.current,
                muted: current.volume.isMuted
            )
        case .ddc, .none:
            break
        }
        onChange?()
    }

    @discardableResult
    func setDefaultSpeaker(uid: String) -> Bool {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if Self.shouldUseFakeHardware {
            return false
        }
        SoftwareVolumeControl.shared.stopAll()
        guard HALDeviceEnumerator.setDefaultOutputUID(trimmed) else { return false }
        handleAudioRouteChange()
        return true
    }
}
