// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProgressNotifier",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ProgressNotifier", targets: ["ProgressNotifier"])],
    targets: [
        .target(name: "ProgressCore"),
        .executableTarget(name: "ProgressNotifier", dependencies: ["ProgressCore"], resources: [.process("Resources")]),
        .testTarget(name: "ProgressCoreTests", dependencies: ["ProgressCore"]),
        .testTarget(name: "ProgressNotifierTests", dependencies: ["ProgressNotifier", "ProgressCore"])
    ]
)
