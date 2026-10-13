// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlickCore"),
        .executableTarget(name: "Flick", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
    ]
)
