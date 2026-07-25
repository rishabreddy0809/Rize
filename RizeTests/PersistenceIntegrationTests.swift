import XCTest
import SwiftData
@testable import Rize

/// Exercises the SwiftData model layer (`UserProfile` / `DailyEntry` / `RizeTask`)
/// and the services that mutate it (`XPManager`) against a real, in-memory
/// `ModelContainer` — the same relationship wiring the app uses, minus CloudKit.
/// This is what actually caught the `tasks`/`entries` optional-relationship bug:
/// a plain unit test of `PlanningEngine` never touches persistence at all.
@MainActor
final class PersistenceIntegrationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([UserProfile.self, DailyEntry.self, RizeTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Relationship wiring

    func testProfileEntryTaskRoundTrip() throws {
        let profile = UserProfile(name: "Alex", goal: "fitness", goalDetail: "")
        context.insert(profile)

        let entry = DailyEntry(date: Date())
        entry.profile = profile
        context.insert(entry)

        let task = RizeTask(title: "Run 5k", duration: "30 min", taskDescription: "", type: "physical")
        task.entry = entry
        context.insert(task)

        try context.save()

        XCTAssertEqual(profile.entries.count, 1, "UserProfile.entries should see the DailyEntry via inverse relationship")
        XCTAssertEqual(entry.tasks.count, 1, "DailyEntry.tasks should see the RizeTask via inverse relationship")
        XCTAssertEqual(entry.tasks.first?.title, "Run 5k")
    }

    /// Regression test for the CloudKit ModelContainer crash: non-optional
    /// to-many relationships (`[RizeTask] = []`, `[DailyEntry] = []`) made
    /// `ModelContainer(for:configurations:)` throw at app launch. This
    /// doesn't turn on CloudKit here (that's exercised by actually booting
    /// the app), but it does prove `tasks`/`entries` behave like plain
    /// non-optional arrays end-to-end through insert/save/fetch.
    func testEmptyRelationshipsDefaultToEmptyArraysNotNil() throws {
        let profile = UserProfile(name: "Sam", goal: "productivity", goalDetail: "")
        context.insert(profile)
        try context.save()

        XCTAssertEqual(profile.entries, [])

        let entry = DailyEntry(date: Date())
        context.insert(entry)
        try context.save()

        XCTAssertEqual(entry.tasks, [])
        XCTAssertTrue(entry.tasks.isEmpty)
    }

    func testCascadeDeleteRemovesChildren() throws {
        let entry = DailyEntry(date: Date())
        context.insert(entry)

        let taskA = RizeTask(title: "A", duration: "10 min", taskDescription: "", type: "work")
        taskA.entry = entry
        let taskB = RizeTask(title: "B", duration: "10 min", taskDescription: "", type: "work")
        taskB.entry = entry
        context.insert(taskA)
        context.insert(taskB)
        try context.save()

        XCTAssertEqual(entry.tasks.count, 2)

        context.delete(entry)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<RizeTask>())
        XCTAssertTrue(remaining.isEmpty, "deleteRule: .cascade on DailyEntry.tasks should delete orphaned RizeTasks")
    }

    // MARK: - XPManager against real persisted models

    func testApplyTaskCompletionAwardsXPAndTracksStreak() throws {
        let profile = UserProfile(name: "Jordan", goal: "fitness", goalDetail: "")
        context.insert(profile)

        let entry = DailyEntry(date: Date())
        entry.profile = profile
        entry.energyScore = 8 // high energy -> 1.0x multiplier
        entry.totalTasksForDay = 2
        entry.tasksCompleted = 1
        context.insert(entry)
        try context.save()

        let startingXP = profile.currentXP
        let result = XPManager.shared.applyTaskCompletion(entry: entry, profile: profile)

        XCTAssertEqual(result.xpDelta, Constants.baseXPPerTask, "high energy (7-10) uses a 1.0x multiplier with no streak bonus below 7")
        XCTAssertEqual(profile.currentXP, startingXP + Constants.baseXPPerTask)
        XCTAssertEqual(entry.xpEarned, Constants.baseXPPerTask)
        XCTAssertEqual(profile.currentStreak, 1, "first ever check-in should start the streak at 1")
        XCTAssertFalse(result.allTasksDone, "1 of 2 tasks completed should not trigger the all-tasks bonus")
    }

    func testApplyTaskCompletionAllTasksBonus() throws {
        let profile = UserProfile(name: "Riley", goal: "both", goalDetail: "")
        context.insert(profile)

        let entry = DailyEntry(date: Date())
        entry.profile = profile
        entry.energyScore = 5 // medium -> 1.5x multiplier
        entry.totalTasksForDay = 1
        entry.tasksCompleted = 1
        context.insert(entry)
        try context.save()

        let result = XPManager.shared.applyTaskCompletion(entry: entry, profile: profile)

        let expectedTaskXP = Int(Double(Constants.baseXPPerTask) * Constants.mediumEnergyMultiplier)
        XCTAssertTrue(result.allTasksDone)
        XCTAssertEqual(result.xpDelta, expectedTaskXP + Constants.allTasksBonus)
        XCTAssertEqual(entry.xpEarned, expectedTaskXP + Constants.allTasksBonus)
    }

    func testUpdateStreakResetsAfterGap() throws {
        let profile = UserProfile(name: "Casey", goal: "fitness", goalDetail: "")
        let calendar = Calendar.current
        profile.currentStreak = 5
        profile.bestStreak = 5
        profile.lastCheckInDate = calendar.date(byAdding: .day, value: -3, to: Date())
        context.insert(profile)
        try context.save()

        XPManager.shared.updateStreak(profile: profile, completedCount: 1)

        XCTAssertEqual(profile.currentStreak, 1, "a 3-day gap should reset the streak rather than incrementing it")
        XCTAssertEqual(profile.bestStreak, 5, "best streak is a high-water mark and should not drop")
    }

    // MARK: - AchievementManager against a real profile/entry

    func testAchievementCheckDoesNotCrashOnFreshProfile() throws {
        let profile = UserProfile(name: "Morgan", goal: "fitness", goalDetail: "")
        context.insert(profile)
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        context.insert(entry)
        try context.save()

        // Just verifying this doesn't crash/throw against a minimal, real
        // persisted profile+entry — the badges added in this branch
        // (ComebackKid, FirstBlood, etc.) all read through `profile`/`entry`.
        _ = AchievementManager.shared.check(profile: profile, entry: entry, xpManager: XPManager.shared)
    }

    // MARK: - GoalTaskGenerator (deterministic fallback path)

    /// Apple Intelligence isn't available in the test/CI simulator, so
    /// `GoalTaskGenerator.tasks` always takes its deterministic template
    /// fallback here — which makes it safe to assert on exact output.
    private func plan(workload: Workload = .light, intent: WorkoutIntent = .light) -> DailyPlan {
        DailyPlan(
            recommendedTasks: [],
            deferredTasks: [],
            workblockTasks: [],
            workout: WorkoutRecommendation(intent: intent, rationale: []),
            recovery: RecoveryRecommendation(emphasis: .none, rationale: []),
            workload: workload,
            confidence: 1.0,
            burnoutRisk: .low,
            rationale: [],
            generatedAt: Date()
        )
    }

    // NOTE: `GoalTaskGenerator.tasks` takes the live on-device Foundation
    // Models path whenever Apple Intelligence is available on the host
    // (true on this Mac), rather than its deterministic template fallback —
    // so these tests intentionally assert only the documented contract
    // ("always returns at least one well-formed, non-empty activity"),
    // not exact copy, since LLM output isn't deterministic across machines.
    func testGoalTaskGeneratorProducesWellFormedActivityForFitnessGoal() async {
        let context = CoachingContext(name: "Alex", goal: "fitness", goalDetail: "training for a marathon")
        let activities = await GoalTaskGenerator.tasks(for: plan(intent: .moderate), context: context)

        XCTAssertFalse(activities.isEmpty)
        for activity in activities {
            XCTAssertFalse(activity.title.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(activity.duration.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(activity.focus.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testGoalTaskGeneratorProducesWellFormedActivityForWorkGoal() async {
        let context = CoachingContext(name: "Jamie", goal: "productivity", goalDetail: "shipping a startup")
        let activities = await GoalTaskGenerator.tasks(for: plan(workload: .heavy), context: context)

        XCTAssertFalse(activities.isEmpty)
        for activity in activities {
            XCTAssertFalse(activity.title.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(activity.duration.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(activity.focus.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testGoalTaskGeneratorNeverReturnsEmptyForBlankGoal() async {
        let context = CoachingContext(name: "", goal: "", goalDetail: "")
        let activities = await GoalTaskGenerator.tasks(for: plan(), context: context)

        XCTAssertFalse(activities.isEmpty, "the generator must always return at least one activity, even with no goal info")
    }
}
