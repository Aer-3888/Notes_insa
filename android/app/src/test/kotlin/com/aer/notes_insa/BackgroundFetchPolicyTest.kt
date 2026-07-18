package com.aer.notes_insa

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import androidx.work.BackoffPolicy
import androidx.work.NetworkType

class BackgroundFetchPolicyTest {
    @Test
    fun `work request requires connectivity and uses conservative backoff`() {
        val request = GradesBackgroundWorker.buildRequest(1)
        val spec = request.workSpec
        assertEquals(15 * 60 * 1000L, spec.intervalDuration)
        assertEquals(NetworkType.CONNECTED, spec.constraints.requiredNetworkType)
        assertTrue(spec.constraints.requiresBatteryNotLow())
        assertEquals(BackoffPolicy.EXPONENTIAL, spec.backoffPolicy)
        assertEquals(15 * 60 * 1000L, spec.backoffDelayDuration)
    }

    @Test
    fun `generic alert waits four hours and then observes daily cooldown`() {
        val start = 1_000L
        val first = BackgroundFailurePolicy.recordFailure(start, FailureWindow())
        assertFalse(first.shouldAlert)

        val beforeThreshold = BackgroundFailurePolicy.recordFailure(
            start + FAILURE_ALERT_AFTER_MS - 1,
            first.window,
        )
        assertFalse(beforeThreshold.shouldAlert)

        val threshold = BackgroundFailurePolicy.recordFailure(
            start + FAILURE_ALERT_AFTER_MS,
            beforeThreshold.window,
        )
        assertTrue(threshold.shouldAlert)

        val alertedAt = start + FAILURE_ALERT_AFTER_MS
        val coolingDown = BackgroundFailurePolicy.recordFailure(
            alertedAt + FAILURE_ALERT_COOLDOWN_MS - 1,
            threshold.window.copy(lastAlertAtMs = alertedAt),
        )
        assertFalse(coolingDown.shouldAlert)

        val nextDay = BackgroundFailurePolicy.recordFailure(
            alertedAt + FAILURE_ALERT_COOLDOWN_MS,
            coolingDown.window,
        )
        assertTrue(nextDay.shouldAlert)
    }

    @Test
    fun `new assessment in an existing subject is a new grade`() {
        val changes = GradeChangeDetector.detect(
            gradesJson("DS1" to "10/20"),
            gradesJson("DS1" to "10/20", "DS2" to "15/20"),
        )
        assertEquals(listOf("Mathématiques"), changes.newSubjects)
        assertTrue(changes.updatedSubjects.isEmpty())
    }

    @Test
    fun `correction and withdrawal are updates`() {
        val corrected = GradeChangeDetector.detect(
            gradesJson("DS1" to "10/20"),
            gradesJson("DS1" to "12/20"),
        )
        assertEquals(listOf("Mathématiques"), corrected.updatedSubjects)

        val withdrawn = GradeChangeDetector.detect(
            gradesJson("DS1" to "10/20", "DS2" to "15/20"),
            gradesJson("DS1" to "10/20"),
        )
        assertEquals(listOf("Mathématiques"), withdrawn.updatedSubjects)
    }

    @Test
    fun `addition wins when a subject also contains a correction`() {
        val changes = GradeChangeDetector.detect(
            gradesJson("DS1" to "10/20"),
            gradesJson("DS1" to "12/20", "DS2" to "15/20"),
        )
        assertEquals(listOf("Mathématiques"), changes.newSubjects)
        assertTrue(changes.updatedSubjects.isEmpty())
    }

    @Test
    fun `missing result is treated as a withdrawn assessment`() {
        val changes = GradeChangeDetector.detect(
            gradesJson("DS1" to "10/20"),
            gradesJson("DS1" to "Aucun resultat"),
        )
        assertEquals(listOf("Mathématiques"), changes.updatedSubjects)
    }

    private fun gradesJson(vararg assessments: Pair<String, String>): String {
        val grades = assessments.joinToString(",") { (name, score) ->
            """{"name":"$name","score":["$score"],"details":null}"""
        }
        return """
            {
              "details": [{
                "name": "Semestre 5",
                "details": [{
                  "name": "UE Math",
                  "details": [{
                    "name": "Mathématiques",
                    "details": [$grades]
                  }]
                }]
              }]
            }
        """.trimIndent()
    }
}
