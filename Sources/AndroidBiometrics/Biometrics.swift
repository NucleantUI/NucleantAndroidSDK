//
//  Biometrics.swift
//  AndroidBiometrics
//
//  Asking the user to confirm with a fingerprint or face, through
//  BiometricManager and BiometricPrompt. Needs `android.permission.USE_BIOMETRIC`
//  in the manifest (a normal permission: granted on install).
//
//  The emulator has a virtual fingerprint reader: enroll one in Settings →
//  Security (it asks for a screen lock first), then touch it with
//  `adb -e emu finger touch 1` or from Extended controls → Fingerprint.
//

import AndroidCore
import Observation
import SwiftJava

/// Whether the device can authenticate with biometrics:
/// `BiometricManager.BIOMETRIC_SUCCESS` / `BIOMETRIC_ERROR_*` / `BIOMETRIC_STATUS_*`.
public enum ABiometricAvailability: Int32, Sendable {
    case available = 0
    /// The hardware is there but busy or broken.
    case unavailable = 1
    /// The hardware is there but nothing is enrolled.
    case noneEnrolled = 11
    case noHardware = 12
    case securityUpdateRequired = 15
    /// The requested authenticators are not supported on this Android.
    case unsupported = -2
    case unknown = -1
}

/// Biometric authentication. Create and use it on the main thread.
@Observable
public final class ABiometrics: @unchecked Sendable {
    public private(set) var availability: ABiometricAvailability
    /// Whether a prompt is showing.
    public private(set) var isAuthenticating = false
    /// Failed attempts (an unknown finger) during the current prompt.
    public private(set) var failedAttempts = 0

    @ObservationIgnored private let manager: BiometricManager
    @ObservationIgnored private let sdkLevel: Int

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = try context.getSystemService("biometric")?.as(BiometricManager.self) else {
            throw AndroidError.serviceUnavailable("biometric")
        }
        self.manager = manager
        self.sdkLevel = try AndroidContext.shared.sdkLevel(in: environment)
        self.availability = .unavailable
        try refresh()
    }

    /// Check the hardware and enrollment again.
    public func refresh() throws {
        availability = ABiometricAvailability(
            rawValue: try sdkLevel >= 30 ? manager.canAuthenticate(Self.biometricWeak) : manager.canAuthenticate()) ?? .unknown
    }

    /// Show the system's biometric prompt. True when the user authenticated,
    /// false when they cancelled; other outcomes (locked out after too many
    /// tries, no biometrics) throw.
    public func authenticate(title: String, subtitle: String? = nil, cancelTitle: String = "Cancel") async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try AndroidMainThread.shared.post { environment in
                    self.showPrompt(
                        title: title, subtitle: subtitle, cancelTitle: cancelTitle,
                        continuation: continuation, in: environment)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// On the main thread.
    private func showPrompt(
        title: String,
        subtitle: String?,
        cancelTitle: String,
        continuation: CheckedContinuation<Bool, any Error>,
        in environment: JNIEnvironment
    ) {
        guard !isAuthenticating else {
            continuation.resume(throwing: ABiometricError.busy)
            return
        }
        // Once it exists, the authentication answers the continuation.
        var authentication: Authentication?
        do {
            let activity = try AndroidContext.shared.activity(in: environment)
            guard let executor = try activity.getMainExecutor() else {
                throw AndroidError.mainThreadUnavailable
            }
            let started = Authentication(biometrics: self, continuation: continuation)
            authentication = started
            let callbacks = try AuthenticationCallbacks(started.handle, environment: environment)
            started.callbacks = callbacks

            let builder = try BiometricPromptBuilder(activity, environment: environment)
            _ = try builder.setTitle(charSequence(title, in: environment))
            if let subtitle {
                _ = try builder.setSubtitle(charSequence(subtitle, in: environment))
            }
            _ = try builder.setNegativeButton(
                charSequence(cancelTitle, in: environment), executor, callbacks.as(DialogInterfaceOnClickListener.self))
            if sdkLevel >= 30 {
                _ = try builder.setAllowedAuthenticators(Self.biometricWeak)
            }
            guard let prompt = try builder.build() else {
                throw ABiometricError.promptFailed
            }
            failedAttempts = 0
            isAuthenticating = true
            try prompt.authenticate(CancellationSignal(environment: environment), executor, callbacks)
        } catch {
            if let authentication {
                authentication.finish(.failure(error))
            } else {
                continuation.resume(throwing: error)
            }
        }
    }

    func attemptFailed() {
        failedAttempts += 1
    }

    func finished() throws {
        isAuthenticating = false
        try refresh()
    }

    /// `BiometricManager.Authenticators.BIOMETRIC_WEAK`.
    static let biometricWeak: Int32 = 0xFF
}

