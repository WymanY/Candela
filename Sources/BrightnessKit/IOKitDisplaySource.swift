import CoreGraphics
import DisplayCore
import Foundation
import IOKit
import IOKit.graphics

/// Gathers identity inputs and connection flags for a `CGDirectDisplayID`. No writes.
public enum IOKitDisplaySource {
    public static func facts(
        for displayIDs: [CGDirectDisplayID],
        screenNames: [CGDirectDisplayID: String] = [:]
    ) -> [DisplayHardwareFacts] {
        let ioDisplays = collectIODisplayDictionaries()
        let ioReg = collectIORegFramebuffers()
        var usedIODisplay = Set<Int>()
        var usedIOReg = Set<Int>()
        return displayIDs.map { id in
            facts(
                for: id,
                screenFallbackName: screenNames[id],
                ioDisplays: ioDisplays,
                ioReg: ioReg,
                usedIODisplay: &usedIODisplay,
                usedIOReg: &usedIOReg
            )
        }
    }

    public static func facts(
        for displayID: CGDirectDisplayID,
        screenFallbackName: String? = nil
    ) -> DisplayHardwareFacts {
        var usedIODisplay = Set<Int>()
        var usedIOReg = Set<Int>()
        return facts(
            for: displayID,
            screenFallbackName: screenFallbackName,
            ioDisplays: collectIODisplayDictionaries(),
            ioReg: collectIORegFramebuffers(),
            usedIODisplay: &usedIODisplay,
            usedIOReg: &usedIOReg
        )
    }

    private static func facts(
        for displayID: CGDirectDisplayID,
        screenFallbackName: String?,
        ioDisplays: [[String: Any]],
        ioReg: [IORegFramebuffer],
        usedIODisplay: inout Set<Int>,
        usedIOReg: inout Set<Int>
    ) -> DisplayHardwareFacts {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        var unit = CGDisplayUnitNumber(displayID)
        let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        let isAsleep = CGDisplayIsAsleep(displayID) != 0
        let isMain = CGDisplayIsMain(displayID) != 0

        let core = CoreDisplayInfo.dictionary(for: displayID) ?? [:]
        let io = takeMatchingIODisplay(
            vendor: vendor,
            product: product,
            serial: serial,
            unit: unit,
            ioDisplays: ioDisplays,
            used: &usedIODisplay
        ) ?? [:]

        var location = locationString(core) ?? locationString(io)
        if location == nil || location == "unknown" {
            location = nil
        }

        let ioRegRecord = takeMatchingIOReg(
            location: location,
            vendor: vendor,
            serial: serial,
            records: ioReg,
            used: &usedIOReg
        )

        if location == nil {
            location = ioRegRecord?.path
        }
        if unit == 0, let parsed = location.flatMap(unitNumberFromLocation) {
            unit = parsed
        }
        let portLocation = location ?? "unit:\(unit)"

        let edid = dataValue(core[DisplayInfoKey.ioDisplayEDID])
            ?? dataValue(io[DisplayInfoKey.ioDisplayEDID])
            ?? ioRegRecord?.edid

        var edidUUID = normalizedEdidUUID(stringValue(ioRegRecord?.edidUUIDRaw) ?? stringValue(core[DisplayInfoKey.edidUUID]))
        if edidUUID == nil, let edid {
            edidUUID = synthesizeEdidUUID(from: edid)
        }

        let attributes = ioRegRecord?.productAttributes ?? productAttributes(from: core) ?? productAttributes(from: io)
        let serialString = stringValue(core[DisplayInfoKey.displaySerialString])
            ?? stringValue(io[DisplayInfoKey.displaySerialString])

        #if arch(arm64)
        let alphanumeric = stringValue(attributes?[DisplayInfoKey.alphanumericSerialNumber])
            ?? edid.flatMap(edidAlphanumericSerial)
            ?? serialString
        #else
        let alphanumeric = serialString ?? edid.flatMap(edidAlphanumericSerial)
        #endif

        let productName = preferredLocalizedName(from: core[DisplayInfoKey.displayProductName])
            ?? preferredLocalizedName(from: io[DisplayInfoKey.displayProductName])
            ?? stringValue(attributes?[DisplayInfoKey.productName])
            ?? edid.flatMap(edidMonitorName)
            ?? ""

        let transport = ioRegRecord.map { ($0.downstream, $0.upstream) }
            ?? transportPair(from: core)
        let ioClass = ioRegRecord.map { "\($0.name) \($0.path)" }

        let mode = currentMode(for: displayID)
        let mirroredMaster = CGDisplayMirrorsDisplay(displayID)
        let isMirroringBuiltIn = mirroredMaster != 0 && CGDisplayIsBuiltin(mirroredMaster) != 0
        return DisplayHardwareFacts(
            displayID: displayID,
            isBuiltin: isBuiltin,
            isAsleep: isAsleep,
            isMain: isMain,
            vendorID: vendor,
            productID: product,
            serial: serial,
            unitNumber: unit,
            alphanumericSerial: alphanumeric,
            edidUUID: edidUUID,
            portLocation: portLocation,
            productName: productName,
            screenFallbackName: screenFallbackName,
            transportDownstream: transport.0,
            transportUpstream: transport.1,
            isVirtualDevice: boolFlag(core[DisplayInfoKey.isVirtualDevice]),
            isAirPlay: boolFlag(core[DisplayInfoKey.isAirPlay]),
            ioClassOrName: ioClass,
            pixelWidth: mode.width,
            pixelHeight: mode.height,
            refreshHz: mode.refresh,
            scaleFactor: mode.scale,
            rotationDegrees: CGDisplayRotation(displayID),
            isMirroringBuiltIn: isMirroringBuiltIn
        )
    }

