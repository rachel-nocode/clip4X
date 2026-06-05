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
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.5")
    ],
    targets: [
        .target(name: "Clip4XCore"),
        .executableTarget(
            name: "Clip4X",
            dependencies: [
                "Clip4XCore",
                .product(name: "AppAuth", package: "AppAuth-iOS")
            ]
        ),
        .testTarget(
            name: "Clip4XCoreTests",
            dependencies: ["Clip4XCore"]
        )
    ]
)
