import CoreGraphics
import DisplayCore
import Foundation
import IOKit

/// CG display side of the Arm64 EDID-fragment score (§7.2).
public struct AVServiceScoreDisplay: Equatable, Sendable {
    public var vendorID: UInt32
    public var productID: UInt32
    public var serial: UInt32
    public var weekOfManufacture: UInt32?
    public var yearOfManufacture: UInt32?
    public var horizontalImageSizeMM: UInt32?
    public var verticalImageSizeMM: UInt32?
    public var location: String
    public var productName: String

    public init(
        vendorID: UInt32,
        productID: UInt32,
        serial: UInt32 = 0,
        weekOfManufacture: UInt32? = nil,
        yearOfManufacture: UInt32? = nil,
        horizontalImageSizeMM: UInt32? = nil,
        verticalImageSizeMM: UInt32? = nil,
        location: String = "",
        productName: String = ""
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.weekOfManufacture = weekOfManufacture
        self.yearOfManufacture = yearOfManufacture
        self.horizontalImageSizeMM = horizontalImageSizeMM
        self.verticalImageSizeMM = verticalImageSizeMM
        self.location = location
        self.productName = productName
    }
}

/// IOReg `DCPAVServiceProxy` side of the score. `serviceLocation` is a walk token only.
public struct AVServiceScoreService: Equatable, Sendable {
    public var edidUUID: String
    public var ioRegPath: String
    public var productName: String
    public var serial: UInt32
    public var serviceLocation: Int

    public init(
        edidUUID: String,
        ioRegPath: String = "",
        productName: String = "",
        serial: UInt32 = 0,
        serviceLocation: Int
    ) {
        self.edidUUID = edidUUID
        self.ioRegPath = ioRegPath
        self.productName = productName
        self.serial = serial
        self.serviceLocation = serviceLocation
    }
}

public struct AVServiceAssignment: Equatable, Sendable {
    public var displayIndex: Int
    public var serviceIndex: Int
    public var serviceLocation: Int
    public var score: Int

    public init(displayIndex: Int, serviceIndex: Int, serviceLocation: Int, score: Int) {
        self.displayIndex = displayIndex
        self.serviceIndex = serviceIndex
        self.serviceLocation = serviceLocation
        self.score = score
    }
}

/// One External `DCPAVServiceProxy` plus the preceding framebuffer record.
public final class AVServiceWalkResult {
    public let scoreService: AVServiceScoreService
    var avService: AnyObject?

    init(scoreService: AVServiceScoreService, avService: AnyObject?) {
        self.scoreService = scoreService
        self.avService = avService
    }

    func takeAVService() -> AnyObject? {
        defer { avService = nil }
        return avService
    }
}

/// EDID-fragment score + IOReg walk for Arm64 `IOAVService` matching.
public enum AVServiceMatcher {
    public static let vendorOffset = 0
    public static let productOffset = 4
    public static let weekYearOffset = 19
    public static let imageSizeOffset = 30
    public static let skipFragment = "0000"

    public static let weekOfManufactureKey = "DisplayWeekManufacture"
    public static let yearOfManufactureKey = "DisplayYearManufacture"
    public static let horizontalImageSizeKey = "DisplayHorizontalImageSize"
    public static let verticalImageSizeKey = "DisplayVerticalImageSize"
    public static let proxyLocationKey = "Location"
    public static let externalLocation = "External"

    /// Hyphenated uppercase slice of length 4 at `offset`.
    public static func uuidSlice(_ uuid: String, offset: Int) -> String {
        String(uuid.uppercased().dropFirst(offset).prefix(4))
    }

    /// `"%04X"` of the clamped vendor. `nil` when `"0000"`.
    public static func vendorFragment(vendorID: UInt32) -> String? {
        let hex = String(format: "%04X", UInt16(clamping: normalizeVendorOrProduct(vendorID)))
        return hex == skipFragment ? nil : hex
    }

    /// Little-endian product `"%02X%02X"` (lo, hi). `nil` when `"0000"`.
    public static func productFragment(productID: UInt32) -> String? {
        let product = normalizeVendorOrProduct(productID)
        let lo = UInt8(truncatingIfNeeded: product & 0xFF)
        let hi = UInt8(truncatingIfNeeded: (product >> 8) & 0xFF)
        let hex = String(format: "%02X%02X", lo, hi)
        return hex == skipFragment ? nil : hex
    }

    /// `"%02X%02X"` week, year-1990. Calendar years (`>= 1990`) are offset; smaller values are EDID raw.
    public static func weekYearFragment(week: UInt32, year: UInt32) -> String? {
        let weekByte = UInt8(truncatingIfNeeded: week)
        let yearByte: UInt8
        if year >= 1990 {
            yearByte = UInt8(truncatingIfNeeded: year &- 1990)
        } else {
            yearByte = UInt8(truncatingIfNeeded: year)
        }
        let hex = String(format: "%02X%02X", weekByte, yearByte)
        return hex == skipFragment ? nil : hex
    }

