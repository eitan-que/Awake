// swift-tools-version: 5.9
import PackageDescription

// Target names are deliberately distinct case-insensitively. macOS filesystems
// are case-insensitive by default, so a target pair like "Awake"/"awake" would
// collide in the build directory. The Makefile renames the products when it
// assembles the bundle.
let package = Package(
    name: "Awake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AwakeApp", targets: ["AwakeApp"]),
        .executable(name: "AwakeCLI", targets: ["AwakeCLI"]),
        .executable(name: "AwakeHelper", targets: ["AwakeHelper"]),
        .executable(name: "MakeIcon", targets: ["MakeIcon"]),
    ],
    targets: [
        .target(name: "AwakeCore"),
        .executableTarget(name: "AwakeApp", dependencies: ["AwakeCore"]),
        .executableTarget(name: "AwakeCLI", dependencies: ["AwakeCore"]),
        .executableTarget(name: "AwakeHelper", dependencies: ["AwakeCore"]),
        .executableTarget(name: "MakeIcon", path: "Tools/MakeIcon"),
    ]
)
