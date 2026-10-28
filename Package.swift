// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "FlickCore"),
        .executableTarget(
            name: "Flick", dependencies: ["FlickCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
    ]
)
