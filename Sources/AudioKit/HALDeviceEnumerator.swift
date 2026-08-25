import CoreAudio
import DisplayCore
import Foundation

/// HAL output-device catalog. Uses `AudioObject*` only (K20). Never AHS.
public enum HALDeviceEnumerator {
    public static var devicesAddress: AudioObjectPropertyAddress {
        HALObject.address(
            kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    public static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        HALObject.address(
            kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    public static var transportAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioDevicePropertyTransportType)
    }

    public static var nameAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioObjectPropertyName)
    }

    public static var manufacturerAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioObjectPropertyManufacturer)
    }

    public static var uidAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioDevicePropertyDeviceUID)
    }

    public static var streamsAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioDevicePropertyStreams)
    }

    public static var outputStreamsAddress: AudioObjectPropertyAddress {
        HALObject.address(
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    public static var streamDirectionAddress: AudioObjectPropertyAddress {
        HALObject.address(kAudioStreamPropertyDirection)
    }

    /// Output streams report `kAudioStreamPropertyDirection == 0`.
    public static let outputStreamDirection: UInt32 = 0

    public static func outputDevices() -> [HALOutputDevice] {
        var devices: [HALOutputDevice] = []
        for deviceID in deviceIDs() {
            guard hasOutputStream(deviceID) else { continue }
            let uid = HALObject.string(deviceID, uidAddress)
            guard !uid.isEmpty else { continue }
            let channels = HALVolumeControl.outputChannelElements(for: deviceID)
            devices.append(
                HALOutputDevice(
                    uid: uid,
                    name: HALObject.string(deviceID, nameAddress),
                    manufacturer: HALObject.string(deviceID, manufacturerAddress),
                    transport: HALObject.uint32(deviceID, transportAddress) ?? 0,
                    hasVolume: HALVolumeControl.hasVolumeProperty(
                        hasProperty: { HALObject.has(deviceID, $0) },
                        channelElements: channels
                    ),
                    hasMute: HALVolumeControl.hasMuteProperty(
                        hasProperty: { HALObject.has(deviceID, $0) },
                        channelElements: channels
                    )
                )
            )
        }
        return devices
    }

    public static func defaultOutputUID() -> String? {
        guard
            let deviceID: AudioDeviceID = HALObject.get(
                AudioObjectID(kAudioObjectSystemObject),
                defaultOutputDeviceAddress
            ),
            deviceID != kAudioObjectUnknown,
            deviceID != 0
        else {
            return nil
        }
        let uid = HALObject.string(deviceID, uidAddress)
        return uid.isEmpty ? nil : uid
    }

    @discardableResult
    public static func setDefaultOutputUID(_ uid: String) -> Bool {
        switchDefaultOutput(
            uid: uid,
            resolveDeviceID: deviceID(forUID:),
            writeDefault: { deviceID in
                HALObject.set(
                    AudioObjectID(kAudioObjectSystemObject),
                    defaultOutputDeviceAddress,
                    deviceID
                )
            },
            readDefaultUID: defaultOutputUID
        )
    }

    static func switchDefaultOutput(
        uid: String,
        resolveDeviceID: (String) -> AudioDeviceID?,
        writeDefault: (AudioDeviceID) -> Bool,
        readDefaultUID: () -> String?
    ) -> Bool {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let deviceID = resolveDeviceID(trimmed) else { return false }
        if readDefaultUID() == trimmed {
            return true
        }
        // Core Audio applies some property changes asynchronously. A successful
        // write is the acknowledgement for this request; the default-output
        // listener is the source of truth for the eventual route state.
        return writeDefault(deviceID)
    }

    public static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        for deviceID in deviceIDs() {
            if HALObject.string(deviceID, uidAddress) == uid {
                return deviceID
            }
        }
        return nil
    }

    public static func hasOutputStream(_ deviceID: AudioDeviceID) -> Bool {
        let scoped = HALObject.array(deviceID, outputStreamsAddress, as: AudioObjectID.self)
        let global = HALObject.array(deviceID, streamsAddress, as: AudioObjectID.self)
        let streams = scoped.isEmpty ? global : scoped
        for stream in streams where stream != kAudioObjectUnknown {
            if HALObject.uint32(stream, streamDirectionAddress) == outputStreamDirection {
                return true
            }
        }
        return false
    }

    static func deviceIDs() -> [AudioDeviceID] {
        HALObject.array(AudioObjectID(kAudioObjectSystemObject), devicesAddress, as: AudioDeviceID.self)
            .filter { $0 != kAudioObjectUnknown && $0 != 0 }
    }
}

// MARK: - AudioObject* I/O (never AudioHardwareService*)

enum HALObject {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        return AudioObjectHasProperty(object, &addr)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(object, &addr, &settable)
        return status == noErr && settable.boolValue
    }

    static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        guard has(object, address) else { return nil }
        var addr = address
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw)
        guard status == noErr else { return nil }
        return raw.load(as: T.self)
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        guard has(object, address), isSettable(object, address) else { return false }
        var addr = address
        var storage = value
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &storage) { pointer in
            AudioObjectSetPropertyData(object, &addr, 0, nil, size, pointer) == noErr
        }
    }

    static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        get(object, address)
    }

    static func float32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        get(object, address)
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String {
        guard has(object, address) else { return "" }
        var addr = address
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let unmanaged else { return "" }
        return unmanaged.takeRetainedValue() as String
    }

    static func array<T>(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        as type: T.Type
    ) -> [T] {
        guard has(object, address) else { return [] }
        var addr = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<T>.size
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        var ioSize = size
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &ioSize, buffer)
        guard status == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    static func withRaw(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        body: (UnsafeMutableRawPointer, Int) -> Void
    ) -> Bool {
        guard has(object, address) else { return false }
        var addr = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        var ioSize = size
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &ioSize, raw) == noErr else {
            return false
        }
        body(raw, Int(ioSize))
        return true
    }
}
