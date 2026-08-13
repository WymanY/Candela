import Foundation

/// Synthesize a hyphenated uppercase EDID UUID from a 128-byte EDID block.
public func synthesizeEdidUUID(from edid: Data) -> String? {
    guard edid.count >= 128 else { return nil }
    let vendor = (UInt16(edid[8]) << 8) | UInt16(edid[9])
    let productLo = edid[10]
    let productHi = edid[11]
    let week = edid[16]
    let year = edid[17]
    let hcm = edid[21]
    let vcm = edid[22]
    return String(
        format: "%04X%02X%02X-%02X%02X-0000-%02X%02X-%02X%02X00000000",
        vendor,
        productLo,
        productHi,
        0,
        0,
        week,
        year,
        hcm,
        vcm
    )
}

/// EDID ASCII descriptor: tag `0xFF` serial, `0xFC` name.
public func edidDescriptorString(from edid: Data, tag: UInt8) -> String? {
    guard edid.count >= 128 else { return nil }
    for offset in [54, 72, 90, 108] {
        guard offset + 18 <= edid.count else { continue }
        if edid[offset] == 0, edid[offset + 1] == 0, edid[offset + 2] == 0, edid[offset + 3] == tag {
            let payload = edid[(offset + 5)..<(offset + 18)]
            let bytes = payload.prefix { $0 != 0x0A && $0 != 0x00 }
            guard let raw = String(bytes: bytes, encoding: .ascii) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
    }
    return nil
}

public func edidAlphanumericSerial(from edid: Data) -> String? {
    edidDescriptorString(from: edid, tag: 0xFF)
}

public func edidMonitorName(from edid: Data) -> String? {
    edidDescriptorString(from: edid, tag: 0xFC)
}
