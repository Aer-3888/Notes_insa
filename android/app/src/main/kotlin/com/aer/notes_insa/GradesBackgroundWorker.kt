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
private const val SHARED_PREFS_FILE = "FlutterSharedPreferences"

// Storage keys — read from WorkerStore (see WorkerStore.kt).
private const val KEY_USERNAME = WorkerStore.KEY_USERNAME
private const val KEY_PASSWORD = WorkerStore.KEY_PASSWORD
private const val KEY_OTP_SECRET = WorkerStore.KEY_OTP_SECRET
private const val KEY_CAS_SESSION = WorkerStore.KEY_CAS_SESSION
private const val KEY_GRADES_JSON = WorkerStore.KEY_GRADES_JSON
private const val KEY_GRADES_UPDATED_AT = WorkerStore.KEY_GRADES_UPDATED_AT

// SharedPreferences key written by the Flutter shared_preferences plugin (flutter.* prefix)
private const val PREF_FETCH_ENABLED = "flutter.background_fetch_enabled"
private const val PREF_LAST_REAUTH_NOTIF_MS = "flutter.last_reauth_notif_ms"
private const val PREF_LAST_CREDS_NOTIF_MS = "flutter.last_creds_notif_ms"
private const val REAUTH_NOTIF_COOLDOWN_MS = 4 * 60 * 60 * 1000L // 4 hours

// A bad password and a transient blip both surface as an Auth() exception and
// are not reliably distinguishable, so consecutive failures are counted and the
// user is warned only once the streak crosses this threshold.
private const val PREF_AUTH_FAIL_COUNT = "flutter.consecutive_auth_failures"
private const val AUTH_FAIL_NOTIFY_THRESHOLD = 3

internal const val TASK_UNIQUE_NAME = "grades_fetch_native"

