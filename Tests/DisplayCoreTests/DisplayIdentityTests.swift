import XCTest
@testable import DisplayCore

final class DisplayIdentityTests: XCTestCase {
    func testSerialPresentKey() {
        let inputs = DisplayIdentityInputs(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0x1234_5678,
            portLocation: "IOService:/port/A",
            unitNumber: 1,
            fallbackName: "DELL U2723QE"
        )
        XCTAssertEqual(makeCore(inputs), "v10AC-pD14C-s12345678")
        XCTAssertEqual(
            makePersistentKey(inputs: inputs, siblings: [inputs], records: [:]),
            "v1:v10AC-pD14C-s12345678"
        )
    }

    func testAlphanumericPathWhenSerialZero() {
        let inputs = DisplayIdentityInputs(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0,
            alphanumericSerial: "CN0ABC123",
            portLocation: "IOService:/port/A",
            unitNumber: 1,
            fallbackName: "DELL U2723QE"
        )
        XCTAssertEqual(makeCore(inputs), "v10AC-pD14C-a-CN0ABC123")
        XCTAssertEqual(
            makePersistentKey(inputs: inputs, siblings: [inputs], records: [:]),
            "v1:v10AC-pD14C-a-CN0ABC123"
        )
    }

    func testEdidUUIDPath() {
        let uuid = "A1B2C3D4-0000-0000-1122-334455667788"
        let inputs = DisplayIdentityInputs(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0,
            edidUUID: uuid,
            portLocation: "IOService:/port/A",
            unitNumber: 1,
            fallbackName: "DELL U2723QE"
        )
        XCTAssertEqual(makeCore(inputs), "edid-A1B2C3D4-0000-0000-1122-334455667788")
        XCTAssertEqual(
            makePersistentKey(inputs: inputs, siblings: [inputs], records: [:]),
            "v1:edid-A1B2C3D4-0000-0000-1122-334455667788"
        )
    }

    func testNameFallbackSanitize() {
        let inputs = DisplayIdentityInputs(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0,
            portLocation: "IOService:/port/A",
            unitNumber: 1,
            fallbackName: "Dell UltraSharp 27!"
        )
        XCTAssertEqual(sanitizeName("Dell UltraSharp 27!"), "dellultrasharp27")
        XCTAssertEqual(makeCore(inputs), "v10AC-pD14C-n-dellultrasharp27")
        XCTAssertEqual(
            makePersistentKey(inputs: inputs, siblings: [inputs], records: [:]),
            "v1:v10AC-pD14C-n-dellultrasharp27"
        )
    }

    func testTwoSerialLessTwinsGetDistinctPortSuffixes() {
        let a = serialLessTwin(port: "IOService:/port/A", name: "DELL U2723QE")
        let b = serialLessTwin(port: "IOService:/port/B", name: "DELL U2723QE")
        let siblings = [a, b]
        let keyA = makePersistentKey(inputs: a, siblings: siblings, records: [:])
        let keyB = makePersistentKey(inputs: b, siblings: siblings, records: [:])
        XCTAssertTrue(keyA.contains("-port-"), keyA)
        XCTAssertTrue(keyB.contains("-port-"), keyB)
        XCTAssertNotEqual(keyA, keyB)
        XCTAssertTrue(keyA.hasSuffix(fnv1a32Hex(a.portLocation)))
        XCTAssertTrue(keyB.hasSuffix(fnv1a32Hex(b.portLocation)))
    }

    func testOneTwinKeepsExistingSuffixedRecord() {
        let inputs = serialLessTwin(port: "IOService:/port/A", name: "DELL U2723QE")
        let suffixed = "v1:" + makeCore(inputs) + "-port-" + fnv1a32Hex(inputs.portLocation)
        let records = [suffixed: DisplayRecord(persistentKey: suffixed, portLocation: inputs.portLocation)]
        let key = makePersistentKey(inputs: inputs, siblings: [inputs], records: records)
        XCTAssertEqual(key, suffixed)
    }

    func testDifferentCoreOnSamePortDoesNotInheritForeignKey() {
        let port = "IOService:/dock/usb-c"
        let dell = serialLessTwin(vendor: 0x10AC, product: 0xD14C, port: port, name: "DELL U2723QE")
        let lg = serialLessTwin(vendor: 0x1E6D, product: 0x5B11, port: port, name: "LG ULTRAGEAR")
        let dellSuffixed = "v1:" + makeCore(dell) + "-port-" + fnv1a32Hex(port)
        let records = [
            dellSuffixed: DisplayRecord(persistentKey: dellSuffixed, portLocation: port),
        ]
        let lgKey = makePersistentKey(inputs: lg, siblings: [lg], records: records)
        XCTAssertNotEqual(lgKey, dellSuffixed)
        XCTAssertEqual(lgKey, "v1:" + makeCore(lg))
        XCTAssertFalse(lgKey.contains(makeCore(dell)))
        XCTAssertNil(resolveRecord(inputs: lg, records: records, aliases: [:]))
        XCTAssertEqual(resolveRecord(inputs: dell, records: records, aliases: [:])?.persistentKey, dellSuffixed)
    }

