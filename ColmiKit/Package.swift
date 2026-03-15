// swift-tools-version: 5.9
// ColmiKit - Cross-platform Swift package for Colmi smart ring communication

import PackageDescription

let package = Package(
    name: "ColmiKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        // Full kit including BLE
        .library(
            name: "ColmiKit",
            targets: ["ColmiProtocol", "ColmiBLE"]
        ),
        // Protocol-only for testing or custom BLE implementations
        .library(
            name: "ColmiProtocol",
            targets: ["ColmiProtocol"]
        ),
        // BLE layer
        .library(
            name: "ColmiBLE",
            targets: ["ColmiBLE"]
        )
    ],
    targets: [
        // Pure Swift protocol implementation - no platform dependencies
        .target(
            name: "ColmiProtocol",
            dependencies: [],
            path: "Sources/ColmiProtocol"
        ),
        // CoreBluetooth wrapper - works on macOS and iOS
        .target(
            name: "ColmiBLE",
            dependencies: ["ColmiProtocol"],
            path: "Sources/ColmiBLE"
        ),
        // Tests
        .testTarget(
            name: "ColmiProtocolTests",
            dependencies: ["ColmiProtocol"],
            path: "Tests/ColmiProtocolTests"
        ),
        .testTarget(
            name: "ColmiBLETests",
            dependencies: ["ColmiBLE"],
            path: "Tests/ColmiBLETests"
        )
    ]
)
