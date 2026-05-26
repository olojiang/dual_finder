// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DualFinder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DualFinderCore", targets: ["DualFinderCore"]),
        .executable(name: "DualFinderApp", targets: ["DualFinderApp"])
    ],
    targets: [
        .target(name: "DualFinderCore"),
        .executableTarget(
            name: "DualFinderApp",
            dependencies: ["DualFinderCore"]
        ),
        .testTarget(
            name: "DualFinderCoreTests",
            dependencies: ["DualFinderCore"]
        )
    ]
)
