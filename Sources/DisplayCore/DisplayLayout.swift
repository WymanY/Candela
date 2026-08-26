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
    case deviceSetChanged(expected: [String], actual: [String])
    case displayGeometryChanged(String)
    case invalidGeometry(String)
    case overlappingDisplays(String, String)
    case disconnectedDisplays([String])
}

/// An in-memory extended-desktop draft. Any display, including the main
/// display, can be repositioned; applying later translates the arrangement so
/// the main display sits at the origin.
public struct DisplayLayoutDraft: Equatable, Sendable {
    public private(set) var slots: [DisplayLayoutSlot]
    public let capturedDeviceKeys: [String]
    public let anchorPersistentKey: String?

    public init(slots: [DisplayLayoutSlot]) {
        self.slots = slots
        self.capturedDeviceKeys = slots.map(\.persistentKey).sorted()
        let main = slots.first(where: \.isMain)
        self.anchorPersistentKey = main?.persistentKey
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
        var next = self
        next.slots[index].origin = DisplayLayoutPlanning.constrainedOrigin(
            moving: next.slots[index],
            proposedOrigin: proposedOrigin,
            otherSlots: next.slots.enumerated().compactMap { offset, slot in
                offset == index ? nil : slot
            },
            snapDistance: snapDistance
        )
        return next
    }

