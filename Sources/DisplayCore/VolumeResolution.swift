import Foundation

/// Chooses HAL, DDC, or software volume after a device match.
/// Built-in / virtual rows never call this.
public enum VolumeResolution {
    public static func bind(
        device: HALOutputDevice?,
        existing: VolumeCapabilities,
        lastVolume: Double?,
        lastMuted: Bool?
    ) -> VolumeCapabilities {
        var volume = existing

        guard let device else {
            if volume.backend == .ddc, volume.supportsVolume {
                return volume
            }
            if volume.backend == .software {
                volume.backend = .none
                volume.supportsVolume = false
                volume.supportsMute = false
                volume.audioDeviceUID = nil
            }
            return volume
        }

        volume.audioDeviceUID = device.uid

        if device.hasVolume {
            volume.backend = .coreAudio
            volume.supportsVolume = true
            volume.supportsMute = device.hasMute || volume.supportsMute
            return volume
        }

        if volume.backend == .ddc, volume.supportsVolume {
            return volume
        }

        if volume.backend != .software {
            volume.current = lastVolume ?? (volume.current > 0 ? volume.current : 1)
            volume.isMuted = lastMuted ?? volume.isMuted
            volume.notes = volume.notes ?? "Software volume"
        }
        volume.backend = .software
        volume.supportsVolume = true
        volume.supportsMute = true
        return volume
    }

    /// Overlay a live HAL read onto an already-bound volume. Does not invent values.
    public static func adoptingHAL(
        _ volume: VolumeCapabilities,
        current: Double?,
        muted: Bool?
    ) -> VolumeCapabilities {
        var next = volume
        if let current {
            next.current = min(1, max(0, current))
        }
        if let muted {
            next.isMuted = muted
        }
        return next
    }
}


public enum VolumeTiming {
    public static let liveWriteInterval: TimeInterval = 0.05
    public static let echoIgnoreInterval: TimeInterval = 0.25
    public static let persistDelta = 0.02
}

/// Slider drag should write hardware sparingly and ignore our own HAL echoes.
public enum VolumeInteractionPolicy {
    public static func shouldIgnoreHALEcho(
        isAdjusting: Bool,
        lastWrite: Date?,
        now: Date = Date(),
        ignoreInterval: TimeInterval = VolumeTiming.echoIgnoreInterval
    ) -> Bool {
        if isAdjusting { return true }
        guard let lastWrite else { return false }
        return now.timeIntervalSince(lastWrite) < ignoreInterval
    }

    public static func shouldWriteLiveVolume(
        lastWrite: Date?,
        now: Date = Date(),
        interval: TimeInterval = VolumeTiming.liveWriteInterval
    ) -> Bool {
        guard let lastWrite else { return true }
        return now.timeIntervalSince(lastWrite) >= interval
    }

    public static func shouldPersist(
        previous: Double?,
        next: Double,
        delta: Double = VolumeTiming.persistDelta
    ) -> Bool {
        guard let previous else { return true }
        return abs(previous - next) > delta
    }

    /// Dragging the slider to zero should look and act muted.
    public static func mutedState(forVolume value: Double, currentlyMuted: Bool) -> Bool? {
        if value <= 0 {
            return currentlyMuted ? nil : true
        }
        return currentlyMuted ? false : nil
    }
}
