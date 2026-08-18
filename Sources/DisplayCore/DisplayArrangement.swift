import CoreGraphics
import Foundation

/// One display's place in the current macOS arrangement.
public struct DisplayArrangementSlot: Codable, Equatable, Sendable {
    public var persistentKey: String
    public var originX: Double
    public var originY: Double
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    public var refreshHz: Double
    public var isMain: Bool
    public var isBuiltin: Bool
    public var mirrorsPersistentKey: String?

    public init(
        persistentKey: String,
        originX: Double,
        originY: Double,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        refreshHz: Double,
        isMain: Bool,
        isBuiltin: Bool,
        mirrorsPersistentKey: String? = nil
    ) {
        self.persistentKey = persistentKey
        self.originX = originX
        self.originY = originY
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.isMain = isMain
        self.isBuiltin = isBuiltin
        self.mirrorsPersistentKey = mirrorsPersistentKey
    }
}

/// Saved extended-desktop arrangement used to undo a built-in mirror.
public struct DisplayArrangementSnapshot: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var slots: [DisplayArrangementSlot]

    public init(capturedAt: Date = Date(), slots: [DisplayArrangementSlot]) {
        self.capturedAt = capturedAt
        self.slots = slots
    }

    public var hasExtendedLayout: Bool {
        slots.contains { $0.mirrorsPersistentKey == nil } && slots.count > 1
    }
}

public struct DisplayMirrorTarget: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var persistentKey: String
    public var isBuiltin: Bool
    public var isVirtual: Bool
    public var origin: CGPoint
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    public var refreshHz: Double
    public var isMain: Bool
    public var mirrorsDisplayID: CGDirectDisplayID

    public init(
        displayID: CGDirectDisplayID,
        persistentKey: String,
        isBuiltin: Bool,
        isVirtual: Bool = false,
        origin: CGPoint,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        refreshHz: Double,
        isMain: Bool,
        mirrorsDisplayID: CGDirectDisplayID = 0
    ) {
        self.displayID = displayID
        self.persistentKey = persistentKey
        self.isBuiltin = isBuiltin
        self.isVirtual = isVirtual
        self.origin = origin
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.isMain = isMain
        self.mirrorsDisplayID = mirrorsDisplayID
    }

    public var isMirroring: Bool {
        mirrorsDisplayID != 0
    }
}

public enum DisplayMirrorKind: String, Equatable, Sendable {
    case none
    case builtin
    case other
}

public enum DisplayMirrorAvailability: Equatable, Sendable {
    case unavailable
    case available
    case mirroringBuiltIn
}

public enum DisplayArrangementPlanning {
    public static func slot(
        for target: DisplayMirrorTarget,
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> DisplayArrangementSlot {
        DisplayArrangementSlot(
            persistentKey: target.persistentKey,
            originX: Double(target.origin.x),
            originY: Double(target.origin.y),
            pixelWidth: target.pixelWidth,
            pixelHeight: target.pixelHeight,
            refreshHz: target.refreshHz,
            isMain: target.isMain,
            isBuiltin: target.isBuiltin,
            mirrorsPersistentKey: target.mirrorsDisplayID == 0
                ? nil
                : keysByDisplayID[target.mirrorsDisplayID]
        )
    }

    public static func capture(
        targets: [DisplayMirrorTarget],
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> DisplayArrangementSnapshot {
        DisplayArrangementSnapshot(
            slots: targets.map { slot(for: $0, keysByDisplayID: keysByDisplayID) }
        )
    }

    public static func kind(for targets: [DisplayMirrorTarget]) -> DisplayMirrorKind {
        let slaves = targets.filter(\.isMirroring)
        guard !slaves.isEmpty else { return .none }
        let masterIDs = Set(slaves.map(\.mirrorsDisplayID))
        let masters = targets.filter { masterIDs.contains($0.displayID) }
        if !masters.isEmpty, masters.allSatisfy(\.isBuiltin) {
            return .builtin
        }
        if slaves.contains(where: \.isBuiltin) {
            return .other
        }
        return .other
    }

    public static func availability(
        targets: [DisplayMirrorTarget],
        savedArrangement: DisplayArrangementSnapshot?
    ) -> DisplayMirrorAvailability {
        if kind(for: targets) == .builtin {
            return .mirroringBuiltIn
        }
        guard canMirrorToBuiltIn(targets: targets) || savedArrangement != nil else {
            return .unavailable
        }
        return .available
    }

    public static func canMirrorToBuiltIn(targets: [DisplayMirrorTarget]) -> Bool {
        guard let builtin = targets.first(where: { $0.isBuiltin && !$0.isVirtual }) else {
            return false
        }
        return targets.contains { target in
            target.displayID != builtin.displayID && !target.isVirtual
        }
    }

    public static func mirrorPlan(targets: [DisplayMirrorTarget]) -> [CGDirectDisplayID]? {
        guard let builtin = targets.first(where: { $0.isBuiltin && !$0.isVirtual }) else {
            return nil
        }
        let slaves = targets.compactMap { target -> CGDirectDisplayID? in
            guard target.displayID != builtin.displayID, !target.isVirtual else { return nil }
            return target.displayID
        }
        return slaves.isEmpty ? nil : slaves
    }

    public static func restorePlan(
        saved: DisplayArrangementSnapshot,
        targets: [DisplayMirrorTarget]
    ) -> [DisplayArrangementSlot] {
        let live = Dictionary(uniqueKeysWithValues: targets.map { ($0.persistentKey, $0) })
        return saved.slots.filter { slot in
            guard let target = live[slot.persistentKey] else { return false }
            return !target.isVirtual
        }
    }
}
