// swift-tools-version: 5.9
import PackageDescription

// One executable. The menu bar app, the `awake` CLI and the privileged daemon
// are the same binary in different modes -- see Sources/Awake/main.swift.
// The tools under Tools/ run at build time and ship in nothing.
let package = Package(
    name: "Awake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Awake", targets: ["Awake"]),
        .executable(name: "MakeIcon", targets: ["MakeIcon"]),
        .executable(name: "MakeDiskImageBackground", targets: ["MakeDiskImageBackground"]),
    ],
    targets: [
        .executableTarget(name: "Awake"),
        .executableTarget(name: "MakeIcon", path: "Tools/MakeIcon"),
        .executableTarget(name: "MakeDiskImageBackground",
                          path: "Tools/MakeDiskImageBackground"),
    ]
)
