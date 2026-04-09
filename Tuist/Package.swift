// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagentDependencies",
    dependencies: [
        .package(path: "../Packages/MagentModules"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.10.0"),
    ]
)
