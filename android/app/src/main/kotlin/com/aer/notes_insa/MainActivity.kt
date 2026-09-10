package com.aer.notes_insa

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.hardware.GeomagneticField
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import kotlin.concurrent.withLock
import mobinsapi.Mobinsapi

private const val CHANNEL = "com.aer.notes_insa/grades"
private const val MAP_CHANNEL = "com.aer.notes_insa/campus_map"
private const val TAG = "MainActivity"

// Deep-link plumbing for background notifications. GradesBackgroundWorker sets
// EXTRA_NOTIF_ROUTE on the tap intent of its reconnect notifications; we read it
// here and forward it to Flutter (see lib/main.dart). Keep the values in sync.
internal const val EXTRA_NOTIF_ROUTE = "notif_route"
internal const val ROUTE_REAUTH = "reauth"
internal const val ROUTE_REFRESH = "refresh"

class MainActivity : FlutterFragmentActivity() {

    // Set once the Flutter channel is wired, so warm-start intents (onNewIntent)
    // can push the tapped route straight to Flutter.
    private var channel: MethodChannel? = null

    // The map draws true-north geometry, so the Android compass (magnetic)
    // needs the local declination. iOS resolves true north itself.
    private var mapChannel: MethodChannel? = null

    // Holds a cold-start route (read in onCreate, before the engine is ready)
    // until Flutter pulls it via "ConsumeNotificationRoute".
    private var pendingRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Engine/channel not ready yet on a cold start, so stash for the pull.
        pendingRoute = intent?.getStringExtra(EXTRA_NOTIF_ROUTE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra(EXTRA_NOTIF_ROUTE) ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onNotificationRoute", route)
        } else {
            pendingRoute = route
        }
    }

    // Blank the recents/task-switcher thumbnail while backgrounded by enabling
    // FLAG_SECURE on pause and clearing it on resume. Toggling it (rather than
    // setting it once) keeps normal screenshots working while the app is open.
    override fun onPause() {
        super.onPause()
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun onResume() {
        super.onResume()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mapChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MAP_CHANNEL,
        )
        mapChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "MagneticDeclination" -> {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    if (latitude == null || longitude == null) {
                        result.error("ERR_INVALID_ARGS", "latitude or longitude missing", null)
                        return@setMethodCallHandler
                    }
                    val field = GeomagneticField(
                        latitude.toFloat(),
                        longitude.toFloat(),
                        0f,
                        System.currentTimeMillis(),
                    )
                    result.success(field.declination.toDouble())
                }

                else -> result.notImplemented()
            }
        }

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {

                "Auth" -> {
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    if (username.isBlank() || password.isBlank()) {
                        result.error("ERR_INVALID_ARGS", "username or password missing", null)
                        return@setMethodCallHandler
                    }
                    runInBackground("Auth", result) {
                        Mobinsapi.auth(username, password)
                        null
                    }
                }

                "IsTokenNeeded" -> {
                    runInBackground("IsTokenNeeded", result) {
                        Mobinsapi.isTokenNeeded()
                    }
                }

                "TriggerEmail" -> {
                    runInBackground("TriggerEmail", result) {
                        Mobinsapi.triggerEmail()
                        null
                    }
                }

                "Validate" -> {
                    val code = call.argument<String>("code") ?: ""
                    if (code.isBlank()) {
                        result.error("ERR_INVALID_ARGS", "code missing", null)
                        return@setMethodCallHandler
                    }
                    runInBackground("Validate", result) {
                        Mobinsapi.validate(code)
                        null
                    }
                }

                "AutoValidate" -> {
                    val secret = call.argument<String>("secret") ?: ""
                    if (secret.isBlank()) {
                        result.error("ERR_INVALID_ARGS", "secret missing", null)
                        return@setMethodCallHandler
                    }
                    runInBackground("AutoValidate", result) {
                        Mobinsapi.autoValidate(secret)
                        null
                    }
                }

                "IsAuthenticated" -> {
                    runInBackground("IsAuthenticated", result) {
                        Mobinsapi.isAuthenticated()
                    }
                }

                "LoadGroups" -> {
                    runInBackground("LoadGroups", result) {
                        Mobinsapi.loadGroups().toInt()
                    }
                }

                "Grades" -> {
                    val id = call.argument<Int>("id") ?: 0
                    runInBackground("Grades", result) {
                        Mobinsapi.grades(id.toLong())
                    }
                }

                "Coefficients" -> {
                    val id = call.argument<Int>("id") ?: 0
                    runInBackground("Coefficients", result) {
                        Mobinsapi.coefficients(id.toLong())
                    }
                }

                "NewCAS" -> {
                    runInBackground("NewCAS", result) {
                        Mobinsapi.newCAS()
                        null
                    }
                }

                "ExportCAS" -> {
                    runInBackground("ExportCAS", result) {
                        Mobinsapi.exportCAS()
                    }
                }

                "ImportCAS" -> {
                    val token = call.argument<String>("token") ?: ""
                    if (token.isBlank()) {
                        result.error("ERR_INVALID_ARGS", "token missing", null)
                        return@setMethodCallHandler
                    }
                    runInBackground("ImportCAS", result) {
                        Mobinsapi.importCAS(token)
                        null
                    }
                }

                "SyncWorkerStore" -> {
                    val values = call.argument<Map<String, String?>>("values")
                    if (values == null) {
                        result.error("ERR_INVALID_ARGS", "values missing", null)
                        return@setMethodCallHandler
                    }
                    runInBackground("SyncWorkerStore", result) {
                        WorkerStore.write(applicationContext, values)
                        null
                    }
                }

                "ReadWorkerStore" -> {
                    val keys = call.argument<List<String>>("keys") ?: emptyList()
                    runInBackground("ReadWorkerStore", result) {
                        WorkerStore.read(applicationContext, keys)
                    }
                }

                "ClearWorkerStore" -> {
                    runInBackground("ClearWorkerStore", result) {
                        WorkerStore.clearAll(applicationContext)
                        null
                    }
                }

                "InitBackgroundTask" -> {
                    val intervalMinutes = (call.argument<Int>("intervalMinutes") ?: 15).toLong()
                    runUtilityInBackground("InitBackgroundTask", result) {
                        GradesBackgroundWorker.schedule(applicationContext, intervalMinutes)
                        null
                    }
                }

                "StopBackgroundTask" -> {
                    runUtilityInBackground("StopBackgroundTask", result) {
                        GradesBackgroundWorker.cancel(applicationContext)
                        null
                    }
                }

                // Cold-start deep link: Flutter pulls the route captured in
                // onCreate once, then it is cleared.
                "ConsumeNotificationRoute" -> {
                    result.success(pendingRoute)
                    pendingRoute = null
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Runs [block] on the shared single-thread native executor and posts the
     * result (or error) back on the main looper. [block] returns the value to
     * pass to result.success(), or throws an Exception forwarded as
     * result.error(). Serializing here (and holding [NativeSession.lock] for the
     * call) ensures a call that outlived its Dart timeout, or a concurrent
     * background worker run, can't overlap and corrupt the shared CAS session.
     */
    private fun runInBackground(
        methodName: String,
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        NativeSession.executor.execute {
            try {
                val value = NativeSession.lock.withLock { block() }
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                if (BuildConfig.DEBUG) {
                    Log.e(TAG, "$methodName failed: ${e.message}", e)
                }
                mainHandler.post {
                    result.error(
                        "ERR_${methodName.uppercase()}",
                        "An error occurred during $methodName execution",
                        null,
                    )
                }
            }
        }
    }

    /** Runs scheduler operations off the UI thread without taking the CAS lock. */
    private fun runUtilityInBackground(
        methodName: String,
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        NativeSession.utilityExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                if (BuildConfig.DEBUG) Log.e(TAG, "$methodName failed", e)
                mainHandler.post {
                    result.error(
                        "ERR_${methodName.uppercase()}",
                        "An error occurred during $methodName execution",
                        null,
                    )
                }
            }
        }
    }
}
