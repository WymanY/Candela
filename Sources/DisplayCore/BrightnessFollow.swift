import Foundation

public struct BrightnessFollowCommand: Equatable, Sendable {
    public var persistentKey: String
    public var brightness: Double

    public init(persistentKey: String, brightness: Double) {
        self.persistentKey = persistentKey
        self.brightness = min(1, max(0, brightness))
    }
}

public enum BrightnessFollowTiming {
    public static let pollInterval: TimeInterval = 0.12
    public static let changeEpsilon = 0.015
    public static let echoIgnoreInterval: TimeInterval = 0.35
}

public enum BrightnessWriteOrigin: String, Equatable, Sendable {
    case user
    case follow
    case explicit
}

/// Keyboard brightness keys only move the built-in panel. Candela keeps every
/// other controllable display at a relative offset from that source.
public enum BrightnessFollowPolicy {
    public static func isControllable(_ snapshot: DisplaySnapshot) -> Bool {
        snapshot.kind != .virtualUnsupported && snapshot.brightness.showsBrightnessSlider
    }

    public static func source(in snapshots: [DisplaySnapshot]) -> DisplaySnapshot? {
        snapshots.first(where: { $0.isBuiltin && isControllable($0) })
    }

    public static func followers(in snapshots: [DisplaySnapshot], sourceKey: String) -> [DisplaySnapshot] {
        snapshots.filter { snapshot in
            snapshot.id.persistentKey != sourceKey && isControllable(snapshot)
        }
    }

    public static func canFollow(in snapshots: [DisplaySnapshot]) -> Bool {
        guard let source = source(in: snapshots) else { return false }
        return !followers(in: snapshots, sourceKey: source.id.persistentKey).isEmpty
    }

    public static func offset(display: Double, source: Double) -> Double {
        min(1, max(-1, display - source))
    }

    public static func appliedBrightness(source: Double, offset: Double) -> Double {
        min(1, max(0, source + offset))
    }

    public static func shouldAdoptSourceChange(
        previous: Double?,
        next: Double,
        lastSourceWrite: Date?,
        now: Date = Date(),
        epsilon: Double = BrightnessFollowTiming.changeEpsilon,
        echoInterval: TimeInterval = BrightnessFollowTiming.echoIgnoreInterval
    ) -> Bool {
        guard let previous else { return false }
        if let lastSourceWrite, now.timeIntervalSince(lastSourceWrite) < echoInterval {
            return false
        }
        return abs(next - previous) > epsilon
    }

    public static func captureOffsets(
        snapshots: [DisplaySnapshot],
        sourceKey: String,
        sourceBrightness: Double
    ) -> [String: Double] {
        var offsets: [String: Double] = [:]
        for snapshot in followers(in: snapshots, sourceKey: sourceKey) {
            offsets[snapshot.id.persistentKey] = offset(
                display: snapshot.brightness.current,
                source: sourceBrightness
            )
        }
        return offsets
    }

    public static func mergingOffsets(
        existing: [String: Double],
        snapshots: [DisplaySnapshot],
        sourceKey: String,
        sourceBrightness: Double
    ) -> [String: Double] {
        var next: [String: Double] = [:]
        for snapshot in followers(in: snapshots, sourceKey: sourceKey) {
            let key = snapshot.id.persistentKey
            next[key] = existing[key] ?? offset(
                display: snapshot.brightness.current,
                source: sourceBrightness
            )
        }
        return next
    }

    public static func plan(
        snapshots: [DisplaySnapshot],
        sourceKey: String,
        sourceBrightness: Double,
        offsets: [String: Double],
        epsilon: Double = BrightnessFollowTiming.changeEpsilon
    ) -> [BrightnessFollowCommand] {
        followers(in: snapshots, sourceKey: sourceKey).compactMap { snapshot in
            let key = snapshot.id.persistentKey
            let stored = offsets[key] ?? offset(
                display: snapshot.brightness.current,
                source: sourceBrightness
            )
            let value = appliedBrightness(source: sourceBrightness, offset: stored)
            guard abs(value - snapshot.brightness.current) > epsilon else {
                return nil
            }
            return BrightnessFollowCommand(persistentKey: key, brightness: value)
        }
    }
}

public struct BrightnessFollowEngine: Equatable, Sendable {
    public var enabled: Bool
    public var offsets: [String: Double]
    public var lastObservedSource: Double?
    public var lastSourceWrite: Date?

    public init(
        enabled: Bool = true,
        offsets: [String: Double] = [:],
        lastObservedSource: Double? = nil,
        lastSourceWrite: Date? = nil
    ) {
        self.enabled = enabled
        self.offsets = offsets
        self.lastObservedSource = lastObservedSource
        self.lastSourceWrite = lastSourceWrite
    }

    public mutating func noteLocalSourceWrite(_ value: Double, at now: Date = Date()) {
        lastObservedSource = min(1, max(0, value))
        lastSourceWrite = now
    }

    public mutating func noteFollowerWrite(key: String, brightness: Double, sourceBrightness: Double) {
        offsets[key] = BrightnessFollowPolicy.offset(display: brightness, source: sourceBrightness)
    }

    public mutating func recapture(snapshots: [DisplaySnapshot]) {
        guard let source = BrightnessFollowPolicy.source(in: snapshots) else {
            offsets = [:]
            return
        }
        offsets = BrightnessFollowPolicy.captureOffsets(
            snapshots: snapshots,
            sourceKey: source.id.persistentKey,
            sourceBrightness: source.brightness.current
        )
        lastObservedSource = source.brightness.current
    }

    public mutating func ingestLiveSource(
        snapshots: [DisplaySnapshot],
        live: Double,
        now: Date = Date()
    ) -> [BrightnessFollowCommand] {
        let clamped = min(1, max(0, live))
        guard enabled, let source = BrightnessFollowPolicy.source(in: snapshots) else {
            lastObservedSource = clamped
            return []
        }
        offsets = BrightnessFollowPolicy.mergingOffsets(
            existing: offsets,
            snapshots: snapshots,
            sourceKey: source.id.persistentKey,
            sourceBrightness: clamped
        )
        let shouldFollow = BrightnessFollowPolicy.shouldAdoptSourceChange(
            previous: lastObservedSource,
            next: clamped,
            lastSourceWrite: lastSourceWrite,
            now: now
        )
        lastObservedSource = clamped
        guard shouldFollow else { return [] }
        return BrightnessFollowPolicy.plan(
            snapshots: snapshots,
            sourceKey: source.id.persistentKey,
            sourceBrightness: clamped,
            offsets: offsets
        )
    }

    public func plan(snapshots: [DisplaySnapshot], sourceBrightness: Double) -> [BrightnessFollowCommand] {
        guard enabled, let source = BrightnessFollowPolicy.source(in: snapshots) else { return [] }
        return BrightnessFollowPolicy.plan(
            snapshots: snapshots,
            sourceKey: source.id.persistentKey,
            sourceBrightness: sourceBrightness,
            offsets: offsets
        )
    }
}
