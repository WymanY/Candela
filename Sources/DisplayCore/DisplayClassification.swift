import CoreGraphics
import Foundation

public let dummyDisplayVendorID: UInt32 = 0xF0F0
public let appleDisplayVendorID: UInt32 = 0x0610

public enum DisplayInfoKey {
    public static let ioDisplayLocation = "IODisplayLocation"
    public static let displaySerialString = "DisplaySerialString"
    public static let displayProductName = "DisplayProductName"
    public static let ioDisplayEDID = "IODisplayEDID"
    public static let displayVendorID = "DisplayVendorID"
    public static let displayProductID = "DisplayProductID"
    public static let displaySerialNumber = "DisplaySerialNumber"
    public static let isVirtualDevice = "kCGDisplayIsVirtualDevice"
    public static let isAirPlay = "kCGDisplayIsAirPlay"
    public static let edidUUID = "EDID UUID"
    public static let displayAttributes = "DisplayAttributes"
    public static let productAttributes = "ProductAttributes"
    public static let alphanumericSerialNumber = "AlphanumericSerialNumber"
    public static let productName = "ProductName"
    public static let transport = "Transport"
    public static let downstream = "Downstream"
    public static let upstream = "Upstream"
    public static let legacyManufacturerID = "LegacyManufacturerID"
    public static let serialNumber = "SerialNumber"
}

public struct VirtualDisplayEvidence: Equatable, Sendable {
    public var vendorID: UInt32
    public var names: [String]
    public var isVirtualDevice: Bool
    public var isAirPlay: Bool
    public var classOrName: String?

    public init(
        vendorID: UInt32,
        names: [String],
        isVirtualDevice: Bool = false,
        isAirPlay: Bool = false,
        classOrName: String? = nil
    ) {
        self.vendorID = vendorID
        self.names = names
        self.isVirtualDevice = isVirtualDevice
        self.isAirPlay = isAirPlay
        self.classOrName = classOrName
    }
}

public func isVirtualUnsupported(_ evidence: VirtualDisplayEvidence) -> Bool {
    if evidence.isVirtualDevice || evidence.isAirPlay {
        return true
    }
    if evidence.vendorID == dummyDisplayVendorID {
        return true
    }
    for name in evidence.names {
        if nameMatchesVirtualDetector(name) {
            return true
        }
    }
    if let classOrName = evidence.classOrName, nameMatchesVirtualDetector(classOrName) {
        return true
    }
    return false
}

public func classifyDisplayKind(isVirtual: Bool, isBuiltin: Bool) -> DisplayKind {
    if isVirtual { return .virtualUnsupported }
    if isBuiltin { return .builtIn }
    return .genericExternal
}

/// Built-in laptop/iMac panels and virtual screens cannot be rotated.
public func supportsDisplayRotation(isVirtual: Bool, isBuiltin: Bool) -> Bool {
    !isVirtual && !isBuiltin
}

/// Reconnect restore is only for newly attached identities, not mode/rotation reconfigs.
public func newlyAttachedDisplayKeys(previous: Set<String>, next: Set<String>) -> Set<String> {
    next.subtracting(previous)
}

public func displayIdentitiesChanged(previous: Set<String>, next: Set<String>) -> Bool {
    previous != next
}

/// Rotation/mode reconfigs keep identities. Skip a full DDC/DS probe only after
/// that identity already has a committed brightness backend.
public func shouldSkipFullCapabilityProbe(key: String, probedKeys: Set<String>) -> Bool {
    probedKeys.contains(key)
}

public func connectionKind(
    isBuiltin: Bool,
    transportDownstream: String?,
    transportUpstream: String?,
    location: String
) -> ConnectionKind {
    if isBuiltin { return .builtIn }
    if let kind = connectionKind(fromTransport: transportDownstream) {
        return kind
    }
    if let kind = connectionKind(fromTransport: transportUpstream) {
        return kind
    }
    return connectionKind(fromLocation: location)
}

public func connectionKind(fromTransport raw: String?) -> ConnectionKind? {
    guard let raw, !raw.isEmpty else { return nil }
    let lower = raw.lowercased()
    if lower.contains("hdmi") { return .hdmi }
    if transportLooksLikeDisplayPort(lower) { return .displayPort }
    if lower.contains("thunderbolt") { return .thunderbolt }
    if lower.contains("usb") { return .usb }
    return nil
}

public func connectionKind(fromLocation location: String) -> ConnectionKind {
    let loc = location.lowercased()
    if loc.contains("hdmi") { return .hdmi }
    if loc.contains("displayport") { return .displayPort }
    if loc.contains("/dp") { return .displayPort }
    if loc.contains("thunderbolt") { return .thunderbolt }
    if loc.contains("usb") { return .usb }
    return .unknown
}

public func effectiveDisplayID(
    _ id: CGDirectDisplayID,
    mirrorsDisplay: CGDirectDisplayID
) -> CGDirectDisplayID {
    mirrorsDisplay == 0 ? id : mirrorsDisplay
}

