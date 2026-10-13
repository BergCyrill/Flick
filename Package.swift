// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlickCore"),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
    ]
)
