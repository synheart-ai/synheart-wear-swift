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
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "SynheartWear",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "SynheartWearTests",
            dependencies: ["SynheartWear"],
            path: "Tests"
        ),
    ]
)
