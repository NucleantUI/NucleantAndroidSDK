//
//  Framework.swift
//  AndroidCore
//
//  swift-java wrappers for the Android framework classes AndroidCore and the
//  capability targets share. Written by hand, method by method, rather than
//  generated from android.jar: only what is called is declared.
//
//  Each `@JavaMethod` is looked up by name and by the JNI signature its Swift
//  types spell, so parameter and result types have to name the exact Java
//  types — a `Uri` result declared as `JavaObject` would look for a method
//  returning `java.lang.Object` and not find it. A `CharSequence` parameter
//  takes `charSequence(_:in:)`.
//

import SwiftJava

// MARK: - java.lang / java.util

/// `java.lang.Runnable`.
@JavaInterface("java.lang.Runnable")
public struct Runnable {
    @JavaMethod
    public func run() throws
}

/// `java.util.concurrent.Executor`.
@JavaInterface("java.util.concurrent.Executor")
public struct Executor {}

/// `java.util.ArrayList`, untyped: elements go in as `Object`, which is the
/// erased signature `add` has.
@JavaClass("java.util.ArrayList")
open class JavaArrayList: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func add(_ element: JavaObject?) throws -> Bool
}

/// `text` as the `java.lang.CharSequence` framework methods take.
public func charSequence(_ text: String, in environment: JNIEnvironment) -> CharSequence? {
    JavaString(text, environment: environment).as(CharSequence.self)
}

// MARK: - android.content

/// `android.content.Context`.
@JavaClass("android.content.Context")
open class Context: JavaObject {
    @JavaMethod
    open func getApplicationContext() throws -> Context!

    /// `Object getSystemService(String)`; cast the result with `as(_:)`.
    @JavaMethod
    open func getSystemService(_ name: String) throws -> JavaObject!

    @JavaMethod
    open func checkSelfPermission(_ permission: String) throws -> Int32

    @JavaMethod
    open func getPackageName() throws -> String

    @JavaMethod
    open func getPackageManager() throws -> PackageManager!

    @JavaMethod
    open func getResources() throws -> Resources!

    /// API 28.
    @JavaMethod
    open func getMainExecutor() throws -> Executor!

    /// `registerReceiver(BroadcastReceiver, IntentFilter, String, Handler, int)`, API 26.
    @JavaMethod
    open func registerReceiver(
        _ receiver: BroadcastReceiver?,
        _ filter: IntentFilter?,
        _ broadcastPermission: JavaString?,
        _ scheduler: Handler?,
        _ flags: Int32
    ) throws -> Intent!

    @JavaMethod
    open func unregisterReceiver(_ receiver: BroadcastReceiver?) throws
}

extension Context {
    /// `Context.RECEIVER_NOT_EXPORTED`, API 33.
    public static let receiverNotExported: Int32 = 4
}

/// `android.content.Intent`.
@JavaClass("android.content.Intent")
open class Intent: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ action: String, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func getAction() throws -> String

    @JavaMethod
    open func getIntExtra(_ name: String, _ defaultValue: Int32) throws -> Int32

    @JavaMethod
    open func getBooleanExtra(_ name: String, _ defaultValue: Bool) throws -> Bool

    @JavaMethod
    open func getStringExtra(_ name: String) throws -> String

    @JavaMethod
    open func setType(_ type: String) throws -> Intent!

    @JavaMethod
    open func putExtra(_ name: String, _ value: JavaString?) throws -> Intent!

    @JavaMethod
    open func putExtra(_ name: String, _ value: Parcelable?) throws -> Intent!

    @JavaMethod
    open func putExtra(_ name: String, _ value: Int32) throws -> Intent!

    @JavaMethod
    open func putExtra(_ name: String, _ value: [String]) throws -> Intent!

    @JavaMethod
    open func addFlags(_ flags: Int32) throws -> Intent!

    @JavaMethod
    open func addCategory(_ category: String) throws -> Intent!

    @JavaMethod
    open func hasExtra(_ name: String) throws -> Bool

    @JavaMethod
    open func removeExtra(_ name: String) throws

    /// The URI an answering app sent back (a picked document, for one).
    @JavaMethod
    open func getData() throws -> Uri!
}

extension JavaClass<Intent> {
    @JavaStaticMethod
    public func createChooser(_ target: Intent?, _ title: CharSequence?) throws -> Intent!
}

/// `android.content.IntentFilter`.
@JavaClass("android.content.IntentFilter")
open class IntentFilter: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ action: String, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func addAction(_ action: String) throws
}

/// `android.content.BroadcastReceiver`.
@JavaClass("android.content.BroadcastReceiver")
open class BroadcastReceiver: JavaObject {}

