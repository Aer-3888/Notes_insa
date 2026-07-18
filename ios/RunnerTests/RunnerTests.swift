import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testFailureAlertThresholdAndCooldown() {
    let hour = 60.0 * 60.0 * 1000.0
    XCTAssertFalse(GradesBackgroundTask.shouldAlertForFailure(
      nowMs: 4 * hour - 1,
      startedAtMs: 0,
      lastAlertAtMs: nil
    ))
    XCTAssertTrue(GradesBackgroundTask.shouldAlertForFailure(
      nowMs: 4 * hour,
      startedAtMs: 0,
      lastAlertAtMs: nil
    ))
    XCTAssertFalse(GradesBackgroundTask.shouldAlertForFailure(
      nowMs: 28 * hour - 1,
      startedAtMs: 0,
      lastAlertAtMs: 4 * hour
    ))
    XCTAssertTrue(GradesBackgroundTask.shouldAlertForFailure(
      nowMs: 28 * hour,
      startedAtMs: 0,
      lastAlertAtMs: 4 * hour
    ))
  }

  func testNewAssessmentIsNewGrade() {
    let changes = GradesBackgroundTask.detectChanges(
      gradesJson(["DS1": "10/20"]),
      gradesJson(["DS1": "10/20", "DS2": "15/20"])
    )
    XCTAssertEqual(changes.0, ["Mathématiques"])
    XCTAssertTrue(changes.1.isEmpty)
  }

  func testCorrectionAndWithdrawalAreUpdates() {
    let corrected = GradesBackgroundTask.detectChanges(
      gradesJson(["DS1": "10/20"]),
      gradesJson(["DS1": "12/20"])
    )
    XCTAssertEqual(corrected.1, ["Mathématiques"])

    let withdrawn = GradesBackgroundTask.detectChanges(
      gradesJson(["DS1": "10/20", "DS2": "15/20"]),
      gradesJson(["DS1": "10/20"])
    )
    XCTAssertEqual(withdrawn.1, ["Mathématiques"])
  }

  func testAdditionWinsOverCorrection() {
    let changes = GradesBackgroundTask.detectChanges(
      gradesJson(["DS1": "10/20"]),
      gradesJson(["DS1": "12/20", "DS2": "15/20"])
    )
    XCTAssertEqual(changes.0, ["Mathématiques"])
    XCTAssertTrue(changes.1.isEmpty)
  }

  private func gradesJson(_ assessments: [String: String]) -> String {
    let grades = assessments.keys.sorted().map { name in
      "{\"name\":\"\(name)\",\"score\":[\"\(assessments[name]!)\"],\"details\":null}"
    }.joined(separator: ",")
    return """
    {
      "details": [{
        "name": "Semestre 5",
        "details": [{
          "name": "UE Math",
          "details": [{
            "name": "Mathématiques",
            "details": [\(grades)]
          }]
        }]
      }]
    }
    """
  }
}
