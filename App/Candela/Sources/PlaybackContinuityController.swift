#if !CANDELA_MAS
import AppKit
import AudioKit
import CoreGraphics
import Darwin
import IOKit.hidsystem
import os

/// Restores media playback only when an output-device migration interrupted a
/// GUI media client that was actively producing audio before the switch.
@MainActor
final class PlaybackContinuityController {
    struct Snapshot {
        let processIDs: Set<Int32>
        let targetOutputUID: String
    }

    private let log = Logger(subsystem: "app.candela.macos", category: "audio-route")
    private var restoreTask: Task<Void, Never>?

    func captureBeforeRouteChange(targetOutputUID: String) -> Snapshot? {
        let processIDs = Self.runningGUIOutputProcessIDs()
        // System media commands target one now-playing application. Only arm
        // continuity protection when there is one unambiguous GUI audio client.
        guard processIDs.count == 1 else { return nil }
        return Snapshot(processIDs: processIDs, targetOutputUID: targetOutputUID)
    }

    func restoreIfInterrupted(after snapshot: Snapshot?) {
        restoreTask?.cancel()
        guard let snapshot else { return }

        restoreTask = Task { [weak self] in
            do {
                // The affected players stop about two seconds after Core Audio
                // migrates the stream. Let that decision settle before checking.
                try await Task.sleep(for: .milliseconds(2_800))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let runningProcessIDs = Self.runningGUIOutputProcessIDs()
            let currentOutputUID = HALDeviceEnumerator.defaultOutputUID()
            let shouldResume = PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: snapshot.processIDs,
                runningProcessIDs: runningProcessIDs,
                expectedOutputUID: snapshot.targetOutputUID,
                currentOutputUID: currentOutputUID
            )
            self?.log.info(
                "checked playback after output migration; runningProcesses=\(runningProcessIDs.count, privacy: .public) routeMatches=\(currentOutputUID == snapshot.targetOutputUID, privacy: .public) shouldResume=\(shouldResume, privacy: .public)"
            )
            guard shouldResume else {
                return
            }

            // Some players keep a stale "playing" state after their audio stream
            // dies. An explicit pause first makes the following play/pause key a
            // deterministic request to start a fresh stream.
            guard Self.pauseNowPlayingApplication() else { return }
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard PlaybackContinuityPolicy.shouldResume(
                capturedProcessIDs: snapshot.processIDs,
                runningProcessIDs: Self.runningGUIOutputProcessIDs(),
                expectedOutputUID: snapshot.targetOutputUID,
                currentOutputUID: HALDeviceEnumerator.defaultOutputUID()
            ) else {
                return
            }

            Self.postPlayPauseMediaKey()
            self?.log.info(
                "restored playback after output migration; capturedProcesses=\(snapshot.processIDs.count, privacy: .public)"
            )
        }
    }

    func cancel() {
        restoreTask?.cancel()
        restoreTask = nil
    }

    private static func runningGUIOutputProcessIDs() -> Set<Int32> {
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        return Set(HALDeviceEnumerator.runningOutputProcessIDs().filter { pid in
            guard pid != ownPID else { return false }
            guard let application = NSRunningApplication(processIdentifier: pid) else { return false }
            return application.activationPolicy == .regular
        })
    }

    private static func postPlayPauseMediaKey() {
        postMediaKey(isDown: true)
        postMediaKey(isDown: false)
    }

    private typealias MediaRemoteSendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendMediaRemoteCommand: MediaRemoteSendCommand? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else {
            return nil
        }
        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            dlclose(handle)
            return nil
        }
        return unsafeBitCast(symbol, to: MediaRemoteSendCommand.self)
    }()

    private static func pauseNowPlayingApplication() -> Bool {
        sendMediaRemoteCommand?(1, nil) ?? false
    }

    private static func postMediaKey(isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = (Int(NX_KEYTYPE_PLAY) << 16) | (keyState << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
#endif
