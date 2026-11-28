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
import Foundation
import SwiftJava
import Testing

@Suite(.serialized, .enabled(if: FakeAndroid.javac != nil, "needs a JDK: JAVA_HOME with bin/javac"))
struct JavaExceptionTests {
    /// What `BiometricManager.canAuthenticate` throws without `USE_BIOMETRIC`.
    static let missingPermission = "java.lang.SecurityException: Must have USE_BIOMETRIC permission"

    @Test func biometricsInitThrowsTheSecurityException() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.setBiometricPermission(false)

        let error = #expect(throws: (any Error).self) { try ABiometrics() }
        #expect(error.map { "\($0)" }?.hasPrefix(Self.missingPermission) == true)
    }

    @Test func biometricsRefreshThrowsOnceThePermissionIsGone() throws {
        let android = try FakeAndroid.shared.get()
        try android.attachActivity()
        try android.setBiometricPermission(true)
        let biometrics = try ABiometrics()
        #expect(biometrics.availability == .noneEnrolled)

        try android.setBiometricPermission(false)
        let error = #expect(throws: (any Error).self) { try biometrics.refresh() }
        #expect(error.map { "\($0)" }?.hasPrefix(Self.missingPermission) == true)
        #expect(biometrics.availability == .noneEnrolled)
    }
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

    /// Whether the manifest declares `USE_BIOMETRIC`, as far as the stand-in
    /// BiometricManager is concerned.
    func setBiometricPermission(_ declared: Bool) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        try JavaClass<BiometricManager>(environment: environment).declared = declared
    }

    /// The stand-ins: just the members the Swift side calls, with the
    /// signatures Android's have.
    static let sources: [String: String] = [
        "android/content/Context.java": """
            package android.content;

            public class Context {
                public Context getApplicationContext() { return this; }

                public Object getSystemService(String name) {
                    return name.equals("biometric") ? new android.hardware.biometrics.BiometricManager() : null;
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

            public class BiometricManager {
                /** Whether the manifest declares USE_BIOMETRIC. */
                public static boolean declared = false;

                public int canAuthenticate() { return canAuthenticate(0xFF); }

                public int canAuthenticate(int authenticators) {
                    if (!declared) {
                        throw new SecurityException("Must have USE_BIOMETRIC permission: "
                            + "Neither user 10140 nor current process has android.permission.USE_BIOMETRIC.");
                    }
                    return 11; // BIOMETRIC_ERROR_NONE_ENROLLED
                }
            }
            """,
    ]
}

extension JavaClass<BiometricManager> {
    /// The stand-in's permission switch (FakeAndroid); not Android's.
    @JavaStaticField
    var declared: Bool
}