    /// `"%02X%02X"` of mm/10. `nil` when `"0000"`.
    public static func imageSizeFragment(horizontalMM: UInt32, verticalMM: UInt32) -> String? {
        let hex = String(
            format: "%02X%02X",
            UInt8(truncatingIfNeeded: horizontalMM / 10),
            UInt8(truncatingIfNeeded: verticalMM / 10)
        )
        return hex == skipFragment ? nil : hex
    }

    /// Each fragment hit +1. Location exact +10. Product name case-insensitive +1. Serial equal +1.
    public static func score(display: AVServiceScoreDisplay, service: AVServiceScoreService) -> Int {
        var total = 0
        let uuid = service.edidUUID
        if let fragment = vendorFragment(vendorID: display.vendorID),
           fragment == uuidSlice(uuid, offset: vendorOffset)
        {
            total += 1
        }
        if let fragment = productFragment(productID: display.productID),
           fragment == uuidSlice(uuid, offset: productOffset)
        {
            total += 1
        }
        if let week = display.weekOfManufacture,
           let year = display.yearOfManufacture,
           let fragment = weekYearFragment(week: week, year: year),
           fragment == uuidSlice(uuid, offset: weekYearOffset)
        {
            total += 1
        }
        if let horizontal = display.horizontalImageSizeMM,
           let vertical = display.verticalImageSizeMM,
           let fragment = imageSizeFragment(horizontalMM: horizontal, verticalMM: vertical),
           fragment == uuidSlice(uuid, offset: imageSizeOffset)
        {
            total += 1
        }
        if !display.location.isEmpty, display.location == service.ioRegPath {
            total += 10
        }
        if !display.productName.isEmpty,
           !service.productName.isEmpty,
           display.productName.caseInsensitiveCompare(service.productName) == .orderedSame
        {
            total += 1
        }
        if display.serial != 0, display.serial == service.serial {
            total += 1
        }
        return total
    }

    /// Score descending, greedy. Do not reuse `serviceLocation`. Discard score 0.
    public static func assign(
        displays: [AVServiceScoreDisplay],
        services: [AVServiceScoreService]
    ) -> [AVServiceAssignment] {
        struct Pair {
            var displayIndex: Int
            var serviceIndex: Int
            var serviceLocation: Int
            var score: Int
        }

        var pairs: [Pair] = []
        for (displayIndex, display) in displays.enumerated() {
            for (serviceIndex, service) in services.enumerated() {
                let value = score(display: display, service: service)
                if value > 0 {
                    pairs.append(
                        Pair(
                            displayIndex: displayIndex,
                            serviceIndex: serviceIndex,
                            serviceLocation: service.serviceLocation,
                            score: value
                        )
                    )
                }
            }
        }
        pairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.displayIndex != $1.displayIndex { return $0.displayIndex < $1.displayIndex }
            if $0.serviceLocation != $1.serviceLocation { return $0.serviceLocation < $1.serviceLocation }
            return $0.serviceIndex < $1.serviceIndex
        }