public func shouldHideClamshellBuiltin(isBuiltin: Bool, isAsleep: Bool) -> Bool {
    isBuiltin && isAsleep
}

public func visibleOnlineDisplayIDs(
    _ ids: [CGDirectDisplayID],
    isBuiltin: (CGDirectDisplayID) -> Bool,
    isAsleep: (CGDirectDisplayID) -> Bool,
    mirrorsDisplay: (CGDirectDisplayID) -> CGDirectDisplayID
) -> [CGDirectDisplayID] {
    var seen = Set<CGDirectDisplayID>()
    var result: [CGDirectDisplayID] = []
    result.reserveCapacity(ids.count)
    for id in ids {
        if shouldHideClamshellBuiltin(isBuiltin: isBuiltin(id), isAsleep: isAsleep(id)) {
            continue
        }
        if mirrorsDisplay(id) != 0 {
            continue
        }
        let effective = effectiveDisplayID(id, mirrorsDisplay: mirrorsDisplay(id))
        if seen.insert(effective).inserted {
            result.append(effective)
        }
    }
    return result
}

public func visibleOnlineDisplayIDs(_ ids: [CGDirectDisplayID]) -> [CGDirectDisplayID] {
    visibleOnlineDisplayIDs(
        ids,
        isBuiltin: { CGDisplayIsBuiltin($0) != 0 },
        isAsleep: { CGDisplayIsAsleep($0) != 0 },
        mirrorsDisplay: { CGDisplayMirrorsDisplay($0) }
    )
}

/// Last `@N` in `kIODisplayLocationKey` when `N` is a short decimal (Intel unit).
public func unitNumberFromLocation(_ location: String) -> UInt32? {
    guard let at = location.lastIndex(of: "@") else { return nil }
    let suffix = location[location.index(after: at)...]
    let digits = suffix.prefix(while: { $0.isNumber })
    guard (1...3).contains(digits.count), let value = UInt32(digits) else { return nil }
    return value
}

public func preferredLocalizedName(from productName: Any?) -> String? {
    if let string = productName as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let map = productName as? [String: String] {
        if let us = nonemptyString(map["en_US"]) { return us }
        return map.values.lazy.compactMap(nonemptyString).first
    }
    if let map = productName as? [String: Any] {
        if let us = nonemptyString(map["en_US"] as? String) { return us }
        for value in map.values {
            if let name = preferredLocalizedName(from: value) {
                return name
            }
        }
    }
    return nil
}

public func uint32Value(_ any: Any?) -> UInt32? {
    if let value = any as? UInt32 { return value }
    if let value = any as? Int { return UInt32(truncatingIfNeeded: value) }
    if let value = any as? Int64 { return UInt32(truncatingIfNeeded: value) }
    if let value = any as? UInt64 { return UInt32(truncatingIfNeeded: value) }
    if let number = any as? NSNumber { return number.uint32Value }
    return nil
}

public func boolFlag(_ any: Any?) -> Bool {
    if let value = any as? Bool { return value }
    if let value = any as? Int { return value != 0 }
    if let value = any as? UInt32 { return value != 0 }
    if let number = any as? NSNumber { return number.intValue != 0 }
    if let string = any as? String {
        let lower = string.lowercased()
        return lower == "true" || lower == "yes" || lower == "1"
    }
    return false
}

public func stringValue(_ any: Any?) -> String? {
    if let string = any as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

public func dataValue(_ any: Any?) -> Data? {
    if let data = any as? Data, !data.isEmpty { return data }
    return nil
}

public func productAttributes(from dictionary: [String: Any]) -> [String: Any]? {
    if let nested = dictionary[DisplayInfoKey.productAttributes] as? [String: Any] {
        return nested
    }
    if let attrs = dictionary[DisplayInfoKey.displayAttributes] as? [String: Any],
       let nested = attrs[DisplayInfoKey.productAttributes] as? [String: Any]
    {
        return nested
    }
    return nil
}

public func transportPair(from dictionary: [String: Any]) -> (downstream: String?, upstream: String?) {
    let transport = dictionary[DisplayInfoKey.transport] as? [String: Any]
        ?? (dictionary[DisplayInfoKey.displayAttributes] as? [String: Any])?[DisplayInfoKey.transport] as? [String: Any]
    return (
        stringValue(transport?[DisplayInfoKey.downstream]),
        stringValue(transport?[DisplayInfoKey.upstream])
    )
}

public func normalizedEdidUUID(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed.uppercased()
}

private func nameMatchesVirtualDetector(_ raw: String) -> Bool {
    let lower = raw.lowercased()
    return lower.contains("dummy")
        || lower.contains("sidecar")
        || lower.contains("airplay")
        || lower.contains("continuity")
        || lower.contains("displaylink")
}

private func transportLooksLikeDisplayPort(_ lower: String) -> Bool {
    if lower.contains("displayport") { return true }
    if lower == "dp" { return true }
    let tokens = lower.split { !$0.isLetter && !$0.isNumber }
    return tokens.contains { $0 == "dp" }
}

private func nonemptyString(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