/**
 * Native WorkManager worker that fetches grades without going through a Flutter MethodChannel.
 *
 * The Flutter-side callbackDispatcher approach registers the custom channel in MainActivity only,
 * so MethodChannel calls fail in the headless isolate when the app process was killed.
 * This worker calls Mobinsapi directly, making background fetch reliable across process restarts.
 *
 * Reads credentials and the previous grades snapshot from [WorkerStore], a dedicated AndroidX
 * EncryptedSharedPreferences file the Flutter app mirrors on every credential change. The worker
 * cannot read flutter_secure_storage 10.x directly (custom cipher + prefixed keys).
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

            val securePrefs = WorkerStore.openOrNull(appContext) ?: return@withContext Result.success()

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
                try {
                    Mobinsapi.auth(username, password)
                } catch (e: Exception) {
                    // Count the failure and skip this run. A transient blip rarely
                    // repeats across runs (15+ min apart) while invalid credentials
                    // persist, so we warn the user only after a few in a row. The
                    // counter is reset on the next successful authentication.
                    val failCount = prefs.getInt(PREF_AUTH_FAIL_COUNT, 0) + 1
                    prefs.edit().putInt(PREF_AUTH_FAIL_COUNT, failCount).apply()
                    Log.w(TAG, "Auth failed (attempt $failCount), skipping this run")
                    if (failCount >= AUTH_FAIL_NOTIFY_THRESHOLD) {
                        showCredentialsNotification()
                    }
                    return@withContext Result.success()
                }

                if (Mobinsapi.isTokenNeeded()) {
                    if (otpSecret == null) {
                        Log.d(TAG, "2FA required but no OTP secret stored — notifying user")
                        showReauthNotification()
                        return@withContext Result.success()
                    }
                    try {
                        Mobinsapi.autoValidate(otpSecret)
                    } catch (e: Exception) {
                        // Stored OTP secret invalid/expired — prompt manual reconnect.
                        Log.w(TAG, "Auto-validate failed — prompting user to reconnect")
                        showReauthNotification()
                        return@withContext Result.success()
                    }
                }
            }

            // Authenticated now (restored session or fresh re-auth), so clear any
            // prior auth-failure streak that may have warned the user.
            if (prefs.getInt(PREF_AUTH_FAIL_COUNT, 0) != 0) {
                prefs.edit().putInt(PREF_AUTH_FAIL_COUNT, 0).apply()
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
            val groupCount = Mobinsapi.loadGroups().toInt()
            if (groupCount <= 0) {
                Log.w(TAG, "No groups available, skipping")
                return@withContext Result.success()
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
            // Stamp the write so the foreground can tell this snapshot is newer
            // than its own copy and adopt it on resume (see _adoptWorkerGradesIfNewer).
            securePrefs.edit()
                .putString(KEY_GRADES_JSON, newJson)
                .putString(KEY_GRADES_UPDATED_AT, System.currentTimeMillis().toString())
                .apply()
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

    // A subject's grades plus its display name (the map key is a composite path).
    private data class SubjectGrades(val displayName: String, val grades: List<String>)

    // Returns (newGrades, updatedGrades) subject display-name lists.
    private fun detectChanges(oldJson: String, newJson: String): Pair<List<String>, List<String>> {
        return try {
            val oldSubjects = extractSubjects(oldJson)
            val newSubjects = extractSubjects(newJson)
            val newGrades = mutableListOf<String>()
            val updatedGrades = mutableListOf<String>()
            for ((key, newEntry) in newSubjects) {
                if (newEntry.grades.isEmpty()) continue
                val oldEntry = oldSubjects[key]
                when {
                    oldEntry == null || oldEntry.grades.isEmpty() -> newGrades.add(newEntry.displayName)
                    oldEntry.grades != newEntry.grades -> updatedGrades.add(newEntry.displayName)
                }
            }
            Pair(newGrades, updatedGrades)
        } catch (e: Exception) {
            Log.w(TAG, "Change detection failed")
            Pair(emptyList(), emptyList())
        }
    }

    // Mirrors JsonCurriculumParser in lib/data.dart.
    // Returns: "semester|ue|subject" composite key → subject grades. The composite
    // key avoids collisions when the same subject name appears in different UEs/semesters.
    private fun extractSubjects(json: String): Map<String, SubjectGrades> {
        val result = mutableMapOf<String, SubjectGrades>()
        try {
            val root = JSONObject(json)
            val yearDetails = root.optJSONArray("details") ?: return result
            for (si in 0 until yearDetails.length()) {
                val semester = yearDetails.optJSONObject(si) ?: continue
                val semesterName = semester.optString("name", "")
                val ueContainer = semester.optJSONArray("details") ?: continue
                // Flatten any STPI wrapper levels (the FILIERE node and the
                // scientific sub-grouping) so the real UEs are compared, matching
                // JsonCurriculumParser in lib/data.dart and extractSubjects in
                // GradesBackgroundTask.swift. Keep all three in sync.
                val ues = mutableListOf<JSONObject>()
                collectUeNodes(ueContainer, ues)
                for (ue in ues) {
                    val ueName = ue.optString("name", "")
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
                        result["$semesterName|$ueName|$name"] = SubjectGrades(name, gradeList)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "JSON parsing failed")
        }
        return result
    }

    // Shape-detection helpers mirroring lib/data.dart, used to flatten the extra
    // STPI grouping levels before reading UEs. Kept identical to the Dart parser
    // and the Swift task so change detection agrees across platforms.

    // A leaf has no child details, i.e. it is an individual grade.
    private fun nodeIsLeaf(node: JSONObject): Boolean {
        val d = node.optJSONArray("details")
        return d == null || d.length() == 0
    }

    // A subject directly parents grades, so all of its children are leaves.
    private fun nodeHasGradeChildren(node: JSONObject): Boolean {
        val d = node.optJSONArray("details") ?: return false
        if (d.length() == 0) return false
        for (i in 0 until d.length()) {
            val c = d.optJSONObject(i) ?: return false
            if (!nodeIsLeaf(c)) return false
        }
        return true
    }

    // A UE directly parents at least one subject that has grades.
    private fun nodeIsUe(node: JSONObject): Boolean {
        val d = node.optJSONArray("details") ?: return false
        for (i in 0 until d.length()) {
            val c = d.optJSONObject(i) ?: continue
            if (nodeHasGradeChildren(c)) return true
        }
        return false
    }

    // A container groups UEs or further containers rather than subjects (the
    // STPI FILIERE wrapper or a scientific sub-grouping) and must be flattened.
    private fun nodeIsContainer(node: JSONObject): Boolean {
        val d = node.optJSONArray("details") ?: return false
        for (i in 0 until d.length()) {
            val c = d.optJSONObject(i) ?: continue
            if (nodeIsUe(c) || nodeIsContainer(c)) return true
        }
        return false
    }

    // Walks the groupings beneath a semester and collects the real UE nodes,
    // flattening any wrapper levels in between.
    private fun collectUeNodes(nodes: JSONArray, out: MutableList<JSONObject>) {
        for (i in 0 until nodes.length()) {
            val node = nodes.optJSONObject(i) ?: continue
            if (nodeIsContainer(node)) {
                val children = node.optJSONArray("details")
                if (children != null) collectUeNodes(children, out)
            } else {
                out.add(node)
            }
        }
    }

    // Handles both String scores (legacy format) and List scores (current mobinsapi format).
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
        val prefs = appContext.getSharedPreferences(SHARED_PREFS_FILE, Context.MODE_PRIVATE)
        val lastMs = prefs.getLong(PREF_LAST_REAUTH_NOTIF_MS, 0L)
        if (System.currentTimeMillis() - lastMs < REAUTH_NOTIF_COOLDOWN_MS) {
            Log.d(TAG, "Reauth notification suppressed (cooldown active)")
            return
        }
        prefs.edit().putLong(PREF_LAST_REAUTH_NOTIF_MS, System.currentTimeMillis()).apply()
        ensureNotificationChannel()
        buildAndPost(
            id = 3,
            title = "Reconnexion requise",
            body = "Une double authentification est nécessaire. Ouvrez l'application pour vous reconnecter.",
            route = ROUTE_REAUTH,
        )
    }

    // Posted after repeated background auth failures, which usually means the
    // INSA password changed. Has its own cooldown so it does not spam.
    private fun showCredentialsNotification() {
        val prefs = appContext.getSharedPreferences(SHARED_PREFS_FILE, Context.MODE_PRIVATE)
        val lastMs = prefs.getLong(PREF_LAST_CREDS_NOTIF_MS, 0L)
        if (System.currentTimeMillis() - lastMs < REAUTH_NOTIF_COOLDOWN_MS) {
            Log.d(TAG, "Credentials notification suppressed (cooldown active)")
            return
        }
        prefs.edit().putLong(PREF_LAST_CREDS_NOTIF_MS, System.currentTimeMillis()).apply()
        ensureNotificationChannel()
        buildAndPost(
            id = 4,
            title = "Reconnexion requise",
            body = "Vos identifiants semblent invalides. Ouvrez l'application pour vous reconnecter.",
            route = ROUTE_REAUTH,
        )
    }

    // [route], when set, is attached as an intent extra so MainActivity can
    // deep-link the tap to a specific Flutter screen (see EXTRA_NOTIF_ROUTE in
    // MainActivity.kt and the handler in lib/main.dart). Grades notifications
    // leave it null and just open the app.
    private fun buildAndPost(id: Int, title: String, body: String, route: String? = null) {
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
        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
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
                    ExistingPeriodicWorkPolicy.UPDATE,
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
