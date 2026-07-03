package com.aer.notes_insa

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Dedicated AndroidX [EncryptedSharedPreferences] store shared between the Flutter
 * app (which writes through the MethodChannel) and [GradesBackgroundWorker] (which reads).
 *
 * flutter_secure_storage 10.x stores values under its own RSA+AES cipher with
 * prefixed keys in a plain SharedPreferences file, which the worker cannot read.
 * Rather than reimplement the plugin's internals, the app mirrors the few secrets
 * the worker needs into this store on every credential change, and the worker reads
 * (and updates its grades snapshot) here using the same AndroidX scheme.
 *
 * Key names must stay in sync with WorkerSyncService in lib/services/worker_sync_service.dart.
 */
object WorkerStore {
    private const val TAG = "WorkerStore"
    private const val FILE_NAME = "NotesInsaWorkerStore"

    const val KEY_USERNAME = "username"
    const val KEY_PASSWORD = "password"
    const val KEY_OTP_SECRET = "otp_secret"
    const val KEY_CAS_SESSION = "cas_session"
    const val KEY_GRADES_JSON = "stored_grades_json"
    const val KEY_GRADES_UPDATED_AT = "stored_grades_updated_at"

    // TOTP step (floor(epochSeconds / 30)) most recently claimed by an
    // autoValidate caller, so the worker and the foreground don't submit the
    // same one-time code in the same step. See GradesBackgroundWorker.kt,
    // GradesBackgroundTask.swift, and grades_provider.dart.
    const val KEY_LAST_TOTP_STEP = "last_totp_step"

    /** Opens the store, or returns null if it cannot be created/decrypted. */
    fun openOrNull(context: Context): SharedPreferences? = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (e: Exception) {
        Log.e(TAG, "Failed to open worker store")
        null
    }

    /**
     * Reads the requested keys. Returns null if the store cannot be opened;
     * keys with no stored value are returned as null entries.
     *
     * Used by the Flutter side to pull back values the worker updated on its
     * own (e.g. a CAS session rotated during a background re-auth) — the
     * Flutter → worker mirror in [write] is one-way, so this is the only path
     * for those changes to reach flutter_secure_storage.
     */
    fun read(context: Context, keys: List<String>): Map<String, String?>? {
        val prefs = openOrNull(context) ?: return null
        return keys.associateWith { prefs.getString(it, null) }
    }

    /**
     * Writes the provided keys. A null value removes that key. Keys absent from
     * [values] are left untouched, so callers can sync a subset.
     */
    fun write(context: Context, values: Map<String, String?>) {
        val prefs = openOrNull(context) ?: return
        val editor = prefs.edit()
        for ((key, value) in values) {
            if (value == null) editor.remove(key) else editor.putString(key, value)
        }
        editor.apply()
    }

    /** Clears all stored data (called on logout). */
    fun clearAll(context: Context) {
        openOrNull(context)?.edit()?.clear()?.apply()
    }
}
