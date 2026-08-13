// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CandelaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CandelaPrivateIO", targets: ["CandelaPrivateIO"]),
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        .library(name: "BrightnessKit", targets: ["BrightnessKit"]),
        .library(name: "AudioKit", targets: ["AudioKit"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    targets: [
        .target(
            name: "CandelaPrivateIO",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DisplayCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "PersistenceKit",
            dependencies: ["DisplayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "BrightnessKit",
            dependencies: ["DisplayCore", "CandelaPrivateIO"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreDisplay"),
            ]
        ),
        .target(
            name: "AudioKit",
            dependencies: ["DisplayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .target(
            name: "TestSupport",
            dependencies: ["DisplayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
        .testTarget(name: "BrightnessKitTests", dependencies: ["BrightnessKit", "TestSupport"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit", "TestSupport"]),
        .testTarget(name: "PersistenceKitTests", dependencies: ["PersistenceKit"]),
    ],
    swiftLanguageModes: [.v5]
)
