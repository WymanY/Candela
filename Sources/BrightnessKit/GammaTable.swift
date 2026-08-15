import CoreGraphics
import Foundation

/// `r'[i] = baselineR[i] * t` (same for G/B). No clamp — reconstruction may use t > 1.
public func scaleGamma(baseline: [Float], t: Float) -> [Float] {
    baseline.map { $0 * t }
}

public func gammaTablePeak(_ table: [Float]) -> Float {
    table.max() ?? 0
}

/// Invert a leftover dim if the current peak is clearly not a ColorSync baseline.
public func reconstructGammaBaseline(current: [Float], measuredT: Float) -> [Float] {
    if measuredT > 0.05 && measuredT < 0.98 {
        return scaleGamma(baseline: current, t: 1 / measuredT)
    }
    return current
}

struct GammaTable {
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    var count: UInt32 { UInt32(red.count) }

    var peak: Float {
        max(gammaTablePeak(red), gammaTablePeak(green), gammaTablePeak(blue))
    }
}

/// ColorSync LUT capture / apply. Never calls `CGDisplayRestoreColorSyncSettings()`.
final class GammaBackend {
    private(set) var baseline: GammaTable?
    private(set) var supportsSoftware = true
    private(set) var lastAppliedT: Double = 1.0
    private(set) var hasWritten = false

    func readTable(displayID: CGDirectDisplayID) -> GammaTable? {
        Self.readTransferTable(displayID: displayID)
    }

    @discardableResult
    func captureBaseline(displayID: CGDirectDisplayID) -> Bool {
        guard let table = readTable(displayID: displayID) else {
            supportsSoftware = false
            return false
        }
        baseline = table
        supportsSoftware = true
        return true
    }

    /// Recapture after reconfig. Restore our LUT first so we do not bake `t` into the new baseline.
    func recapture(displayID: CGDirectDisplayID, reapply t: Double?, allowDimToBlack: Bool) {
        if hasWritten {
            _ = restore(displayID: displayID)
        }
        guard captureBaseline(displayID: displayID) else { return }
        if let t {
            _ = apply(displayID: displayID, t: t, allowDimToBlack: allowDimToBlack)
        }
    }

    func prepareForProbe(
        displayID: CGDirectDisplayID,
        lastBrightness: Double?,
        restoreOnReconnect: Bool,
        allowDimToBlack: Bool
    ) -> (ok: Bool, current: Double) {
        guard let current = readTable(displayID: displayID) else {
            supportsSoftware = false
            return (false, 1)
        }
        let measuredT = Double(current.peak)
        baseline = GammaTable(
            red: reconstructGammaBaseline(current: current.red, measuredT: current.peak),
            green: reconstructGammaBaseline(current: current.green, measuredT: current.peak),
            blue: reconstructGammaBaseline(current: current.blue, measuredT: current.peak)
        )
        supportsSoftware = true
        if let target = gammaLaunchRepairTarget(
            measuredT: measuredT,
            lastBrightness: lastBrightness,
            restoreOnReconnect: restoreOnReconnect
        ) {
            guard apply(displayID: displayID, t: target, allowDimToBlack: allowDimToBlack) else {
                return (false, target)
            }
            return (true, lastAppliedT)
        }
        lastAppliedT = min(1, max(0, measuredT))
        return (true, lastAppliedT)
    }

    func apply(displayID: CGDirectDisplayID, t: Double, allowDimToBlack: Bool) -> Bool {
        guard let baseline else {
            supportsSoftware = false
            return false
        }
        let floor = allowDimToBlack ? 0.0 : BrightnessTiming.gammaFloor
        let scaled = Float(min(1, max(floor, t)))
        let red = scaleGamma(baseline: baseline.red, t: scaled)
        let green = scaleGamma(baseline: baseline.green, t: scaled)
        let blue = scaleGamma(baseline: baseline.blue, t: scaled)
        guard Self.writeTransferTable(displayID: displayID, red: red, green: green, blue: blue) else {
            supportsSoftware = false
            return false
        }
        lastAppliedT = Double(scaled)
        hasWritten = true
        return true
    }

    func restore(displayID: CGDirectDisplayID) -> Bool {
        guard let baseline else { return true }
        let ok = Self.writeTransferTable(
            displayID: displayID,
            red: baseline.red,
            green: baseline.green,
            blue: baseline.blue
        )
        if ok {
            lastAppliedT = 1
            hasWritten = false
        }
        return ok
    }

    func expectedPeak(t: Double) -> Float {
        (baseline?.peak ?? 1) * Float(t)
    }

    private static func readTransferTable(displayID: CGDirectDisplayID) -> GammaTable? {
        var capacity: UInt32 = 256
        if let table = readTransferTable(displayID: displayID, capacity: capacity) {
            return table
        }
        var sampleCount: UInt32 = 0
        var probe = [Float](repeating: 0, count: 1)
        let status = probe.withUnsafeMutableBufferPointer { buf in
            CGGetDisplayTransferByTable(displayID, 1, buf.baseAddress, buf.baseAddress, buf.baseAddress, &sampleCount)
        }
        guard status == .success, sampleCount > 1 else { return nil }
        capacity = sampleCount
        return readTransferTable(displayID: displayID, capacity: capacity)
    }

    private static func readTransferTable(displayID: CGDirectDisplayID, capacity: UInt32) -> GammaTable? {
        var red = [Float](repeating: 0, count: Int(capacity))
        var green = [Float](repeating: 0, count: Int(capacity))
        var blue = [Float](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        let status = red.withUnsafeMutableBufferPointer { redBuf in
            green.withUnsafeMutableBufferPointer { greenBuf in
                blue.withUnsafeMutableBufferPointer { blueBuf in
                    CGGetDisplayTransferByTable(
                        displayID,
                        capacity,
                        redBuf.baseAddress,
                        greenBuf.baseAddress,
                        blueBuf.baseAddress,
                        &sampleCount
                    )
                }
            }
        }
        guard status == .success, sampleCount > 0 else { return nil }
        let count = Int(sampleCount)
        return GammaTable(
            red: Array(red.prefix(count)),
            green: Array(green.prefix(count)),
            blue: Array(blue.prefix(count))
        )
    }

    private static func writeTransferTable(
        displayID: CGDirectDisplayID,
        red: [Float],
        green: [Float],
        blue: [Float]
    ) -> Bool {
        let count = UInt32(red.count)
        guard count > 0, red.count == green.count, green.count == blue.count else { return false }
        let status = red.withUnsafeBufferPointer { redBuf in
            green.withUnsafeBufferPointer { greenBuf in
                blue.withUnsafeBufferPointer { blueBuf in
                    CGSetDisplayTransferByTable(
                        displayID,
                        count,
                        redBuf.baseAddress,
                        greenBuf.baseAddress,
                        blueBuf.baseAddress
                    )
                }
            }
        }
        return status == .success
    }
}
