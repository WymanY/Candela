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
        .library(name: "ControlKit", targets: ["ControlKit"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .executable(name: "candela-cli", targets: ["candela-cli"]),
        .executable(name: "candela-mcp", targets: ["candela-mcp"]),
    ],
    targets: [
        .target(
            name: "CandelaPrivateIO",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedLibrary("objc"),
            ]
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
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "ControlKit",
            dependencies: ["DisplayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "candela-cli",
            dependencies: ["ControlKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "candela-mcp",
            dependencies: ["ControlKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "TestSupport",
            dependencies: ["DisplayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore", "TestSupport"]),
        .testTarget(name: "BrightnessKitTests", dependencies: ["BrightnessKit", "TestSupport"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit", "TestSupport"]),
        .testTarget(name: "PersistenceKitTests", dependencies: ["PersistenceKit"]),
        .testTarget(name: "ControlKitTests", dependencies: ["ControlKit", "TestSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
