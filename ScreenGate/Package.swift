// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ScreenGate", platforms: [.macOS(.v12)],
    products: [.executable(name: "ScreenGate", targets: ["ScreenGateApp"]),
               .executable(name: "ScreenGateService", targets: ["ScreenGateService"])],
    targets: [
        .target(name: "Policy", publicHeadersPath: "include"),
        .target(name: "MacBridge", publicHeadersPath: "include", linkerSettings: [
            .linkedFramework("CoreGraphics"), .linkedFramework("IOKit"),
            .linkedFramework("SystemConfiguration"), .linkedFramework("Security")]),
        .target(name: "Shared", dependencies: ["Policy", "MacBridge"]),
        .executableTarget(name: "ScreenGateService", dependencies: ["Shared", "MacBridge", "Policy"]),
        .executableTarget(name: "ScreenGateApp", dependencies: ["Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared", "Policy"])
    ]
)
