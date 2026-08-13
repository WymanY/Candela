import CandelaPrivateIO
import CoreGraphics
import Dispatch
import DisplayCore
import Foundation

/// Injected writer for mailbox tests. Real I/O is DisplayServices then gamma.
public protocol BrightnessWriting: AnyObject {
    func writeBrightness(_ value: Double) -> Bool
}

/// Per-identity I/O box. Mailbox methods hop to `candela.io.<persistentKey>`.
public final class DisplayIOBox: @unchecked Sendable {
    public let persistentKey: String
    public var sessionDisplayID: UInt32
    public var onBrightnessCapabilitiesChange: ((BrightnessCapabilities) -> Void)?

    private let queue: DispatchQueue
    private let enablesHardware: Bool
    private let brightnessWriter: BrightnessWriting?

    private var brightness: Double
    private var volume: Double
    private var muted: Bool
    private var audioUID: String?
    private var brightnessCaps: BrightnessCapabilities
    private var volumeCaps: VolumeCapabilities
    private var context: BrightnessProbeContext
    private var backend: BrightnessBackendKind

    private var brightnessLatest: Double?
    private var volumeLatest: Double?
    private var muteLatest: Bool?
    private var ddcInFlight = false
    private var lastDDC: ContinuousClock.Instant?
    private var writeScheduled = false
    private var sliderHoldWork: DispatchWorkItem?
    private var waitSpacingWork: DispatchWorkItem?
    private var consecutiveFails = 0
    private var liveFailNotes: String?

    private let gamma = GammaBackend()
    private var keepAlive: DispatchSourceTimer?
    private var interferenceHits = 0
    private var interferenceStopped = false
    private var ddcClient: Arm64DDCClient?
    public var useDDCMute = false

    /// `enablesHardware` defaults to false so fakes/tests never touch a real `CGDirectDisplayID`.
    public init(
        snapshot: DisplaySnapshot,
        enablesHardware: Bool = false,
        brightnessWriter: BrightnessWriting? = nil
    ) {
        self.persistentKey = snapshot.id.persistentKey
        self.sessionDisplayID = snapshot.sessionDisplayID
        self.queue = DispatchQueue(label: "candela.io.\(snapshot.id.persistentKey)")
        self.enablesHardware = enablesHardware && brightnessWriter == nil
        self.brightnessWriter = brightnessWriter
        self.brightness = snapshot.brightness.current
        self.volume = snapshot.volume.current
        self.muted = snapshot.volume.isMuted
        self.audioUID = snapshot.volume.audioDeviceUID
        self.brightnessCaps = snapshot.brightness
        self.volumeCaps = snapshot.volume
        self.backend = snapshot.brightness.backend
        self.context = BrightnessProbeContext(
            vendorID: snapshot.id.fields.inputs.vendorID,
            isBuiltin: snapshot.isBuiltin
        )
    }

    deinit {
        sliderHoldWork?.cancel()
        waitSpacingWork?.cancel()
        keepAlive?.cancel()
        if enablesHardware {
            _ = gamma.restore(displayID: sessionDisplayID)
        }
    }

    public func setBrightness(_ value: Double) {
        let clamped = Self.clamp(value)
        queue.async {
            self.brightness = clamped
            self.brightnessCaps.current = clamped
            self.brightnessLatest = clamped
            if !self.writeScheduled {
                self.armSliderHoldLocked()
            }
        }
    }

    public func setVolume(_ value: Double) {
        let clamped = Self.clamp(value)
        queue.async {
            self.volume = clamped
            self.volumeCaps.current = clamped
            self.volumeLatest = clamped
            if !self.writeScheduled {
                self.armSliderHoldLocked()
            }
        }
    }

    public func setMuted(_ muted: Bool) {
        queue.async {
            self.muted = muted
            self.volumeCaps.isMuted = muted
            self.muteLatest = muted
            if !self.writeScheduled {
                self.armSliderHoldLocked()
            }
        }
    }

