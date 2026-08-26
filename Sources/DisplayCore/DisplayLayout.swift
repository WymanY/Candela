import Foundation

public struct DisplayLayoutPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DisplayLayoutSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct DisplayLayoutSlot: Codable, Equatable, Sendable {
    public var persistentKey: String
    public var name: String
    public var origin: DisplayLayoutPoint
    public var size: DisplayLayoutSize
    public var isMain: Bool
    public var isBuiltin: Bool

    public init(
        persistentKey: String,
        name: String,
        origin: DisplayLayoutPoint,
        size: DisplayLayoutSize,
        isMain: Bool,
        isBuiltin: Bool
    ) {
        self.persistentKey = persistentKey
        self.name = name
        self.origin = origin
        self.size = size
        self.isMain = isMain
        self.isBuiltin = isBuiltin
    }
}

public enum DisplayLayoutAvailability: Equatable, Sendable {
    case available
    case insufficientDisplays
    case mirroring
}

public enum DisplayLayoutValidationError: Error, Equatable, Sendable {
    case missingMainDisplay
    case multipleMainDisplays
    case unknownDisplay(String)
    case mainDisplayIsAnchored
    case deviceSetChanged(expected: [String], actual: [String])
    case displayGeometryChanged(String)
    case invalidGeometry(String)
    case overlappingDisplays(String, String)
    case disconnectedDisplays([String])
}

/// An in-memory extended-desktop draft. The main display and its origin are
/// captured as immutable anchor metadata so editing cannot silently move it.
public struct DisplayLayoutDraft: Equatable, Sendable {
    public private(set) var slots: [DisplayLayoutSlot]
    public let capturedDeviceKeys: [String]
    public let anchorPersistentKey: String?
    public let anchorOrigin: DisplayLayoutPoint?

    public init(slots: [DisplayLayoutSlot]) {
        self.slots = slots
        self.capturedDeviceKeys = slots.map(\.persistentKey).sorted()
        let main = slots.first(where: \.isMain)
        self.anchorPersistentKey = main?.persistentKey
        self.anchorOrigin = main?.origin
    }

    public func slot(for persistentKey: String) -> DisplayLayoutSlot? {
        slots.first { $0.persistentKey == persistentKey }
    }

    public func moving(
        persistentKey: String,
        to proposedOrigin: DisplayLayoutPoint,
        snapDistance: Double
    ) throws -> DisplayLayoutDraft {
        guard let index = slots.firstIndex(where: { $0.persistentKey == persistentKey }) else {
            throw DisplayLayoutValidationError.unknownDisplay(persistentKey)
        }
        guard !slots[index].isMain else {
            throw DisplayLayoutValidationError.mainDisplayIsAnchored
        }
        var next = self
        next.slots[index].origin = DisplayLayoutPlanning.snappedOrigin(
            moving: next.slots[index],
            proposedOrigin: proposedOrigin,
            otherSlots: next.slots.enumerated().compactMap { offset, slot in
                offset == index ? nil : slot
            },
            snapDistance: snapDistance
        )
        return next
    }

    public func validated(liveDeviceKeys: [String]? = nil) throws {
        if let liveDeviceKeys {
            let actual = liveDeviceKeys.sorted()
            guard capturedDeviceKeys == actual else {
                throw DisplayLayoutValidationError.deviceSetChanged(
                    expected: capturedDeviceKeys,
                    actual: actual
                )
            }
        }

        let mains = slots.filter(\.isMain)
        guard !mains.isEmpty else {
            throw DisplayLayoutValidationError.missingMainDisplay
        }
        guard mains.count == 1 else {
            throw DisplayLayoutValidationError.multipleMainDisplays
        }
        guard mains[0].persistentKey == anchorPersistentKey,
              mains[0].origin == anchorOrigin
        else {
            throw DisplayLayoutValidationError.mainDisplayIsAnchored
        }

        for slot in slots {
            let values = [slot.origin.x, slot.origin.y, slot.size.width, slot.size.height]
            guard values.allSatisfy(\.isFinite),
                  slot.size.width > 0,
                  slot.size.height > 0,
                  slot.origin.x.rounded() >= Double(Int32.min),
                  slot.origin.x.rounded() <= Double(Int32.max),
                  slot.origin.y.rounded() >= Double(Int32.min),
                  slot.origin.y.rounded() <= Double(Int32.max)
            else {
                throw DisplayLayoutValidationError.invalidGeometry(slot.persistentKey)
            }
        }

        for firstIndex in slots.indices {
            for secondIndex in slots.indices where secondIndex > firstIndex {
                if DisplayLayoutPlanning.overlaps(slots[firstIndex], slots[secondIndex]) {
                    throw DisplayLayoutValidationError.overlappingDisplays(
                        slots[firstIndex].persistentKey,
                        slots[secondIndex].persistentKey
                    )
                }
            }
        }

        let disconnected = DisplayLayoutPlanning.disconnectedKeys(in: slots)
        if !disconnected.isEmpty {
            throw DisplayLayoutValidationError.disconnectedDisplays(disconnected)
        }
    }
}

