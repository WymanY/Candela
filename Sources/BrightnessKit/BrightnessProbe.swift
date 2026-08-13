import DisplayCore
import Foundation

public enum BrightnessTiming {
    public static let sliderHoldMilliseconds = 80
    public static let ddcWriteSpacingMilliseconds = 80
    public static let gammaKeepAliveMilliseconds = 2_000
    public static let liveFailThreshold = 3
    public static let restoreDelayAfterAttachMilliseconds = 700
    public static let gammaFloor: Double = 0.05
    public static let launchRepairEpsilon: Double = 0.02
    public static let interferenceEpsilon: Double = 0.02
    public static let interferenceHitLimit = 3
}

public struct BrightnessProbeContext: Equatable, Sendable {
    public var vendorID: UInt32
    public var isBuiltin: Bool
    public var softwareDimmingEnabled: Bool
    public var softwareDimmingDisabled: Bool
    public var allowDimToBlack: Bool
    public var lastBrightness: Double?
    public var restoreOnReconnect: Bool
    public var forceDDC: Bool

    public init(
        vendorID: UInt32,
        isBuiltin: Bool,
        softwareDimmingEnabled: Bool = true,
        softwareDimmingDisabled: Bool = false,
        allowDimToBlack: Bool = false,
        lastBrightness: Double? = nil,
        restoreOnReconnect: Bool = true,
        forceDDC: Bool = false
    ) {
        self.vendorID = vendorID
        self.isBuiltin = isBuiltin
        self.softwareDimmingEnabled = softwareDimmingEnabled
        self.softwareDimmingDisabled = softwareDimmingDisabled
        self.allowDimToBlack = allowDimToBlack
        self.lastBrightness = lastBrightness
        self.restoreOnReconnect = restoreOnReconnect
        self.forceDDC = forceDDC
    }

    public var softwareAllowed: Bool {
        softwareDimmingEnabled && !softwareDimmingDisabled
    }
}

/// macOS 15+ HDR skip. Missing HDR symbols (`nil`) mean “treat as pre-15”.
public func shouldSkipDisplayServicesForHDR(
    vendorID: UInt32,
    hdrSupported: Bool?,
    hdrEnabled: Bool?
) -> Bool {
    guard vendorID != appleDisplayVendorID else { return false }
    guard let hdrSupported, let hdrEnabled else { return false }
    return hdrSupported && hdrEnabled
}

/// Exclusive probe winner: DisplayServices → DDC → gamma → none.
public func probeBrightnessWinner(
    kind: DisplayKind,
    displayServicesSucceeded: Bool,
    skipDisplayServicesForHDR: Bool,
    softwareAllowed: Bool,
    gammaAvailable: Bool,
    isBuiltin: Bool = false,
    ddcAvailable: Bool = false,
    forceDDC: Bool = false
) -> BrightnessBackendKind {
    if kind == .virtualUnsupported {
        return .none
    }
    if displayServicesSucceeded && !skipDisplayServicesForHDR {
        return .displayServices
    }
    if !isBuiltin && (ddcAvailable || forceDDC) {
        return .ddc
    }
    if softwareAllowed && gammaAvailable {
        return .softwareGamma
    }
    return .none
}

/// Live-fail hysteresis. DS never falls through to DDC (K22).
public func nextBackendAfterLiveFailure(
    current: BrightnessBackendKind,
    consecutiveFails: Int,
    softwareAllowed: Bool
) -> BrightnessBackendKind? {
    guard consecutiveFails >= BrightnessTiming.liveFailThreshold else { return nil }
    switch current {
    case .displayServices:
        return softwareAllowed ? .softwareGamma : BrightnessBackendKind.none
    case .ddc:
        return softwareAllowed ? .softwareGamma : nil
    case .softwareGamma, .none:
        return nil
    }
}

/// `nil` = table already matches expected `t`; otherwise the `t` to write.
public func gammaLaunchRepairTarget(
    measuredT: Double,
    lastBrightness: Double?,
    restoreOnReconnect: Bool,
    epsilon: Double = BrightnessTiming.launchRepairEpsilon
) -> Double? {
    let expected = lastBrightness ?? 1.0
    if abs(measuredT - expected) <= epsilon {
        return nil
    }
    if restoreOnReconnect, let lastBrightness {
        return lastBrightness
    }
    return 1.0
}
