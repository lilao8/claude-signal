// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSignal",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeSignalCore"),
        .executableTarget(
            name: "ClaudeSignal",
            dependencies: ["ClaudeSignalCore"]
        ),
        .testTarget(
            name: "ClaudeSignalCoreTests",
            dependencies: ["ClaudeSignalCore"]
        ),
    ]
)
