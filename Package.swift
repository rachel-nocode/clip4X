// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "clip4X",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Clip4X", targets: ["Clip4X"])
    ],
    targets: [
        .target(name: "Clip4XCore"),
        .executableTarget(
            name: "Clip4X",
            dependencies: ["Clip4XCore"]
        ),
        .testTarget(
            name: "Clip4XCoreTests",
            dependencies: ["Clip4XCore"]
        )
    ]
)