    func testFFFFFFFFVendorProductTreatedAsZero() {
        let inputs = DisplayIdentityInputs(
            vendorID: 0xFFFF_FFFF,
            productID: 0xFFFF_FFFF,
            serial: 0x1234_5678,
            portLocation: "IOService:/port/A",
            unitNumber: 0,
            fallbackName: "Unknown"
        )
        XCTAssertEqual(makeCore(inputs), "v0000-p0000-s12345678")
        XCTAssertEqual(
            makePersistentKey(inputs: inputs, siblings: [inputs], records: [:]),
            "v1:v0000-p0000-s12345678"
        )
        let zeroed = DisplayIdentityInputs(
            vendorID: 0,
            productID: 0,
            serial: 0x1234_5678,
            portLocation: inputs.portLocation,
            unitNumber: 0,
            fallbackName: "Unknown"
        )
        XCTAssertEqual(makeCore(inputs), makeCore(zeroed))
    }

    func testFNV1a32KnownASCII() {
        // FNV-1a 32 of "foobar": offset 2166136261, prime 16777619.
        XCTAssertEqual(fnv1a32("foobar"), 3_214_735_720)
        XCTAssertEqual(fnv1a32Hex("foobar"), "bf9cf968")
        XCTAssertEqual(fnv1a32(""), 2_166_136_261)
        XCTAssertEqual(fnv1a32Hex(""), "811c9dc5")
        XCTAssertEqual(fnv1a32Hex("a"), "e40c292c")
    }

    func testIdentityEqualityIgnoresFallbackName() {
        let base = DisplayIdentityInputs(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0x1234_5678,
            portLocation: "IOService:/port/A",
            unitNumber: 1,
            fallbackName: "DELL U2723QE"
        )
        var renamed = base
        renamed.fallbackName = "Dell UltraSharp"
        let left = DisplayIdentity(
            persistentKey: "v1:v10AC-pD14C-s12345678",
            fields: DisplayIdentityFields(inputs: base)
        )
        let right = DisplayIdentity(
            persistentKey: "v1:v10AC-pD14C-s12345678",
            fields: DisplayIdentityFields(inputs: renamed)
        )
        XCTAssertEqual(left, right)
        XCTAssertEqual(Set([left, right]).count, 1)
        XCTAssertNotEqual(left.fields.inputs.fallbackName, right.fields.inputs.fallbackName)
    }

    func testSynthesizeEdidUUID() {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[8] = 0x10
        bytes[9] = 0xAC
        bytes[10] = 0x4C
        bytes[11] = 0xD1
        bytes[16] = 0x0A
        bytes[17] = 0x22
        bytes[21] = 0x3C
        bytes[22] = 0x22
        let uuid = synthesizeEdidUUID(from: Data(bytes))
        XCTAssertEqual(uuid, "10AC4CD1-0000-0000-0A22-3C2200000000")
        XCTAssertNil(synthesizeEdidUUID(from: Data(repeating: 0, count: 16)))
    }

    func testEdidDescriptorSerialAndName() {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[54] = 0
        bytes[55] = 0
        bytes[56] = 0
        bytes[57] = 0xFF
        let serial = Array("CN0ABC123".utf8)
        for (index, byte) in serial.enumerated() {
            bytes[59 + index] = byte
        }
        bytes[59 + serial.count] = 0x0A
        bytes[72] = 0
        bytes[73] = 0
        bytes[74] = 0
        bytes[75] = 0xFC
        let name = Array("DELL U2723QE".utf8)
        for (index, byte) in name.enumerated() {
            bytes[77 + index] = byte
        }
        bytes[77 + name.count] = 0x0A
        let data = Data(bytes)
        XCTAssertEqual(edidAlphanumericSerial(from: data), "CN0ABC123")
        XCTAssertEqual(edidMonitorName(from: data), "DELL U2723QE")
    }

    func testApplyLiveKeyAliasCopiesRecord() {
        let old = DisplayRecord(persistentKey: "v1:old", lastBrightness: 0.5)
        let result = applyLiveKeyAlias(
            oldKey: "v1:old",
            newKey: "v1:new",
            recordAtOld: old,
            recordAtNew: nil
        )
        XCTAssertEqual(result.copiedRecord?.persistentKey, "v1:new")
        XCTAssertEqual(result.copiedRecord?.lastBrightness, 0.5)
        XCTAssertEqual(result.aliasOldKey, "v1:old")
        XCTAssertEqual(result.aliasNewKey, "v1:new")
        let same = applyLiveKeyAlias(
            oldKey: "v1:new",
            newKey: "v1:new",
            recordAtOld: old,
            recordAtNew: nil
        )
        XCTAssertNil(same.copiedRecord)
    }

    private func serialLessTwin(
        vendor: UInt32 = 0x10AC,
        product: UInt32 = 0xD14C,
        port: String,
        name: String
    ) -> DisplayIdentityInputs {
        DisplayIdentityInputs(
            vendorID: vendor,
            productID: product,
            serial: 0,
            portLocation: port,
            unitNumber: 0,
            fallbackName: name
        )
    }
}
