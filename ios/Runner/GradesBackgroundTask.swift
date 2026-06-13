import Foundation
import BackgroundTasks
import UserNotifications

/// iOS counterpart of `GradesBackgroundWorker.kt`.
///
/// Android uses a WorkManager `PeriodicWorkRequest` (15-min, network + battery
/// constraints). iOS has no exact equivalent: `BGTaskScheduler` runs tasks
/// *opportunistically*, when the system predicts a good moment (often hours
/// apart, never guaranteed). The configured interval is therefore an
/// `earliestBeginDate` hint, not a schedule. Timely grade-change notifications
/// are consequently far less reliable on iOS than on Android — a server push
/// (worker → APNs) would be the only way to reach Android parity.
///
/// The task runs in the app's own process, calls `Mobinsapi` directly (no
/// Flutter engine), and reads credentials / the previous snapshot from the
/// Keychain-backed `WorkerStore`.
@available(iOS 13.0, *)
enum GradesBackgroundTask {
    /// Must match the entry in `BGTaskSchedulerPermittedIdentifiers` (Info.plist).
    static let processingIdentifier = "com.aer.notes_insa.grades.processing"

    // UserDefaults keys written by the Flutter shared_preferences plugin, which
    // prefixes everything with "flutter." (mirrors the Android PREF_* keys).
    private static let prefFetchEnabled = "flutter.background_fetch_enabled"
    private static let prefLastReauthNotifMs = "flutter.last_reauth_notif_ms"
    private static let reauthNotifCooldownMs: Double = 4 * 60 * 60 * 1000 // 4 hours

    // Keep the default in sync with lib/background_tasks.dart.
    private static let defaultIntervalMinutes = 15

    // MARK: - Registration & scheduling

