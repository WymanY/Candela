import CoreAudio
import Foundation

/// Same fourcc as `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`.
/// Call only through `AudioObject*` when `HasProperty` is true. Never AHS.
public let kCandelaVirtualMainVolume: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'

public enum HALFourCC {
    public static func make(_ fourCC: String) -> UInt32 {
        let bytes = Array(fourCC.utf8)
        guard bytes.count == 4 else { return 0 }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }

    public static func string(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}

/// HAL volume/mute. Write order is §9.4 / K20. No VirtualMasterMute. Never AHS.
public enum HALVolumeControl {
    public enum VolumeWritePath: Equatable, Sendable {
        case virtualMainVolume(AudioObjectPropertyScope)
        case volumeScalarMain
        case volumeScalarChannels
        case unavailable
    }

    public enum MuteWritePath: Equatable, Sendable {
        case muteMain
        case muteChannels
        case unavailable
    }

    public static func virtualMainVolumeAddress(
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        HALObject.address(kCandelaVirtualMainVolume, scope: scope)
    }

    public static func volumeScalarAddress(
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        HALObject.address(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: element
        )
    }

    public static func muteAddress(
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        HALObject.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: element
        )
    }

    public static func streamConfigurationAddress() -> AudioObjectPropertyAddress {
        HALObject.address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    /// Channel elements implied by an output `AudioBufferList`. Starts at 1.
    /// Do not treat stream/`mNumberBuffers` as a channel count.
    public static func channelElements(
        bufferChannelCounts: [UInt32]
    ) -> [AudioObjectPropertyElement] {
        var element: AudioObjectPropertyElement = 1
        var result: [AudioObjectPropertyElement] = []
        result.reserveCapacity(bufferChannelCounts.reduce(0) { $0 + Int($1) })
        for count in bufferChannelCounts {
            var remaining = count
            while remaining > 0 {
                result.append(element)
                element += 1
                remaining -= 1
            }
        }
        return result
    }

    public static func clampedScalar(_ value: Double) -> Float32 {
        if value.isNaN { return 0 }
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        return Float32(value)
    }

    public static func volumeWritePath(
        hasProperty: (AudioObjectPropertyAddress) -> Bool,
        isSettable: (AudioObjectPropertyAddress) -> Bool,
        channelElements: [AudioObjectPropertyElement]
    ) -> VolumeWritePath {
        let vmvcOutput = virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeOutput)
        if hasProperty(vmvcOutput) {
            if isSettable(vmvcOutput) {
                return .virtualMainVolume(kAudioObjectPropertyScopeOutput)
            }
        } else {
            let vmvcGlobal = virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeGlobal)
            if hasProperty(vmvcGlobal), isSettable(vmvcGlobal) {
                return .virtualMainVolume(kAudioObjectPropertyScopeGlobal)
            }
        }

        let main = volumeScalarAddress(element: kAudioObjectPropertyElementMain)
        if hasProperty(main), isSettable(main) {
            return .volumeScalarMain
        }

