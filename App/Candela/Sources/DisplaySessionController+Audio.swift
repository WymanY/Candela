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
                let desiredVolume = record?.lastVolume ?? snapshot.volume.current
                let desiredMuted = record?.lastMuted ?? snapshot.volume.isMuted
                let current = HALVolumeControl.volume(uid: uid)
                let muted = HALVolumeControl.isMuted(uid: uid)
                let volumeMatches = current.map { abs($0 - desiredVolume) <= 0.02 } ?? false
                let muteMatches = muted.map { $0 == desiredMuted } ?? false
                if record?.lastVolume == nil, let current {
                    volume.current = current
                } else {
                    volume.current = desiredVolume
                    if !volumeMatches {
                        HALVolumeControl.setVolume(uid: uid, value: desiredVolume)
                    }
                }
                if record?.lastMuted == nil, let muted {
                    volume.isMuted = muted
                } else {
                    volume.isMuted = desiredMuted
                    if volume.supportsMute, !muteMatches {
                        HALVolumeControl.setMuted(uid: uid, muted: desiredMuted)
                    }
                }
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
        if var resolved = next, resolved.displayKey == nil, let uid = resolved.uid {
            if resolved.volume.backend == .coreAudio {
                let keepDesired = speaker?.uid == uid
                let desiredVolume = keepDesired ? (speaker?.volume.current ?? resolved.volume.current) : resolved.volume.current
                let desiredMuted = keepDesired ? (speaker?.volume.isMuted ?? resolved.volume.isMuted) : resolved.volume.isMuted
                let current = HALVolumeControl.volume(uid: uid)
                let muted = HALVolumeControl.isMuted(uid: uid)
                if keepDesired, abs((current ?? desiredVolume) - desiredVolume) > 0.02 {
                    HALVolumeControl.setVolume(uid: uid, value: desiredVolume)
                    resolved.volume.current = desiredVolume
                } else if let current {
                    resolved.volume.current = current
                } else if keepDesired {
                    resolved.volume.current = desiredVolume
                }
                if keepDesired, resolved.volume.supportsMute, (muted ?? desiredMuted) != desiredMuted {
                    HALVolumeControl.setMuted(uid: uid, muted: desiredMuted)
                    resolved.volume.isMuted = desiredMuted
                } else if let muted {
                    resolved.volume.isMuted = muted
                } else if keepDesired {
                    resolved.volume.isMuted = desiredMuted
                }
            }
            next = resolved
        }
        speaker = next
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
