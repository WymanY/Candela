import Foundation

public struct DisplayIdentityInputs: Equatable, Sendable {
    public var vendorID: UInt32
    public var productID: UInt32
    public var serial: UInt32
    public var alphanumericSerial: String?
    public var edidUUID: String?
    public var portLocation: String
    public var unitNumber: UInt32
    public var fallbackName: String

    public init(
        vendorID: UInt32,
        productID: UInt32,
        serial: UInt32,
        alphanumericSerial: String? = nil,
        edidUUID: String? = nil,
        portLocation: String,
        unitNumber: UInt32,
        fallbackName: String
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.alphanumericSerial = alphanumericSerial
        self.edidUUID = edidUUID
        self.portLocation = portLocation
        self.unitNumber = unitNumber
        self.fallbackName = fallbackName
    }
}

public struct DisplayIdentityFields: Equatable, Sendable {
    public var inputs: DisplayIdentityInputs

    public init(inputs: DisplayIdentityInputs) {
        self.inputs = inputs
    }
}

public struct DisplayIdentity: Codable, Sendable {
    public var persistentKey: String
    public var fields: DisplayIdentityFields

    public init(persistentKey: String, fields: DisplayIdentityFields) {
        self.persistentKey = persistentKey
        self.fields = fields
    }
}

extension DisplayIdentity: Hashable, Equatable {
    public static func == (l: Self, r: Self) -> Bool {
        l.persistentKey == r.persistentKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(persistentKey)
    }
}

extension DisplayIdentityInputs: Codable {}
extension DisplayIdentityFields: Codable {}
