// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagentModules",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MagentCore",
            targets: ["MagentCore"]
        ),
        .library(
            name: "GhosttyBridge",
            targets: ["GhosttyBridge"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Libraries/GhosttyKit.xcframework"
        ),
        .target(
            name: "MagentCore",
            path: "Sources/MagentCore"
        ),
        .target(
            name: "GhosttyBridge",
            dependencies: ["GhosttyKit"],
            path: "Sources/GhosttyBridge"
        ),
    ]
)
