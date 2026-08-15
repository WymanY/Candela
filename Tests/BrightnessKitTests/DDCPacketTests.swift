import BrightnessKit
import XCTest

final class DDCPacketTests: XCTestCase {
    func testVCPConstants() {
        XCTAssertEqual(DDCPacket.VCP.brightness, 0x10)
        XCTAssertEqual(DDCPacket.VCP.volume, 0x62)
        XCTAssertEqual(DDCPacket.VCP.mute, 0x8D)
    }

    func testArm64GetGoldenVectors() {
        XCTAssertEqual(DDCPacket.arm64Get(vcp: 0x10), [0x82, 0x01, 0x10, 0xFD])
        XCTAssertEqual(DDCPacket.arm64Get(vcp: 0x62), [0x82, 0x01, 0x62, 0x8F])
    }

    func testArm64SetGoldenVectors() {
        XCTAssertEqual(DDCPacket.arm64Set(vcp: 0x10, value: 0), [0x84, 0x03, 0x10, 0x00, 0x00, 0xA8])
        XCTAssertEqual(DDCPacket.arm64Set(vcp: 0x10, value: 50), [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        XCTAssertEqual(DDCPacket.arm64Set(vcp: 0x10, value: 100), [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
        XCTAssertEqual(DDCPacket.arm64Set(vcp: 0x62, value: 25), [0x84, 0x03, 0x62, 0x00, 0x19, 0xC3])
    }

    func testIntelGetGoldenVectors() {
        XCTAssertEqual(DDCPacket.intelGet(vcp: 0x10), [0x51, 0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(DDCPacket.intelGet(vcp: 0x62), [0x51, 0x82, 0x01, 0x62, 0xDE])
    }

    func testIntelSetGoldenVectors() {
        XCTAssertEqual(DDCPacket.intelSet(vcp: 0x10, value: 50), [0x51, 0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        XCTAssertEqual(DDCPacket.intelSet(vcp: 0x10, value: 100), [0x51, 0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
        XCTAssertEqual(DDCPacket.intelSet(vcp: 0x62, value: 25), [0x51, 0x84, 0x03, 0x62, 0x00, 0x19, 0xC3])
    }

    func testParseReplyFixture() {
        let reply: [UInt8] = [0x6E, 0x51, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x2B]
        let parsed = DDCPacket.parseReply(reply)
        XCTAssertEqual(parsed?.max, 100)
        XCTAssertEqual(parsed?.current, 50)
    }

    func testParseReplyRejectsInvalidPackets() {
        let valid: [UInt8] = [0x6E, 0x51, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x2B]
        XCTAssertNil(DDCPacket.parseReply(Array(valid.dropLast())))
        var badChecksum = valid
        badChecksum[10] ^= 0xFF
        XCTAssertNil(DDCPacket.parseReply(badChecksum))
        var badOpcode = valid
        badOpcode[2] = 0x03
        XCTAssertNil(DDCPacket.parseReply(badOpcode))
        var badResult = valid
        badResult[3] = 0x01
        XCTAssertNil(DDCPacket.parseReply(badResult))
    }

    func testXor8MatchesDocumentedIntelGetChecksum() {
        XCTAssertEqual(DDCPacket.xor8(seed: 0x6E, bytes: [0x51, 0x82, 0x01, 0x62]), 0xDE)
    }
}
