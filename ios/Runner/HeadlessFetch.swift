import Flutter
import Foundation

/// Runs the Dart grade fetch in a headless Flutter engine.
///
/// Mirrors HeadlessFetch.kt: the credentials travel in the request rather than
/// being read on the Dart side, so the isolate needs no plugins registered.
enum HeadlessFetch {
    private static let channelName = "com.aer.notes_insa/background_fetch"
    private static let entrypoint = "backgroundFetchMain"
    private static let timeout: TimeInterval = 4 * 60

    struct Request {
        let username: String
        let password: String
        let otpSecret: String?
        let casSession: String?
        let claimedTotpStep: Int64?
    }

    struct Outcome {
        let status: String
        let gradesJson: String?
        let casSession: String?
    }

    /// Blocks the calling background thread until the fetch finishes or times
    /// out. Must not be called from the main thread.
    static func run(
        request: Request,
        onTotpStepClaimed: @escaping (Int64) -> Void
    ) -> Outcome {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome = Outcome(status: "retry", gradesJson: nil, casSession: nil)
        var engine: FlutterEngine?

        DispatchQueue.main.async {
            let created = FlutterEngine(
                name: "background-fetch",
                project: nil,
                allowHeadlessExecution: true
            )
            engine = created

            guard created.run(withEntrypoint: entrypoint) else {
                NSLog("[HeadlessFetch] Could not start the headless engine")
                semaphore.signal()
                return
            }

            let channel = FlutterMethodChannel(
                name: channelName,
                binaryMessenger: created.binaryMessenger
            )

            channel.setMethodCallHandler { call, result in
                switch call.method {
                case "takeRequest":
                    result([
                        "username": request.username,
                        "password": request.password,
                        "otpSecret": request.otpSecret as Any,
                        "casSession": request.casSession as Any,
                        "claimedTotpStep": request.claimedTotpStep as Any,
                    ])

                case "claimTotpStep":
                    if let args = call.arguments as? [String: Any],
                       let step = args["step"] as? NSNumber {
                        onTotpStepClaimed(step.int64Value)
                    }
                    result(nil)

                case "complete":
                    let args = call.arguments as? [String: Any] ?? [:]
                    outcome = Outcome(
                        status: args["status"] as? String ?? "retry",
                        gradesJson: args["gradesJson"] as? String,
                        casSession: args["casSession"] as? String
                    )
                    result(nil)
                    semaphore.signal()

                case "failed":
                    NSLog("[HeadlessFetch] Dart fetch failed")
                    result(nil)
                    semaphore.signal()

                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            NSLog("[HeadlessFetch] Dart fetch timed out")
        }

        DispatchQueue.main.async { engine?.destroyContext() }
        return outcome
    }
}
