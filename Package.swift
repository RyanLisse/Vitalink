// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vitalink",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "vitalink", targets: ["VitalinkExec"]),
        .library(name: "VitalinkCLI", targets: ["VitalinkCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "VitalinkCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/VitalinkCLI"
        ),
        .executableTarget(
            name: "VitalinkExec",
            dependencies: ["VitalinkCLI"],
            path: "Sources/VitalinkExec",
            linkerSettings: [
                .linkedFramework("HealthKit"),
            ]
        ),
        .testTarget(
            name: "VitalinkTests",
            dependencies: ["VitalinkCLI"],
            path: "Tests/VitalinkTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
