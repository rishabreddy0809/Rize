import XCTest
@testable import Rize

/// Pure/deterministic logic on the SwiftData model types — computed properties
/// and parsing helpers that don't need a `ModelContainer` at all (contrast with
/// `PersistenceIntegrationTests`, which exercises actual insert/save/fetch).
final class ModelLogicTests: XCTestCase {

    // MARK: - UserProfile.currentLevel / progressPercentage

    func testCurrentLevelTracksXPTier() {
        let profile = UserProfile(name: "Alex", goal: "fitness")
        profile.currentXP = 0
        XCTAssertEqual(profile.currentLevel, "ASH")

        profile.currentXP = 500
        XCTAssertEqual(profile.currentLevel, "AWAKENING")

        profile.currentXP = 7000
        XCTAssertEqual(profile.currentLevel, "ETERNAL")
    }

    func testProgressPercentageIsClampedBetweenZeroAndOne() {
        let profile = UserProfile(name: "Alex", goal: "fitness")

        profile.currentXP = 0
        XCTAssertEqual(profile.progressPercentage, 0.0, accuracy: 0.0001)

        profile.currentXP = 499 // just below the Awakening threshold — nearly full bar
        XCTAssertEqual(profile.progressPercentage, Double(499) / Double(500), accuracy: 0.0001)

        // Eternal has no next tier — progress should read as complete (1.0),
        // not divide by a made-up ceiling and overshoot.
        profile.currentXP = 50_000
        XCTAssertEqual(profile.progressPercentage, 1.0, accuracy: 0.0001)
    }

    // MARK: - UserProfile.unlockAchievement

    func testUnlockAchievementIsIdempotent() {
        let profile = UserProfile(name: "Alex", goal: "fitness")

        XCTAssertTrue(profile.unlockAchievement("first_blood"), "first unlock should report success")
        XCTAssertFalse(profile.unlockAchievement("first_blood"), "re-unlocking the same id should be a no-op")
        XCTAssertEqual(profile.unlockedAchievements, ["first_blood"])
    }

    func testUnlockAchievementAccumulatesDistinctIds() {
        let profile = UserProfile(name: "Alex", goal: "fitness")
        _ = profile.unlockAchievement("first_blood")
        _ = profile.unlockAchievement("perfect_week")

        XCTAssertEqual(Set(profile.unlockedAchievements), Set(["first_blood", "perfect_week"]))
    }

    // MARK: - UserProfile.hasSportsGoal

    func testHasSportsGoalTrueForFitnessOrBothGoal() {
        XCTAssertTrue(UserProfile(name: "A", goal: "fitness").hasSportsGoal)
        XCTAssertTrue(UserProfile(name: "A", goal: "both").hasSportsGoal)
    }

    func testHasSportsGoalDetectsSportsKeywordUnderProductivityGoal() {
        let profile = UserProfile(name: "A", goal: "productivity", goalDetail: "Running, Deep Focus")
        XCTAssertTrue(profile.hasSportsGoal, "goalDetail mentioning 'Running' should count even though the top-level goal is productivity")
    }

    func testHasSportsGoalFalseForPureProductivityGoal() {
        let profile = UserProfile(name: "A", goal: "productivity", goalDetail: "Coding, Studying")
        XCTAssertFalse(profile.hasSportsGoal)
    }

    // MARK: - RizeTask.minutes(from:)

    func testMinutesParsesPlainMinuteString() {
        XCTAssertEqual(RizeTask.minutes(from: "30 min"), 30)
    }

    func testMinutesParsesHourString() {
        XCTAssertEqual(RizeTask.minutes(from: "1 hr"), 60)
        XCTAssertEqual(RizeTask.minutes(from: "1.5 hr"), 90)
    }

    func testMinutesFallsBackTo30ForUnparseableString() {
        XCTAssertEqual(RizeTask.minutes(from: ""), 30)
        XCTAssertEqual(RizeTask.minutes(from: "a while"), 30)
    }

    // MARK: - RizeTask.asPlanningTask

    func testAsPlanningTaskMapsFieldsAndDefaultsPriority() {
        let task = RizeTask(title: "Run 5k", duration: "45 min", taskDescription: "", type: "workout")
        let planningTask = task.asPlanningTask()

        XCTAssertEqual(planningTask.title, "Run 5k")
        XCTAssertEqual(planningTask.estimatedMinutes, 45)
        XCTAssertEqual(planningTask.priority, .medium, "no priority given at init should default to medium")
        XCTAssertFalse(planningTask.isCompleted)
    }

    func testAsPlanningTaskReflectsCompletionAndCustomPriority() {
        let task = RizeTask(title: "Ship feature", duration: "2 hr", taskDescription: "", type: "work", priority: .high)
        task.completed = true
        let planningTask = task.asPlanningTask()

        XCTAssertTrue(planningTask.isCompleted)
        XCTAssertEqual(planningTask.priority, .high)
        XCTAssertEqual(planningTask.estimatedMinutes, 120)
    }

    // MARK: - RizeTask.priority (legacy nil rows)

    func testPriorityFallsBackToMediumForLegacyNilRawValue() {
        let task = RizeTask(title: "Old row", duration: "10 min", taskDescription: "", type: "work")
        task.priorityRaw = nil // simulates a row persisted before `priority` existed
        XCTAssertEqual(task.priority, .medium)
    }

    func testPrioritySetterRoundTripsThroughRawValue() {
        let task = RizeTask(title: "T", duration: "10 min", taskDescription: "", type: "work")
        task.priority = .low
        XCTAssertEqual(task.priorityRaw, TaskPriority.low.rawValue)
        XCTAssertEqual(task.priority, .low)
    }

    // MARK: - RizeTask.recurrenceDays

    func testRecurrenceDaysDefaultsToEmptyForOneTimeTask() {
        let task = RizeTask(title: "T", duration: "10 min", taskDescription: "", type: "work")
        XCTAssertEqual(task.recurrenceDays, [])
        XCTAssertNil(task.recurrenceDaysRaw)
    }

    func testRecurrenceDaysRoundTripsThroughInit() {
        let task = RizeTask(
            title: "Gym",
            duration: "30 min",
            taskDescription: "",
            type: "physical",
            recurrenceDays: [2, 4, 6]
        )
        XCTAssertEqual(task.recurrenceDays, [2, 4, 6])
        XCTAssertEqual(task.recurrenceDaysRaw, "2,4,6", "should serialize sorted, comma-separated")
    }

    func testRecurrenceDaysSetterClearsRawValueWhenEmptied() {
        let task = RizeTask(title: "Gym", duration: "30 min", taskDescription: "", type: "physical", recurrenceDays: [1])
        task.recurrenceDays = []
        XCTAssertNil(task.recurrenceDaysRaw, "clearing repeat days should fall back to nil, not an empty string")
        XCTAssertEqual(task.recurrenceDays, [])
    }

    func testRecurrenceDaysGetterToleratesMalformedRawValue() {
        let task = RizeTask(title: "T", duration: "10 min", taskDescription: "", type: "work")
        task.recurrenceDaysRaw = "3,,x,5" // simulates a corrupted/partial row
        XCTAssertEqual(task.recurrenceDays, [3, 5], "non-numeric or empty components should be dropped, not crash")
    }
}
