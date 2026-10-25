// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InkBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CMenuBar"),
        .executableTarget(
            name: "InkBar",
            dependencies: ["CMenuBar"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "InkBarTests",
            dependencies: ["InkBar"]
        ),
    ]
)
