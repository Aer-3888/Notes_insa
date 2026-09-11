import Flutter
import Foundation

/// iOS counterpart of `MainActivity.kt`'s MethodCallHandler.
///
/// Bridges the Dart `MethodChannel('com.aer.notes_insa/grades')` (see
/// lib/services/grades_service.dart and worker_sync_service.dart) to the native
/// Keychain-backed `WorkerStore` and the background task scheduler.
///
/// Each call runs off the main thread and posts its result/error back
/// on the main thread, preserving the `ERR_<METHOD>` error-code contract the
/// Dart side relies on.
enum GradesBridge {
    static let channelName = "com.aer.notes_insa/grades"
    static let notificationRouteKey = "notes_insa_route"
    private static var routeChannel: FlutterMethodChannel?
    private static var pendingNotificationRoute: String?
    private static var routeConsumerReady = false

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        routeChannel = channel
        channel.setMethodCallHandler { call, result in
            handle(call, result)
        }
    }

    private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        case "SyncWorkerStore":
            guard let values = args?["values"] as? [String: Any] else {
                return result(invalidArgs("values missing"))
            }
            runInBackground("SyncWorkerStore", result) {
                try WorkerStore.write(values: normalizeNulls(values))
                return nil
            }

        case "ReadWorkerStore":
            let keys = args?["keys"] as? [String] ?? []
            runInBackground("ReadWorkerStore", result) {
                denormalizeNulls(try WorkerStore.read(keys: keys))
            }

        case "ClearWorkerStore":
            runInBackground("ClearWorkerStore", result) {
                try WorkerStore.clearAll()
                return nil
            }

        case "InitBackgroundTask":
            let interval = args?["intervalMinutes"] as? Int ?? 15
            if #available(iOS 13.0, *) {
                do {
                    try GradesBackgroundTask.schedule(intervalMinutes: interval)
                } catch {
                    return result(FlutterError(
                        code: "ERR_INITBACKGROUNDTASK",
                        message: "Failed to schedule background task",
                        details: nil
                    ))
                }
            }
            result(nil)

        case "StopBackgroundTask":
            if #available(iOS 13.0, *) {
                GradesBackgroundTask.cancel()
            }
            result(nil)

        case "ConsumeNotificationRoute":
            result(pendingNotificationRoute)
            pendingNotificationRoute = nil
            routeConsumerReady = true

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    static func handleNotificationRoute(_ route: String) {
        DispatchQueue.main.async {
            if routeConsumerReady, let channel = routeChannel {
                channel.invokeMethod("onNotificationRoute", arguments: route)
            } else {
                pendingNotificationRoute = route
            }
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
        // Run on the shared serial queue and hold the native lock for the call
        // so a timed-out foreground call, or a concurrent background task run,
        // cannot overlap and corrupt the shared CAS session (see NativeSession).
        NativeSession.queue.async {
            NativeSession.lock.lock()
            defer { NativeSession.lock.unlock() }
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
            // updateValue preserves an explicit Optional.none as a dictionary
            // value; subscript assignment with nil would remove the key and
            // silently drop worker-store deletion requests.
            out.updateValue((value is NSNull) ? nil : (value as? String), forKey: key)
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
