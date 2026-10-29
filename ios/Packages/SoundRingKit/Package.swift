// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundRingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Input", targets: ["Input"]),
        .library(name: "Detection", targets: ["Detection"]),
        .library(name: "Cloud", targets: ["Cloud"]),
    ],
    targets: [
        // The contracts. Changes need all three software owners to approve.
        .target(name: "Models"),
        .target(name: "Input", dependencies: ["Models"]),      // Lane 1
        .target(name: "Detection", dependencies: ["Models"]),  // Lane 2
        .target(name: "Cloud", dependencies: ["Models"]),      // Lane 3
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
    ]
)
