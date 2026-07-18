package com.aer.notes_insa

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypted key/value store shared between the Flutter app (which writes through
 * the MethodChannel) and [GradesBackgroundWorker] (which reads and updates it).
 *
 * Each value is sealed with an AES-256-GCM key held in the Android Keystore
 * (non-exportable, hardware-backed where available) and the ciphertext is kept
 * in a regular private SharedPreferences file. This replaces the deprecated
 * AndroidX EncryptedSharedPreferences (Jetpack Security), which flutter_secure_
 * storage itself dropped for the same reason.
 *
 * flutter_secure_storage 10.x stores values under its own cipher with prefixed
 * keys the worker cannot read, so the app mirrors the few secrets the worker
 * needs into this store on every credential change. Key names must stay in sync
 * with WorkerSyncService in lib/services/worker_sync_service.dart.
 */
object WorkerStore {
    private const val TAG = "WorkerStore"
    private const val FILE_NAME = "NotesInsaWorkerStoreV2"
    private const val LEGACY_FILE_NAME = "NotesInsaWorkerStore"
    private const val KEY_ALIAS = "NotesInsaWorkerStoreKey"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES = 12

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

    // Deletes the abandoned pre-V2 EncryptedSharedPreferences file once per
    // process, so upgraded users who never log out don't keep it around.
    @Volatile
    private var legacyCleaned = false

    private fun cleanLegacyOnce(context: Context) {
        if (legacyCleaned) return
        legacyCleaned = true
        try {
            context.deleteSharedPreferences(LEGACY_FILE_NAME)
        } catch (e: Exception) {
            // Ignore; the legacy file is no longer read regardless.
        }
    }

    private fun prefs(context: Context): SharedPreferences {
        cleanLegacyOnce(context)
        return context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Returns the Keystore AES key, generating it on first use. Synchronized so
     * a concurrent worker and foreground access cannot both generate (and thus
     * overwrite) the key on the very first use, which would leave earlier
     * ciphertext undecryptable.
     */
    @Synchronized
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** Seals [plaintext] as base64(iv || ciphertext) under the Keystore key. */
    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    /** Reverses [encrypt], returning null if the value cannot be decrypted. */
    private fun decrypt(encoded: String): String? = try {
        val combined = Base64.decode(encoded, Base64.NO_WRAP)
        val iv = combined.copyOfRange(0, IV_BYTES)
        val ciphertext = combined.copyOfRange(IV_BYTES, combined.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(GCM_TAG_BITS, iv),
        )
        String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to decrypt a stored value")
        null
    }

    /**
     * Reads and decrypts the requested keys. Returns null if the store cannot be
     * opened; keys with no stored value (or that fail to decrypt) come back as
     * null entries.
     */
    fun read(context: Context, keys: List<String>): Map<String, String?>? = try {
        val prefs = prefs(context)
        keys.associateWith { key -> prefs.getString(key, null)?.let(::decrypt) }
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read worker store")
        null
    }

    /**
     * Encrypts and writes the provided keys. A null value removes that key. Keys
     * absent from [values] are left untouched, so callers can sync a subset.
     */
    fun write(context: Context, values: Map<String, String?>) {
        try {
            val editor = prefs(context).edit()
            for ((key, value) in values) {
                if (value == null) editor.remove(key) else editor.putString(key, encrypt(value))
            }
            editor.apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write worker store")
        }
    }

    /** Clears all stored data (called on logout), durably reporting failure. */
    fun clearAll(context: Context) {
        if (!prefs(context).edit().clear().commit()) {
            throw IllegalStateException("Failed to clear worker store")
        }
    }
}
