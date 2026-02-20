// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SynheartWear",
    platforms: [
        .iOS(.v13),
        .watchOS(.v8),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SynheartWear",
            targets: ["SynheartWear"]
        ),
    ],
    dependencies: [
        // Add dependencies here if needed
    ],
    targets: [
        .target(
            name: "SynheartWear",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "SynheartWearTests",
            dependencies: ["SynheartWear"],
            path: "Tests"
        ),
    ]
)
