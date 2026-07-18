package com.aer.notes_insa

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import mobinsapi.Mobinsapi
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

private const val TAG = "GradesBackgroundWorker"
private const val CHANNEL_ID = "grades_updates"
private const val RECONNECT_CHANNEL_ID = "reconnect_updates"
private const val SYNC_CHANNEL_ID = "sync_status"
private const val SHARED_PREFS_FILE = "FlutterSharedPreferences"

// Storage keys — read from WorkerStore (see WorkerStore.kt).
private const val KEY_USERNAME = WorkerStore.KEY_USERNAME
private const val KEY_PASSWORD = WorkerStore.KEY_PASSWORD
private const val KEY_OTP_SECRET = WorkerStore.KEY_OTP_SECRET
private const val KEY_CAS_SESSION = WorkerStore.KEY_CAS_SESSION
private const val KEY_GRADES_JSON = WorkerStore.KEY_GRADES_JSON
private const val KEY_GRADES_UPDATED_AT = WorkerStore.KEY_GRADES_UPDATED_AT
private const val KEY_LAST_TOTP_STEP = WorkerStore.KEY_LAST_TOTP_STEP

// TOTP codes change once per step (RFC 6238 default period). Used to coordinate
// autoValidate with the foreground so they don't submit the same one-time code
// in the same step. If the real period differs the worst case is an unnecessary
// skip (harmless retry), never a new failure.
private const val TOTP_STEP_SECONDS = 30L

// SharedPreferences key written by the Flutter shared_preferences plugin (flutter.* prefix)
private const val PREF_FETCH_ENABLED = "flutter.background_fetch_enabled"
private const val PREF_LAST_REAUTH_NOTIF_MS = "flutter.last_reauth_notif_ms"
private const val PREF_LAST_CREDS_NOTIF_MS = "flutter.last_creds_notif_ms"
private const val REAUTH_NOTIF_COOLDOWN_MS = 4 * 60 * 60 * 1000L // 4 hours

// Legacy preference retained only so a successful/disabled run cleans up state
// written by older app versions.
private const val PREF_AUTH_FAIL_COUNT = "flutter.consecutive_auth_failures"

internal const val TASK_UNIQUE_NAME = "grades_fetch_native"

/**
 * Native WorkManager worker that fetches grades without going through a Flutter MethodChannel.
 *
 * The Flutter-side callbackDispatcher approach registers the custom channel in MainActivity only,
 * so MethodChannel calls fail in the headless isolate when the app process was killed.
 * This worker calls Mobinsapi directly, making background fetch reliable across process restarts.
 *
 * Reads credentials and the previous grades snapshot from [WorkerStore], a Keystore-encrypted
 * store the Flutter app mirrors on every credential change. The worker cannot read
 * flutter_secure_storage 10.x directly (custom cipher + prefixed keys).
 */
