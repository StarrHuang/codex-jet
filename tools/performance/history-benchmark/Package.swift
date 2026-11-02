// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HistoryStorePerformance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "CodexReset", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "HistoryStorePerformance",
            dependencies: [.product(name: "ResetCore", package: "CodexReset")]),
    ])