public enum DisplayLayoutPlanning {
    private static let contactTolerance = 0.5

    public static func availability(targets: [DisplayMirrorTarget]) -> DisplayLayoutAvailability {
        let real = targets.filter { !$0.isVirtual }
        guard DisplayArrangementPlanning.kind(for: real) == .none else {
            return .mirroring
        }
        return real.count >= 2 ? .available : .insufficientDisplays
    }

    public static func snappedOrigin(
        moving: DisplayLayoutSlot,
        proposedOrigin: DisplayLayoutPoint,
        otherSlots: [DisplayLayoutSlot],
        snapDistance: Double
    ) -> DisplayLayoutPoint {
        guard snapDistance >= 0 else { return proposedOrigin }
        var x = proposedOrigin.x
        var y = proposedOrigin.y
        var bestX = snapDistance + 1
        var bestY = snapDistance + 1

        for other in otherSlots {
            // Align matching edges or place the moving display directly to the
            // left/right. The same candidates handle all four horizontal edges.
            let xCandidates = [
                other.origin.x,
                other.origin.x + other.size.width,
                other.origin.x - moving.size.width,
                other.origin.x + other.size.width - moving.size.width,
            ]
            for candidate in xCandidates {
                let distance = abs(proposedOrigin.x - candidate)
                if distance <= snapDistance, distance < bestX {
                    x = candidate
                    bestX = distance
                }
            }

            // Align matching edges or place the moving display directly above/below.
            let yCandidates = [
                other.origin.y,
                other.origin.y + other.size.height,
                other.origin.y - moving.size.height,
                other.origin.y + other.size.height - moving.size.height,
            ]
            for candidate in yCandidates {
                let distance = abs(proposedOrigin.y - candidate)
                if distance <= snapDistance, distance < bestY {
                    y = candidate
                    bestY = distance
                }
            }
        }
        return DisplayLayoutPoint(x: x, y: y)
    }

    public static func overlaps(_ lhs: DisplayLayoutSlot, _ rhs: DisplayLayoutSlot) -> Bool {
        let intersectionWidth = min(maxX(lhs), maxX(rhs)) - max(lhs.origin.x, rhs.origin.x)
        let intersectionHeight = min(maxY(lhs), maxY(rhs)) - max(lhs.origin.y, rhs.origin.y)
        return intersectionWidth > contactTolerance && intersectionHeight > contactTolerance
    }

    public static func disconnectedKeys(in slots: [DisplayLayoutSlot]) -> [String] {
        guard let start = slots.first else { return [] }
        let byKey = Dictionary(uniqueKeysWithValues: slots.map { ($0.persistentKey, $0) })
        var visited: Set<String> = [start.persistentKey]
        var pending = [start.persistentKey]

        while let key = pending.popLast(), let current = byKey[key] {
            for candidate in slots where !visited.contains(candidate.persistentKey) {
                if touches(current, candidate) {
                    visited.insert(candidate.persistentKey)
                    pending.append(candidate.persistentKey)
                }
            }
        }
        return slots.map(\.persistentKey).filter { !visited.contains($0) }.sorted()
    }

    public static func touches(_ lhs: DisplayLayoutSlot, _ rhs: DisplayLayoutSlot) -> Bool {
        let verticalOverlap = min(maxY(lhs), maxY(rhs)) - max(lhs.origin.y, rhs.origin.y)
        let horizontalOverlap = min(maxX(lhs), maxX(rhs)) - max(lhs.origin.x, rhs.origin.x)
        let touchesVerticalEdge = verticalOverlap > contactTolerance
            && (abs(maxX(lhs) - rhs.origin.x) <= contactTolerance
                || abs(maxX(rhs) - lhs.origin.x) <= contactTolerance)
        let touchesHorizontalEdge = horizontalOverlap > contactTolerance
            && (abs(maxY(lhs) - rhs.origin.y) <= contactTolerance
                || abs(maxY(rhs) - lhs.origin.y) <= contactTolerance)
        return touchesVerticalEdge || touchesHorizontalEdge
    }

    private static func maxX(_ slot: DisplayLayoutSlot) -> Double {
        slot.origin.x + slot.size.width
    }

    private static func maxY(_ slot: DisplayLayoutSlot) -> Double {
        slot.origin.y + slot.size.height
    }
}
