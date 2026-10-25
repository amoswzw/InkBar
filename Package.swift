// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InkBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/amoswzw/InkKit.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "CMenuBar"),
        .executableTarget(
            name: "InkBar",
            dependencies: ["CMenuBar", .product(name: "InkKit", package: "InkKit")],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "InkBarTests",
            dependencies: ["InkBar"]
        ),
    ]
)