        for element in channelElements {
            let address = volumeScalarAddress(element: element)
            if hasProperty(address), isSettable(address) {
                return .volumeScalarChannels
            }
        }
        return .unavailable
    }

    public static func muteWritePath(
        hasProperty: (AudioObjectPropertyAddress) -> Bool,
        isSettable: (AudioObjectPropertyAddress) -> Bool,
        channelElements: [AudioObjectPropertyElement]
    ) -> MuteWritePath {
        let main = muteAddress(element: kAudioObjectPropertyElementMain)
        if hasProperty(main), isSettable(main) {
            return .muteMain
        }
        for element in channelElements {
            let address = muteAddress(element: element)
            if hasProperty(address), isSettable(address) {
                return .muteChannels
            }
        }
        return .unavailable
    }

    public static func hasVolumeProperty(
        hasProperty: (AudioObjectPropertyAddress) -> Bool,
        channelElements: [AudioObjectPropertyElement]
    ) -> Bool {
        if hasProperty(virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeOutput)) {
            return true
        }
        if hasProperty(virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeGlobal)) {
            return true
        }
        if hasProperty(volumeScalarAddress(element: kAudioObjectPropertyElementMain)) {
            return true
        }
        return channelElements.contains { hasProperty(volumeScalarAddress(element: $0)) }
    }

    public static func hasMuteProperty(
        hasProperty: (AudioObjectPropertyAddress) -> Bool,
        channelElements: [AudioObjectPropertyElement]
    ) -> Bool {
        if hasProperty(muteAddress(element: kAudioObjectPropertyElementMain)) {
            return true
        }
        return channelElements.contains { hasProperty(muteAddress(element: $0)) }
    }

    public static func outputChannelElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var counts: [UInt32] = []
        let ok = HALObject.withRaw(deviceID, streamConfigurationAddress()) { raw, _ in
            let list = raw.assumingMemoryBound(to: AudioBufferList.self)
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            counts = buffers.map(\.mNumberChannels)
        }
        guard ok else { return [] }
        return channelElements(bufferChannelCounts: counts)
    }

    @discardableResult
    public static func setVolume(uid: String, value: Double) -> Bool {
        guard let deviceID = HALDeviceEnumerator.deviceID(forUID: uid) else { return false }
        let scalar = clampedScalar(value)
        let channels = outputChannelElements(for: deviceID)
        let path = volumeWritePath(
            hasProperty: { HALObject.has(deviceID, $0) },
            isSettable: { HALObject.isSettable(deviceID, $0) },
            channelElements: channels
        )
        switch path {
        case .virtualMainVolume(let scope):
            return HALObject.set(deviceID, virtualMainVolumeAddress(scope: scope), scalar)
        case .volumeScalarMain:
            return HALObject.set(
                deviceID,
                volumeScalarAddress(element: kAudioObjectPropertyElementMain),
                scalar
            )
        case .volumeScalarChannels:
            var wrote = false
            for element in channels {
                let address = volumeScalarAddress(element: element)
                if HALObject.set(deviceID, address, scalar) {
                    wrote = true
                }
            }
            return wrote
        case .unavailable:
            return false
        }
    }

    public static func volume(uid: String) -> Double? {
        guard let deviceID = HALDeviceEnumerator.deviceID(forUID: uid) else { return nil }
        let channels = outputChannelElements(for: deviceID)
        let path = volumeWritePath(
            hasProperty: { HALObject.has(deviceID, $0) },
            isSettable: { HALObject.isSettable(deviceID, $0) },
            channelElements: channels
        )
        if let value = readVolume(deviceID: deviceID, path: path, channelElements: channels) {
            return value
        }
        return readVolumeIfPresent(deviceID: deviceID, channelElements: channels)
    }

    @discardableResult
    public static func setMuted(uid: String, muted: Bool) -> Bool {
        guard let deviceID = HALDeviceEnumerator.deviceID(forUID: uid) else { return false }
        let flag: UInt32 = muted ? 1 : 0
        let channels = outputChannelElements(for: deviceID)
        let path = muteWritePath(
            hasProperty: { HALObject.has(deviceID, $0) },
            isSettable: { HALObject.isSettable(deviceID, $0) },
            channelElements: channels
        )
        switch path {
        case .muteMain:
            return HALObject.set(
                deviceID,
                muteAddress(element: kAudioObjectPropertyElementMain),
                flag
            )
        case .muteChannels:
            var wrote = false
            for element in channels {
                if HALObject.set(deviceID, muteAddress(element: element), flag) {
                    wrote = true
                }
            }
            return wrote
        case .unavailable:
            return false
        }
    }

    public static func isMuted(uid: String) -> Bool? {
        guard let deviceID = HALDeviceEnumerator.deviceID(forUID: uid) else { return nil }
        let channels = outputChannelElements(for: deviceID)
        let path = muteWritePath(
            hasProperty: { HALObject.has(deviceID, $0) },
            isSettable: { HALObject.isSettable(deviceID, $0) },
            channelElements: channels
        )
        switch path {
        case .muteMain:
            return HALObject.uint32(
                deviceID,
                muteAddress(element: kAudioObjectPropertyElementMain)
            ).map { $0 != 0 }
        case .muteChannels:
            return mutedIfAllChannels(deviceID: deviceID, channelElements: channels)
        case .unavailable:
            if let main = HALObject.uint32(
                deviceID,
                muteAddress(element: kAudioObjectPropertyElementMain)
            ) {
                return main != 0
            }
            return mutedIfAllChannels(deviceID: deviceID, channelElements: channels)
        }
    }

    private static func readVolume(
        deviceID: AudioDeviceID,
        path: VolumeWritePath,
        channelElements: [AudioObjectPropertyElement]
    ) -> Double? {
        switch path {
        case .virtualMainVolume(let scope):
            return HALObject.float32(deviceID, virtualMainVolumeAddress(scope: scope)).map(Double.init)
        case .volumeScalarMain:
            return HALObject.float32(
                deviceID,
                volumeScalarAddress(element: kAudioObjectPropertyElementMain)
            ).map(Double.init)
        case .volumeScalarChannels:
            for element in channelElements {
                if let value = HALObject.float32(deviceID, volumeScalarAddress(element: element)) {
                    return Double(value)
                }
            }
            return nil
        case .unavailable:
            return nil
        }
    }

    private static func readVolumeIfPresent(
        deviceID: AudioDeviceID,
        channelElements: [AudioObjectPropertyElement]
    ) -> Double? {
        let vmvcOutput = virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeOutput)
        if let value = HALObject.float32(deviceID, vmvcOutput) {
            return Double(value)
        }
        if !HALObject.has(deviceID, vmvcOutput),
           let value = HALObject.float32(
               deviceID,
               virtualMainVolumeAddress(scope: kAudioObjectPropertyScopeGlobal)
           )
        {
            return Double(value)
        }
        if let value = HALObject.float32(
            deviceID,
            volumeScalarAddress(element: kAudioObjectPropertyElementMain)
        ) {
            return Double(value)
        }
        for element in channelElements {
            if let value = HALObject.float32(deviceID, volumeScalarAddress(element: element)) {
                return Double(value)
            }
        }
        return nil
    }

    private static func mutedIfAllChannels(
        deviceID: AudioDeviceID,
        channelElements: [AudioObjectPropertyElement]
    ) -> Bool? {
        var saw = false
        var allMuted = true
        for element in channelElements {
            guard let flag = HALObject.uint32(deviceID, muteAddress(element: element)) else {
                continue
            }
            saw = true
            if flag == 0 {
                allMuted = false
            }
        }
        return saw ? allMuted : nil
    }
}
