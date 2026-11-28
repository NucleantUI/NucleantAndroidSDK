// swift-tools-version: 6.3
//
// NucleantAndroidSDK — Swift APIs over the Android SDK, through swift-java.
//
// One target per capability — AndroidFlashlight, AndroidCamera, AndroidPhotos —
// each the Android side of a capability, calling the framework's Java classes
// through swift-java's `@JavaClass` wrappers. They are the Android halves only:
// the cross-platform types that combine them with the Apple ones come later,
// in their own package. Their API is shaped by what every platform can do, so
// that combining stays a thin layer.
//
// Nothing here knows about NucleantUI or NucleantApplication; an app hands its
// Activity over once (`AndroidContext`) and uses the capability types from then on.
//
// The whole package also compiles on the host (macOS), because swift-java's
// wrappers only look their Java classes up at run time. That is what lets the
// tests, `swift build` and the editor's LSP work without the Android SDK —
// calling the APIs is only meaningful inside an Android process.

import PackageDescription

/// The same swift-java NucleantApplication builds its Android platform with
/// (its `SWIFT_JAVA_VERSION`). Exact, not floored: upstream is already past it
/// (0.7.x), and `from:` would resolve this package alone to the newest release.
/// It still resolves next to NucleantApplication's `from: "0.4.2"` when both are
/// in one app's graph.
let swiftJavaVersion: Version = "0.4.2"

/// One target per capability, each the Android side of it. All of them build on
/// AndroidCore; the camera ones also on the shared camera2 wrappers.
let capabilities: [(name: String, dependencies: [Target.Dependency])] = [
    ("AndroidFlashlight", ["AndroidHardwareCamera2"]),
    ("AndroidCamera", ["AndroidHardwareCamera2"]),
    ("AndroidPhotos", []),
    ("AndroidFiles", []),
    ("AndroidHaptics", []),
    ("AndroidBattery", []),
    ("AndroidSensors", []),
    ("AndroidLocation", []),
    ("AndroidClipboard", []),
    ("AndroidNetwork", []),
    ("AndroidNotifications", []),
    ("AndroidShare", []),
    ("AndroidDevice", []),
    ("AndroidSpeech", []),
    ("AndroidBiometrics", []),
]

let swiftJava: Target.Dependency = .product(name: "SwiftJava", package: "swift-java")

let package = Package(
    name: "NucleantAndroidSDK",
    platforms: [
        // Host builds only (Android has no availability floor here): Mutex from
        // Synchronization needs macOS 15.
        .macOS(.v15)
    ],
    products: [
        .library(name: "AndroidCore", targets: ["AndroidCore"]),
        .library(name: "AndroidHardwareCamera2", targets: ["AndroidHardwareCamera2"]),
    ] + capabilities.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-java", exact: swiftJavaVersion),
    ],
    targets: [
        // The app the capabilities run in: its Activity, the SDK level, runtime
        // permissions, the main (Looper) thread, and the handles the Java
        // callback helpers in Android/java carry back into Swift.
        .target(name: "AndroidCore", dependencies: [swiftJava]),
        // swift-java wrappers for the android.hardware.camera2 classes both the
        // flashlight and the camera drive. A product of its own, because the
        // camera hands them out (ACamera.characteristics, .photoSizes).
        .target(name: "AndroidHardwareCamera2", dependencies: ["AndroidCore", swiftJava]),
    ] + capabilities.map {
        .target(name: $0.name, dependencies: ["AndroidCore", swiftJava] + $0.dependencies)
    } + [
        .testTarget(
            name: "NucleantAndroidSDKTests",
            dependencies: ["AndroidCore", swiftJava] + capabilities.map { .byName(name: $0.name) }
        ),
    ]
)
