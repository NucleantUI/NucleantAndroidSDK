// swift-tools-version: 6.3
//
// Device Lab's Swift: DeviceLabBridge, the one library (libDeviceLabBridge.so)
// the Kotlin app in app/ calls. It uses NucleantAndroidSDK, one level up,
// through its products, as any app does.
//
// jextract turns every `public` declaration of DeviceLabBridge into Java
// (org.nucleantui.devicelab.bridge), so the target holds exactly the surface the
// app uses and forwards into the capability types. app/build.gradle.kts
// cross-compiles it per ABI with the Swift Android SDK.

import PackageDescription

/// NucleantAndroidSDK's swift-java (see its Package.swift).
let swiftJavaVersion: Version = "0.4.2"

/// The NucleantAndroidSDK products the bridge forwards into.
let sdkProducts = [
    "AndroidCore",
    "AndroidHardwareCamera2",
    "AndroidFlashlight",
    "AndroidCamera",
    "AndroidPhotos",
    "AndroidFiles",
    "AndroidHaptics",
    "AndroidBattery",
    "AndroidSensors",
    "AndroidLocation",
    "AndroidClipboard",
    "AndroidNetwork",
    "AndroidNotifications",
    "AndroidShare",
    "AndroidDevice",
    "AndroidSpeech",
    "AndroidBiometrics",
]

let package = Package(
    name: "DeviceLab",
    platforms: [
        // Host builds only (the editor's LSP), as NucleantAndroidSDK's.
        .macOS(.v15)
    ],
    products: [
        .library(name: "DeviceLabBridge", type: .dynamic, targets: ["DeviceLabBridge"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/swiftlang/swift-java", exact: swiftJavaVersion),
    ],
    targets: [
        .target(
            name: "DeviceLabBridge",
            dependencies: sdkProducts.map { .product(name: $0, package: "NucleantAndroidSDK") } + [
                .product(name: "SwiftJava", package: "swift-java"),
            ],
            exclude: ["swift-java.config"],
            // jextract's generated async thunks do not pass Swift 6's sending
            // checks; swift-java's own samples build them in Swift 5 mode too.
            swiftSettings: [.swiftLanguageMode(.v5)],
            plugins: [
                .plugin(name: "JExtractSwiftPlugin", package: "swift-java"),
            ]
        ),
    ]
)
