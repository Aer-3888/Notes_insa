import Flutter
import Foundation

/// iOS counterpart of `MainActivity.kt`'s MethodCallHandler.
///
/// Bridges the Dart `MethodChannel('com.aer.notes_insa/grades')` (see
/// lib/services/grades_service.dart and worker_sync_service.dart) to the native
/// `Mobinsapi` data layer and the Keychain-backed `WorkerStore`.
///
/// Each Mobinsapi call runs off the main thread and posts its result/error back
/// on the main thread, preserving the `ERR_<METHOD>` error-code contract the
/// Dart side relies on.
enum GradesBridge {
    static let channelName = "com.aer.notes_insa/grades"

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            handle(call, result)
        }
    }

    private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        case "Auth":
            let username = args?["username"] as? String ?? ""
            let password = args?["password"] as? String ?? ""
            guard !username.isEmpty, !password.isEmpty else {
                return result(invalidArgs("username or password missing"))
            }
            runInBackground("Auth", result) {
                try MobinsApiClient.auth(username: username, password: password)
                return nil
            }

        case "IsTokenNeeded":
            runInBackground("IsTokenNeeded", result) {
                MobinsApiClient.isTokenNeeded()
            }

        case "TriggerEmail":
            runInBackground("TriggerEmail", result) {
                try MobinsApiClient.triggerEmail()
                return nil
            }

        case "Validate":
            let code = args?["code"] as? String ?? ""
            guard !code.isEmpty else { return result(invalidArgs("code missing")) }
            runInBackground("Validate", result) {
                try MobinsApiClient.validate(code: code)
                return nil
            }

        case "AutoValidate":
            let secret = args?["secret"] as? String ?? ""
            guard !secret.isEmpty else { return result(invalidArgs("secret missing")) }
            runInBackground("AutoValidate", result) {
                try MobinsApiClient.autoValidate(secret: secret)
                return nil
            }

        case "IsAuthenticated":
            runInBackground("IsAuthenticated", result) {
                try MobinsApiClient.isAuthenticated()
            }

        case "LoadGroups":
            runInBackground("LoadGroups", result) {
                try MobinsApiClient.loadGroups()
            }

        case "Grades":
            let id = args?["id"] as? Int ?? 0
            runInBackground("Grades", result) {
                try MobinsApiClient.grades(id: id)
            }

        case "Coefficients":
            let id = args?["id"] as? Int ?? 0
            runInBackground("Coefficients", result) {
                try MobinsApiClient.coefficients(id: id)
            }

        case "NewCAS":
            runInBackground("NewCAS", result) {
                try MobinsApiClient.newCAS()
                return nil
            }

        case "ExportCAS":
            runInBackground("ExportCAS", result) {
                try MobinsApiClient.exportCAS()
            }

        case "ImportCAS":
            let token = args?["token"] as? String ?? ""
            guard !token.isEmpty else { return result(invalidArgs("token missing")) }
            runInBackground("ImportCAS", result) {
                try MobinsApiClient.importCAS(token: token)
                return nil
            }

        case "SyncWorkerStore":
            guard let values = args?["values"] as? [String: Any] else {
                return result(invalidArgs("values missing"))
            }
            runInBackground("SyncWorkerStore", result) {
                WorkerStore.write(values: normalizeNulls(values))
                return nil
            }

        case "ReadWorkerStore":
            let keys = args?["keys"] as? [String] ?? []
            runInBackground("ReadWorkerStore", result) {
                denormalizeNulls(WorkerStore.read(keys: keys))
            }

        case "ClearWorkerStore":
            runInBackground("ClearWorkerStore", result) {
                WorkerStore.clearAll()
                return nil
            }

        case "InitBackgroundTask":
            let interval = args?["intervalMinutes"] as? Int ?? 15
            if #available(iOS 13.0, *) {
                GradesBackgroundTask.schedule(intervalMinutes: interval)
            }
            result(nil)

        case "StopBackgroundTask":
            if #available(iOS 13.0, *) {
                GradesBackgroundTask.cancel()
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    /// Runs `block` on a background queue and posts the result (or a
    /// `FlutterError` with the same `ERR_<METHOD>` code contract as Android)
    /// back on the main queue.
    private static func runInBackground(
        _ methodName: String,
        _ result: @escaping FlutterResult,
        _ block: @escaping () throws -> Any?
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let value = try block()
                DispatchQueue.main.async { result(value) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "ERR_\(methodName.uppercased())",
                        message: "An error occurred during \(methodName) execution",
                        details: nil
                    ))
                }
            }
        }
    }

    private static func invalidArgs(_ message: String) -> FlutterError {
        FlutterError(code: "ERR_INVALID_ARGS", message: message, details: nil)
    }

    /// Flutter's standard codec encodes Dart `null` map values as `NSNull`.
    /// Convert them to Swift `nil` so `WorkerStore.write` removes those keys.
    private static func normalizeNulls(_ values: [String: Any]) -> [String: String?] {
        var out: [String: String?] = [:]
        for (key, value) in values {
            out[key] = (value is NSNull) ? nil : (value as? String)
        }
        return out
    }

    /// Convert Swift `nil` values back to `NSNull` so they survive the standard
    /// codec on the way to Dart (where they decode as `null`).
    private static func denormalizeNulls(_ values: [String: String?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in values {
            out[key] = value ?? NSNull()
        }
        return out
    }
}
