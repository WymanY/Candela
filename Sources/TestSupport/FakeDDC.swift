import DisplayCore
import Foundation

public enum FakeDDCError: Error, Equatable {
    case unavailable
    case unknownVCP
}

public final class FakeDDC: DDCCommanding {
    public var isAvailable: Bool
    public var values: [UInt8: (current: UInt16, max: UInt16)]
    public var recreateCount = 0

    public init(
        isAvailable: Bool = true,
        values: [UInt8: (current: UInt16, max: UInt16)] = [
            0x10: (50, 100),
            0x12: (50, 100),
            0x60: (0x0F, 0x1B),
            0x62: (25, 100),
        ]
    ) {
        self.isAvailable = isAvailable
        self.values = values
    }

    public func read(vcp: UInt8) throws -> (current: UInt16, max: UInt16) {
        guard isAvailable else { throw FakeDDCError.unavailable }
        guard let pair = values[vcp] else { throw FakeDDCError.unknownVCP }
        return pair
    }

    public func write(vcp: UInt8, value: UInt16) throws {
        guard isAvailable else { throw FakeDDCError.unavailable }
        if let existing = values[vcp] {
            values[vcp] = (value, existing.max)
        } else {
            values[vcp] = (value, 100)
        }
    }

    public func recreateHandle() throws {
        recreateCount += 1
    }
}
