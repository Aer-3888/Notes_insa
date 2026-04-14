package com.aer.notes_insa

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import mobinsapi.Mobinsapi
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

private const val TAG = "GradesBackgroundWorker"
private const val CHANNEL_ID = "grades_updates"
private const val SECURE_STORAGE_FILE = "FlutterSecureStorage"
private const val SHARED_PREFS_FILE = "FlutterSharedPreferences"

// Storage keys — must stay in sync with lib/constants.dart
private const val KEY_USERNAME = "username"
private const val KEY_PASSWORD = "password"
private const val KEY_OTP_SECRET = "otp_secret"
private const val KEY_CAS_SESSION = "cas_session"
private const val KEY_GRADES_JSON = "stored_grades_json"

// SharedPreferences keys written by the Flutter shared_preferences plugin (flutter.* prefix)
private const val PREF_FETCH_ENABLED = "flutter.background_fetch_enabled"
private const val PREF_LAST_FETCH_TIME = "flutter.last_fetch_time"

internal const val TASK_UNIQUE_NAME = "grades_fetch_native"

/**
 * Native WorkManager worker that fetches grades without going through a Flutter MethodChannel.
 *
 * The Flutter-side callbackDispatcher approach registers the custom channel in MainActivity only,
 * so MethodChannel calls fail in the headless isolate when the app process was killed.
 * This worker calls Mobinsapi directly, making background fetch reliable across process restarts.
 *
 * Reads credentials from the same EncryptedSharedPreferences file used by flutter_secure_storage,
 * so no data duplication is needed.
 */
