// swift-tools-version: 5.9
import PackageDescription

// One executable. The menu bar app, the `awake` CLI and the privileged daemon
// are the same binary in different modes -- see Sources/Awake/main.swift.
// MakeIcon is a build-time tool and is not shipped in the bundle.
let package = Package(
    name: "Awake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Awake", targets: ["Awake"]),
        .executable(name: "MakeIcon", targets: ["MakeIcon"]),
    ],
    targets: [
        .executableTarget(name: "Awake"),
        .executableTarget(name: "MakeIcon", path: "Tools/MakeIcon"),
    ]
)
