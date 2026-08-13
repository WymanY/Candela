import DisplayCore
import Foundation

public enum FakeSnapshots {
    public static let builtInName = "Built-in Display"
    public static let dellName = "DELL U2723QE"
    public static let hdmiTVName = "HDMI Television"
    public static let sidecarName = "Sidecar"

    public static func standard() -> [DisplaySnapshot] {
        [
            builtIn(),
            dellUSBC(),
            hdmiTV(),
            sidecar(),
        ]
    }

    public static func builtIn() -> DisplaySnapshot {
        makeSnapshot(
            inputs: DisplayIdentityInputs(
                vendorID: 0x0610,
                productID: 0xA050,
                serial: 0x0000_0001,
                portLocation: "IOService:/AppleCLCD2/built-in",
                unitNumber: 0,
                fallbackName: builtInName
            ),
            sessionDisplayID: 1,
            name: builtInName,
            kind: .builtIn,
            isMain: true,
            isBuiltin: true,
            connection: .builtIn,
            brightness: BrightnessCapabilities(
                backend: .displayServices,
                supportsHardware: true,
                supportsSoftware: true,
                current: 0.80
            ),
            volume: VolumeCapabilities(
                backend: .none,
                supportsVolume: false,
                supportsMute: false,
                current: 0
            )
        )
    }

    public static func dellUSBC() -> DisplaySnapshot {
        makeSnapshot(
            inputs: DisplayIdentityInputs(
                vendorID: 0x10AC,
                productID: 0xD14C,
                serial: 0x1234_5678,
                portLocation: "IOService:/AppleACPIPlatformExpert/PEG0/GFX0/display0",
                unitNumber: 1,
                fallbackName: dellName
            ),
            sessionDisplayID: 2,
            name: dellName,
            kind: .genericExternal,
            isMain: false,
            isBuiltin: false,
            connection: .usb,
            brightness: BrightnessCapabilities(
                backend: .ddc,
                supportsHardware: true,
                supportsSoftware: true,
                current: 0.50,
                ddcMax: 100
            ),
            volume: VolumeCapabilities(
                backend: .ddc,
                supportsVolume: true,
                supportsMute: true,
                current: 0.25
            )
        )
    }

    public static func hdmiTV() -> DisplaySnapshot {
        makeSnapshot(
            inputs: DisplayIdentityInputs(
                vendorID: 0x1138,
                productID: 0x0001,
                serial: 0,
                portLocation: "IOService:/AppleACPIPlatformExpert/hdmi0",
                unitNumber: 2,
                fallbackName: hdmiTVName
            ),
            sessionDisplayID: 3,
            name: hdmiTVName,
            kind: .genericExternal,
            isMain: false,
            isBuiltin: false,
            connection: .hdmi,
            brightness: BrightnessCapabilities(
                backend: .softwareGamma,
                supportsHardware: false,
                supportsSoftware: true,
                current: 0.70
            ),
            volume: VolumeCapabilities(
                backend: .none,
                supportsVolume: false,
                supportsMute: false,
                current: 0
            )
        )
    }

    public static func sidecar() -> DisplaySnapshot {
        makeSnapshot(
            inputs: DisplayIdentityInputs(
                vendorID: 0xF0F0,
                productID: 0x0000,
                serial: 0,
                portLocation: "IOService:/virtual/sidecar",
                unitNumber: 3,
                fallbackName: sidecarName
            ),
            sessionDisplayID: 4,
            name: sidecarName,
            kind: .virtualUnsupported,
            isMain: false,
            isBuiltin: false,
            connection: .unknown,
            brightness: BrightnessCapabilities(
                backend: .none,
                supportsHardware: false,
                supportsSoftware: false,
                current: 1
            ),
            volume: VolumeCapabilities(
                backend: .none,
                supportsVolume: false,
                supportsMute: false,
                current: 0
            )
        )
    }

    private static func makeSnapshot(
        inputs: DisplayIdentityInputs,
        sessionDisplayID: UInt32,
        name: String,
        kind: DisplayKind,
        isMain: Bool,
        isBuiltin: Bool,
        connection: ConnectionKind,
        brightness: BrightnessCapabilities,
        volume: VolumeCapabilities
    ) -> DisplaySnapshot {
        let identity = makeIdentity(inputs: inputs, siblings: [inputs])
        return DisplaySnapshot(
            id: identity,
            sessionDisplayID: sessionDisplayID,
            name: name,
            kind: kind,
            isMain: isMain,
            isBuiltin: isBuiltin,
            connection: connection,
            brightness: brightness,
            volume: volume
        )
    }
}
