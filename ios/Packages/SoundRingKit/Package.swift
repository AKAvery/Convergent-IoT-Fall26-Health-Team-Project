// swift-tools-version: 6.0
import Foundation
import PackageDescription

// TensorFlow Lite C (iPhone + Simulator only) comes from ios/scripts/fetch_tflite.sh. Without it the
// package still builds: Detection then has no TFLiteClassifier and the model tests are skipped.
let tflitePath = "Vendor/TensorFlowLiteC.xcframework"
let hasTFLite = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + tflitePath + "/Info.plist")

var detectionDeps: [Target.Dependency] = ["Models"]
var extraTargets: [Target] = []
if hasTFLite {
    detectionDeps.append(.target(name: "TensorFlowLiteC", condition: .when(platforms: [.iOS])))
    extraTargets.append(.binaryTarget(name: "TensorFlowLiteC", path: tflitePath))
}

let package = Package(
    name: "SoundRingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Input", targets: ["Input"]),
        .library(name: "Detection", targets: ["Detection"]),
        .library(name: "Cloud", targets: ["Cloud"]),
        .library(name: "Names", targets: ["Names"]),
        .executable(name: "soundring-listen", targets: ["SoundRingListen"]),
    ],
    dependencies: [
        // Lane 3: Auth + Firestore only (Spark plan). No Storage or Functions, which need Blaze.
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0"),
    ],
    targets: [
        // The contracts. Changes need all three software owners to approve.
        .target(name: "Models"),
        .target(name: "Input", dependencies: ["Models"]),      // Lane 1
        .target(name: "Detection", dependencies: detectionDeps,  // Lane 2
                resources: [.copy("Resources/Models"), .process("Resources/categories.json")]),
        .target(name: "Cloud", dependencies: [                 // Lane 3
            "Models",
            .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
        ]),
        // "Someone said your name": Apple's on-device speech-to-text on the box audio (iOS 26+).
        .target(name: "Names"),
        // Mac tool: the real boxes over CoreBluetooth through the same Input code as the app.
        .executableTarget(name: "SoundRingListen", dependencies: ["Models", "Input", "Detection", "Names"]),
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
        .testTarget(name: "InputTests", dependencies: ["Models", "Input"]),
        .testTarget(name: "DetectionTests", dependencies: ["Models", "Input", "Detection"]),
        .testTarget(name: "NamesTests", dependencies: ["Names", "Input"]),
    ] + extraTargets
)