    private static func currentMode(for displayID: CGDirectDisplayID) -> (width: UInt32, height: UInt32, refresh: Double, scale: Double) {
        let width = UInt32(CGDisplayPixelsWide(displayID))
        let height = UInt32(CGDisplayPixelsHigh(displayID))
        var refresh = 0.0
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            refresh = mode.refreshRate
        }
        let bounds = CGDisplayBounds(displayID)
        let pointWidth = Double(bounds.width)
        let scale = pointWidth > 0 ? Double(width) / pointWidth : 1
        return (width, height, refresh, scale)
    }

    private static func locationString(_ dictionary: [String: Any]) -> String? {
        stringValue(dictionary[DisplayInfoKey.ioDisplayLocation])
    }

    private static func takeMatchingIODisplay(
        vendor: UInt32,
        product: UInt32,
        serial: UInt32,
        unit: UInt32,
        ioDisplays: [[String: Any]],
        used: inout Set<Int>
    ) -> [String: Any]? {
        var fallback: Int?
        for (index, dict) in ioDisplays.enumerated() where !used.contains(index) {
            let dVendor = uint32Value(dict[DisplayInfoKey.displayVendorID]) ?? 0
            let dProduct = uint32Value(dict[DisplayInfoKey.displayProductID]) ?? 0
            guard dVendor == vendor, dProduct == product else { continue }
            let dSerial = uint32Value(dict[DisplayInfoKey.displaySerialNumber]) ?? 0
            let dUnit = unitNumberFromLocation(stringValue(dict[DisplayInfoKey.ioDisplayLocation]) ?? "") ?? 0
            if serial != 0 {
                if dSerial == serial {
                    used.insert(index)
                    return dict
                }
                continue
            }
            if dUnit == unit {
                used.insert(index)
                return dict
            }
            if fallback == nil { fallback = index }
        }
        if serial == 0, let fallback {
            used.insert(fallback)
            return ioDisplays[fallback]
        }
        return nil
    }

    private static func takeMatchingIOReg(
        location: String?,
        vendor: UInt32,
        serial: UInt32,
        records: [IORegFramebuffer],
        used: inout Set<Int>
    ) -> IORegFramebuffer? {
        if let location, !location.isEmpty {
            if let index = records.indices.first(where: { !used.contains($0) && records[$0].path == location }) {
                used.insert(index)
                return records[index]
            }
        }
        let candidates = records.indices.filter { index in
            guard !used.contains(index) else { return false }
            let record = records[index]
            guard let legacy = record.legacyManufacturer, legacy == vendor else { return false }
            if serial != 0, let recordSerial = record.serial, recordSerial != 0 {
                return recordSerial == serial
            }
            return true
        }
        if candidates.count == 1 {
            used.insert(candidates[0])
            return records[candidates[0]]
        }
        return nil
    }

    private static func collectIODisplayDictionaries() -> [[String: Any]] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let dict = ioDisplayInfoDictionary(service) {
                result.append(dict)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func ioDisplayInfoDictionary(_ service: io_service_t) -> [String: Any]? {
        guard let unmanaged = IODisplayCreateInfoDictionary(
            service,
            IOOptionBits(kIODisplayOnlyPreferredName)
        ) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }

    private static func collectIORegFramebuffers() -> [IORegFramebuffer] {
        collectIORegFramebuffers(matching: "AppleCLCD2")
            + collectIORegFramebuffers(matching: "IOMobileFramebufferShim")
    }

    private static func collectIORegFramebuffers(matching className: String) -> [IORegFramebuffer] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(className),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [IORegFramebuffer] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            result.append(readFramebuffer(service))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func readFramebuffer(_ service: io_service_t) -> IORegFramebuffer {
        let props = cfProperties(service)
        let attributes = productAttributes(from: props) ?? [:]
        let transport = transportPair(from: props)
        return IORegFramebuffer(
            name: serviceName(service),
            path: servicePath(service),
            productAttributes: attributes,
            edidUUIDRaw: stringValue(props[DisplayInfoKey.edidUUID]),
            edid: dataValue(props[DisplayInfoKey.ioDisplayEDID]) ?? dataValue(props["EDID"]),
            downstream: transport.downstream,
            upstream: transport.upstream,
            legacyManufacturer: uint32Value(attributes[DisplayInfoKey.legacyManufacturerID]),
            serial: uint32Value(attributes[DisplayInfoKey.serialNumber])
        )
    }

    private static func cfProperties(_ entry: io_registry_entry_t) -> [String: Any] {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    private static func serviceName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &buffer)
        return String(cString: buffer)
    }

    private static func servicePath(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS else {
            return ""
        }
        return String(cString: buffer)
    }
}

private struct IORegFramebuffer {
    var name: String
    var path: String
    var productAttributes: [String: Any]
    var edidUUIDRaw: String?
    var edid: Data?
    var downstream: String?
    var upstream: String?
    var legacyManufacturer: UInt32?
    var serial: UInt32?
}
