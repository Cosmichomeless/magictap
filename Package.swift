// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicTap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MagicTap", targets: ["MagicTap"]),
    ],
    targets: [
        // Pure, hardware-independent tap recognition logic (unit-tested).
        .target(name: "MagicTapCore"),
        // Menu bar app: multitouch input, click injection, UI.
        .executableTarget(name: "MagicTap", dependencies: ["MagicTapCore"]),
        .testTarget(name: "MagicTapCoreTests", dependencies: ["MagicTapCore"]),
    ]
)
