import Foundation

public struct HALOutputDevice: Equatable, Sendable {
    public var uid: String
    public var name: String
    public var manufacturer: String
    public var transport: UInt32
    public var hasVolume: Bool
    public var hasMute: Bool

    public init(
        uid: String,
        name: String,
        manufacturer: String,
        transport: UInt32,
        hasVolume: Bool,
        hasMute: Bool
    ) {
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.transport = transport
        self.hasVolume = hasVolume
        self.hasMute = hasMute
    }
}

public enum AudioMatching {
    /// HDMI `'hdmi'`, DisplayPort `'dprt'`, Thunderbolt `'thun'`, USB `'usb '`.
    public static let transportHDMI: UInt32 = 0x6864_6D69
    public static let transportDisplayPort: UInt32 = 0x6470_7274
    public static let transportThunderbolt: UInt32 = 0x7468_756E
    public static let transportUSB: UInt32 = 0x7573_6220

    /// Pure. No I/O. Uses `display.kind` (USB allowlist), `persistentKey`,
    /// vendor/product from fields, `connection`, `name`, and `overrideUID`.
    /// Built-in and virtual displays never bind. A missing override rematches.
    public static func match(
        display: DisplaySnapshot,
        overrideUID: String?,
        devices: [HALOutputDevice]
    ) -> String? {
        assign(displays: [(display, overrideUID)], devices: devices)[display.id.persistentKey]
    }

    /// Global greedy assignment (§9.3). Keyed by `persistentKey`.
    static func assign(
        displays: [(DisplaySnapshot, String?)],
        devices: [HALOutputDevice]
    ) -> [String: String] {
        let uniqueDevices = uniquedDevices(devices)
        var pairs: [ScoredPair] = []
        pairs.reserveCapacity(displays.count * uniqueDevices.count)

        for (display, overrideUID) in displays {
            guard allowsBinding(display) else { continue }
            let override = resolvedOverride(overrideUID, devices: uniqueDevices)
            for device in uniqueDevices {
                let score = score(display: display, device: device, overrideUID: override)
                if score >= 6 || override == device.uid {
                    pairs.append(
                        ScoredPair(
                            persistentKey: display.id.persistentKey,
                            uid: device.uid,
                            score: score
                        )
                    )
                }
            }
        }

        return assignPairs(pairs)
    }

    static func leftoverStripped(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        return leftoverRegex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
    }

    static func normalize(_ raw: String) -> String {
        var text = leftoverStripped(raw).uppercased()
        for token in transportSubstrings {
            text = text.replacingOccurrences(of: token, with: " ")
        }
        var kept = String()
        kept.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                kept.unicodeScalars.append(scalar)
            } else {
                kept.unicodeScalars.append(" ")
            }
        }
        return kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func modelToken(_ raw: String) -> String? {
        let prepared = leftoverStripped(raw).uppercased()
        let range = NSRange(prepared.startIndex..., in: prepared)
        guard let match = modelRegex.firstMatch(in: prepared, range: range),
              let swiftRange = Range(match.range, in: prepared)
        else {
            return nil
        }
        return String(prepared[swiftRange])
    }

    static func sizeToken(_ raw: String) -> Int? {
        let prepared = leftoverStripped(raw).uppercased()
        let range = NSRange(prepared.startIndex..., in: prepared)
        let matches = sizeRegex.matches(in: prepared, range: range)
        for match in matches {
            let group = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let swiftRange = Range(group, in: prepared),
                  let inches = Int(prepared[swiftRange]),
                  (15...49).contains(inches)
            else {
                continue
            }
            return inches
        }
        return nil
    }
}

// MARK: - Internals

extension AudioMatching {
    static let vendorTokens: [String] = [
        "APPLE", "LG", "DELL", "SAMSUNG", "BENQ", "ASUS", "ACER", "AOC", "HP", "LENOVO",
        "VIEWSONIC", "MSI", "PHILIPS", "EIZO", "NEC", "IIYAMA", "HUAWEI", "XIAOMI",
        "SONY", "SHARP", "INNOCN", "KTC", "GIGABYTE", "AORUS", "ALIENWARE",
    ]

    /// Longer transport phrases first so `USB-C` is not reduced via `USB`.
    private static let transportSubstrings = [
        "DISPLAY PORT",
        "DISPLAYPORT",
        "THUNDERBOLT",
        "HDMI",
        "USB-C",
        "USB C",
        "USB",
    ]

