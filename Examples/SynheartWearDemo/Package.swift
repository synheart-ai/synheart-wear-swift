// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SynheartWearDemo",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SynheartWearDemo", targets: ["SynheartWearDemo"])
    ],
    dependencies: [
        .package(name: "SynheartWear", path: "../..")
    ],
    targets: [
        .target(
            name: "SynheartWearDemo",
            dependencies: [
                .product(name: "SynheartWear", package: "SynheartWear")
            ],
            path: "Sources/SynheartWearDemo"
        )
    ]
)
