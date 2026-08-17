import Foundation
import IOKit.ps

public enum PowerSourceKind: String, Equatable, Sendable {
    case battery
    case ac
    case offline
    case unknown
}

public struct PowerStatus: Equatable, Sendable {
    public var source: PowerSourceKind
    public var isPresent: Bool
    public var percent: Int?
    public var minutesToEmpty: Int?
    public var isCharging: Bool
    public var isLowPowerModeEnabled: Bool

    public init(
        source: PowerSourceKind,
        isPresent: Bool,
        percent: Int?,
        minutesToEmpty: Int? = nil,
        isCharging: Bool = false,
        isLowPowerModeEnabled: Bool = false
    ) {
        self.source = source
        self.isPresent = isPresent
        self.percent = percent.map { min(100, max(0, $0)) }
        self.minutesToEmpty = minutesToEmpty.flatMap { $0 > 0 ? $0 : nil }
        self.isCharging = isCharging
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    public var showsOnBattery: Bool {
        isPresent && source == .battery && percent != nil
    }

    public var showsOnPower: Bool {
        isPresent && source == .ac && percent != nil
    }

    public var showsInPanel: Bool {
        showsOnBattery || showsOnPower
    }
}

public enum PowerStatusReader {
    public static func current() -> PowerStatus {
        snapshot(
            from: liveDescriptions(),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    public static func snapshot(
        from descriptions: [[String: Any]],
        isLowPowerModeEnabled: Bool = false
    ) -> PowerStatus {
        let batteries = descriptions.filter { description in
            let type = string(description[kIOPSTypeKey])
            let present = bool(description[kIOPSIsPresentKey]) ?? true
            return type == kIOPSInternalBatteryType && present
        }
        guard let battery = preferredBattery(in: batteries) else {
            return PowerStatus(
                source: .unknown,
                isPresent: false,
                percent: nil,
                isLowPowerModeEnabled: isLowPowerModeEnabled
            )
        }

        return PowerStatus(
            source: sourceKind(string(battery[kIOPSPowerSourceStateKey])),
            isPresent: true,
            percent: percent(from: battery),
            minutesToEmpty: int(battery[kIOPSTimeToEmptyKey]),
            isCharging: bool(battery[kIOPSIsChargingKey]) ?? false,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )
    }

    private static func liveDescriptions() -> [[String: Any]] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }
        return list.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
    }

    private static func preferredBattery(in batteries: [[String: Any]]) -> [String: Any]? {
        batteries.first { sourceKind(string($0[kIOPSPowerSourceStateKey])) == .battery }
            ?? batteries.first
    }

    private static func sourceKind(_ raw: String?) -> PowerSourceKind {
        switch raw {
        case kIOPSBatteryPowerValue:
            return .battery
        case kIOPSACPowerValue:
            return .ac
        case kIOPSOffLineValue:
            return .offline
        default:
            return .unknown
        }
    }

    private static func percent(from description: [String: Any]) -> Int? {
        guard let current = number(description[kIOPSCurrentCapacityKey]) else {
            return nil
        }
        let maxCapacity = number(description[kIOPSMaxCapacityKey]) ?? 100
        guard maxCapacity > 0 else { return nil }
        return Int((current / maxCapacity * 100).rounded())
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }
}

public enum PowerStatusPresentation {
    public static func title(for status: PowerStatus) -> String? {
        guard status.showsOnBattery, let percent = status.percent else { return nil }
        return "\(percent)%"
    }

    public static func accessibilityTitle(for status: PowerStatus) -> String? {
        guard status.showsInPanel, let percent = status.percent else { return nil }
        var parts: [String] = []
        if status.showsOnPower {
            parts.append(
                status.isCharging
                    ? String(localized: "Charging", bundle: .module)
                    : String(localized: "Plugged In", bundle: .module)
            )
        }
        parts.append(String(localized: "Battery \(percent) percent", bundle: .module))
        if let remaining = remainingTitle(for: status) {
            parts.append(remaining)
        }
        if status.isLowPowerModeEnabled {
            parts.append(String(localized: "Low Power Mode", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }

    public static func remainingTitle(for status: PowerStatus) -> String? {
        guard status.showsOnBattery, let minutes = status.minutesToEmpty, minutes > 0 else {
            return nil
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let leftover = minutes % 60
            if leftover == 0 {
                return String(localized: "\(hours)h left", bundle: .module)
            }
            return String(localized: "\(hours)h \(leftover)m left", bundle: .module)
        }
        return String(localized: "\(minutes)m left", bundle: .module)
    }

    public static func symbolName(for status: PowerStatus) -> String {
        if status.showsOnPower {
            return "battery.100percent.bolt"
        }
        guard let percent = status.percent else { return "battery.100percent" }
        switch percent {
        case 0..<13:
            return "battery.0percent"
        case 13..<38:
            return "battery.25percent"
        case 38..<63:
            return "battery.50percent"
        case 63..<88:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }
}
