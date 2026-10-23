// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexReset",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResetCore", targets: ["ResetCore"]),
        .executable(name: "ResetApp", targets: ["ResetApp"]),
    ],
    targets: [
        .target(name: "ResetCore"),
        .executableTarget(name: "ResetApp", dependencies: ["ResetCore"], exclude: ["Resources"]),
        .testTarget(name: "ResetCoreTests", dependencies: ["ResetCore"]),
    ]
)
