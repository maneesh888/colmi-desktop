// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ColmiSync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ColmiSync", targets: ["ColmiSync"])
    ],
    dependencies: [
        // Local ColmiKit package for protocol and models
        .package(path: "../../ColmiKit")
    ],
    targets: [
        .executableTarget(
            name: "ColmiSync",
            dependencies: [
                .product(name: "ColmiProtocol", package: "ColmiKit")
            ],
            path: "Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ColmiSyncTests",
            dependencies: ["ColmiSync"],
            path: "Tests"
        )
    ]
)
