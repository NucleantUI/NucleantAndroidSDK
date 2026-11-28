//
//  A Java exception thrown under a capability's API has to reach the Swift
//  caller as an error it can catch, carrying the exception, instead of ending
//  the process in swift-java's "Java call threw unhandled exception" trap.
//
//  These run the real Swift code against a real JVM on the host: the few
//  Android classes it touches are stand-ins (FakeAndroid), compiled with the
//  JDK's javac, that behave like the framework does when the manifest lacks
//  a permission.
//

import AndroidBiometrics
import AndroidCore
import AndroidHaptics
import AndroidNetwork
import Foundation
import SwiftJava
import Testing

@Suite(.serialized, .enabled(if: FakeAndroid.javac != nil, "needs a JDK: JAVA_HOME with bin/javac"))
struct JavaExceptionTests {
    static let useBiometric = "android.permission.USE_BIOMETRIC"
    static let vibrate = "android.permission.VIBRATE"
    static let accessNetworkState = "android.permission.ACCESS_NETWORK_STATE"

    // MARK: Biometrics

    @Test func biometricsInitThrowsTheSecurityException() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.declare(Self.useBiometric, false)

        expectSecurityException("Must have USE_BIOMETRIC permission", Self.useBiometric) { _ = try ABiometrics() }
    }

    @Test func biometricsRefreshThrowsOnceThePermissionIsGone() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.declare(Self.useBiometric, true)
        let biometrics = try ABiometrics()
        #expect(biometrics.availability == .noneEnrolled)

        try android.declare(Self.useBiometric, false)
        expectSecurityException("Must have USE_BIOMETRIC permission", Self.useBiometric) { try biometrics.refresh() }
        #expect(biometrics.availability == .noneEnrolled)
    }

    // MARK: Haptics

    @Test func hapticsThrowTheSecurityExceptionWithoutVibrate() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.declare(Self.vibrate, false)
        // Finding the vibrator needs no permission; using it does.
        let vibrator = try AVibrator()
        #expect(vibrator.hasVibrator)

        expectSecurityException("vibrate", Self.vibrate) { try vibrator.vibrate(milliseconds: 40) }
        expectSecurityException("vibrate", Self.vibrate) {
            try vibrator.vibrate(pattern: [(milliseconds: 100, intensity: 1), (milliseconds: 50, intensity: 0)])
        }
        expectSecurityException("vibrate", Self.vibrate) { try vibrator.play(.click) }
        expectSecurityException("cancelVibrate", Self.vibrate) { try vibrator.cancel() }
    }

    @Test func hapticsVibrateWithVibrateDeclared() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.declare(Self.vibrate, true)
        let vibrator = try AVibrator()

        #expect(throws: Never.self) { try vibrator.vibrate(milliseconds: 40) }
        #expect(throws: Never.self) { try vibrator.play(.click) }
        #expect(throws: Never.self) { try vibrator.cancel() }
    }

    // MARK: Network

    @Test func networkInitThrowsTheSecurityException() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.declare(Self.accessNetworkState, false)

        expectSecurityException("ConnectivityService", Self.accessNetworkState) { _ = try ANetwork() }
    }
}

/// `body` throws the SecurityException Android's permission check throws when
/// the manifest lacks `permission`, and its description is that exception:
/// "java.lang.SecurityException: `message`: Neither user … nor current process
/// has `permission`."
private func expectSecurityException(
    _ message: String,
    _ permission: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) {
    let error = #expect(throws: (any Error).self, sourceLocation: sourceLocation) { try body() }
    guard let error else { return }
    let description = "\(error)"
    #expect(description.hasPrefix("java.lang.SecurityException: \(message): Neither user"), sourceLocation: sourceLocation)
    #expect(description.contains("has \(permission)."), sourceLocation: sourceLocation)
}

/// A JVM in the test process with stand-ins for the Android classes the
/// tests drive. Started once, with the stand-ins on its classpath.
final class FakeAndroid: Sendable {
    static let shared = Result { try FakeAndroid() }