class GradesBackgroundWorker(
    private val appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = appContext.getSharedPreferences(SHARED_PREFS_FILE, Context.MODE_PRIVATE)
        try {
            if (!prefs.getBoolean(PREF_FETCH_ENABLED, true)) {
                Log.d(TAG, "Background fetch disabled, skipping")
                resetFailureWindow(prefs)
                return@withContext Result.success()
            }

            // Acquire the same lock used by foreground MethodChannel cleanup
            // before reading credentials. Logout therefore either waits for this
            // whole run and clears its final writes, or clears first and makes
            // this run observe an empty store; it cannot resurrect an account.
            NativeSession.lock.lock()

            val store = WorkerStore.read(
                appContext,
                listOf(
                    KEY_USERNAME, KEY_PASSWORD, KEY_OTP_SECRET, KEY_CAS_SESSION,
                    KEY_GRADES_JSON,
                ),
            )

            val username = store[KEY_USERNAME]
            val password = store[KEY_PASSWORD]
            if (username == null || password == null) {
                Log.d(TAG, "No credentials stored, skipping")
                resetFailureWindow(prefs)
                return@withContext Result.success()
            }

            val otpSecret = store[KEY_OTP_SECRET]
            val casSession = store[KEY_CAS_SESSION]

            // The lock is held from the credential read through every native and
            // worker-store write. It is released in the finally below.

            // Try to restore the previous CAS session to skip full re-auth
            if (casSession != null) {
                try {
                    Mobinsapi.importCAS(casSession)
                    Log.d(TAG, "CAS session restored")
                } catch (e: Exception) {
                    Log.w(TAG, "ImportCAS failed, starting new session")
                    WorkerStore.write(appContext, mapOf(KEY_CAS_SESSION to null))
                    Mobinsapi.newCAS()
                }
            } else {
                Mobinsapi.newCAS()
            }
            if (isStopped) return@withContext Result.retry()

            // Re-auth only if the restored session is no longer valid
            if (!Mobinsapi.isAuthenticated()) {
                Log.d(TAG, "Not authenticated, running re-auth")
                try {
                    Mobinsapi.auth(username, password)
                } catch (e: Exception) {
                    if (isStopped) return@withContext Result.retry()
                    // Mobinsapi exposes only a generic exception here, so it is
                    // unsafe to claim the password is invalid: an INSA outage or
                    // captive network looks identical. Track a truthful generic
                    // failure incident and let WorkManager back off.
                    Log.w(TAG, "Authentication attempt failed")
                    recordRetryableFailure(prefs)
                    return@withContext Result.retry()
                }
                if (isStopped) return@withContext Result.retry()

                if (Mobinsapi.isTokenNeeded()) {
                    if (otpSecret == null) {
                        Log.d(TAG, "2FA required but no OTP secret stored — notifying user")
                        resetFailureWindow(prefs)
                        showReauthNotification()
                        return@withContext Result.success()
                    }
                    // TOTP replay guard: the foreground app shares this OTP
                    // secret, so if the current 30s step was already claimed
                    // (here or by grades_provider.dart), submitting now would
                    // replay the identical code and be rejected. Skip and let the
                    // next run (a new step) handle it. Keep in sync with the Dart
                    // and Swift implementations.
                    val currentStep = totpStep()
                    // Read the claimed step fresh rather than from the up-front
                    // snapshot, so the race window with a concurrent foreground
                    // claim stays as small as possible (avoids replaying the
                    // same one-time code in the same step).
                    val claimedStep = WorkerStore.read(appContext, listOf(KEY_LAST_TOTP_STEP))
                        .get(KEY_LAST_TOTP_STEP)?.toLongOrNull()
                    if (claimedStep == currentStep) {
                        Log.d(TAG, "TOTP step $currentStep already claimed, skipping this run")
                        return@withContext Result.success()
                    }
                    WorkerStore.write(
                        appContext,
                        mapOf(KEY_LAST_TOTP_STEP to currentStep.toString()),
                    )
                    try {
                        Mobinsapi.autoValidate(otpSecret)
                    } catch (e: Exception) {
                        if (isStopped) return@withContext Result.retry()
                        // Validation/network failures are indistinguishable at
                        // this API boundary. Do not claim the secret is invalid.
                        Log.w(TAG, "Auto-validate attempt failed")
                        recordRetryableFailure(prefs)
                        return@withContext Result.retry()
                    }
                    if (isStopped) return@withContext Result.retry()
                }
            }

            // Export the (possibly refreshed) session for next time
            try {
                val newSession = Mobinsapi.exportCAS()
                if (isStopped) return@withContext Result.retry()
                WorkerStore.write(appContext, mapOf(KEY_CAS_SESSION to newSession))
            } catch (e: Exception) {
                Log.w(TAG, "ExportCAS failed (non-fatal)")
            }

            // Snapshot read up front (see store read above), before overwriting.
            val previousJson = store[KEY_GRADES_JSON]
            val groupCount = Mobinsapi.loadGroups().toInt()
            if (isStopped) return@withContext Result.retry()
            if (groupCount <= 0) {
                Log.w(TAG, "No groups available")
                recordRetryableFailure(prefs)
                return@withContext Result.retry()
            }

            val newJson = if (groupCount == 1) {
                Mobinsapi.grades(0)
            } else {
                val first = JSONObject(Mobinsapi.grades(0))
                val mergedDetails = JSONArray()

                first.optJSONArray("details")?.let { mergeDetails(mergedDetails, it) }
                for (i in 1 until groupCount) {
                    val extra = JSONObject(Mobinsapi.grades(i.toLong()))
                    extra.optJSONArray("details")?.let { mergeDetails(mergedDetails, it) }
                }
                first.put("details", mergedDetails)
                first.toString()
            }
            GradeChangeDetector.validate(newJson)
            if (isStopped) return@withContext Result.retry()
            // Stamp the write so the foreground can tell this snapshot is newer
            // than its own copy and adopt it on resume (see _adoptWorkerGradesIfNewer).
            WorkerStore.write(
                appContext,
                mapOf(
                    KEY_GRADES_JSON to newJson,
                    KEY_GRADES_UPDATED_AT to System.currentTimeMillis().toString(),
                ),
            )
            resetFailureWindow(prefs)
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

            val (newGrades, updatedGrades) = GradeChangeDetector.detect(previousJson, newJson)

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
        } catch (e: org.json.JSONException) {
            if (isStopped) return@withContext Result.retry()
            Log.e(TAG, "Background fetch failed on malformed data", e)
            recordRetryableFailure(prefs)
            Result.retry()
        } catch (e: Exception) {
            if (isStopped) return@withContext Result.retry()
            // Likely transient (network, native blip): let WorkManager retry
            // with its backoff policy.
            Log.e(TAG, "Background fetch failed", e)
            recordRetryableFailure(prefs)
            Result.retry()
        } finally {
            // Guards the early no-op returns above, which never take the lock.
            if (NativeSession.lock.isHeldByCurrentThread) NativeSession.lock.unlock()
        }
    }

    /**
     * Merges [incoming] nodes into [target], deduplicating by name. When a node
     * with the same name already exists and both carry child `details` arrays,
     * their children are merged recursively instead of dropping the second
     * wrapper wholesale — otherwise distinct semesters sharing a wrapper name
     * (e.g. two "ANNEE 3" cards) would be lost. Mirrors
     * GradesService._mergeDetails in lib/services/grades_service.dart.
     */
    private fun mergeDetails(target: JSONArray, incoming: JSONArray) {
        for (j in 0 until incoming.length()) {
            val item = incoming.optJSONObject(j)
            if (item == null) {
                target.put(incoming.get(j))
                continue
            }
            val name = item.optString("name", "")
            if (name.isEmpty()) {
                target.put(item)
                continue
            }

            var existing: JSONObject? = null
            for (k in 0 until target.length()) {
                val candidate = target.optJSONObject(k)
                if (candidate != null && candidate.optString("name", "") == name) {
                    existing = candidate
                    break
                }
            }

            if (existing == null) {
                target.put(item)
                continue
            }

            val existingChildren = existing.optJSONArray("details")
            val itemChildren = item.optJSONArray("details")
            if (existingChildren != null && itemChildren != null) {
                mergeDetails(existingChildren, itemChildren)
            }
        }
    }

    private fun recordRetryableFailure(prefs: android.content.SharedPreferences) {
        try {
            val nowMs = System.currentTimeMillis()
            val previous = FailureWindow(
                startedAtMs = if (prefs.contains(PREF_FAILURE_STARTED_AT_MS)) {
                    prefs.getLong(PREF_FAILURE_STARTED_AT_MS, nowMs)
                } else {
                    null
                },
                lastAlertAtMs = if (prefs.contains(PREF_LAST_FAILURE_ALERT_MS)) {
                    prefs.getLong(PREF_LAST_FAILURE_ALERT_MS, 0L)
                } else {
                    null
                },
            )
            val decision = BackgroundFailurePolicy.recordFailure(nowMs, previous)
            prefs.edit()
                .putLong(PREF_FAILURE_STARTED_AT_MS, decision.window.startedAtMs!!)
                .remove(PREF_AUTH_FAIL_COUNT)
                .apply()
            if (decision.shouldAlert && showBackgroundFailureNotification()) {
                prefs.edit().putLong(PREF_LAST_FAILURE_ALERT_MS, nowMs).apply()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update background failure state")
        }
    }

    private fun resetFailureWindow(prefs: android.content.SharedPreferences) {
        prefs.edit()
            .remove(PREF_FAILURE_STARTED_AT_MS)
            .remove(PREF_AUTH_FAIL_COUNT)
            .remove(PREF_LAST_CREDS_NOTIF_MS)
            .apply()
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
        // Private visibility so subject names are hidden on a secure lock screen.
        buildAndPost(
            id = id,
            title = title,
            body = body,
            route = ROUTE_REFRESH,
            privateVisibility = true,
        )
    }

    // Current TOTP step: floor(epochSeconds / period). Two autoValidate calls in
    // the same step generate the same one-time code.
    private fun totpStep(): Long = System.currentTimeMillis() / 1000L / TOTP_STEP_SECONDS

    private fun showReauthNotification() {
        val prefs = appContext.getSharedPreferences(SHARED_PREFS_FILE, Context.MODE_PRIVATE)
        val lastMs = prefs.getLong(PREF_LAST_REAUTH_NOTIF_MS, 0L)
        if (System.currentTimeMillis() - lastMs < REAUTH_NOTIF_COOLDOWN_MS) {
            Log.d(TAG, "Reauth notification suppressed (cooldown active)")
            return
        }
        ensureNotificationChannel()
        val posted = buildAndPost(
            id = 3,
            title = "Reconnexion requise",
            body = "Une double authentification est nécessaire. Ouvrez l'application pour vous reconnecter.",
            route = ROUTE_REAUTH,
            channelId = RECONNECT_CHANNEL_ID,
        )
        if (posted) {
            prefs.edit().putLong(PREF_LAST_REAUTH_NOTIF_MS, System.currentTimeMillis()).apply()
        }
    }

    private fun showBackgroundFailureNotification(): Boolean {
        ensureNotificationChannel()
        return buildAndPost(
            id = 5,
            title = "Actualisation interrompue",
            body = "Les notes n'ont pas pu être actualisées depuis plusieurs heures. Ouvrez l'application pour réessayer.",
            route = ROUTE_REFRESH,
            channelId = SYNC_CHANNEL_ID,
        )
    }

    // [route], when set, is attached as an intent extra so MainActivity can
    // deep-link the tap to a specific Flutter screen (see EXTRA_NOTIF_ROUTE in
    // MainActivity.kt and the handler in lib/main.dart). Grade and sync-failure
    // notifications use the refresh route; 2FA prompts use the reauth route.
    private fun buildAndPost(
        id: Int,
        title: String,
        body: String,
        route: String? = null,
        channelId: String = CHANNEL_ID,
        privateVisibility: Boolean = false,
    ): Boolean {
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) {
            Log.d(TAG, "Notifications disabled; post skipped")
            return false
        }
        val launchIntent = appContext.packageManager
            .getLaunchIntentForPackage(appContext.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (route != null) putExtra(EXTRA_NOTIF_ROUTE, route)
            }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                appContext, id, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = NotificationCompat.Builder(appContext, channelId)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(
                if (privateVisibility) NotificationCompat.VISIBILITY_PRIVATE
                else NotificationCompat.VISIBILITY_PUBLIC,
            )
            .setAutoCancel(true)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()
        try {
            NotificationManagerCompat.from(appContext).notify(id, notification)
            return true
        } catch (_: SecurityException) {
            Log.w(TAG, "POST_NOTIFICATIONS permission not granted")
            return false
        } catch (e: Exception) {
            Log.w(TAG, "Notification could not be posted", e)
            return false
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Grade updates: hide their content on a secure lock screen since they
        // carry academic information.
        val gradesChannel = NotificationChannel(
            CHANNEL_ID,
            "Nouvelles notes",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Notifications lorsqu'une note est publiée"
            enableVibration(true)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        }

        // Reconnect/security prompts: separate channel so the user can tune them
        // independently from grade updates.
        val reconnectChannel = NotificationChannel(
            RECONNECT_CHANNEL_ID,
            "Reconnexion",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Invitations à se reconnecter (double authentification)"
            enableVibration(true)
        }

        val syncChannel = NotificationChannel(
            SYNC_CHANNEL_ID,
            "Actualisation des notes",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Alertes lorsque l'actualisation en arrière-plan reste interrompue"
        }

        nm.createNotificationChannel(gradesChannel)
        nm.createNotificationChannel(reconnectChannel)
        nm.createNotificationChannel(syncChannel)
    }

    companion object {
        /** Schedule (or reschedule) the periodic native background task. */
        fun schedule(context: Context, intervalMinutes: Long) {
            // WorkManager enforces a 15 minute floor for periodic work. Clamp
            // defensively so a bad value from the method channel cannot request
            // a shorter interval that WorkManager would silently reject, or a
            // wastefully long one.
            val safeInterval = intervalMinutes.coerceIn(15L, 60L)
            val request = buildRequest(safeInterval)
            val operation = WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    TASK_UNIQUE_NAME,
                    ExistingPeriodicWorkPolicy.UPDATE,
                    request,
                )
            Log.d(TAG, "Scheduled native background task: ${safeInterval}min")
            operation.result.get()
        }

        internal fun buildRequest(intervalMinutes: Long): PeriodicWorkRequest {
            val safeInterval = intervalMinutes.coerceIn(15L, 60L)
            return PeriodicWorkRequestBuilder<GradesBackgroundWorker>(
                safeInterval,
                TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(true)
                        .build(),
                )
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    15L,
                    TimeUnit.MINUTES,
                )
                .build()
        }

        /** Cancel the periodic native background task. */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(TASK_UNIQUE_NAME).result.get()
            Log.d(TAG, "Cancelled native background task")
        }
    }
}