/// `android.content.pm.PackageManager`.
@JavaClass("android.content.pm.PackageManager")
open class PackageManager: JavaObject {
    @JavaMethod
    open func getLaunchIntentForPackage(_ packageName: String) throws -> Intent!

    @JavaMethod
    open func hasSystemFeature(_ name: String) throws -> Bool
}

/// `android.content.res.Resources`.
@JavaClass("android.content.res.Resources")
open class Resources: JavaObject {
    @JavaMethod
    open func getDisplayMetrics() throws -> DisplayMetrics!
}

// MARK: - android.app

/// `android.app.Activity`.
@JavaClass("android.app.Activity")
open class Activity: Context {
    @JavaMethod
    open func requestPermissions(_ permissions: [String], _ requestCode: Int32) throws

    @JavaMethod
    open func startActivity(_ intent: Intent?) throws

    @JavaMethod
    open func startActivityForResult(_ intent: Intent?, _ requestCode: Int32) throws

    /// The intent that started (or, after `setIntent`, last brought back) the Activity.
    @JavaMethod
    open func getIntent() throws -> Intent!

    @JavaMethod
    open func getWindow() throws -> Window!
}

// MARK: - android.view

/// `android.view.Window`.
@JavaClass("android.view.Window")
open class Window: JavaObject {
    @JavaMethod
    open func addFlags(_ flags: Int32) throws

    @JavaMethod
    open func clearFlags(_ flags: Int32) throws

    @JavaMethod
    open func getAttributes() throws -> WindowLayoutParams!

    @JavaMethod
    open func setAttributes(_ attributes: WindowLayoutParams?) throws
}

/// `android.view.WindowManager.LayoutParams`.
@JavaClass("android.view.WindowManager$LayoutParams")
open class WindowLayoutParams: JavaObject {
    /// -1 follows the system; 0...1 overrides it for this window.
    @JavaField
    public var screenBrightness: Float

    @JavaField
    public var flags: Int32
}

extension WindowLayoutParams {
    public static let flagKeepScreenOn: Int32 = 0x80
}

// MARK: - android.net

/// `android.net.Uri`.
@JavaClass("android.net.Uri", implements: Parcelable.self)
open class Uri: JavaObject {
    @JavaMethod
    open func getLastPathSegment() throws -> String
}

// MARK: - android.os

/// `android.os.Parcelable`.
@JavaInterface("android.os.Parcelable")
public struct Parcelable {}

/// `android.os.Bundle`.
@JavaClass("android.os.Bundle")
open class Bundle: JavaObject {}

/// `android.os.Build.VERSION`, for `SDK_INT`.
@JavaClass("android.os.Build$VERSION")
open class BuildVersion: JavaObject {}

extension JavaClass<BuildVersion> {
    @JavaStaticField(isFinal: true)
    public var SDK_INT: Int32

    @JavaStaticField(isFinal: true)
    public var RELEASE: String
}

/// `android.os.Looper`.
@JavaClass("android.os.Looper")
open class Looper: JavaObject {
    @JavaMethod
    open func isCurrentThread() throws -> Bool
}

extension JavaClass<Looper> {
    @JavaStaticMethod
    public func getMainLooper() throws -> Looper!
}

/// `android.os.Handler`.
@JavaClass("android.os.Handler")
open class Handler: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ looper: Looper?, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func post(_ runnable: Runnable?) throws -> Bool

    @JavaMethod
    open func postDelayed(_ runnable: Runnable?, _ delayMillis: Int64) throws -> Bool
}

/// `android.os.CancellationSignal`.
@JavaClass("android.os.CancellationSignal")
open class CancellationSignal: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func cancel() throws
}

// MARK: - android.util

/// `android.util.Size`.
@JavaClass("android.util.Size")
open class Size: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ width: Int32, _ height: Int32, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func getWidth() throws -> Int32

    @JavaMethod
    open func getHeight() throws -> Int32
}

/// `android.util.DisplayMetrics`.
@JavaClass("android.util.DisplayMetrics")
open class DisplayMetrics: JavaObject {
    @JavaField
    public var widthPixels: Int32

    @JavaField
    public var heightPixels: Int32

    @JavaField
    public var density: Float

    @JavaField
    public var densityDpi: Int32
}

// MARK: - org.nucleantui.android (Android/java)

/// `org.nucleantui.android.NativeRunnable`: a Runnable whose run() is Swift.
/// See AndroidMainThread.
@JavaClass("org.nucleantui.android.NativeRunnable", implements: Runnable.self)
open class NativeRunnable: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ handle: Int64, environment: JNIEnvironment? = nil) throws
}
