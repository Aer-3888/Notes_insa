import Foundation
import Security

/// iOS counterpart of Android's `WorkerStore.kt`.
///
/// On Android the worker store is a dedicated AndroidX EncryptedSharedPreferences
/// file shared between the Flutter app and the background WorkManager worker.
/// On iOS the background task (`GradesBackgroundTask`) runs *in the app's own
/// process*, so a plain Keychain item (no App Group / sharing entitlement
/// required) is sufficient. We use a distinct Keychain service so these mirrored
/// secrets stay separate from `flutter_secure_storage`'s own items.
///
/// Items are stored with `kSecAttrAccessibleAfterFirstUnlock` so the background
/// task can read them while the device is locked (after the first unlock since
/// boot).
///
/// Key names MUST stay in sync with `WorkerSyncService` in
/// lib/services/worker_sync_service.dart and with `WorkerStore.kt`.
enum WorkerStore {
    private static let service = "NotesInsaWorkerStore"

    static let keyUsername = "username"
    static let keyPassword = "password"
    static let keyOtpSecret = "otp_secret"
    static let keyCasSession = "cas_session"
    static let keyGradesJson = "stored_grades_json"
    static let keyGradesUpdatedAt = "stored_grades_updated_at"

    // MARK: - Public API (mirrors WorkerStore.kt: read / write / clearAll)

    /// Reads the requested keys. Keys with no stored value come back as `nil`.
    static func read(keys: [String]) -> [String: String?] {
        var result: [String: String?] = [:]
        for key in keys {
            // updateValue keeps the key present with a nil value when nothing is
            // stored (matching Kotlin's `associateWith`). Plain `result[key] =
            // nil` would instead REMOVE the key, so don't simplify this.
            result.updateValue(get(key), forKey: key)
        }
        return result
    }

    /// Writes the provided keys. A `nil` value removes that key. Keys absent
    /// from `values` are left untouched, so callers can sync a subset.
    static func write(values: [String: String?]) {
        for (key, value) in values {
            if let value = value {
                set(key, value)
            } else {
                remove(key)
            }
        }
    }

    /// Clears every stored value (called on logout).
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Single-item helpers

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func set(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Try to update an existing item first; insert if it doesn't exist.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
