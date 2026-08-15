import CoreGraphics
import Foundation

public struct DisplayHardwareFacts: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var isBuiltin: Bool
    public var isAsleep: Bool
    public var isMain: Bool
    public var vendorID: UInt32
    public var productID: UInt32
    public var serial: UInt32
    public var unitNumber: UInt32
    public var alphanumericSerial: String?
    public var edidUUID: String?
    public var portLocation: String
    public var productName: String
    public var screenFallbackName: String?
    public var transportDownstream: String?
    public var transportUpstream: String?
    public var isVirtualDevice: Bool
    public var isAirPlay: Bool
    public var ioClassOrName: String?
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    public var refreshHz: Double
    public var scaleFactor: Double
    public var rotationDegrees: Double

    public init(
        displayID: CGDirectDisplayID,
        isBuiltin: Bool,
        isAsleep: Bool = false,
        isMain: Bool,
        vendorID: UInt32,
        productID: UInt32,
        serial: UInt32,
        unitNumber: UInt32,
        alphanumericSerial: String? = nil,
        edidUUID: String? = nil,
        portLocation: String,
        productName: String,
        screenFallbackName: String? = nil,
        transportDownstream: String? = nil,
        transportUpstream: String? = nil,
        isVirtualDevice: Bool = false,
        isAirPlay: Bool = false,
        ioClassOrName: String? = nil,
        pixelWidth: UInt32 = 0,
        pixelHeight: UInt32 = 0,
        refreshHz: Double = 0,
        scaleFactor: Double = 1,
        rotationDegrees: Double = 0
    ) {
        self.displayID = displayID
        self.isBuiltin = isBuiltin
        self.isAsleep = isAsleep
        self.isMain = isMain
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.unitNumber = unitNumber
        self.alphanumericSerial = alphanumericSerial
        self.edidUUID = edidUUID
        self.portLocation = portLocation
        self.productName = productName
        self.screenFallbackName = screenFallbackName
        self.transportDownstream = transportDownstream
        self.transportUpstream = transportUpstream
        self.isVirtualDevice = isVirtualDevice
        self.isAirPlay = isAirPlay
        self.ioClassOrName = ioClassOrName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.scaleFactor = scaleFactor
        self.rotationDegrees = rotationDegrees
    }

    public var resolvedName: String {
        if let name = nonempty(productName) { return name }
        if let name = nonempty(screenFallbackName) { return name }
        return "Display"
    }

    public var identityInputs: DisplayIdentityInputs {
        let location = nonempty(portLocation) ?? "unit:\(unitNumber)"
        return DisplayIdentityInputs(
            vendorID: vendorID,
            productID: productID,
            serial: serial,
            alphanumericSerial: alphanumericSerial,
            edidUUID: edidUUID,
            portLocation: location,
            unitNumber: unitNumber,
            fallbackName: resolvedName
        )
    }

    public var virtualEvidence: VirtualDisplayEvidence {
        var names = [productName]
        if let screenFallbackName { names.append(screenFallbackName) }
        var classOrName = ioClassOrName
        if classOrName == nil || classOrName?.isEmpty == true {
            classOrName = portLocation
        } else if !portLocation.isEmpty {
            classOrName = "\(classOrName ?? "") \(portLocation)"
        }
        return VirtualDisplayEvidence(
            vendorID: vendorID,
            names: names,
            isVirtualDevice: isVirtualDevice,
            isAirPlay: isAirPlay,
            classOrName: classOrName
        )
    }
}

public struct LiveKeyAlias: Equatable, Sendable {
    public var oldKey: String
    public var newKey: String

    public init(oldKey: String, newKey: String) {
        self.oldKey = oldKey
        self.newKey = newKey
    }
}

public struct CatalogBuildResult: Equatable, Sendable {
    public var snapshots: [DisplaySnapshot]
    public var copiedRecords: [DisplayRecord]
    public var keyAliases: [LiveKeyAlias]
    public var keysByDisplayID: [CGDirectDisplayID: String]

    public init(
        snapshots: [DisplaySnapshot],
        copiedRecords: [DisplayRecord],
        keyAliases: [LiveKeyAlias],
        keysByDisplayID: [CGDirectDisplayID: String]
    ) {
        self.snapshots = snapshots
        self.copiedRecords = copiedRecords
        self.keyAliases = keyAliases
        self.keysByDisplayID = keysByDisplayID
    }
}

public func previewBrightnessCapabilities(isVirtual: Bool, current: Double = 1.0) -> BrightnessCapabilities {
    BrightnessCapabilities(
        backend: .none,
        supportsHardware: false,
        supportsSoftware: !isVirtual,
        current: current
    )
}

