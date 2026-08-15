import CoreAudio
import CoreGraphics
import Foundation

/// Software attenuation for HDMI/DP speakers that expose no HAL or DDC volume.
///
/// At 100% unmuted the tap is torn down so audio stays on the native path.
/// Below that, a private process tap mutes the dry signal and this process
/// plays the same stream back onto the matched device with gain applied.
/// The default output device is never changed.
public final class SoftwareVolumeControl: @unchecked Sendable {
    public static let shared = SoftwareVolumeControl()

    public static let passthroughThreshold = 0.999

    private let queue = DispatchQueue(label: "candela.audio.software")
    private var sessions: [String: Session] = [:]

    private init() {}

    public static func shouldPassthrough(volume: Double, muted: Bool) -> Bool {
        !muted && volume >= passthroughThreshold
    }

    public static func gain(volume: Double, muted: Bool) -> Float32 {
        if muted { return 0 }
        if volume.isNaN || volume <= 0 { return 0 }
        if volume >= 1 { return 1 }
        return Float32(volume * volume)
    }

    public func apply(uid: String, volume: Double, muted: Bool) {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async {
            self.applyLocked(uid: trimmed, volume: volume, muted: muted)
        }
    }

    public func stop(uid: String) {
        queue.async { self.stopLocked(uid: uid) }
    }

    public func stopAll() {
        queue.sync {
            for uid in Array(self.sessions.keys) {
                self.stopLocked(uid: uid)
            }
        }
    }

    public func retain(uids: Set<String>) {
        queue.sync {
            for uid in Array(self.sessions.keys) where !uids.contains(uid) {
                self.stopLocked(uid: uid)
            }
        }
    }

    private func applyLocked(uid: String, volume: Double, muted: Bool) {
        let gain = Self.gain(volume: volume, muted: muted)
        if Self.shouldPassthrough(volume: volume, muted: muted) {
            stopLocked(uid: uid)
            return
        }
        if let session = sessions[uid] {
            session.gain.pointee = gain
            return
        }
        guard let session = startLocked(uid: uid, gain: gain) else { return }
        sessions[uid] = session
    }

    private func startLocked(uid: String, gain: Float32) -> Session? {
        if #available(macOS 14.2, *) {
            return startTapLocked(uid: uid, gain: gain)
        }
        return nil
    }

    @available(macOS 14.2, *)
    private func startTapLocked(uid: String, gain: Float32) -> Session? {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        guard let processObject = Self.processObjectID() else { return nil }

        let description = CATapDescription(
            excludingProcesses: [processObject],
            deviceUID: uid,
            stream: 0
        )
        description.name = "Candela Software Volume"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted

        var tapID = AudioObjectID()
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        if status != noErr || tapID == kAudioObjectUnknown || tapID == 0 {
            return nil
        }

        let tapUID = HALObject.string(tapID, HALObject.address(kAudioTapPropertyUID))
        guard !tapUID.isEmpty else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let aggregateUID = "candela.software-volume.\(UUID().uuidString)"
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: 1,
        ]
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Candela Volume",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: uid],
            ],
            kAudioAggregateDeviceTapListKey: [tapEntry],
        ]

        var aggregateID = AudioObjectID()
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID)
        if status != noErr || aggregateID == 0 {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let gainStorage = UnsafeMutablePointer<Float32>.allocate(capacity: 1)
        gainStorage.initialize(to: gain)

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, inputData, _, outputData, _ in
            SoftwareVolumeControl.mix(
                input: inputData,
                output: outputData,
                gain: gainStorage.pointee
            )
        }
        guard status == noErr, let ioProcID else {
            gainStorage.deinitialize(count: 1)
            gainStorage.deallocate()
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        if status != noErr {
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            gainStorage.deinitialize(count: 1)
            gainStorage.deallocate()
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        return Session(
            tapID: tapID,
            aggregateID: aggregateID,
            ioProcID: ioProcID,
            gain: gainStorage
        )
    }

    private func stopLocked(uid: String) {
        guard let session = sessions.removeValue(forKey: uid) else { return }
        session.teardown()
    }

    private static func processObjectID() -> AudioObjectID? {
        var address = HALObject.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = ProcessInfo.processInfo.processIdentifier
        var objectID = AudioObjectID()
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifier,
            &size,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown, objectID != 0 else {
            return nil
        }
        return objectID
    }

    static func mix(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        gain: Float32
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard !outputs.isEmpty else { return }

        for (index, outBuffer) in outputs.enumerated() {
            guard let outRaw = outBuffer.mData else { continue }
            let outCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float32>.size
            let outSamples = outRaw.assumingMemoryBound(to: Float32.self)
            if gain <= 0 || inputs.isEmpty {
                outSamples.update(repeating: 0, count: outCount)
                continue
            }
            let source = inputs[min(index, inputs.count - 1)]
            guard let inRaw = source.mData else {
                outSamples.update(repeating: 0, count: outCount)
                continue
            }
            let inCount = Int(source.mDataByteSize) / MemoryLayout<Float32>.size
            let inSamples = inRaw.assumingMemoryBound(to: Float32.self)
            let count = min(outCount, inCount)
            var cursor = 0
            while cursor < count {
                outSamples[cursor] = inSamples[cursor] * gain
                cursor += 1
            }
            if count < outCount {
                (outSamples + count).update(repeating: 0, count: outCount - count)
            }
        }
    }

    private struct Session {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        var ioProcID: AudioDeviceIOProcID
        var gain: UnsafeMutablePointer<Float32>

        func teardown() {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            gain.deinitialize(count: 1)
            gain.deallocate()
        }
    }
}
