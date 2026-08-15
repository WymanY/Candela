import Foundation

/// The single output path macOS can play through at a time.
public struct SpeakerOutput: Equatable, Sendable {
    public var name: String
    public var uid: String?
    public var displayKey: String?
    public var volume: VolumeCapabilities

    public init(
        name: String,
        uid: String? = nil,
        displayKey: String? = nil,
        volume: VolumeCapabilities
    ) {
        self.name = name
        self.uid = uid
        self.displayKey = displayKey
        self.volume = volume
    }
}

public struct SpeakerChoice: Equatable, Sendable {
    public var uid: String
    public var name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Picks the active speaker. Only one output is selected at a time.
public enum SpeakerResolution {
    public static func resolve(
        snapshots: [DisplaySnapshot],
        defaultUID: String?,
        devices: [HALOutputDevice]
    ) -> SpeakerOutput? {
        if let defaultUID, !defaultUID.isEmpty {
            if let snapshot = snapshots.first(where: { $0.volume.audioDeviceUID == defaultUID }) {
                return SpeakerOutput(
                    name: snapshot.name,
                    uid: defaultUID,
                    displayKey: snapshot.id.persistentKey,
                    volume: snapshot.volume
                )
            }
            if let device = devices.first(where: { $0.uid == defaultUID }) {
                return SpeakerOutput(
                    name: displayName(for: device, snapshots: snapshots),
                    uid: device.uid,
                    displayKey: nil,
                    volume: VolumeCapabilities(
                        backend: device.hasVolume ? .coreAudio : .none,
                        supportsVolume: device.hasVolume,
                        supportsMute: device.hasMute,
                        current: 0,
                        audioDeviceUID: device.uid
                    )
                )
            }
        }

        if let snapshot = snapshots.first(where: { $0.volume.supportsVolume }) {
            return SpeakerOutput(
                name: snapshot.name,
                uid: snapshot.volume.audioDeviceUID,
                displayKey: snapshot.id.persistentKey,
                volume: snapshot.volume
            )
        }
        return nil
    }

    public static func choices(
        snapshots: [DisplaySnapshot],
        devices: [HALOutputDevice]
    ) -> [SpeakerChoice] {
        var seen = Set<String>()
        var result: [SpeakerChoice] = []
        for device in devices {
            let uid = device.uid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty, seen.insert(uid).inserted else { continue }
            if uid.hasPrefix("candela.software-volume.") { continue }
            result.append(
                SpeakerChoice(
                    uid: uid,
                    name: displayName(for: device, snapshots: snapshots)
                )
            )
        }
        return result
    }

    public static func displayName(
        for device: HALOutputDevice,
        snapshots: [DisplaySnapshot]
    ) -> String {
        if let snapshot = snapshots.first(where: { $0.volume.audioDeviceUID == device.uid }) {
            return snapshot.name
        }
        let named = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? device.uid : named
    }
}
