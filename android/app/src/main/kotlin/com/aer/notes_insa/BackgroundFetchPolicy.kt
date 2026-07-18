package com.aer.notes_insa

import org.json.JSONArray
import org.json.JSONObject

internal const val PREF_FAILURE_STARTED_AT_MS = "flutter.background_failure_started_at_ms"
internal const val PREF_LAST_FAILURE_ALERT_MS = "flutter.last_background_failure_alert_ms"
internal const val FAILURE_ALERT_AFTER_MS = 4 * 60 * 60 * 1000L
internal const val FAILURE_ALERT_COOLDOWN_MS = 24 * 60 * 60 * 1000L

internal data class FailureWindow(
    val startedAtMs: Long? = null,
    val lastAlertAtMs: Long? = null,
)

internal data class FailureDecision(
    val window: FailureWindow,
    val shouldAlert: Boolean,
)

internal object BackgroundFailurePolicy {
    fun recordFailure(nowMs: Long, previous: FailureWindow): FailureDecision {
        val startedAt = previous.startedAtMs ?: nowMs
        val oldEnough = nowMs - startedAt >= FAILURE_ALERT_AFTER_MS
        val cooldownElapsed = previous.lastAlertAtMs == null ||
            nowMs - previous.lastAlertAtMs >= FAILURE_ALERT_COOLDOWN_MS
        return FailureDecision(
            window = previous.copy(startedAtMs = startedAt),
            shouldAlert = oldEnough && cooldownElapsed,
        )
    }
}

internal data class GradeChanges(
    val newSubjects: List<String>,
    val updatedSubjects: List<String>,
)

/** Pure assessment-level change detection shared by the worker and unit tests. */
internal object GradeChangeDetector {
    private data class SubjectSnapshot(
        val displayName: String,
        val assessments: Map<String, List<String>>,
    )

    fun validate(json: String) {
        JSONObject(json)
    }

    fun detect(oldJson: String, newJson: String): GradeChanges {
        val oldSubjects = extractSubjects(oldJson)
        val newSubjects = extractSubjects(newJson)
        val newGrades = linkedSetOf<String>()
        val updatedGrades = linkedSetOf<String>()

        for ((key, current) in newSubjects) {
            val previous = oldSubjects[key]
            if (current.assessments.isEmpty()) {
                if (previous != null && previous.assessments.isNotEmpty()) {
                    updatedGrades.add(current.displayName)
                }
                continue
            }
            if (previous == null || previous.assessments.isEmpty()) {
                newGrades.add(current.displayName)
                continue
            }

            var hasAddition = false
            var hasUpdate = false
            val assessmentNames = previous.assessments.keys + current.assessments.keys
            for (name in assessmentNames) {
                val oldScores = previous.assessments[name]
                val newScores = current.assessments[name]
                when {
                    oldScores == null -> {
                        if (!newScores.isNullOrEmpty()) hasAddition = true
                    }
                    newScores == null -> hasUpdate = true
                    oldScores != newScores -> {
                        if (isStrictSuperset(requireNotNull(oldScores), requireNotNull(newScores))) {
                            hasAddition = true
                        } else {
                            hasUpdate = true
                        }
                    }
                }
            }
            // A subject is listed once. A newly published assessment is the most
            // useful headline if additions and corrections arrive together.
            when {
                hasAddition -> newGrades.add(current.displayName)
                hasUpdate -> updatedGrades.add(current.displayName)
            }
        }

        return GradeChanges(newGrades.sorted(), updatedGrades.sorted())
    }

    private fun isStrictSuperset(oldScores: List<String>, newScores: List<String>): Boolean {
        if (newScores.size <= oldScores.size) return false
        val remaining = newScores.toMutableList()
        for (score in oldScores) {
            if (!remaining.remove(score)) return false
        }
        return true
    }

