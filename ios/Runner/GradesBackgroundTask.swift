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
/// The task runs in the app's own process and runs the fetch in a headless
/// Dart isolate (see HeadlessFetch.swift), so it shares the app's network path (no
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
    private static let prefLastCredsNotifMs = "flutter.last_creds_notif_ms"
    private static let reauthNotifCooldownMs: Double = 4 * 60 * 60 * 1000 // 4 hours
    private static let prefFailureStartedAtMs = "flutter.background_failure_started_at_ms"
    private static let prefLastFailureAlertMs = "flutter.last_background_failure_alert_ms"
    private static let failureAlertAfterMs: Double = 4 * 60 * 60 * 1000
    private static let failureAlertCooldownMs: Double = 24 * 60 * 60 * 1000

    // Legacy preference retained only so a successful/disabled run cleans up
    // state written by older app versions.
    private static let prefAuthFailCount = "flutter.consecutive_auth_failures"

    // Keep the default in sync with lib/background_tasks.dart.
    private static let defaultIntervalMinutes = 15

    // TOTP codes change once per step (RFC 6238 default period). Used to
    // coordinate autoValidate with the foreground so they don't submit the same
    // one-time code in the same step. If the real period differs the worst case
    // is an unnecessary skip (harmless retry), never a new failure.
    private static let totpStepSeconds = 30.0

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
    static func schedule(intervalMinutes: Int) throws {
        let safeInterval = min(60, max(15, intervalMinutes))
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(safeInterval) * 60)
        try BGScheduler.submit(request)
    }

    /// Cancel any pending fetch (called from StopBackgroundTask).
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
    }

    // MARK: - Handler

    private static func handle(task: BGProcessingTask) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: prefFetchEnabled) != nil,
           defaults.bool(forKey: prefFetchEnabled) == false {
            resetFailureWindow(defaults: defaults)
            task.setTaskCompleted(success: true)
            return
        }

        // Reschedule before work starts so a crash cannot permanently stop the
        // periodic chain. Disabled tasks exit above and do not resurrect it.
        let interval = (UserDefaults.standard.object(forKey: "flutter.background_fetch_interval") as? Int)
            ?? defaultIntervalMinutes
        do {
            try schedule(intervalMinutes: interval)
        } catch {
            NSLog("[GradesBackgroundTask] Failed to schedule next run: \(error)")
        }

        let queue = DispatchQueue(label: "com.aer.notes_insa.grades.work")
        // Shared flag so doWork() can stop between steps once the
        // system asks for the task back, rather than running to completion.
        let token = CancellationToken()
        let completion = TaskCompletionGate(task: task)
        let workItem = DispatchWorkItem {
            let success = doWork(isCancelled: { token.isCancelled })
            completion.complete(success: success)
        }
        task.expirationHandler = {
            // Complete immediately; the native call may return later, but the
            // gate prevents a second completion and cancellation checks prevent
            // subsequent persistence or notifications.
            token.cancel()
            workItem.cancel()
            completion.complete(success: false)
        }
        queue.async(execute: workItem)
    }

    // MARK: - Core fetch (mirrors GradesBackgroundWorker.doWork)

    /// Returns true on a clean run (including intentional skips), false on a
    /// failure that warrants a retry.
    @discardableResult
    static func doWork(isCancelled: () -> Bool = { false }) -> Bool {
        let defaults = UserDefaults.standard
        // Default true when never set (matches Android PREF_FETCH_ENABLED default).
        if defaults.object(forKey: prefFetchEnabled) != nil,
           defaults.bool(forKey: prefFetchEnabled) == false {
            NSLog("[GradesBackgroundTask] Background fetch disabled, skipping")
            resetFailureWindow(defaults: defaults)
            return true
        }

        // Acquire the same session lock used by foreground calls and worker-store
        // cleanup before reading credentials. A logout therefore serializes with
        // this entire run and cannot be followed by a stale background write.
        NativeSession.lock.lock()
        defer { NativeSession.lock.unlock() }

        do {
            guard let username = try WorkerStore.get(WorkerStore.keyUsername),
                  let password = try WorkerStore.get(WorkerStore.keyPassword) else {
                NSLog("[GradesBackgroundTask] No credentials stored, skipping")
                resetFailureWindow(defaults: defaults)
                return true
            }

            let otpSecret = try WorkerStore.get(WorkerStore.keyOtpSecret)
            let casSession = try WorkerStore.get(WorkerStore.keyCasSession)

            let previousJson = try WorkerStore.get(WorkerStore.keyGradesJson)

            let claimedStep = try WorkerStore.get(WorkerStore.keyLastTotpStep)
                .flatMap { Int64($0) }

            let outcome = HeadlessFetch.run(
                request: HeadlessFetch.Request(
                    username: username,
                    password: password,
                    otpSecret: otpSecret,
                    casSession: casSession,
                    claimedTotpStep: claimedStep
                ),
                onTotpStepClaimed: { step in
                    try? WorkerStore.write(
                        values: [WorkerStore.keyLastTotpStep: String(step)]
                    )
                }
            )
            if isCancelled() { return false }

            switch outcome.status {
            case "needsReauth":
                NSLog("[GradesBackgroundTask] 2FA required, notifying user")
                resetFailureWindow(defaults: defaults)
                showReauthNotification()
                return true

            case "totpStepClaimed":
                NSLog("[GradesBackgroundTask] TOTP step already claimed, skipping")
                return true

            case "ok":
                break

            default:
                NSLog("[GradesBackgroundTask] Fetch did not complete")
                recordRetryableFailure(defaults: defaults)
                return false
            }

            guard let newJson = outcome.gradesJson else {
                recordRetryableFailure(defaults: defaults)
                return false
            }

            if let session = outcome.casSession {
                try WorkerStore.write(values: [WorkerStore.keyCasSession: session])
            }

            _ = try parseObject(newJson)

            // Bail before persisting/notifying if the system reclaimed our time
            // during the grade fetches above.
            if isCancelled() { return false }

            // Stamp the write so the foreground can tell this snapshot is newer
            // than its own copy and adopt it on resume.
            let stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            try WorkerStore.write(values: [WorkerStore.keyGradesJson: newJson])
            if isCancelled() { return false }
            try WorkerStore.write(values: [WorkerStore.keyGradesUpdatedAt: stamp])
            resetFailureWindow(defaults: defaults)

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
            if isCancelled() { return false }
            NSLog("[GradesBackgroundTask] Background fetch failed: \(error)")
            recordRetryableFailure(defaults: defaults)
            return false
        }
    }

    // MARK: - JSON helpers

    private static func parseObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw NSError(
                domain: "NotesInsaGradesBackgroundTask",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Grades response is not a JSON object"]
            )
        }
        return object
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
        let assessments: [String: [String]]
    }

    /// Returns assessment-level additions and corrections/removals by subject.
    static func detectChanges(_ oldJson: String, _ newJson: String) -> ([String], [String]) {
        let oldSubjects = extractSubjects(oldJson)
        let newSubjects = extractSubjects(newJson)
        var newGrades = Set<String>()
        var updatedGrades = Set<String>()
        for (key, newEntry) in newSubjects {
            let oldEntry = oldSubjects[key]
            if newEntry.assessments.isEmpty {
                if let oldEntry = oldEntry, !oldEntry.assessments.isEmpty {
                    updatedGrades.insert(newEntry.displayName)
                }
                continue
            }
            guard let oldEntry = oldEntry, !oldEntry.assessments.isEmpty else {
                newGrades.insert(newEntry.displayName)
                continue
            }

            var hasAddition = false
            var hasUpdate = false
            let names = Set(oldEntry.assessments.keys).union(newEntry.assessments.keys)
            for name in names {
                let oldScores = oldEntry.assessments[name]
                let newScores = newEntry.assessments[name]
                if oldScores == nil, let newScores = newScores, !newScores.isEmpty {
                    hasAddition = true
                } else if newScores == nil {
                    hasUpdate = true
                } else if let oldScores = oldScores, let newScores = newScores,
                          oldScores != newScores {
                    if isStrictSuperset(oldScores, newScores) {
                        hasAddition = true
                    } else {
                        hasUpdate = true
                    }
                }
            }
            if hasAddition {
                newGrades.insert(newEntry.displayName)
            } else if hasUpdate {
                updatedGrades.insert(newEntry.displayName)
            }
        }
        return (newGrades.sorted(), updatedGrades.sorted())
    }

    private static func isStrictSuperset(_ oldScores: [String], _ newScores: [String]) -> Bool {
        if newScores.count <= oldScores.count { return false }
        var remaining = newScores
        for score in oldScores {
            guard let index = remaining.firstIndex(of: score) else { return false }
            remaining.remove(at: index)
        }
        return true
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
            let semesterName = normalized(semester["name"] as? String ?? "")
            guard let ueContainer = semester["details"] as? [Any] else { continue }
            // Flatten any STPI wrapper levels (the FILIERE node and the scientific
            // sub-grouping) so the real UEs are compared, matching
            // JsonCurriculumParser in lib/data.dart and extractSubjects in
            // GradesBackgroundWorker.kt. Keep all three in sync.
            for ue in collectUeNodes(ueContainer) {
                let ueName = normalized(ue["name"] as? String ?? "")
                guard let subjects = ue["details"] as? [Any] else { continue }
                for case let subject as [String: Any] in subjects {
                    let name = normalized(subject["name"] as? String ?? "")
                    if name.isEmpty { continue }
                    var assessments: [String: [String]] = [:]
                    if let gradeDetails = subject["details"] as? [Any] {
                        for (index, item) in gradeDetails.enumerated() {
                            guard let grade = item as? [String: Any],
                                  let rawScore = extractScore(grade["score"]) else { continue }
                            let score = normalized(rawScore)
                            if score.localizedCaseInsensitiveContains("aucun") { continue }
                            let gradeName = normalized(grade["name"] as? String ?? "")
                            let key = gradeName.isEmpty ? "assessment_\(index)" : gradeName
                            assessments[key, default: []].append(score)
                        }
                    }
                    if assessments.isEmpty {
                        if let rawScore = extractScore(subject["score"]) {
                            let score = normalized(rawScore)
                            if !score.localizedCaseInsensitiveContains("aucun") {
                                assessments["__subject_score__"] = [score]
                            }
                        }
                    }
                    for key in assessments.keys {
                        assessments[key]?.sort()
                    }
                    result["\(semesterName)|\(ueName)|\(name)"] =
                        SubjectGrades(displayName: name, assessments: assessments)
                }
            }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // Shape-detection helpers mirroring lib/data.dart, used to flatten the extra
    // STPI grouping levels before reading UEs. Kept identical to the Dart parser
    // and the Kotlin worker so change detection agrees across platforms.

    private static func nodeIsLeaf(_ node: [String: Any]) -> Bool {
        guard let d = node["details"] as? [Any] else { return true }
        return d.isEmpty
    }

    private static func nodeHasGradeChildren(_ node: [String: Any]) -> Bool {
        guard let d = node["details"] as? [Any], !d.isEmpty else { return false }
        for child in d {
            guard let c = child as? [String: Any] else { return false }
            if !nodeIsLeaf(c) { return false }
        }
        return true
    }

    private static func nodeIsUe(_ node: [String: Any]) -> Bool {
        guard let d = node["details"] as? [Any] else { return false }
        for child in d {
            if let c = child as? [String: Any], nodeHasGradeChildren(c) { return true }
        }
        return false
    }

    private static func nodeIsContainer(_ node: [String: Any]) -> Bool {
        guard let d = node["details"] as? [Any] else { return false }
        for child in d {
            if let c = child as? [String: Any], nodeIsUe(c) || nodeIsContainer(c) { return true }
        }
        return false
    }

    private static func collectUeNodes(_ nodes: [Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for node in nodes {
            guard let n = node as? [String: Any] else { continue }
            if nodeIsContainer(n) {
                if let children = n["details"] as? [Any] {
                    out.append(contentsOf: collectUeNodes(children))
                }
            } else {
                out.append(n)
            }
        }
        return out
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

    private static func recordRetryableFailure(defaults: UserDefaults) {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let startedAt = (defaults.object(forKey: prefFailureStartedAtMs) as? NSNumber)?.doubleValue
            ?? nowMs
        let lastAlertAt = (defaults.object(forKey: prefLastFailureAlertMs) as? NSNumber)?.doubleValue
        defaults.set(startedAt, forKey: prefFailureStartedAtMs)
        defaults.removeObject(forKey: prefAuthFailCount)

        if shouldAlertForFailure(
            nowMs: nowMs,
            startedAtMs: startedAt,
            lastAlertAtMs: lastAlertAt
        ) {
            showBackgroundFailureNotification { posted in
                if posted {
                    defaults.set(nowMs, forKey: prefLastFailureAlertMs)
                }
            }
        }
    }

    static func shouldAlertForFailure(
        nowMs: Double,
        startedAtMs: Double,
        lastAlertAtMs: Double?
    ) -> Bool {
        let oldEnough = nowMs - startedAtMs >= failureAlertAfterMs
        let cooldownElapsed = lastAlertAtMs == nil ||
            nowMs - lastAlertAtMs! >= failureAlertCooldownMs
        return oldEnough && cooldownElapsed
    }

    private static func resetFailureWindow(defaults: UserDefaults) {
        defaults.removeObject(forKey: prefFailureStartedAtMs)
        defaults.removeObject(forKey: prefAuthFailCount)
        defaults.removeObject(forKey: prefLastCredsNotifMs)
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
        post(id: id, title: title, body: body, payload: payload, route: "refresh")
    }

    // Current TOTP step: floor(epochSeconds / period). Two autoValidate calls in
    // the same step generate the same one-time code.
    private static func totpStep() -> Int64 {
        return Int64(Date().timeIntervalSince1970 / totpStepSeconds)
    }

    private static func showReauthNotification() {
        let defaults = UserDefaults.standard
        let lastMs = defaults.double(forKey: prefLastReauthNotifMs)
        let nowMs = Date().timeIntervalSince1970 * 1000
        if nowMs - lastMs < reauthNotifCooldownMs {
            return // cooldown active
        }
        post(
            id: "reauth_required",
            title: "Reconnexion requise",
            body: "Une double authentification est nécessaire. Ouvrez l'application pour vous reconnecter.",
            payload: "reauth_required",
            route: "reauth"
        ) { posted in
            if posted {
                defaults.set(nowMs, forKey: prefLastReauthNotifMs)
            }
        }
    }

    private static func showBackgroundFailureNotification(
        completion: @escaping (Bool) -> Void
    ) {
        post(
            id: "background_refresh_failed",
            title: "Actualisation interrompue",
            body: "Les notes n'ont pas pu être actualisées depuis plusieurs heures. Ouvrez l'application pour réessayer.",
            payload: "background_refresh_failed",
            route: "refresh",
            completion: completion
        )
    }

    private static func post(
        id: String,
        title: String,
        body: String,
        payload: String,
        route: String? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Keep the payload for diagnostics and attach an app-owned native route
        // consumed by AppDelegate/GradesBridge on notification taps.
        var userInfo: [String: Any] = ["payload": payload]
        if let route = route {
            userInfo[GradesBridge.notificationRouteKey] = route
        }
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            var allowed = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional
            if #available(iOS 14.0, *), settings.authorizationStatus == .ephemeral {
                allowed = true
            }
            guard allowed else {
                completion?(false)
                return
            }
            center.add(request) { error in
                if let error = error {
                    NSLog("[GradesBackgroundTask] Notification post failed: \(error)")
                }
                completion?(error == nil)
            }
        }
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

/// Ensures normal completion and expiration can race without completing a
/// BGTask twice.
@available(iOS 13.0, *)
private final class TaskCompletionGate {
    private let lock = NSLock()
    private let task: BGTask
    private var completed = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

/// Thread-safe one-way cancellation flag. The task's expiration handler and the
/// work item run on different threads, so the flag is guarded by a lock.
private final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
