package com.aer.notes_insa

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

private const val TAG = "HeadlessFetch"
private const val CHANNEL = "com.aer.notes_insa/background_fetch"
private const val ENTRYPOINT = "backgroundFetchMain"
private const val TIMEOUT_MS = 4 * 60 * 1000L

data class FetchRequest(
    val username: String,
    val password: String,
    val otpSecret: String?,
    val casSession: String?,
    val claimedTotpStep: Long?,
)

data class FetchOutcome(
    val status: String,
    val gradesJson: String? = null,
    val casSession: String? = null,
)

/**
 * Runs the Dart grade fetch in a headless Flutter isolate.
 *
 * The credentials travel in the request rather than being read on the Dart
 * side, so the isolate needs no plugins registered.
 */
object HeadlessFetch {
    suspend fun run(
        context: Context,
        request: FetchRequest,
        onTotpStepClaimed: (Long) -> Unit,
    ): FetchOutcome {
        val outcome = CompletableDeferred<FetchOutcome>()
        val main = Handler(Looper.getMainLooper())
        var engine: FlutterEngine? = null

        main.post {
            try {
                val created = FlutterEngine(context.applicationContext)
                engine = created

                MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL)
                    .setMethodCallHandler { call, result ->
                        when (call.method) {
                            "takeRequest" -> result.success(
                                mapOf(
                                    "username" to request.username,
                                    "password" to request.password,
                                    "otpSecret" to request.otpSecret,
                                    "casSession" to request.casSession,
                                    "claimedTotpStep" to request.claimedTotpStep,
                                ),
                            )

                            "claimTotpStep" -> {
                                val step = (call.argument<Number>("step"))?.toLong()
                                if (step != null) onTotpStepClaimed(step)
                                result.success(null)
                            }

                            "complete" -> {
                                outcome.complete(
                                    FetchOutcome(
                                        status = call.argument<String>("status") ?: "retry",
                                        gradesJson = call.argument("gradesJson"),
                                        casSession = call.argument("casSession"),
                                    ),
                                )
                                result.success(null)
                            }

                            "failed" -> {
                                Log.w(TAG, "Dart fetch failed: ${call.argument<String>("reason")}")
                                outcome.complete(FetchOutcome("retry"))
                                result.success(null)
                            }

                            else -> result.notImplemented()
                        }
                    }

                val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(bundle, ENTRYPOINT),
                )
            } catch (e: Exception) {
                Log.e(TAG, "Could not start the headless engine", e)
                outcome.complete(FetchOutcome("retry"))
            }
        }

        val result = withTimeoutOrNull(TIMEOUT_MS) { outcome.await() }
            ?: FetchOutcome("retry").also { Log.w(TAG, "Dart fetch timed out") }

        main.post { engine?.destroy() }
        return result
    }
}
