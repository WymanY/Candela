import Foundation

private let fnvOffsetBasis: UInt32 = 2_166_136_261
private let fnvPrime: UInt32 = 16_777_619
private let missingVendorProduct: UInt32 = 0xFFFF_FFFF

public func normalizeVendorOrProduct(_ value: UInt32) -> UInt32 {
    value == missingVendorProduct ? 0 : value
}

/// Keep ASCII `[A-Za-z0-9_-]`, truncate to 64. Empty after filtering is missing.
public func sanitizeToken(_ raw: String) -> String? {
    var kept = String()
    kept.reserveCapacity(min(raw.count, 64))
    for scalar in raw.unicodeScalars {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D:
            kept.unicodeScalars.append(scalar)
            if kept.count == 64 { return kept }
        default:
            continue
        }
    }
    return kept.isEmpty ? nil : kept
}

public func sanitizeName(_ raw: String) -> String? {
    sanitizeToken(raw.lowercased())
}

public func alphanumericMissing(_ inputs: DisplayIdentityInputs) -> Bool {
    guard let serial = inputs.alphanumericSerial else { return true }
    return sanitizeToken(serial) == nil
}

public func fnv1a32(_ bytes: [UInt8]) -> UInt32 {
    var hash = fnvOffsetBasis
    for byte in bytes {
        hash = hash ^ UInt32(byte)
        hash = hash &* fnvPrime
    }
    return hash
}

public func fnv1a32(_ string: String) -> UInt32 {
    fnv1a32(Array(string.utf8))
}

public func fnv1a32Hex(_ string: String) -> String {
    String(format: "%08x", fnv1a32(string))
}

public func makeCore(_ inputs: DisplayIdentityInputs) -> String {
    let vendor = normalizeVendorOrProduct(inputs.vendorID)
    let product = normalizeVendorOrProduct(inputs.productID)
    if inputs.serial != 0 {
        return String(format: "v%04X-p%04X-s%08X", vendor, product, inputs.serial)
    }
    if let token = inputs.alphanumericSerial.flatMap(sanitizeToken) {
        return String(format: "v%04X-p%04X-a-%@", vendor, product, token)
    }
    if let uuid = inputs.edidUUID, !uuid.isEmpty {
        return "edid-" + uuid.uppercased()
    }
    let name = sanitizeName(inputs.fallbackName) ?? ""
    return String(format: "v%04X-p%04X-n-%@", vendor, product, name)
}

public func resolveAlias(_ key: String, aliases: [String: String]) -> String {
    aliases[key] ?? key
}

public func makePersistentKey(
    inputs: DisplayIdentityInputs,
    siblings: [DisplayIdentityInputs],
    records: [String: DisplayRecord],
    aliases: [String: String] = [:]
) -> String {
    let core = makeCore(inputs)
    let suffixed = "v1:" + core + "-port-" + fnv1a32Hex(inputs.portLocation)
    let unsuffixed = "v1:" + core
    let twins = siblings.filter { sibling in
        makeCore(sibling) == core && sibling.serial == 0 && alphanumericMissing(sibling)
    }
    if twins.count >= 2 {
        return suffixed
    }
    let recordAtSuffix = records[suffixed] ?? records[resolveAlias(suffixed, aliases: aliases)]
    if recordAtSuffix != nil {
        return suffixed
    }
    return unsuffixed
}

public func makePersistentKey(
    inputs: DisplayIdentityInputs,
    siblings: [DisplayIdentityInputs],
    records: [DisplayRecord],
    aliases: [String: String] = [:]
) -> String {
    let keyed = Dictionary(records.map { ($0.persistentKey, $0) }, uniquingKeysWith: { _, last in last })
    return makePersistentKey(inputs: inputs, siblings: siblings, records: keyed, aliases: aliases)
}

/// Cold-start resolve. Tries `[suffixed, unsuffixed]` + one-hop aliases only.
/// Never matches on `portLocation` alone.
public func resolveRecord(
    inputs: DisplayIdentityInputs,
    records: [String: DisplayRecord],
    aliases: [String: String]
) -> DisplayRecord? {
    let core = makeCore(inputs)
    let suffixed = "v1:" + core + "-port-" + fnv1a32Hex(inputs.portLocation)
    let unsuffixed = "v1:" + core
    for candidate in [suffixed, unsuffixed] {
        let resolved = resolveAlias(candidate, aliases: aliases)
        if let record = records[resolved] ?? records[candidate] {
            return record
        }
    }
    return nil
}

public func makeIdentity(
    inputs: DisplayIdentityInputs,
    siblings: [DisplayIdentityInputs],
    records: [String: DisplayRecord] = [:],
    aliases: [String: String] = [:]
) -> DisplayIdentity {
    DisplayIdentity(
        persistentKey: makePersistentKey(
            inputs: inputs,
            siblings: siblings,
            records: records,
            aliases: aliases
        ),
        fields: DisplayIdentityFields(inputs: inputs)
    )
}

public struct LiveKeyAliasResult: Equatable, Sendable {
    public var copiedRecord: DisplayRecord?
    public var aliasOldKey: String?
    public var aliasNewKey: String?

    public init(copiedRecord: DisplayRecord?, aliasOldKey: String?, aliasNewKey: String?) {
        self.copiedRecord = copiedRecord
        self.aliasOldKey = aliasOldKey
        self.aliasNewKey = aliasNewKey
    }
}

/// §5 aliasing: still-connected box whose computed key changed.
public func applyLiveKeyAlias(
    oldKey: String?,
    newKey: String,
    recordAtOld: DisplayRecord?,
    recordAtNew: DisplayRecord?
) -> LiveKeyAliasResult {
    guard let oldKey, oldKey != newKey, recordAtOld != nil else {
        return LiveKeyAliasResult(copiedRecord: nil, aliasOldKey: nil, aliasNewKey: nil)
    }
    var copied: DisplayRecord?
    if recordAtNew == nil, var record = recordAtOld {
        record.persistentKey = newKey
        copied = record
    }
    return LiveKeyAliasResult(copiedRecord: copied, aliasOldKey: oldKey, aliasNewKey: newKey)
}
