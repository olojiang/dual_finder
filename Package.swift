// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DualFinder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DualFinderCore", targets: ["DualFinderCore"]),
        .executable(name: "DualFinderApp", targets: ["DualFinderApp"]),
        .executable(name: "DualFinderHotkeyHelper", targets: ["DualFinderHotkeyHelper"])
    ],
    targets: [
        .target(name: "DualFinderCore"),
        .executableTarget(
            name: "DualFinderApp",
            dependencies: ["DualFinderCore"],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "DualFinderHotkeyHelper",
            dependencies: ["DualFinderCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "DualFinderCoreTests",
            dependencies: ["DualFinderCore"]
        ),
        .testTarget(
            name: "DualFinderAppTests",
            dependencies: ["DualFinderApp"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
