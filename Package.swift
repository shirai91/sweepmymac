// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Sweep", targets: ["Sweep"]),
        .executable(name: "sweep-cli", targets: ["sweep-cli"]),
        .library(name: "SweepCore", targets: ["SweepCore"]),
    ],
    targets: [
        .target(
            name: "SweepCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "Sweep", dependencies: ["SweepCore"]),
        .executableTarget(name: "sweep-cli", dependencies: ["SweepCore"]),
        .testTarget(name: "SweepCoreTests", dependencies: ["SweepCore"]),
    ],
    swiftLanguageModes: [.v5]
)