    public func currentBrightness() async -> Double {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.brightness) }
        }
    }

    public func currentVolume() async -> Double {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.volume) }
        }
    }

    public func isMuted() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.muted) }
        }
    }

    public func currentBrightnessCapabilities() async -> BrightnessCapabilities {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.brightnessCaps) }
        }
    }

    public func debugLastDDCStamped() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.lastDDC != nil) }
        }
    }

    public func probeBrightness(kind: DisplayKind) async -> BrightnessCapabilities {
        await probeBrightness(kind: kind, context: nil)
    }

    public func probeBrightness(kind: DisplayKind, context: BrightnessProbeContext) async -> BrightnessCapabilities {
        await probeBrightness(kind: kind, context: Optional(context))
    }

    public func bindAudio(uid: String?) {
        queue.async { self.audioUID = uid }
    }

    public func probeDDCVolume() async -> VolumeCapabilities {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.probeDDCVolumeLocked())
            }
        }
    }

    public func recreateHandles() async {
        await recreateHandles(sessionDisplayID: nil)
    }

    public func recreateHandles(sessionDisplayID: UInt32?) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let sessionDisplayID {
                    self.sessionDisplayID = sessionDisplayID
                }
                self.recreateHandlesLocked()
                continuation.resume()
            }
        }
    }

    public func restoreSoftwareOnQuit() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.restoreSoftwareLocked()
                continuation.resume()
            }
        }
    }

    /// Sync restore so quit can write the baseline LUT before `terminate`.
    public func restoreSoftwareOnQuitNow() {
        queue.sync { self.restoreSoftwareLocked() }
    }

    /// Exposes the private I/O pointer type without declaring any extern symbol.
    public static var ioavServiceRefSize: Int {
        MemoryLayout<IOAVServiceRef>.size
    }

    private func probeBrightness(kind: DisplayKind, context: BrightnessProbeContext?) async -> BrightnessCapabilities {
        await withCheckedContinuation { continuation in
            queue.async {
                if let context {
                    self.context = context
                }
                continuation.resume(returning: self.probeLocked(kind: kind))
            }
        }
    }

    private func probeLocked(kind: DisplayKind) -> BrightnessCapabilities {
        consecutiveFails = 0
        liveFailNotes = nil
        if kind == .virtualUnsupported {
            return commitBackendLocked(.none, current: brightness)
        }
        if !enablesHardware {
            return brightnessCaps
        }

        let skipHDR = shouldSkipDisplayServicesForHDR(
            vendorID: context.vendorID,
            hdrSupported: enablesHardware ? PrivateSymbols.isHDRSupported(sessionDisplayID) : nil,
            hdrEnabled: enablesHardware ? PrivateSymbols.isHDREnabled(sessionDisplayID) : nil
        )
        var dsValue: Float?
        if enablesHardware, !skipHDR {
            dsValue = DisplayServicesBackend.get(sessionDisplayID)
        }
        let ddcRead = probeDDCBrightnessLocked()
        let winner = probeBrightnessWinner(
            kind: kind,
            displayServicesSucceeded: dsValue != nil,
            skipDisplayServicesForHDR: skipHDR,
            softwareAllowed: context.softwareAllowed,
            gammaAvailable: true,
            isBuiltin: context.isBuiltin,
            ddcAvailable: ddcRead.available,
            forceDDC: context.forceDDC && !context.isBuiltin
        )

        switch winner {
        case .displayServices:
            if backend == .softwareGamma {
                _ = gamma.restore(displayID: sessionDisplayID)
                stopKeepAliveLocked()
            }
            ddcClient = nil
            if let dsValue {
                brightness = Double(dsValue)
            }
            return commitBackendLocked(.displayServices, current: brightness)
        case .ddc:
            if backend == .softwareGamma {
                _ = gamma.restore(displayID: sessionDisplayID)
                stopKeepAliveLocked()
            }
            if let current = ddcRead.current {
                brightness = current
            }
            brightnessCaps.ddcMax = ddcRead.max
            return commitBackendLocked(.ddc, current: brightness)
        case .softwareGamma:
            if enablesHardware {
                let prepared = gamma.prepareForProbe(
                    displayID: sessionDisplayID,
                    lastBrightness: context.lastBrightness,
                    restoreOnReconnect: context.restoreOnReconnect,
                    allowDimToBlack: context.allowDimToBlack
                )
                if !prepared.ok {
                    return commitBackendLocked(.none, current: brightness)
                }
                brightness = prepared.current
            }
            let caps = commitBackendLocked(.softwareGamma, current: brightness)
            updateKeepAliveLocked()
            return caps
        case .none:
            if backend == .softwareGamma {
                _ = gamma.restore(displayID: sessionDisplayID)
                stopKeepAliveLocked()
            }
            return commitBackendLocked(.none, current: brightness)
        }
    }

    private func recreateHandlesLocked() {
        guard enablesHardware else { return }
        let reapply = backend == .softwareGamma ? brightness : nil
        gamma.recapture(
            displayID: sessionDisplayID,
            reapply: reapply,
            allowDimToBlack: context.allowDimToBlack
        )
        recreateDDCClientLocked()
        updateKeepAliveLocked()
    }

    private func restoreSoftwareLocked() {
        stopKeepAliveLocked()
        sliderHoldWork?.cancel()
        sliderHoldWork = nil
        waitSpacingWork?.cancel()
        waitSpacingWork = nil
        writeScheduled = false
        guard enablesHardware else { return }
        _ = gamma.restore(displayID: sessionDisplayID)
    }

    private func armSliderHoldLocked() {
        sliderHoldWork?.cancel()
        writeScheduled = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.writeScheduled = false
            self.sliderHoldWork = nil
            self.scheduleNextLocked()
        }
        sliderHoldWork = work
        queue.asyncAfter(
            deadline: .now() + .milliseconds(BrightnessTiming.sliderHoldMilliseconds),
            execute: work
        )
    }

    private func scheduleNextLocked() {
        if ddcInFlight { return }
        if brightnessLatest == nil && volumeLatest == nil && muteLatest == nil {
            return
        }
        if brightnessLatest != nil {
            if brightnessUsesDDC {
                let wait = ddcWaitIntervalLocked()
                if wait > .zero {
                    armWaitSpacingLocked(wait) { self.beginWriteBrightnessLocked() }
                    return
                }
            }
            beginWriteBrightnessLocked()
            return
        }
        if volumeLatest != nil || muteLatest != nil {
            if volumeUsesDDC {
                let wait = ddcWaitIntervalLocked()
                if wait > .zero {
                    armWaitSpacingLocked(wait) { self.beginWriteVolumeLocked() }
                    return
                }
            }
            beginWriteVolumeLocked()
        }
    }

    private func beginWriteBrightnessLocked() {
        let toSend = brightnessLatest
        brightnessLatest = nil
        guard let toSend else { return }
        if brightnessUsesDDC {
            ddcInFlight = true
            _ = performDDCBrightnessPulseLocked(toSend)
            lastDDC = .now
            ddcInFlight = false
        } else {
            _ = performBrightnessWriteLocked(toSend)
        }
        scheduleNextLocked()
    }

    private func beginWriteVolumeLocked() {
        let volumeToSend = volumeLatest
        volumeLatest = nil
        let muteToSend = muteLatest
        muteLatest = nil
        if volumeUsesDDC {
            ddcInFlight = true
            if let volumeToSend {
                _ = performDDCVolumePulseLocked(volumeToSend)
            }
            if let muteToSend {
                _ = performDDCMuteLocked(muteToSend)
            }
            lastDDC = .now
            ddcInFlight = false
        }
        scheduleNextLocked()
    }

    @discardableResult
    private func performBrightnessWriteLocked(_ value: Double) -> Bool {
        let ok: Bool
        if let brightnessWriter {
            ok = brightnessWriter.writeBrightness(value)
        } else if !enablesHardware {
            ok = true
        } else {
            switch backend {
            case .displayServices:
                ok = DisplayServicesBackend.set(sessionDisplayID, Float(value))
            case .softwareGamma:
                ok = gamma.apply(
                    displayID: sessionDisplayID,
                    t: value,
                    allowDimToBlack: context.allowDimToBlack
                )
                updateKeepAliveLocked()
            case .ddc:
                ok = performDDCBrightnessPulseLocked(value)
                lastDDC = .now
            case .none:
                ok = false
            }
        }
        // DS / gamma / injected writer never stamp lastDDC or ddcInFlight.
        feedLiveFailureLocked(success: ok)
        return ok
    }

    private func feedLiveFailureLocked(success: Bool) {
        if success {
            consecutiveFails = 0
            return
        }
        consecutiveFails += 1
        guard let next = nextBackendAfterLiveFailure(
            current: backend,
            consecutiveFails: consecutiveFails,
            softwareAllowed: context.softwareAllowed
        ) else {
            return
        }
        if next == .softwareGamma {
            var applied = !enablesHardware
            if enablesHardware {
                if gamma.baseline == nil {
                    _ = gamma.captureBaseline(displayID: sessionDisplayID)
                }
                applied = gamma.apply(
                    displayID: sessionDisplayID,
                    t: brightness,
                    allowDimToBlack: context.allowDimToBlack
                )
            }
            if applied {
                liveFailNotes = "!"
                _ = commitBackendLocked(.softwareGamma, current: brightness)
                updateKeepAliveLocked()
            } else {
                liveFailNotes = "!"
                _ = commitBackendLocked(.none, current: brightness)
                stopKeepAliveLocked()
            }
        } else {
            if backend == .softwareGamma {
                _ = gamma.restore(displayID: sessionDisplayID)
            }
            liveFailNotes = "!"
            _ = commitBackendLocked(.none, current: brightness)
            stopKeepAliveLocked()
        }
        consecutiveFails = 0
        let caps = brightnessCaps
        onBrightnessCapabilitiesChange?(caps)
    }

    private func commitBackendLocked(_ next: BrightnessBackendKind, current: Double) -> BrightnessCapabilities {
        backend = next
        brightness = current
        let hdrWashes = next == .softwareGamma && (PrivateSymbols.isHDREnabled(sessionDisplayID) ?? false)
        let caps: BrightnessCapabilities
        switch next {
        case .displayServices:
            caps = BrightnessCapabilities(
                backend: .displayServices,
                supportsHardware: true,
                supportsSoftware: context.softwareAllowed,
                current: current,
                hdrWashes: false,
                notes: liveFailNotes
            )
        case .softwareGamma:
            caps = BrightnessCapabilities(
                backend: .softwareGamma,
                supportsHardware: false,
                supportsSoftware: gamma.supportsSoftware,
                current: current,
                hdrWashes: hdrWashes,
                notes: liveFailNotes
            )
        case .ddc:
            caps = BrightnessCapabilities(
                backend: .ddc,
                supportsHardware: true,
                supportsSoftware: context.softwareAllowed,
                current: current,
                ddcMax: brightnessCaps.ddcMax,
                notes: liveFailNotes
            )
        case .none:
            caps = BrightnessCapabilities(
                backend: .none,
                supportsHardware: false,
                supportsSoftware: false,
                current: current
            )
        }
        brightnessCaps = caps
        return caps
    }

    private var brightnessUsesDDC: Bool {
        backend == .ddc
    }

    private func ddcWaitIntervalLocked() -> Duration {
        guard let lastDDC else { return .zero }
        let elapsed = ContinuousClock.now - lastDDC
        let floor = Duration.milliseconds(BrightnessTiming.ddcWriteSpacingMilliseconds)
        if elapsed >= floor { return .zero }
        return floor - elapsed
    }

    private func armWaitSpacingLocked(_ wait: Duration, fire: @escaping () -> Void) {
        waitSpacingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.waitSpacingWork = nil
            fire()
        }
        waitSpacingWork = work
        let ns = wait.components.seconds * 1_000_000_000 + wait.components.attoseconds / 1_000_000_000
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(ns)), execute: work)
    }

    private var volumeUsesDDC: Bool {
        volumeCaps.backend == .ddc
    }

    private func ensureDDCClientLocked() {
        guard enablesHardware, !context.isBuiltin, Arm64DDCClient.isSupported else {
            ddcClient = nil
            return
        }
        if ddcClient?.displayID != sessionDisplayID {
            ddcClient = Arm64DDCClient(displayID: sessionDisplayID)
        }
    }

    private func recreateDDCClientLocked() {
        guard enablesHardware, !context.isBuiltin, Arm64DDCClient.isSupported else {
            ddcClient = nil
            return
        }
        if ddcClient == nil || ddcClient?.displayID != sessionDisplayID {
            ddcClient = Arm64DDCClient(displayID: sessionDisplayID)
        } else {
            try? ddcClient?.recreateHandle()
        }
    }

    private func probeDDCBrightnessLocked() -> (available: Bool, current: Double?, max: UInt16) {
        guard enablesHardware, !context.isBuiltin else {
            return (false, nil, 0)
        }
        ensureDDCClientLocked()
        guard let client = ddcClient, client.isAvailable else {
            return (false, nil, 0)
        }
        ddcInFlight = true
        defer {
            lastDDC = .now
            ddcInFlight = false
        }
        if let (current, max) = try? client.read(vcp: DDCPacket.VCP.brightness), max > 0 {
            return (true, Double(current) / Double(max), max)
        }
        if context.forceDDC {
            return (true, nil, 100)
        }
        return (false, nil, 0)
    }

    private func probeDDCVolumeLocked() -> VolumeCapabilities {
        if volumeCaps.backend == .coreAudio, volumeCaps.supportsVolume {
            return volumeCaps
        }
        guard enablesHardware, !context.isBuiltin else { return volumeCaps }
        ensureDDCClientLocked()
        guard let client = ddcClient, client.isAvailable else { return volumeCaps }
        ddcInFlight = true
        defer {
            lastDDC = .now
            ddcInFlight = false
        }
        guard let (current, max) = try? client.read(vcp: DDCPacket.VCP.volume), max > 0 else {
            return volumeCaps
        }
        volume = Double(current) / Double(max)
        volumeCaps = VolumeCapabilities(
            backend: .ddc,
            supportsVolume: true,
            supportsMute: true,
            current: volume,
            isMuted: volume == 0,
            audioDeviceUID: nil,
            notes: volumeCaps.notes
        )
        return volumeCaps
    }

    @discardableResult
    private func performDDCBrightnessPulseLocked(_ value: Double) -> Bool {
        pulseDDCLocked(vcp: DDCPacket.VCP.brightness, value: value, max: brightnessCaps.ddcMax)
    }

    @discardableResult
    private func performDDCVolumePulseLocked(_ value: Double) -> Bool {
        pulseDDCLocked(vcp: DDCPacket.VCP.volume, value: value, max: 100)
    }

    @discardableResult
    private func performDDCMuteLocked(_ muted: Bool) -> Bool {
        if useDDCMute {
            return pulseDDCLocked(vcp: DDCPacket.VCP.mute, value: muted ? 1 : 2, max: 2)
        }
        if muted {
            return performDDCVolumePulseLocked(0)
        }
        return performDDCVolumePulseLocked(volume == 0 ? 0.5 : volume)
    }

    @discardableResult
    private func pulseDDCLocked(vcp: UInt8, value: Double, max: UInt16) -> Bool {
        guard let client = ddcClient, client.isAvailable else { return false }
        let scale = max == 0 ? 100 : max
        let raw = UInt16((Self.clamp(value) * Double(scale)).rounded())
        var ok = false
        for cycle in 0..<2 {
            if cycle > 0 {
                usleep(10_000)
            }
            do {
                try client.write(vcp: vcp, value: raw)
                ok = true
            } catch {
                ok = false
            }
        }
        if !ok {
            do {
                try client.write(vcp: vcp, value: raw)
                ok = true
            } catch {
                ok = false
            }
        }
        if vcp == DDCPacket.VCP.brightness {
            feedLiveFailureLocked(success: ok)
        }
        return ok
    }

    private func updateKeepAliveLocked() {
        let shouldRun = enablesHardware
            && backend == .softwareGamma
            && brightness < 1.0
            && !interferenceStopped
            && gamma.supportsSoftware
        if shouldRun {
            startKeepAliveLocked()
        } else {
            stopKeepAliveLocked()
        }
    }

    private func startKeepAliveLocked() {
        if keepAlive != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(BrightnessTiming.gammaKeepAliveMilliseconds),
            repeating: .milliseconds(BrightnessTiming.gammaKeepAliveMilliseconds)
        )
        timer.setEventHandler { [weak self] in
            self?.keepAliveTickLocked()
        }
        timer.resume()
        keepAlive = timer
    }

    private func stopKeepAliveLocked() {
        keepAlive?.cancel()
        keepAlive = nil
    }

    private func keepAliveTickLocked() {
        guard enablesHardware, backend == .softwareGamma, brightness < 1.0 else {
            stopKeepAliveLocked()
            return
        }
        if let current = gamma.readTable(displayID: sessionDisplayID) {
            let expected = gamma.expectedPeak(t: gamma.lastAppliedT)
            if expected > 0, abs(Double(current.peak - expected)) > BrightnessTiming.interferenceEpsilon {
                interferenceHits += 1
                if interferenceHits >= BrightnessTiming.interferenceHitLimit {
                    interferenceStopped = true
                    stopKeepAliveLocked()
                    return
                }
            }
        }
        _ = gamma.apply(
            displayID: sessionDisplayID,
            t: brightness,
            allowDimToBlack: context.allowDimToBlack
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