class GradesBackgroundWorker(
    private val appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val prefs = appContext.getSharedPreferences(SHARED_PREFS_FILE, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(PREF_FETCH_ENABLED, true)) {
                Log.d(TAG, "Background fetch disabled, skipping")
                return@withContext Result.success()
            }

            val securePrefs = openSecurePrefs() ?: return@withContext Result.success()

            val username = securePrefs.getString(KEY_USERNAME, null)
            val password = securePrefs.getString(KEY_PASSWORD, null)
            if (username == null || password == null) {
                Log.d(TAG, "No credentials stored, skipping")
                return@withContext Result.success()
            }

            val otpSecret = securePrefs.getString(KEY_OTP_SECRET, null)
            val casSession = securePrefs.getString(KEY_CAS_SESSION, null)

            // Try to restore the previous CAS session to skip full re-auth
            if (casSession != null) {
                try {
                    Mobinsapi.importCAS(casSession)
                    Log.d(TAG, "CAS session restored")
                } catch (e: Exception) {
                    Log.w(TAG, "ImportCAS failed, starting new session")
                    securePrefs.edit().remove(KEY_CAS_SESSION).apply()
                    Mobinsapi.newCAS()
                }
            } else {
                Mobinsapi.newCAS()
            }

            // Re-auth only if the restored session is no longer valid
            if (!Mobinsapi.isAuthenticated()) {
                Log.d(TAG, "Not authenticated, running re-auth")
                Mobinsapi.auth(username, password)

                if (Mobinsapi.isTokenNeeded()) {
                    if (otpSecret == null) {
                        Log.d(TAG, "2FA required but no OTP secret stored — notifying user")
                        showReauthNotification()
                        return@withContext Result.success()
                    }
                    Mobinsapi.autoValidate(otpSecret)
                }
            }

            // Export the (possibly refreshed) session for next time
            try {
                val newSession = Mobinsapi.exportCAS()
                securePrefs.edit().putString(KEY_CAS_SESSION, newSession).apply()
            } catch (e: Exception) {
                Log.w(TAG, "ExportCAS failed (non-fatal)")
            }

            // Read the previous snapshot before overwriting it
            val previousJson = securePrefs.getString(KEY_GRADES_JSON, null)
            val groupId = Mobinsapi.loadGroups().toInt()
            val newJson = Mobinsapi.grades(groupId.toLong())
            securePrefs.edit().putString(KEY_GRADES_JSON, newJson).apply()

            prefs.edit().putString(PREF_LAST_FETCH_TIME, java.time.Instant.now().toString()).apply()
            Log.d(TAG, "Grades fetched successfully")

            when {
                previousJson == null -> {
                    Log.d(TAG, "First fetch — data stored, no notification")
                    return@withContext Result.success()
                }
                previousJson == newJson -> {
                    Log.d(TAG, "No changes detected")
                    return@withContext Result.success()
                }
            }

            val (newGrades, updatedGrades) = detectChanges(previousJson, newJson)

            if (newGrades.isEmpty() && updatedGrades.isEmpty()) {
                Log.d(TAG, "JSON changed but no grade changes found")
                return@withContext Result.success()
            }

            if (newGrades.isNotEmpty()) {
                showGradesNotification(
                    id = 1,
                    title = "Nouvelles notes disponibles",
                    subjects = newGrades,
                    singlePrefix = "Nouvelle note",
                    multiPrefix = "Nouvelles notes",
                )
            }
            if (updatedGrades.isNotEmpty()) {
                showGradesNotification(
                    id = 2,
                    title = "Notes mises à jour",
                    subjects = updatedGrades,
                    singlePrefix = "Note mise à jour",
                    multiPrefix = "Notes mises à jour",
                )
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background fetch failed", e)
            Result.retry()
        }
    }

    // Opens the same EncryptedSharedPreferences file that flutter_secure_storage uses.
    private fun openSecurePrefs() = try {
        val masterKey = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            appContext,
            SECURE_STORAGE_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (e: Exception) {
        Log.e(TAG, "Failed to open secure storage")
        null
    }

    // Returns (newGrades, updatedGrades) subject name lists.
    private fun detectChanges(oldJson: String, newJson: String): Pair<List<String>, List<String>> {
        return try {
            val oldSubjects = extractSubjects(oldJson)
            val newSubjects = extractSubjects(newJson)
            val newGrades = mutableListOf<String>()
            val updatedGrades = mutableListOf<String>()
            for ((name, newGradeList) in newSubjects) {
                if (newGradeList.isEmpty()) continue
                val oldGradeList = oldSubjects[name]
                when {
                    oldGradeList == null || oldGradeList.isEmpty() -> newGrades.add(name)
                    oldGradeList != newGradeList -> updatedGrades.add(name)
                }
            }
            Pair(newGrades, updatedGrades)
        } catch (e: Exception) {
            Log.w(TAG, "Change detection failed")
            Pair(emptyList(), emptyList())
        }
    }

    // Mirrors JsonCurriculumParser in lib/data.dart.
    // Returns: subject name → list of "gradeName:score" strings.
    private fun extractSubjects(json: String): Map<String, List<String>> {
        val result = mutableMapOf<String, List<String>>()
        try {
            val root = JSONObject(json)
            val yearDetails = root.optJSONArray("details") ?: return result
            for (si in 0 until yearDetails.length()) {
                val semester = yearDetails.optJSONObject(si) ?: continue
                val ues = semester.optJSONArray("details") ?: continue
                for (ui in 0 until ues.length()) {
                    val ue = ues.optJSONObject(ui) ?: continue
                    val subjects = ue.optJSONArray("details") ?: continue
                    for (subi in 0 until subjects.length()) {
                        val subject = subjects.optJSONObject(subi) ?: continue
                        val name = subject.optString("name", "")
                        if (name.isEmpty()) continue
                        val gradeList = mutableListOf<String>()
                        // Prefer detailed grade entries
                        val gradeDetails = subject.optJSONArray("details")
                        if (gradeDetails != null) {
                            for (gi in 0 until gradeDetails.length()) {
                                val grade = gradeDetails.optJSONObject(gi) ?: continue
                                val score = extractScore(grade.opt("score")) ?: continue
                                if (!score.contains("Aucun")) {
                                    gradeList.add("${grade.optString("name")}:$score")
                                }
                            }
                        }
                        // Fallback: top-level subject score
                        if (gradeList.isEmpty()) {
                            val score = extractScore(subject.opt("score"))
                            if (score != null && !score.contains("Aucun")) {
                                gradeList.add("$name:$score")
                            }
                        }
                        result[name] = gradeList
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "JSON parsing failed")
        }
        return result
    }

    // Handles both String scores (old inscore format) and List scores (new mobinsapi format).
    private fun extractScore(field: Any?): String? = when (field) {
        is String -> field.takeIf { it.isNotEmpty() }
        is JSONArray -> if (field.length() > 0 && field.opt(0) is String) field.optString(0) else null
        else -> null
    }

    private fun showGradesNotification(
        id: Int,
        title: String,
        subjects: List<String>,
        singlePrefix: String,
        multiPrefix: String,
    ) {
        ensureNotificationChannel()
        val body = when {
            subjects.size == 1 -> "$singlePrefix : ${subjects[0]}"
            subjects.size <= 3 -> "$multiPrefix : ${subjects.joinToString(", ")}"
            else -> "$multiPrefix : ${subjects.take(3).joinToString(", ")} et ${subjects.size - 3} autre(s)"
        }
        buildAndPost(id, title, body)
    }

    private fun showReauthNotification() {
        ensureNotificationChannel()
        buildAndPost(
            id = 3,
            title = "Reconnexion requise",
            body = "Une double authentification est nécessaire. Ouvrez l'application pour vous reconnecter.",
        )
    }

    private fun buildAndPost(id: Int, title: String, body: String) {
        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(appContext).notify(id, notification)
        } catch (_: SecurityException) {
            Log.w(TAG, "POST_NOTIFICATIONS permission not granted")
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Grades Updates",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Notifications for new grade updates"
                enableVibration(true)
            }
            val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    companion object {
        /** Schedule (or reschedule) the periodic native background task. */
        fun schedule(context: Context, intervalMinutes: Long) {
            val request = PeriodicWorkRequestBuilder<GradesBackgroundWorker>(
                intervalMinutes, TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(true)
                        .build(),
                )
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    TASK_UNIQUE_NAME,
                    ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
                    request,
                )
            Log.d(TAG, "Scheduled native background task: ${intervalMinutes}min")
        }

        /** Cancel the periodic native background task. */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(TASK_UNIQUE_NAME)
            Log.d(TAG, "Cancelled native background task")
        }
    }
}