        var usedDisplays = Set<Int>()
        var usedLocations = Set<Int>()
        var usedServices = Set<Int>()
        var result: [AVServiceAssignment] = []
        result.reserveCapacity(min(displays.count, services.count))
        for pair in pairs {
            if usedDisplays.contains(pair.displayIndex) { continue }
            if usedLocations.contains(pair.serviceLocation) { continue }
            if usedServices.contains(pair.serviceIndex) { continue }
            usedDisplays.insert(pair.displayIndex)
            usedLocations.insert(pair.serviceLocation)
            usedServices.insert(pair.serviceIndex)
            result.append(
                AVServiceAssignment(
                    displayIndex: pair.displayIndex,
                    serviceIndex: pair.serviceIndex,
                    serviceLocation: pair.serviceLocation,
                    score: pair.score
                )
            )
        }
        return result
    }

    public static func scoreDisplay(
        vendorID: UInt32,
        productID: UInt32,
        serial: UInt32,
        location: String,
        productName: String,
        coreDisplay: [String: Any] = [:]
    ) -> AVServiceScoreDisplay {
        AVServiceScoreDisplay(
            vendorID: vendorID,
            productID: productID,
            serial: serial,
            weekOfManufacture: uint32Value(coreDisplay[weekOfManufactureKey]),
            yearOfManufacture: uint32Value(coreDisplay[yearOfManufactureKey]),
            horizontalImageSizeMM: uint32Value(coreDisplay[horizontalImageSizeKey]),
            verticalImageSizeMM: uint32Value(coreDisplay[verticalImageSizeKey]),
            location: location,
            productName: productName
        )
    }

    public static func scoreDisplay(for displayID: CGDirectDisplayID) -> AVServiceScoreDisplay {
        let dictionary = CoreDisplayInfo.dictionary(for: displayID) ?? [:]
        let vendor = normalizeVendorOrProduct(
            uint32Value(dictionary[DisplayInfoKey.displayVendorID]) ?? CGDisplayVendorNumber(displayID)
        )
        let product = normalizeVendorOrProduct(
            uint32Value(dictionary[DisplayInfoKey.displayProductID]) ?? CGDisplayModelNumber(displayID)
        )
        let serial = uint32Value(dictionary[DisplayInfoKey.displaySerialNumber]) ?? CGDisplaySerialNumber(displayID)
        let location = stringValue(dictionary[DisplayInfoKey.ioDisplayLocation]) ?? ""
        let name = preferredLocalizedName(from: dictionary[DisplayInfoKey.displayProductName]) ?? ""
        return scoreDisplay(
            vendorID: vendor,
            productID: product,
            serial: serial,
            location: location,
            productName: name,
            coreDisplay: dictionary
        )
    }

    /// Recursive `IOService` walk. `Location == "External"` is required to emit.
    public static func walkExternalAVServices() -> [AVServiceWalkResult] {
        #if arch(arm64) && !CANDELA_GAMMA_ONLY && !CANDELA_MAS
        walkIOReg()
        #else
        []
        #endif
    }

    public static func match(displayID: CGDirectDisplayID) -> (AVServiceWalkResult, Int)? {
        guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }
        let walked = walkExternalAVServices()
        guard !walked.isEmpty else { return nil }
        let display = scoreDisplay(for: displayID)
        let assignments = assign(displays: [display], services: walked.map(\.scoreService))
        guard let hit = assignments.first else { return nil }
        return (walked[hit.serviceIndex], hit.score)
    }
}

#if arch(arm64) && !CANDELA_GAMMA_ONLY && !CANDELA_MAS
extension AVServiceMatcher {
    private static let framebufferNames: Set<String> = [
        "AppleCLCD2",
        "IOMobileFramebufferShim",
    ]
    private static let proxyName = "DCPAVServiceProxy"

    private static func walkIOReg() -> [AVServiceWalkResult] {
        guard IOAVSymbols.isReady else { return [] }

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var currentEntry: io_registry_entry_t = 0
        var currentRecord = emptyRecord(serviceLocation: 0)
        var serviceLocation = 0
        var emitted: [AVServiceWalkResult] = []

        defer {
            if currentEntry != 0 {
                IOObjectRelease(currentEntry)
            }
        }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let name = registryName(entry)
            if framebufferNames.contains(name) {
                IOObjectRetain(entry)
                if currentEntry != 0 {
                    IOObjectRelease(currentEntry)
                }
                currentEntry = entry
                serviceLocation += 1
                currentRecord = readFramebufferRecord(entry, serviceLocation: serviceLocation)
            } else if name == proxyName {
                if registryLocation(entry) == externalLocation,
                   let service = IOAVSymbols.createService(from: entry)
                {
                    let record = currentEntry == 0 ? emptyRecord(serviceLocation: serviceLocation) : currentRecord
                    emitted.append(AVServiceWalkResult(scoreService: record, avService: service))
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return emitted
    }

    private static func emptyRecord(serviceLocation: Int) -> AVServiceScoreService {
        AVServiceScoreService(edidUUID: "", ioRegPath: "", productName: "", serial: 0, serviceLocation: serviceLocation)
    }

    private static func readFramebufferRecord(
        _ entry: io_registry_entry_t,
        serviceLocation: Int
    ) -> AVServiceScoreService {
        let props = cfProperties(entry)
        let attributes = productAttributes(from: props) ?? [:]
        return AVServiceScoreService(
            edidUUID: normalizedEdidUUID(stringValue(props[DisplayInfoKey.edidUUID])) ?? "",
            ioRegPath: registryPath(entry),
            productName: stringValue(attributes[DisplayInfoKey.productName]) ?? "",
            serial: uint32Value(attributes[DisplayInfoKey.serialNumber]) ?? 0,
            serviceLocation: serviceLocation
        )
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &buffer)
        return String(cString: buffer)
    }

    private static func registryPath(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS else {
            return ""
        }
        return String(cString: buffer)
    }

    private static func registryLocation(_ entry: io_registry_entry_t) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            entry,
            proxyLocationKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        return stringValue(unmanaged.takeRetainedValue())
    }

    private static func cfProperties(_ entry: io_registry_entry_t) -> [String: Any] {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = props?.takeRetainedValue() as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }
}
#endif