    /// The JDK compiler beside the JVM swift-java loads (`JAVA_HOME`).
    static let javac: URL? = ProcessInfo.processInfo.environment["JAVA_HOME"]
        .map { URL(fileURLWithPath: $0).appendingPathComponent("bin/javac") }
        .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }

    private init() throws {
        let javac = try #require(Self.javac)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NucleantAndroidSDKTests-\(UUID().uuidString)")
        let classes = root.appendingPathComponent("classes")
        var files: [String] = []
        for (path, source) in Self.sources {
            let file = root.appendingPathComponent("src/\(path)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: file, atomically: true, encoding: .utf8)
            files.append(file.path)
        }
        let compile = Process()
        compile.executableURL = javac
        compile.arguments = ["-d", classes.path] + files
        try compile.run()
        compile.waitUntilExit()
        try #require(compile.terminationStatus == 0, "javac failed on the stand-in classes")
        _ = try JavaVirtualMachine.shared(classpath: [classes.path])
    }

    /// Hand a new stand-in Activity over, as the host's `onCreate` does.
    func attachActivity() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        AndroidContext.shared.attach(activity: try Activity.dynamicJavaNewObject(in: environment))
    }

    /// Whether the app's manifest declares `permission`, as far as the
    /// stand-ins are concerned.
    func declare(_ permission: String, _ declared: Bool) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        try JavaClass<FakeManifest>(environment: environment).declare(permission, declared)
    }

    /// The stand-ins: just the members the Swift side calls, with the
    /// signatures Android's have.
    static let sources: [String: String] = [
        "org/nucleantui/test/FakeManifest.java": """
            package org.nucleantui.test;

            import java.util.HashSet;
            import java.util.Set;

            /** Not Android: the permissions the stand-ins treat as declared. */
            public final class FakeManifest {
                private static final Set<String> declared = new HashSet<>();

                public static synchronized void declare(String permission, boolean isDeclared) {
                    if (isDeclared) declared.add(permission); else declared.remove(permission);
                }

                /** What Context.enforceCallingOrSelfPermission throws when the manifest lacks permission. */
                public static synchronized void enforce(String permission, String message) {
                    if (!declared.contains(permission)) {
                        throw new SecurityException(message + ": Neither user 10140 nor current process has "
                            + permission + ".");
                    }
                }
            }
            """,
        "android/content/Context.java": """
            package android.content;

            public class Context {
                public Context getApplicationContext() { return this; }

                public Object getSystemService(String name) {
                    switch (name) {
                        case "biometric": return new android.hardware.biometrics.BiometricManager();
                        case "vibrator": return new android.os.Vibrator();
                        case "connectivity": return new android.net.ConnectivityManager();
                        default: return null;
                    }
                }
            }
            """,
        "android/app/Activity.java": """
            package android.app;

            public class Activity extends android.content.Context {}
            """,
        "android/os/Build.java": """
            package android.os;

            public class Build {
                public static class VERSION {
                    public static final int SDK_INT = 30;
                    public static final String RELEASE = "11";
                }
            }
            """,
        "android/hardware/biometrics/BiometricManager.java": """
            package android.hardware.biometrics;

            import org.nucleantui.test.FakeManifest;

            public class BiometricManager {
                public int canAuthenticate() { return canAuthenticate(0xFF); }

                public int canAuthenticate(int authenticators) {
                    FakeManifest.enforce("android.permission.USE_BIOMETRIC", "Must have USE_BIOMETRIC permission");
                    return 11; // BIOMETRIC_ERROR_NONE_ENROLLED
                }
            }
            """,
        "android/os/Vibrator.java": """
            package android.os;

            import org.nucleantui.test.FakeManifest;

            public class Vibrator {
                public boolean hasVibrator() { return true; }

                public boolean hasAmplitudeControl() { return true; }

                public void vibrate(VibrationEffect effect) {
                    FakeManifest.enforce("android.permission.VIBRATE", "vibrate");
                }

                public void cancel() {
                    FakeManifest.enforce("android.permission.VIBRATE", "cancelVibrate");
                }
            }
            """,
        "android/os/VibrationEffect.java": """
            package android.os;

            public class VibrationEffect {
                public static VibrationEffect createOneShot(long milliseconds, int amplitude) {
                    return new VibrationEffect();
                }

                public static VibrationEffect createWaveform(long[] timings, int[] amplitudes, int repeat) {
                    return new VibrationEffect();
                }

                public static VibrationEffect createPredefined(int effectId) {
                    return new VibrationEffect();
                }
            }
            """,
        "android/net/ConnectivityManager.java": """
            package android.net;

            import org.nucleantui.test.FakeManifest;

            public class ConnectivityManager {
                public Network getActiveNetwork() {
                    FakeManifest.enforce("android.permission.ACCESS_NETWORK_STATE", "ConnectivityService");
                    return null;
                }
            }
            """,
        "android/net/Network.java": """
            package android.net;

            public class Network {}
            """,
    ]
}

/// The stand-ins' manifest (FakeAndroid); not Android's.
@JavaClass("org.nucleantui.test.FakeManifest")
open class FakeManifest: JavaObject {}

extension JavaClass<FakeManifest> {
    @JavaStaticMethod
    func declare(_ permission: String, _ declared: Bool) throws
}
