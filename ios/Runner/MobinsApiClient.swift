import Foundation
import Mobinsapi

/// Thin Swift wrapper over the gomobile-generated `Mobinsapi` framework.
///
/// Every native data-layer call is isolated here, so if the gomobile-generated
/// symbol names or error conventions differ from what's assumed below (they
/// depend on the gomobile / gobind version), THIS is the only file to reconcile.
///
/// After building the framework on the Mac, verify the generated signatures in:
///   ios/Frameworks/Mobinsapi.xcframework/ios-arm64/Mobinsapi.framework/Headers/Mobinsapi.objc.h
///
/// Mirrors `mobinsapi/Mobinsapi.java` (the Android gobind proxy):
///   auth, autoValidate, coefficients, exportCAS, grades, importCAS,
///   isAuthenticated, isTokenNeeded, loadGroups, newCAS, triggerEmail, validate
///
/// NOTE on the throwing convention: gomobile maps a Go `func F() error` to an
/// ObjC method/function with a trailing `NSError**`, which Swift imports as
/// `throws`. A Go `func F() (T, error)` imports as `throws -> T`. If the
/// importer instead exposes the raw `NSError**` out-param (free C functions are
/// not always auto-bridged to `throws`), switch the calls below to the manual
/// form, e.g.:
///     var err: NSError?
///     let value = MobinsapiGrades(id, &err)
///     if let err = err { throw err }
enum MobinsApiClient {

    // MARK: - Auth flow

    static func auth(username: String, password: String) throws {
        try MobinsapiAuth(username, password)
    }

    static func isTokenNeeded() -> Bool {
        return MobinsapiIsTokenNeeded()
    }

    static func triggerEmail() throws {
        try MobinsapiTriggerEmail()
    }

    static func validate(code: String) throws {
        try MobinsapiValidate(code)
    }

    static func autoValidate(secret: String) throws {
        try MobinsapiAutoValidate(secret)
    }

    /// Go signature: `func IsAuthenticated() (bool, error)`.
    /// If the BOOL+NSError** combination bridges to `throws -> Void` (a known
    /// Swift importer quirk for ObjC methods returning BOOL), use the manual
    /// out-param form documented at the top of this file instead.
    static func isAuthenticated() throws -> Bool {
        return try MobinsapiIsAuthenticated()
    }

    // MARK: - CAS session

    static func newCAS() throws {
        try MobinsapiNewCAS()
    }

    static func exportCAS() throws -> String {
        return try MobinsapiExportCAS()
    }

    static func importCAS(token: String) throws {
        try MobinsapiImportCAS(token)
    }

    // MARK: - Grades

    /// Returns the number of available groups (cards).
    static func loadGroups() throws -> Int {
        return try Int(MobinsapiLoadGroups())
    }

    /// `id` is the 0-based group index.
    static func grades(id: Int) throws -> String {
        return try MobinsapiGrades(Int(id))
    }

    static func coefficients(id: Int) throws -> String {
        return try MobinsapiCoefficients(Int(id))
    }
}
