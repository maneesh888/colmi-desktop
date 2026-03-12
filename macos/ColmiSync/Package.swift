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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ColmiSync",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "ColmiSyncTests",
            dependencies: ["ColmiSync"],
            path: "Tests"
        )
    ]
)