    /// Register the task handler. Call once from `application(_:didFinishLaunching…)`
    /// before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            handle(task: task as! BGProcessingTask)
        }
    }

    /// Schedule (or reschedule) the periodic fetch. `intervalMinutes` is used as
    /// the earliest-begin hint.
    static func schedule(intervalMinutes: Int) {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(intervalMinutes) * 60)
        do {
            try BGScheduler.submit(request)
        } catch {
            NSLog("[GradesBackgroundTask] Failed to schedule: \(error)")
        }
    }

    /// Cancel any pending fetch (called from StopBackgroundTask).
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
    }

    // MARK: - Handler

    private static func handle(task: BGProcessingTask) {
        // Always reschedule the next run first, so a crash mid-work doesn't
        // permanently stop background fetch.
        let interval = (UserDefaults.standard.object(forKey: "flutter.background_fetch_interval") as? Int)
            ?? defaultIntervalMinutes
        schedule(intervalMinutes: interval)

        let queue = DispatchQueue(label: "com.aer.notes_insa.grades.work")
        let workItem = DispatchWorkItem {
            let success = doWork()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            // System is reclaiming time; abandon this run. It will retry later.
            workItem.cancel()
        }
        queue.async(execute: workItem)
    }

    // MARK: - Core fetch (mirrors GradesBackgroundWorker.doWork)

    /// Returns true on a clean run (including intentional skips), false on a
    /// failure that warrants a retry.
    @discardableResult
    static func doWork() -> Bool {
        let defaults = UserDefaults.standard
        // Default true when never set (matches Android PREF_FETCH_ENABLED default).
        if defaults.object(forKey: prefFetchEnabled) != nil,
           defaults.bool(forKey: prefFetchEnabled) == false {
            NSLog("[GradesBackgroundTask] Background fetch disabled, skipping")
            return true
        }

        guard let username = WorkerStore.get(WorkerStore.keyUsername),
              let password = WorkerStore.get(WorkerStore.keyPassword) else {
            NSLog("[GradesBackgroundTask] No credentials stored, skipping")
            return true
        }

        let otpSecret = WorkerStore.get(WorkerStore.keyOtpSecret)
        let casSession = WorkerStore.get(WorkerStore.keyCasSession)

        do {
            // Try to restore the previous CAS session to skip a full re-auth.
            if let casSession = casSession {
                do {
                    try MobinsApiClient.importCAS(token: casSession)
                } catch {
                    WorkerStore.write(values: [WorkerStore.keyCasSession: nil])
                    try MobinsApiClient.newCAS()
                }
            } else {
                try MobinsApiClient.newCAS()
            }

            // Re-auth only if the restored session is no longer valid.
            if try !MobinsApiClient.isAuthenticated() {
                do {
                    try MobinsApiClient.auth(username: username, password: password)
                } catch {
                    // Wrong credentials or a transient blip — skip silently
                    // rather than retry-storming the CAS endpoint.
                    NSLog("[GradesBackgroundTask] Auth failed — skipping this run")
                    return true
                }

                if MobinsApiClient.isTokenNeeded() {
                    guard let otpSecret = otpSecret else {
                        showReauthNotification()
                        return true
                    }
                    do {
                        try MobinsApiClient.autoValidate(secret: otpSecret)
                    } catch {
                        showReauthNotification()
                        return true
                    }
                }
            }

            // Export the (possibly refreshed) session for next time.
            if let newSession = try? MobinsApiClient.exportCAS() {
                WorkerStore.write(values: [WorkerStore.keyCasSession: newSession])
            }

            // Read the previous snapshot before overwriting it.
            let previousJson = WorkerStore.get(WorkerStore.keyGradesJson)

            let groupCount = try MobinsApiClient.loadGroups()
            if groupCount <= 0 {
                NSLog("[GradesBackgroundTask] No groups available, skipping")
                return true
            }

            let newJson: String
            if groupCount == 1 {
                newJson = try MobinsApiClient.grades(id: 0)
            } else {
                var first = try parseObject(MobinsApiClient.grades(id: 0))
                var mergedDetails: [Any] = []
                if let d = first["details"] as? [Any] { mergeDetails(&mergedDetails, d) }
                for i in 1..<groupCount {
                    let extra = try parseObject(MobinsApiClient.grades(id: i))
                    if let d = extra["details"] as? [Any] { mergeDetails(&mergedDetails, d) }
                }
                first["details"] = mergedDetails
                newJson = try serialize(first)
            }

            // Stamp the write so the foreground can tell this snapshot is newer
            // than its own copy and adopt it on resume.
            let stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            WorkerStore.write(values: [
                WorkerStore.keyGradesJson: newJson,
                WorkerStore.keyGradesUpdatedAt: stamp,
            ])

            if previousJson == nil {
                return true // First fetch — store only, no notification.
            }
            if previousJson == newJson {
                return true // No changes.
            }

            let (newGrades, updatedGrades) = detectChanges(previousJson!, newJson)
            if newGrades.isEmpty && updatedGrades.isEmpty {
                return true
            }

            if !newGrades.isEmpty {
                showGradesNotification(
                    id: "grades_new",
                    payload: "new_grades",
                    title: "Nouvelles notes disponibles",
                    subjects: newGrades,
                    singlePrefix: "Nouvelle note",
                    multiPrefix: "Nouvelles notes"
                )
            }
            if !updatedGrades.isEmpty {
                showGradesNotification(
                    id: "grades_updated",
                    payload: "updated_grades",
                    title: "Notes mises à jour",
                    subjects: updatedGrades,
                    singlePrefix: "Note mise à jour",
                    multiPrefix: "Notes mises à jour"
                )
            }
            return true
        } catch {
            NSLog("[GradesBackgroundTask] Background fetch failed: \(error)")
            return false // Triggers a system retry.
        }
    }

    // MARK: - JSON helpers

    private static func parseObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func serialize(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Mirrors GradesService._mergeDetails / GradesBackgroundWorker.mergeDetails:
    /// merge `incoming` into `target`, deduplicating by name and recursing into
    /// matching containers so distinct semesters sharing a wrapper name survive.
    private static func mergeDetails(_ target: inout [Any], _ incoming: [Any]) {
        for item in incoming {
            guard let dict = item as? [String: Any] else {
                target.append(item)
                continue
            }
            guard let name = dict["name"] as? String, !name.isEmpty else {
                target.append(dict)
                continue
            }
            if let idx = target.firstIndex(where: {
                ($0 as? [String: Any])?["name"] as? String == name
            }) {
                if var existing = target[idx] as? [String: Any],
                   var existingChildren = existing["details"] as? [Any],
                   let itemChildren = dict["details"] as? [Any] {
                    mergeDetails(&existingChildren, itemChildren)
                    existing["details"] = existingChildren
                    target[idx] = existing
                }
                // else: true duplicate leaf — skip.
            } else {
                target.append(dict)
            }
        }
    }

    // MARK: - Change detection (mirrors GradesBackgroundWorker)

    private struct SubjectGrades {
        let displayName: String
        let grades: [String]
    }

    /// Returns (newGrades, updatedGrades) subject display-name lists.
    private static func detectChanges(_ oldJson: String, _ newJson: String) -> ([String], [String]) {
        let oldSubjects = extractSubjects(oldJson)
        let newSubjects = extractSubjects(newJson)
        var newGrades: [String] = []
        var updatedGrades: [String] = []
        for (key, newEntry) in newSubjects {
            if newEntry.grades.isEmpty { continue }
            let oldEntry = oldSubjects[key]
            if oldEntry == nil || oldEntry!.grades.isEmpty {
                newGrades.append(newEntry.displayName)
            } else if oldEntry!.grades != newEntry.grades {
                updatedGrades.append(newEntry.displayName)
            }
        }
        return (newGrades, updatedGrades)
    }

    /// "semester|ue|subject" composite key → subject grades. Mirrors
    /// JsonCurriculumParser / GradesBackgroundWorker.extractSubjects.
    private static func extractSubjects(_ json: String) -> [String: SubjectGrades] {
        var result: [String: SubjectGrades] = [:]
        guard let root = try? parseObject(json),
              let yearDetails = root["details"] as? [Any] else {
            return result
        }
        for case let semester as [String: Any] in yearDetails {
            let semesterName = semester["name"] as? String ?? ""
            guard let ues = semester["details"] as? [Any] else { continue }
            for case let ue as [String: Any] in ues {
                let ueName = ue["name"] as? String ?? ""
                guard let subjects = ue["details"] as? [Any] else { continue }
                for case let subject as [String: Any] in subjects {
                    let name = subject["name"] as? String ?? ""
                    if name.isEmpty { continue }
                    var gradeList: [String] = []
                    if let gradeDetails = subject["details"] as? [Any] {
                        for case let grade as [String: Any] in gradeDetails {
                            guard let score = extractScore(grade["score"]) else { continue }
                            if !score.contains("Aucun") {
                                let gradeName = grade["name"] as? String ?? ""
                                gradeList.append("\(gradeName):\(score)")
                            }
                        }
                    }
                    if gradeList.isEmpty {
                        if let score = extractScore(subject["score"]), !score.contains("Aucun") {
                            gradeList.append("\(name):\(score)")
                        }
                    }
                    result["\(semesterName)|\(ueName)|\(name)"] =
                        SubjectGrades(displayName: name, grades: gradeList)
                }
            }
        }
        return result
    }

    /// Handles both String scores (legacy) and array scores (current mobinsapi).
    private static func extractScore(_ field: Any?) -> String? {
        if let s = field as? String {
            return s.isEmpty ? nil : s
        }
        if let arr = field as? [Any], let first = arr.first as? String {
            return first
        }
        return nil
    }

    // MARK: - Notifications

    private static func showGradesNotification(
        id: String,
        payload: String,
        title: String,
        subjects: [String],
        singlePrefix: String,
        multiPrefix: String
    ) {
        let body: String
        if subjects.count == 1 {
            body = "\(singlePrefix) : \(subjects[0])"
        } else if subjects.count <= 3 {
            body = "\(multiPrefix) : \(subjects.joined(separator: ", "))"
        } else {
            let head = subjects.prefix(3).joined(separator: ", ")
            body = "\(multiPrefix) : \(head) et \(subjects.count - 3) autre(s)"
        }
        post(id: id, title: title, body: body, payload: payload)
    }

    private static func showReauthNotification() {
        let defaults = UserDefaults.standard
        let lastMs = defaults.double(forKey: prefLastReauthNotifMs)
        let nowMs = Date().timeIntervalSince1970 * 1000
        if nowMs - lastMs < reauthNotifCooldownMs {
            return // cooldown active
        }
        defaults.set(nowMs, forKey: prefLastReauthNotifMs)
        post(
            id: "reauth_required",
            title: "Reconnexion requise",
            body: "Une double authentification est nécessaire. Ouvrez l'application pour vous reconnecter.",
            payload: "reauth_required"
        )
    }

    private static func post(id: String, title: String, body: String, payload: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Mirror the flutter_local_notifications payload so a tap can be routed
        // by NotificationService.tapStream once the app is foregrounded.
        content.userInfo = ["payload": payload]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Small indirection so `schedule` reads cleanly; `BGTaskScheduler.submit`
/// throws, and isolating it keeps the call site tidy.
@available(iOS 13.0, *)
private enum BGScheduler {
    static func submit(_ request: BGTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }
}
