import Foundation

/// Pure DDC/CI packet builders. No I²C, IOAVService, or IOI2C I/O.
public enum DDCPacket {
    public enum VCP {
        public static let brightness: UInt8 = 0x10
        public static let volume: UInt8 = 0x62
        public static let mute: UInt8 = 0x8D
    }

    /// Inclusive XOR fold: `seed ^ bytes[0] ^ … ^ bytes[n-1]`.
    public static func xor8(seed: UInt8, bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Arm64 `IOAVService` GET. `0x51` is the write `dataAddress`, not a buffer byte.
    public static func arm64Get(vcp: UInt8) -> [UInt8] {
        arm64Packet(send: [vcp], checksumSeed: 0x6E)
    }

    /// Arm64 `IOAVService` SET. Checksum seed is `0x6E ^ 0x51` (`0x3F`).
    public static func arm64Set(vcp: UInt8, value: UInt16) -> [UInt8] {
        arm64Packet(send: [vcp, UInt8(value >> 8), UInt8(truncatingIfNeeded: value)], checksumSeed: 0x6E ^ 0x51)
    }

    /// Intel `IOI2CInterface` GET. `0x51` is the first send byte.
    public static func intelGet(vcp: UInt8) -> [UInt8] {
        intelPacket(prefix: [0x51, 0x82, 0x01, vcp])
    }

    /// Intel `IOI2CInterface` SET. Seven bytes including checksum.
    public static func intelSet(vcp: UInt8, value: UInt16) -> [UInt8] {
        intelPacket(prefix: [0x51, 0x84, 0x03, vcp, UInt8(value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    /// Shared GET reply: 11 bytes, `xor8(0x50, [0]…[9]) == [10]`, `[2]==0x02`, `[3]==0x00`.
    public static func parseReply(_ reply: [UInt8]) -> (current: UInt16, max: UInt16)? {
        guard reply.count == 11 else { return nil }
        guard xor8(seed: 0x50, bytes: Array(reply[0...9])) == reply[10] else { return nil }
        guard reply[2] == 0x02, reply[3] == 0x00 else { return nil }
        let max = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        let current = (UInt16(reply[8]) << 8) | UInt16(reply[9])
        return (current: current, max: max)
    }

    private static func arm64Packet(send: [UInt8], checksumSeed: UInt8) -> [UInt8] {
        var packet = [0x80 | UInt8(send.count + 1), UInt8(send.count)] + send
        packet.append(xor8(seed: checksumSeed, bytes: packet))
        return packet
    }

    private static func intelPacket(prefix: [UInt8]) -> [UInt8] {
        prefix + [xor8(seed: 0x6E, bytes: prefix)]
    }
}