    private fun extractSubjects(json: String): Map<String, SubjectSnapshot> {
        val root = JSONObject(json)
        val result = linkedMapOf<String, SubjectSnapshot>()
        val semesters = root.optJSONArray("details") ?: return result
        for (semesterIndex in 0 until semesters.length()) {
            val semester = semesters.optJSONObject(semesterIndex) ?: continue
            val semesterName = normalized(semester.optString("name", ""))
            val containers = semester.optJSONArray("details") ?: continue
            for (ue in collectUeNodes(containers)) {
                val ueName = normalized(ue.optString("name", ""))
                val subjects = ue.optJSONArray("details") ?: continue
                for (subjectIndex in 0 until subjects.length()) {
                    val subject = subjects.optJSONObject(subjectIndex) ?: continue
                    val subjectName = normalized(subject.optString("name", ""))
                    if (subjectName.isEmpty()) continue

                    val assessments = linkedMapOf<String, MutableList<String>>()
                    val gradeDetails = subject.optJSONArray("details")
                    if (gradeDetails != null) {
                        for (gradeIndex in 0 until gradeDetails.length()) {
                            val grade = gradeDetails.optJSONObject(gradeIndex) ?: continue
                            val score = extractScore(grade.opt("score")) ?: continue
                            if (isMissingResult(score)) continue
                            val gradeName = normalized(grade.optString("name", ""))
                                .ifEmpty { "assessment_$gradeIndex" }
                            assessments.getOrPut(gradeName) { mutableListOf() }.add(score)
                        }
                    }
                    if (assessments.isEmpty()) {
                        val score = extractScore(subject.opt("score"))
                        if (score != null && !isMissingResult(score)) {
                            assessments.getOrPut("__subject_score__") { mutableListOf() }.add(score)
                        }
                    }
                    val frozen = assessments.mapValues { (_, scores) -> scores.sorted() }
                    result["$semesterName|$ueName|$subjectName"] =
                        SubjectSnapshot(subjectName, frozen)
                }
            }
        }
        return result
    }

    private fun normalized(value: String): String = value.trim().replace(Regex("\\s+"), " ")

    private fun isMissingResult(score: String): Boolean =
        score.contains("aucun", ignoreCase = true)

    private fun extractScore(field: Any?): String? = when (field) {
        is String -> normalized(field).takeIf { it.isNotEmpty() }
        is JSONArray -> if (field.length() > 0 && field.opt(0) is String) {
            normalized(field.optString(0)).takeIf { it.isNotEmpty() }
        } else {
            null
        }
        else -> null
    }

    private fun nodeIsLeaf(node: JSONObject): Boolean {
        val details = node.optJSONArray("details")
        return details == null || details.length() == 0
    }

    private fun nodeHasGradeChildren(node: JSONObject): Boolean {
        val details = node.optJSONArray("details") ?: return false
        if (details.length() == 0) return false
        for (index in 0 until details.length()) {
            val child = details.optJSONObject(index) ?: return false
            if (!nodeIsLeaf(child)) return false
        }
        return true
    }

    private fun nodeIsUe(node: JSONObject): Boolean {
        val details = node.optJSONArray("details") ?: return false
        for (index in 0 until details.length()) {
            val child = details.optJSONObject(index) ?: continue
            if (nodeHasGradeChildren(child)) return true
        }
        return false
    }

    private fun nodeIsContainer(node: JSONObject): Boolean {
        val details = node.optJSONArray("details") ?: return false
        for (index in 0 until details.length()) {
            val child = details.optJSONObject(index) ?: continue
            if (nodeIsUe(child) || nodeIsContainer(child)) return true
        }
        return false
    }

    private fun collectUeNodes(nodes: JSONArray): List<JSONObject> {
        val result = mutableListOf<JSONObject>()
        for (index in 0 until nodes.length()) {
            val node = nodes.optJSONObject(index) ?: continue
            if (nodeIsContainer(node)) {
                node.optJSONArray("details")?.let { result.addAll(collectUeNodes(it)) }
            } else {
                result.add(node)
            }
        }
        return result
    }
}