/// One prompt, from showing to its answer. Keeps itself alive until then.
final class Authentication: @unchecked Sendable {
    let biometrics: ABiometrics
    private var continuation: CheckedContinuation<Bool, any Error>?
    var callbacks: AuthenticationCallbacks?
    private(set) var handle: Int64 = 0

    init(biometrics: ABiometrics, continuation: CheckedContinuation<Bool, any Error>) {
        self.biometrics = biometrics
        self.continuation = continuation
        // The handle holds it weakly, so it holds itself until it finishes.
        retainedSelf = Unmanaged.passRetained(self)
        handle = NativeHandle.retain(self)
    }

    private var retainedSelf: Unmanaged<Authentication>?

    /// code: 0 success, -1 the cancel button, else `BIOMETRIC_ERROR_*`.
    func finished(code: Int32, message: String) {
        switch code {
        case 0:
            finish(.success(true))
        case -1, 5, 10, 13: // cancel button, CANCELED, USER_CANCELED, NEGATIVE_BUTTON
            finish(.success(false))
        default:
            finish(.failure(ABiometricError.failed(code: code, message: message)))
        }
    }

    /// Answer `authenticate` with `result`: the prompt's outcome, or why it
    /// could not be shown. A failure while wrapping up is the answer instead.
    func finish(_ result: Result<Bool, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        var result = result
        do {
            try biometrics.finished()
        } catch {
            result = .failure(error)
        }
        try? callbacks?.disarm()
        continuation.resume(with: result)
        NativeHandle<Authentication>.release(handle)
        retainedSelf?.release()
        retainedSelf = nil
    }
}

public enum ABiometricError: Error, CustomStringConvertible {
    case busy
    case promptFailed
    /// `BiometricPrompt.BIOMETRIC_ERROR_*`, with the system's message.
    case failed(code: Int32, message: String)

    public var description: String {
        switch self {
        case .busy: "A biometric prompt is already showing"
        case .promptFailed: "The biometric prompt could not be created"
        case .failed(let code, let message): message.isEmpty ? "Biometric error \(code)" : message
        }
    }
}

// MARK: - Framework

/// `android.hardware.biometrics.BiometricManager`, API 29.
@JavaClass("android.hardware.biometrics.BiometricManager")
open class BiometricManager: JavaObject {
    /// API 29 (deprecated in 30).
    @JavaMethod
    open func canAuthenticate() throws -> Int32

    /// API 30.
    @JavaMethod
    open func canAuthenticate(_ authenticators: Int32) throws -> Int32
}

/// `android.hardware.biometrics.BiometricPrompt`.
@JavaClass("android.hardware.biometrics.BiometricPrompt")
open class BiometricPrompt: JavaObject {
    @JavaMethod
    open func authenticate(
        _ cancel: CancellationSignal?, _ executor: Executor?, _ callback: BiometricPromptAuthenticationCallback?) throws
}

/// `android.hardware.biometrics.BiometricPrompt.Builder`.
@JavaClass("android.hardware.biometrics.BiometricPrompt$Builder")
open class BiometricPromptBuilder: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func setTitle(_ title: CharSequence?) throws -> BiometricPromptBuilder!

    @JavaMethod
    open func setSubtitle(_ subtitle: CharSequence?) throws -> BiometricPromptBuilder!

    @JavaMethod
    open func setNegativeButton(
        _ text: CharSequence?, _ executor: Executor?, _ listener: DialogInterfaceOnClickListener?
    ) throws -> BiometricPromptBuilder!

    /// API 30.
    @JavaMethod
    open func setAllowedAuthenticators(_ authenticators: Int32) throws -> BiometricPromptBuilder!

    @JavaMethod
    open func build() throws -> BiometricPrompt!
}

/// `android.hardware.biometrics.BiometricPrompt.AuthenticationCallback`.
@JavaClass("android.hardware.biometrics.BiometricPrompt$AuthenticationCallback")
open class BiometricPromptAuthenticationCallback: JavaObject {}

/// `android.content.DialogInterface.OnClickListener`.
@JavaInterface("android.content.DialogInterface$OnClickListener")
public struct DialogInterfaceOnClickListener {}

// MARK: - AuthenticationCallbacks (Android/java)

@JavaClass("org.nucleantui.android.biometrics.AuthenticationCallbacks", implements: DialogInterfaceOnClickListener.self)
class AuthenticationCallbacks: BiometricPromptAuthenticationCallback {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    func disarm() throws
}

@JavaImplementation("org.nucleantui.android.biometrics.AuthenticationCallbacks")
extension AuthenticationCallbacks {
    @JavaMethod
    static func nativeOnFinished(_ handle: Int64, _ code: Int32, _ message: String, environment: JNIEnvironment) {
        NativeHandle<Authentication>.owner(handle)?.finished(code: code, message: message)
    }

    @JavaMethod
    static func nativeOnAttemptFailed(_ handle: Int64, environment: JNIEnvironment) {
        NativeHandle<Authentication>.owner(handle)?.biometrics.attemptFailed()
    }
}
