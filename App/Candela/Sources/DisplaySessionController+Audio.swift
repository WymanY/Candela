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
            if let uid {
                let liveCurrent = HALVolumeControl.volume(uid: uid)
                let liveMuted = HALVolumeControl.isMuted(uid: uid)
                volume = VolumeResolution.adoptingLiveOutput(
                    volume,
                    deviceUID: uid,
                    hasHALVolume: device?.hasVolume == true || liveCurrent != nil,
                    current: liveCurrent,
                    muted: liveMuted
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
        if var resolved = next, let uid = resolved.uid {
            let device = devices.first(where: { $0.uid == uid })
            let liveCurrent = HALVolumeControl.volume(uid: uid)
            let liveMuted = HALVolumeControl.isMuted(uid: uid)
            resolved.volume = VolumeResolution.adoptingLiveOutput(
                resolved.volume,
                deviceUID: uid,
                hasHALVolume: device?.hasVolume == true || liveCurrent != nil,
                current: liveCurrent,
                muted: liveMuted
            )
            if let key = resolved.displayKey,
               let index = snapshots.firstIndex(where: { $0.id.persistentKey == key })
            {
                snapshots[index].volume = VolumeResolution.adoptingLiveOutput(
                    snapshots[index].volume,
                    deviceUID: uid,
                    hasHALVolume: device?.hasVolume == true || liveCurrent != nil,
                    current: resolved.volume.current,
                    muted: resolved.volume.isMuted
                )
            }
            next = resolved
        }
        speaker = next
        observeActiveSpeakerVolume()
    }

    func beginSpeakerVolumeAdjustment() {
        isAdjustingSpeakerVolume = true
    }

    func endSpeakerVolumeAdjustment(_ value: Double) {
        isAdjustingSpeakerVolume = false
        applyInteractiveSpeakerVolume(value, persist: true, forceLiveWrite: true, notify: false)
    }

    func setSpeakerVolume(_ value: Double) {
        applyInteractiveSpeakerVolume(
            value,
            persist: !isAdjustingSpeakerVolume,
            forceLiveWrite: !isAdjustingSpeakerVolume,
            notify: !isAdjustingSpeakerVolume
        )
    }

    func setSpeakerMuted(_ muted: Bool) {
        if let key = speaker?.displayKey {
            applySpeakerMute(key: key, muted: muted, persist: true, notify: true)
            return
        }
        applyStandaloneSpeaker(volume: speaker?.volume.current, muted: muted, persist: true, notify: true)
    }

    private func applyInteractiveSpeakerVolume(
        _ value: Double,
        persist: Bool,
        forceLiveWrite: Bool,
        notify: Bool
    ) {
        let clamped = min(1, max(0, value))
        let mutedChange = VolumeInteractionPolicy.mutedState(
            forVolume: clamped,
            currentlyMuted: speaker?.volume.isMuted == true
        )
        let writeLive = forceLiveWrite || VolumeInteractionPolicy.shouldWriteLiveVolume(lastWrite: lastLiveVolumeWrite)
        if let key = speaker?.displayKey {
            if let mutedChange {
                applySpeakerMute(key: key, muted: mutedChange, persist: true, notify: false, writeLive: false)
            }
            applySpeakerVolume(
                key: key,
                value: clamped,
                persist: persist,
                notify: notify,
                writeLive: writeLive
            )
            return
        }
        applyStandaloneSpeaker(
            volume: clamped,
            muted: mutedChange,
            persist: persist || mutedChange != nil,
            notify: notify,
            writeLive: writeLive
        )
    }

    func applySpeakerVolume(
        key: String,
        value: Double,
        persist: Bool,
        notify: Bool,
        writeLive: Bool = true
    ) {
        let clamped = min(1, max(0, value))
        if persist {
            var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
            if VolumeInteractionPolicy.shouldPersist(previous: record.lastVolume, next: clamped) {
                record.lastVolume = clamped
                persistence.save(record)
            }
        }
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].volume.current = clamped
            boxes[key]?.setVolume(clamped)
            if writeLive {
                applyLiveVolume(snapshots[index])
                lastLiveVolumeWrite = Date()
            }
        } else {
            boxes[key]?.setVolume(clamped)
        }
        if var current = speaker, current.displayKey == key {
            current.volume.current = clamped
            speaker = current
        }
        if notify {
            refreshSpeaker()
            onChange?()
        }
    }

    func applySpeakerMute(key: String, muted: Bool, persist: Bool, notify: Bool, writeLive: Bool = true) {
        if persist {
            var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
            if record.lastMuted != muted {
                record.lastMuted = muted
                persistence.save(record)
            }
        }
        boxes[key]?.setMuted(muted)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].volume.isMuted = muted
            if writeLive {
                applyLiveVolume(snapshots[index])
                lastLiveVolumeWrite = Date()
            }
        }
        if var current = speaker, current.displayKey == key {
            current.volume.isMuted = muted
            speaker = current
        }
        if notify {
            refreshSpeaker()
            onChange?()
        }
    }

    private func applyStandaloneSpeaker(
        volume: Double?,
        muted: Bool?,
        persist: Bool,
        notify: Bool,
        writeLive: Bool = true
    ) {
        guard var current = speaker, let uid = current.uid else { return }
        if let volume {
            current.volume.current = min(1, max(0, volume))
        }
        if let muted {
            current.volume.isMuted = muted
        }
        speaker = current
        if writeLive {
            switch current.volume.backend {
            case .coreAudio:
                HALVolumeControl.setVolume(uid: uid, value: current.volume.current)
                if current.volume.supportsMute {
                    HALVolumeControl.setMuted(uid: uid, muted: current.volume.isMuted)
                }
                lastLiveVolumeWrite = Date()
            case .software:
                SoftwareVolumeControl.shared.apply(
                    uid: uid,
                    volume: current.volume.current,
                    muted: current.volume.isMuted
                )
                lastLiveVolumeWrite = Date()
            case .ddc, .none:
                break
            }
        }
        _ = persist
        if notify {
            onChange?()
        }
    }

    @discardableResult
    func setDefaultSpeaker(uid: String) -> Bool {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if Self.shouldUseFakeHardware {
            return false
        }
#if !CANDELA_MAS
        if HALDeviceEnumerator.defaultOutputUID() == trimmed {
            return true
        }
        let playbackSnapshot = playbackContinuity.captureBeforeRouteChange(targetOutputUID: trimmed)
#endif
        guard HALDeviceEnumerator.setDefaultOutputUID(trimmed) else { return false }
#if !CANDELA_MAS
        playbackContinuity.restoreIfInterrupted(after: playbackSnapshot)
#endif
        return true
    }
}
