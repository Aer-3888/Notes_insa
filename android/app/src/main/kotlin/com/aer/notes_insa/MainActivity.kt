package com.aer.notes_insa

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import android.util.Log
import mobinsapi.Mobinsapi

private const val CHANNEL = "com.aer.notes_insa/grades"
private const val TAG = "MainActivity"

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
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

                "ClearWorkerStore" -> {
                    runInBackground("ClearWorkerStore", result) {
                        WorkerStore.clearAll(applicationContext)
                        null
                    }
                }

                "InitBackgroundTask" -> {
                    val intervalMinutes = (call.argument<Int>("intervalMinutes") ?: 15).toLong()
                    GradesBackgroundWorker.schedule(applicationContext, intervalMinutes)
                    result.success(null)
                }

                "StopBackgroundTask" -> {
                    GradesBackgroundWorker.cancel(applicationContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Runs [block] on a background thread and posts the result (or error) back
     * on the main looper. [block] returns the value to pass to result.success(),
     * or throws an Exception which is forwarded as result.error().
     */
    private fun runInBackground(
        methodName: String,
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            try {
                val value = block()
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
        }.start()
    }
}
