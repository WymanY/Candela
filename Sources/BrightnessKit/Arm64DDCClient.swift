import CoreGraphics
import Darwin
import DisplayCore
import Foundation
import IOKit
import os

public enum Arm64DDCError: Error, Equatable {
    case unavailable
    case builtIn
    case noService
    case getUnavailable
    case ioFailure(Int32)
    case invalidReply
}

/// Apple Silicon DDC/CI via `IOAVService`. x86_64 / `CANDELA_GAMMA_ONLY` is a stub.
public final class Arm64DDCClient: DDCCommanding {
    public static let chipAddress: UInt32 = 0x37
    public static let writeDataAddress: UInt32 = 0x51
    public static let readOffsetPrimary: UInt32 = 0
    public static let readOffsetFallback: UInt32 = 0x51
    public static let replyByteCount = 11
    public static let ddcReadGapMicroseconds: useconds_t = 50_000

    public let displayID: CGDirectDisplayID
    public private(set) var isAvailable = false
    public private(set) var getAvailable = false
    public private(set) var pinnedReadOffset: UInt32?
    public private(set) var lastIOReturn: Int32 = 0
    public private(set) var lastMatchScore = 0
    public private(set) var lastServiceLocation: Int?

    private static let log = Logger(subsystem: "app.candela.macos", category: "ddc")

    #if arch(arm64) && !CANDELA_GAMMA_ONLY
    private var avService: AnyObject?
    private var needsReadGap = false
    #endif

    public static var isSupported: Bool {
        #if arch(arm64) && !CANDELA_GAMMA_ONLY
        IOAVSymbols.isReady
        #else
        false
        #endif
    }

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        #if arch(arm64) && !CANDELA_GAMMA_ONLY
        if CGDisplayIsBuiltin(displayID) == 0 {
            try? recreateHandle()
        }
        #endif
    }

    public func read(vcp: UInt8) throws -> (current: UInt16, max: UInt16) {
        #if arch(arm64) && !CANDELA_GAMMA_ONLY
        try ensureUsable(forGet: true)
        if needsReadGap {
            usleep(Self.ddcReadGapMicroseconds)
            needsReadGap = false
        }
        try writePacket(DDCPacket.arm64Get(vcp: vcp))
        usleep(Self.ddcReadGapMicroseconds)
        if let pinned = pinnedReadOffset {
            return try readReply(offset: pinned)
        }
        if let parsed = try? readReply(offset: Self.readOffsetPrimary) {
            pinnedReadOffset = Self.readOffsetPrimary
            return parsed
        }
        if let parsed = try? readReply(offset: Self.readOffsetFallback) {
            pinnedReadOffset = Self.readOffsetFallback
            return parsed
        }
        getAvailable = false
        throw Arm64DDCError.getUnavailable
        #else
        _ = vcp
        throw Arm64DDCError.unavailable
        #endif
    }

    public func write(vcp: UInt8, value: UInt16) throws {
        #if arch(arm64) && !CANDELA_GAMMA_ONLY
        try ensureUsable(forGet: false)
        try writePacket(DDCPacket.arm64Set(vcp: vcp, value: value))
        needsReadGap = true
        #else
        _ = vcp
        _ = value
        throw Arm64DDCError.unavailable
        #endif
    }

    public func recreateHandle() throws {
        #if arch(arm64) && !CANDELA_GAMMA_ONLY
        avService = nil
        pinnedReadOffset = nil
        needsReadGap = false
        getAvailable = false
        isAvailable = false
        lastMatchScore = 0
        lastServiceLocation = nil

        guard CGDisplayIsBuiltin(displayID) == 0 else {
            throw Arm64DDCError.builtIn
        }
        guard IOAVSymbols.isReady else {
            throw Arm64DDCError.unavailable
        }
        guard let (matched, score) = AVServiceMatcher.match(displayID: displayID) else {
            throw Arm64DDCError.noService
        }
        guard let service = matched.takeAVService() else {
            throw Arm64DDCError.noService
        }
        avService = service
        isAvailable = true
        getAvailable = true
        lastMatchScore = score
        lastServiceLocation = matched.scoreService.serviceLocation
        Self.log.debug("recreated IOAVService score=\(score, privacy: .public)")
        #endif
    }

    #if arch(arm64) && !CANDELA_GAMMA_ONLY
    private func ensureUsable(forGet: Bool) throws {
        guard CGDisplayIsBuiltin(displayID) == 0 else {
            throw Arm64DDCError.builtIn
        }
        guard isAvailable, avService != nil else {
            throw Arm64DDCError.unavailable
        }
        if forGet, !getAvailable {
            throw Arm64DDCError.getUnavailable
        }
    }

    private func writePacket(_ packet: [UInt8]) throws {
        guard let avService else { throw Arm64DDCError.unavailable }
        let status = IOAVSymbols.writeI2C(
            service: avService,
            dataAddress: Self.writeDataAddress,
            bytes: packet
        )
        lastIOReturn = status
        guard status == kIOReturnSuccess else {
            throw Arm64DDCError.ioFailure(status)
        }
    }

    private func readReply(offset: UInt32) throws -> (current: UInt16, max: UInt16) {
        guard let avService else { throw Arm64DDCError.unavailable }
        let (status, reply) = IOAVSymbols.readI2C(
            service: avService,
            offset: offset,
            count: Self.replyByteCount
        )
        lastIOReturn = status
        guard status == kIOReturnSuccess else {
            throw Arm64DDCError.ioFailure(status)
        }
        guard let parsed = DDCPacket.parseReply(reply) else {
            throw Arm64DDCError.invalidReply
        }
        return parsed
    }
    #endif
}
