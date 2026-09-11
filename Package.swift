// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
