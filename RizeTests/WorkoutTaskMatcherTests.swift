import XCTest
@testable import Rize

/// `WorkoutTaskMatcher` decides whether a real HealthKit workout should
/// auto-complete a planned "workout" task — getting this wrong either leaves
/// a finished workout unchecked (annoying) or completes the wrong task
/// (worse: silently wrong data). These tests are deliberately adversarial
/// about the "wrong task" side.
final class WorkoutTaskMatcherTests: XCTestCase {

    private let now = Date()

    private func workoutTask(_ title: String, duration: String, type: String = "workout", completed: Bool = false) -> RizeTask {
        let task = RizeTask(title: title, duration: duration, taskDescription: "", type: type)
        task.completed = completed
        return task
    }

    // MARK: - Distance matching

    func testMatchesWithinDistanceTolerance() {
        let task = workoutTask("Easy 5 mile run", duration: "5 mi")
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 5.1 * 1609.344, movingTime: 2700)
        XCTAssertTrue(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testDoesNotMatchOutsideDistanceTolerance() {
        let task = workoutTask("Easy 5 mile run", duration: "5 mi")
        // 2 miles short is well past the 15%-or-0.25mi tolerance band.
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 3 * 1609.344, movingTime: 1500)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testKilometerDistanceIsConvertedBeforeComparing() {
        let task = workoutTask("8k run", duration: "8 km")
        // 8km ≈ 4.97mi — a workout logged at 5.0mi should still be within tolerance.
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 5.0 * 1609.344, movingTime: 2400)
        XCTAssertTrue(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    // MARK: - Duration matching (no distance stated)

    func testMatchesWithinDurationToleranceWhenNoDistanceStated() {
        let task = workoutTask("Strength training", duration: "40 min")
        let workout = WorkoutSummary(type: "Strength", startDate: now, movingTime: 42 * 60)
        XCTAssertTrue(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testDoesNotMatchOutsideDurationTolerance() {
        let task = workoutTask("Strength training", duration: "40 min")
        let workout = WorkoutSummary(type: "Strength", startDate: now, movingTime: 10 * 60)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    // MARK: - Activity-type gating (the "wrong task" guard)

    func testDoesNotMatchWhenActivityTypeDisagreesWithTaskText() {
        // A bike ride should never complete a task that's explicitly about running.
        let task = workoutTask("Easy 5 mile run", duration: "5 mi")
        let workout = WorkoutSummary(type: "Ride", startDate: now, distanceMeters: 5 * 1609.344, movingTime: 1500)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testUnrecognizedWorkoutTypeSkipsTheTypeGateAndFallsThroughToDistance() {
        // "Elliptical" IS in the keyword table, so this is really testing that
        // an activity type outside the table (e.g. from a niche HK type) doesn't
        // crash — it should just fall through to the distance/duration check.
        let task = workoutTask("5 mile trek", duration: "5 mi")
        let workout = WorkoutSummary(type: "SomeUnlistedActivity", startDate: now, distanceMeters: 5 * 1609.344, movingTime: 2700)
        XCTAssertTrue(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    // MARK: - Guard clauses

    func testNeverMatchesANonWorkoutTask() {
        let task = workoutTask("Read for 30 min", duration: "30 min", type: "work")
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 5 * 1609.344, movingTime: 2700)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testNeverMatchesAnAlreadyCompletedTask() {
        let task = workoutTask("Easy 5 mile run", duration: "5 mi", completed: true)
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 5 * 1609.344, movingTime: 2700)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }

    func testNoMatchWhenTaskHasNoParsableDistanceOrDuration() {
        let task = workoutTask("Go outside", duration: "")
        let workout = WorkoutSummary(type: "Run", startDate: now, distanceMeters: 5 * 1609.344, movingTime: 2700)
        XCTAssertFalse(WorkoutTaskMatcher.matches(workout: workout, task: task))
    }
}