    private static let leftoverRegex = try! NSRegularExpression(pattern: #" \([0-9]+\)$"#)
    private static let modelRegex = try! NSRegularExpression(pattern: #"[A-Z]{0,3}[0-9]{3,5}[A-Z0-9]{0,4}"#)
    private static let sizeRegex = try! NSRegularExpression(pattern: #"\b([1-9][0-9])\b"#)

    private static let pnpToVendorToken: [String: String] = [
        "APP": "APPLE",
        "GSM": "LG",
        "DEL": "DELL",
        "SAM": "SAMSUNG",
        "BNQ": "BENQ",
        "AUS": "ASUS",
        "ACR": "ACER",
        "AOC": "AOC",
        "HPN": "HP",
        "HWP": "HP",
        "HPQ": "HP",
        "LEN": "LENOVO",
        "VSC": "VIEWSONIC",
        "MSI": "MSI",
        "PHL": "PHILIPS",
        "ENC": "EIZO",
        "NEC": "NEC",
        "IVM": "IIYAMA",
        "HUA": "HUAWEI",
        "XMI": "XIAOMI",
        "SNY": "SONY",
        "SHP": "SHARP",
        "INN": "INNOCN",
        "KTC": "KTC",
        "GBT": "GIGABYTE",
        "AOR": "AORUS",
    ]

    private struct ScoredPair {
        var persistentKey: String
        var uid: String
        var score: Int
    }

    static func allowsBinding(_ display: DisplaySnapshot) -> Bool {
        switch display.kind {
        case .builtIn, .virtualUnsupported:
            return false
        case .appleExternal, .genericExternal:
            return true
        }
    }

    static func transportAllowed(kind: DisplayKind, transport: UInt32) -> Bool {
        switch transport {
        case transportHDMI, transportDisplayPort, transportThunderbolt:
            return true
        case transportUSB:
            return kind == .appleExternal
        default:
            return false
        }
    }

    static func resolvedOverride(_ overrideUID: String?, devices: [HALOutputDevice]) -> String? {
        guard let overrideUID, !overrideUID.isEmpty else { return nil }
        return devices.contains(where: { $0.uid == overrideUID }) ? overrideUID : nil
    }

    static func uniquedDevices(_ devices: [HALOutputDevice]) -> [HALOutputDevice] {
        var seen = Set<String>()
        var unique: [HALOutputDevice] = []
        unique.reserveCapacity(devices.count)
        for device in devices {
            if seen.insert(device.uid).inserted {
                unique.append(device)
            }
        }
        return unique
    }

    static func score(
        display: DisplaySnapshot,
        device: HALOutputDevice,
        overrideUID: String?
    ) -> Int {
        let isOverride = overrideUID == device.uid
        if !isOverride && !transportAllowed(kind: display.kind, transport: device.transport) {
            return 0
        }

        var total = 0
        if isOverride {
            total += 1000
        }

        let displayName = normalize(display.name)
        let deviceName = normalize(device.name)
        if displayName.count >= 3 && displayName == deviceName {
            total += 10
        }
        let containedLength = min(displayName.count, deviceName.count)
        if containedLength >= 5 && (displayName.contains(deviceName) || deviceName.contains(displayName)) {
            total += 6
        }

        if let displayModel = modelToken(display.name),
           let deviceModel = modelToken(device.name),
           displayModel == deviceModel
        {
            total += 8
        }
        if let displaySize = sizeToken(display.name),
           let deviceSize = sizeToken(device.name),
           displaySize == deviceSize
        {
            total += 2
        }

        if !vendorTokens(in: display).isDisjoint(with: vendorTokens(in: device)) {
            total += 4
        }

        if display.connection == .hdmi && device.transport == transportHDMI {
            total += 3
        }
        if display.connection == .displayPort && device.transport == transportDisplayPort {
            total += 3
        }
        if display.connection == .thunderbolt && device.transport == transportThunderbolt {
            total += 3
        }
        if display.kind == .appleExternal
            && (device.transport == transportUSB || device.transport == transportThunderbolt)
        {
            total += 3
        }

        return total
    }

    static func vendorTokens(in display: DisplaySnapshot) -> Set<String> {
        var tokens = vendorTokens(in: display.name)
        if let mapped = vendorToken(forVendorID: display.id.fields.inputs.vendorID) {
            tokens.insert(mapped)
        }
        return tokens
    }

    static func vendorTokens(in device: HALOutputDevice) -> Set<String> {
        vendorTokens(in: device.name).union(vendorTokens(in: device.manufacturer))
    }

    static func vendorTokens(in raw: String) -> Set<String> {
        let haystack = leftoverStripped(raw).uppercased()
        var hits = Set<String>()
        for token in vendorTokens where haystack.contains(token) {
            hits.insert(token)
        }
        return hits
    }

    public static func vendorToken(forVendorID vendorID: UInt32) -> String? {
        guard let pnp = pnpID(from: vendorID) else { return nil }
        return pnpToVendorToken[pnp]
    }

    public static func pnpID(from vendorID: UInt32) -> String? {
        let normalized = vendorID == 0xFFFF_FFFF ? 0 : vendorID
        guard normalized != 0 else { return nil }
        let packed = normalized & 0x7FFF
        func letter(_ value: UInt32) -> Character? {
            let index = Int(value & 0x1F)
            guard (1...26).contains(index), let scalar = UnicodeScalar(64 + index) else {
                return nil
            }
            return Character(scalar)
        }
        guard
            let first = letter(packed >> 10),
            let second = letter(packed >> 5),
            let third = letter(packed)
        else {
            return nil
        }
        return String([first, second, third])
    }

    private static func assignPairs(_ pairs: [ScoredPair]) -> [String: String] {
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.persistentKey != rhs.persistentKey { return lhs.persistentKey < rhs.persistentKey }
            return lhs.uid < rhs.uid
        }

        var orderedScores: [Int] = []
        var seenScores = Set<Int>()
        for pair in sorted where seenScores.insert(pair.score).inserted {
            orderedScores.append(pair.score)
        }

        var takenKeys = Set<String>()
        var takenUIDs = Set<String>()
        var assigned: [String: String] = [:]

        for score in orderedScores {
            let live = sorted.filter { pair in
                pair.score == score
                    && !takenKeys.contains(pair.persistentKey)
                    && !takenUIDs.contains(pair.uid)
            }
            var keyCount: [String: Int] = [:]
            var uidCount: [String: Int] = [:]
            for pair in live {
                keyCount[pair.persistentKey, default: 0] += 1
                uidCount[pair.uid, default: 0] += 1
            }
            for pair in live {
                if takenKeys.contains(pair.persistentKey) || takenUIDs.contains(pair.uid) {
                    continue
                }
                // Same-score ambiguity on this display or device: bind neither pair.
                if keyCount[pair.persistentKey, default: 0] > 1 || uidCount[pair.uid, default: 0] > 1 {
                    continue
                }
                takenKeys.insert(pair.persistentKey)
                takenUIDs.insert(pair.uid)
                assigned[pair.persistentKey] = pair.uid
            }
        }

        return assigned
    }
}
