// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "icloud-status",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "icloud-status",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Rainbow",
            ],
            path: "Sources"
        ),
    ]
)
