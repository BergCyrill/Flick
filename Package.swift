// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Keep equal to the Sparkle input in flake.nix.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "FlickCore"),
        .executableTarget(
            name: "Flick", dependencies: ["FlickCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
    ]
)