    /// CoreGraphics keeps the main display at (0, 0). Translate the draft so
    /// relative placement is preserved when the main display was moved.
    public func placingMainAtZero() -> DisplayLayoutDraft {
        guard let main = slots.first(where: \.isMain) else { return self }
        guard main.origin != DisplayLayoutPoint(x: 0, y: 0) else { return self }
        return DisplayLayoutDraft(
            slots: slots.map { slot in
                var next = slot
                next.origin = DisplayLayoutPoint(
                    x: slot.origin.x - main.origin.x,
                    y: slot.origin.y - main.origin.y
                )
                return next
            }
        )
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
        guard mains[0].persistentKey == anchorPersistentKey else {
            throw DisplayLayoutValidationError.missingMainDisplay
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
    private static let minimumContact = 1.0

    public static func availability(targets: [DisplayMirrorTarget]) -> DisplayLayoutAvailability {
        let real = targets.filter { !$0.isVirtual }
        guard DisplayArrangementPlanning.kind(for: real) == .none else {
            return .mirroring
        }
        return real.count >= 2 ? .available : .insufficientDisplays
    }

    /// Keeps the moving display on the arrangement rails used by System Settings:
    /// flush against at least one neighbor, never overlapping, and never
    /// disconnecting the desktop. The display stays on its current edge until
    /// the pointer reaches a corner, then it can wrap to the adjacent edge.
    public static func constrainedOrigin(
        moving: DisplayLayoutSlot,
        proposedOrigin: DisplayLayoutPoint,
        otherSlots: [DisplayLayoutSlot],
        snapDistance: Double
    ) -> DisplayLayoutPoint {
        guard !otherSlots.isEmpty else { return proposedOrigin }

        let rails = otherSlots.flatMap { railSegments(moving: moving, other: $0) }
        guard !rails.isEmpty else { return proposedOrigin }

        let current = rails.filter { $0.contains(moving.origin, tolerance: contactTolerance) }
        var candidates = current.isEmpty ? rails : current
        if !current.isEmpty {
            for segment in current {
                let projected = segment.projectedOrigin(proposedOrigin)
                if segment.isAtEnd(moving.origin, slop: minimumContact),
                   segment.isAtEnd(projected, slop: minimumContact) {
                    candidates.append(contentsOf: rails.filter { other in
                        other.endpoints().contains {
                            distanceSquared(from: $0, to: projected) <= 8
                        }
                    })
                }
            }
        }

        var bestOrigin: DisplayLayoutPoint?
        var bestDistance = Double.infinity

        func consider(_ origin: DisplayLayoutPoint) {
            var placed = moving
            placed.origin = origin
            guard otherSlots.allSatisfy({ !overlaps(placed, $0) }) else { return }
            var layout = otherSlots
            layout.append(placed)
            guard disconnectedKeys(in: layout).isEmpty else { return }
            let nextDistance = distanceSquared(from: origin, to: proposedOrigin)
            if nextDistance < bestDistance {
                bestDistance = nextDistance
                bestOrigin = origin
            }
        }

        consider(moving.origin)
        for segment in candidates {
            consider(segment.projectedOrigin(proposedOrigin))
            let proposedFree = segment.fixedX == nil ? proposedOrigin.x : proposedOrigin.y
            for snap in alignmentValues(
                movingLength: segment.fixedX == nil ? moving.size.width : moving.size.height,
                others: otherSlots,
                origin: { segment.fixedX == nil ? $0.origin.x : $0.origin.y },
                length: { segment.fixedX == nil ? $0.size.width : $0.size.height },
                proposed: proposedFree,
                snapDistance: snapDistance
            ) {
                consider(segment.origin(free: snap))
            }
        }

        return bestOrigin ?? moving.origin
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

    private struct ArrangementRail {
        let fixedX: Double?
        let fixedY: Double?
        let range: ClosedRange<Double>

        func origin(free: Double) -> DisplayLayoutPoint {
            if let fixedX {
                return DisplayLayoutPoint(x: fixedX, y: DisplayLayoutPlanning.clamped(free, range.lowerBound, range.upperBound))
            }
            return DisplayLayoutPoint(
                x: DisplayLayoutPlanning.clamped(free, range.lowerBound, range.upperBound),
                y: fixedY ?? 0
            )
        }

        func projectedOrigin(_ proposed: DisplayLayoutPoint) -> DisplayLayoutPoint {
            origin(free: fixedX == nil ? proposed.x : proposed.y)
        }

        func contains(_ origin: DisplayLayoutPoint, tolerance: Double) -> Bool {
            if let fixedX {
                return abs(origin.x - fixedX) <= tolerance && range.expanded(by: tolerance).contains(origin.y)
            }
            if let fixedY {
                return abs(origin.y - fixedY) <= tolerance && range.expanded(by: tolerance).contains(origin.x)
            }
            return false
        }

        func isAtEnd(_ origin: DisplayLayoutPoint, slop: Double) -> Bool {
            let value = fixedX == nil ? origin.x : origin.y
            return abs(value - range.lowerBound) <= slop || abs(value - range.upperBound) <= slop
        }

        func endpoints() -> [DisplayLayoutPoint] {
            [origin(free: range.lowerBound), origin(free: range.upperBound)]
        }
    }

    private static func railSegments(
        moving: DisplayLayoutSlot,
        other: DisplayLayoutSlot
    ) -> [ArrangementRail] {
        var rails: [ArrangementRail] = []
        let minY = other.origin.y - moving.size.height + minimumContact
        let maxY = other.origin.y + other.size.height - minimumContact
        if minY <= maxY {
            rails.append(ArrangementRail(
                fixedX: other.origin.x - moving.size.width,
                fixedY: nil,
                range: minY...maxY
            ))
            rails.append(ArrangementRail(
                fixedX: other.origin.x + other.size.width,
                fixedY: nil,
                range: minY...maxY
            ))
        }
        let minX = other.origin.x - moving.size.width + minimumContact
        let maxX = other.origin.x + other.size.width - minimumContact
        if minX <= maxX {
            rails.append(ArrangementRail(
                fixedX: nil,
                fixedY: other.origin.y - moving.size.height,
                range: minX...maxX
            ))
            rails.append(ArrangementRail(
                fixedX: nil,
                fixedY: other.origin.y + other.size.height,
                range: minX...maxX
            ))
        }
        return rails
    }

    private static func alignmentValues(
        movingLength: Double,
        others: [DisplayLayoutSlot],
        origin: (DisplayLayoutSlot) -> Double,
        length: (DisplayLayoutSlot) -> Double,
        proposed: Double,
        snapDistance: Double
    ) -> [Double] {
        guard snapDistance >= 0 else { return [] }
        var values: [Double] = []
        for other in others {
            let candidates = [
                origin(other),
                origin(other) + length(other) - movingLength,
            ]
            for candidate in candidates where abs(proposed - candidate) <= snapDistance {
                values.append(candidate)
            }
        }
        return values
    }

    private static func clamped(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func distanceSquared(from lhs: DisplayLayoutPoint, to rhs: DisplayLayoutPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

private extension ClosedRange where Bound == Double {
    func expanded(by amount: Double) -> ClosedRange<Double> {
        (lowerBound - amount)...(upperBound + amount)
    }
}