public func previewVolumeCapabilities() -> VolumeCapabilities {
    VolumeCapabilities(
        backend: .none,
        supportsVolume: false,
        supportsMute: false,
        current: 0
    )
}

/// Assemble live snapshots. No I/O. Brightness/volume backends stay neutral.
public func buildLiveCatalog(
    facts: [DisplayHardwareFacts],
    records: [String: DisplayRecord],
    aliases: [String: String],
    previousKeysByDisplayID: [CGDirectDisplayID: String],
    previousSnapshots: [DisplaySnapshot] = []
) -> CatalogBuildResult {
    let siblings = facts.map(\.identityInputs)
    var records = records
    var aliases = aliases
    var snapshots: [DisplaySnapshot] = []
    var copiedRecords: [DisplayRecord] = []
    var keyAliases: [LiveKeyAlias] = []
    var keysByDisplayID: [CGDirectDisplayID: String] = [:]
    let previousByKey = Dictionary(
        previousSnapshots.map { ($0.id.persistentKey, $0) },
        uniquingKeysWith: { _, last in last }
    )

    for fact in facts {
        let inputs = fact.identityInputs
        let newKey = makePersistentKey(
            inputs: inputs,
            siblings: siblings,
            records: records,
            aliases: aliases
        )
        let oldKey = previousKeysByDisplayID[fact.displayID]
        let aliasResult = applyLiveKeyAlias(
            oldKey: oldKey,
            newKey: newKey,
            recordAtOld: lookupRecord(oldKey, records: records, aliases: aliases),
            recordAtNew: lookupRecord(newKey, records: records, aliases: aliases)
        )
        if let copied = aliasResult.copiedRecord {
            records[copied.persistentKey] = copied
            copiedRecords.append(copied)
        }
        if let aliasOld = aliasResult.aliasOldKey, let aliasNew = aliasResult.aliasNewKey {
            aliases[aliasOld] = aliasNew
            keyAliases.append(LiveKeyAlias(oldKey: aliasOld, newKey: aliasNew))
        }

        let isVirtual = isVirtualUnsupported(fact.virtualEvidence)
        let kind = classifyDisplayKind(isVirtual: isVirtual, isBuiltin: fact.isBuiltin)
        let connection = connectionKind(
            isBuiltin: fact.isBuiltin,
            transportDownstream: fact.transportDownstream,
            transportUpstream: fact.transportUpstream,
            location: inputs.portLocation
        )
        var brightness = previewBrightnessCapabilities(isVirtual: isVirtual)
        if let previous = previousByKey[newKey] ?? oldKey.flatMap({ previousByKey[$0] }) {
            brightness.current = previous.brightness.current
        }
        let identity = DisplayIdentity(
            persistentKey: newKey,
            fields: DisplayIdentityFields(inputs: inputs)
        )
        let hardwareName = fact.resolvedName
        let record = lookupRecord(newKey, records: records, aliases: aliases)
        snapshots.append(
            DisplaySnapshot(
                id: identity,
                sessionDisplayID: fact.displayID,
                name: DisplayNameResolver.displayName(hardwareName: hardwareName, customName: record?.customName),
                kind: kind,
                isMain: fact.isMain,
                isBuiltin: fact.isBuiltin,
                connection: connection,
                brightness: brightness,
                volume: previewVolumeCapabilities(),
                contrast: .unsupported,
                input: .unsupported,
                rotation: supportsDisplayRotation(isVirtual: isVirtual, isBuiltin: fact.isBuiltin)
                    ? .supported(DisplayRotation.from(degrees: fact.rotationDegrees))
                    : .unsupported,
                hardwareName: hardwareName,
                pixelWidth: fact.pixelWidth,
                pixelHeight: fact.pixelHeight,
                refreshHz: fact.refreshHz,
                scaleFactor: fact.scaleFactor
            )
        )
        keysByDisplayID[fact.displayID] = newKey
    }

    snapshots.sort { lhs, rhs in
        if lhs.isMain != rhs.isMain { return lhs.isMain }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    return CatalogBuildResult(
        snapshots: snapshots,
        copiedRecords: copiedRecords,
        keyAliases: keyAliases,
        keysByDisplayID: keysByDisplayID
    )
}

private func lookupRecord(
    _ key: String?,
    records: [String: DisplayRecord],
    aliases: [String: String]
) -> DisplayRecord? {
    guard let key else { return nil }
    let resolved = resolveAlias(key, aliases: aliases)
    return records[resolved] ?? records[key]
}

private func nonempty(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
