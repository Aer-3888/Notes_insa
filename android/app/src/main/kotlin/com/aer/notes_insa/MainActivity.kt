package com.aer.notes_insa

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import android.util.Log

private const val CHANNEL = "com.aer.notes_insa/fetch_grades"

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "FetchGrades") {
                val username = (call.arguments as? Map<*, *>)?.get("username") as? String ?: ""
                val password = (call.arguments as? Map<*, *>)?.get("password") as? String ?: ""
                val secret = (call.arguments as? Map<*, *>)?.get("secret") as? String ?: ""

                if (username.isBlank() || password.isBlank()) {
                    result.error("ERR_INVALID_ARGS", "username or password missing", null)
                    return@setMethodCallHandler
                }
                if (secret == "STUB") {
                    result.success("{\"Réseaux\":\"16/20\",\"Langage C\":\"17/20\"}")
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val mobileClass = Class.forName("mobile.Mobile")
                        val method = mobileClass.getMethod("fetchGrades", String::class.java, String::class.java, String::class.java)
                        val jsonResult = method.invoke(null, username, password, secret) as String
                        Handler(Looper.getMainLooper()).post {
                            result.success(jsonResult)
                        }
                    } catch (e: ClassNotFoundException) {
                        Log.e("MainActivity", "mobile.Mobile class not found", e)
                        Handler(Looper.getMainLooper()).post {
                            result.error("ERR_AAR_NOT_FOUND", "mobile.Mobile class not found. Ensure inscore.aar is included.", e.stackTraceToString())
                        }
                    } catch (e: NoSuchMethodException) {
                        Log.e("MainActivity", "fetchGrades method not found", e)
                        Handler(Looper.getMainLooper()).post {
                            result.error("ERR_METHOD_NOT_FOUND", "fetchGrades method not found in mobile.Mobile", e.stackTraceToString())
                        }
                    } catch (e: java.lang.reflect.InvocationTargetException) {
                        val cause = e.cause ?: e
                        Log.e("MainActivity", "fetchGrades threw exception: " + (cause.message ?: ""), cause)
                        Handler(Looper.getMainLooper()).post {
                            result.error("ERR_FETCH_FAILED", "Failed to fetch grades: " + (cause.message ?: ""), cause.stackTraceToString())
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Unexpected error", e)
                        Handler(Looper.getMainLooper()).post {
                            result.error("ERR_UNKNOWN", "Unexpected error: " + (e.message ?: ""), e.stackTraceToString())
                        }
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }
}
