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

        // XPManager.shared is a real singleton backed by UserDefaults (not
        // reset by the fresh in-memory ModelContainer above) — reset the
        // fields these tests touch so they're deterministic regardless of
        // what a previous test run left behind.
        XPManager.shared.isUnderSiege = false
        XPManager.shared.realmDefense = 100
        XPManager.shared.defenseHistoryJSON = "[]"
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

    /// Regression test: the siege-break bonus used to only appear in the
    /// returned `xpDelta` (what the toast shows) without ever being added to
    /// `profile.currentXP` — the bonus was promised but never paid.
    func testApplyTaskCompletionCreditsSiegeBonusToRealXP() throws {
        let profile = UserProfile(name: "Sky", goal: "fitness", goalDetail: "")
        context.insert(profile)

        let entry = DailyEntry(date: Date())
        entry.profile = profile
        entry.energyScore = 2 // <= 3 -> the larger (30 XP) siege-break bonus
        entry.totalTasksForDay = 2
        entry.tasksCompleted = 1
        context.insert(entry)
        try context.save()

        XPManager.shared.isUnderSiege = true
        let startingXP = profile.currentXP
        let result = XPManager.shared.applyTaskCompletion(entry: entry, profile: profile)

        XCTAssertTrue(result.siegeBroken)
        XCTAssertEqual(result.bonusXP, 30, "energy <= 3 while under siege should award the 30 XP bonus")
        XCTAssertEqual(
            profile.currentXP, startingXP + result.xpDelta,
            "the siege bonus reported in xpDelta must actually be credited to profile.currentXP, not just shown in the toast"
        )
        XCTAssertEqual(entry.xpEarned, result.xpDelta)
    }

    /// Regression test: `bestXPDay` used to compare against
    /// `profile.currentXP` (the all-time cumulative total, which only ever
    /// grows), so it silently converged to "lifetime XP" instead of "most
    /// XP earned in any single day."
    func testBestXPDayTracksSingleDayNotCumulativeTotal() throws {
        let profile = UserProfile(name: "Drew", goal: "fitness", goalDetail: "")
        context.insert(profile)

        // Day 1: a big day — all tasks done, earns the all-tasks bonus too.
        let day1 = DailyEntry(date: Date())
        day1.profile = profile
        day1.energyScore = 8 // high energy -> 1.0x multiplier
        day1.totalTasksForDay = 1
        day1.tasksCompleted = 1
        context.insert(day1)
        try context.save()
        _ = XPManager.shared.applyTaskCompletion(entry: day1, profile: profile)

        let bestAfterDay1 = profile.bestXPDay
        XCTAssertEqual(bestAfterDay1, day1.xpEarned)
        XCTAssertEqual(bestAfterDay1, Constants.baseXPPerTask + Constants.allTasksBonus)

        // Day 2: a small day — a single task, nowhere near day 1's total.
        let day2 = DailyEntry(date: Date())
        day2.profile = profile
        day2.energyScore = 8
        day2.totalTasksForDay = 5
        day2.tasksCompleted = 1
        context.insert(day2)
        try context.save()
        _ = XPManager.shared.applyTaskCompletion(entry: day2, profile: profile)

        XCTAssertEqual(profile.bestXPDay, bestAfterDay1, "a smaller day should not lower or replace the existing best-day record")
        XCTAssertGreaterThan(
            profile.currentXP, profile.bestXPDay,
            "lifetime XP (both days combined) should now exceed the best single day — proving bestXPDay tracks per-day totals, not cumulative currentXP"
        )
    }

    // MARK: - AchievementManager.realm_defender (actual vitality, not just "defended")

    /// Regression test: `realm_defender` used to unlock off `DefenseDay.defended`
    /// alone, which only means "completed >= 1 task that day" — not that
    /// vitality actually reached 100%. Seven "defended" days starting from a
    /// low vitality would unlock the achievement despite vitality never
    /// hitting 100%.
    func testRealmDefenderRequiresActualFullVitalityNotJustDefendedDays() throws {
        let profile = UserProfile(name: "Taylor", goal: "fitness", goalDetail: "")
        context.insert(profile)
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        context.insert(entry)
        try context.save()

        let defendedButNotFull = (0..<7).map { DefenseDay(date: "day\($0)", defended: true, defenseValue: 70) }
        XPManager.shared.defenseHistoryJSON = try encodeHistory(defendedButNotFull)
        let resultsBelowFull = AchievementManager.shared.check(profile: profile, entry: entry, xpManager: XPManager.shared)
        XCTAssertFalse(
            resultsBelowFull.contains { $0.id == "realm_defender" },
            "7 'defended' days at 70% vitality should not unlock realm_defender"
        )

        let fullVitality = (0..<7).map { DefenseDay(date: "day\($0)", defended: true, defenseValue: 100) }
        XPManager.shared.defenseHistoryJSON = try encodeHistory(fullVitality)
        let resultsAtFull = AchievementManager.shared.check(profile: profile, entry: entry, xpManager: XPManager.shared)
        XCTAssertTrue(
            resultsAtFull.contains { $0.id == "realm_defender" },
            "7 consecutive days at 100% vitality should unlock realm_defender"
        )
    }

    private func encodeHistory(_ history: [DefenseDay]) throws -> String {
        let data = try JSONEncoder().encode(history)
        return String(data: data, encoding: .utf8) ?? "[]"
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

    // MARK: - AchievementManager.iron_will vs perfect_week

    /// Regression test: `iron_will` used to check `currentStreak >= 7`,
    /// identical to `perfect_week` — so a streak that later reset would
    /// silently "lose" a milestone the user genuinely earned. `bestStreak`
    /// is a permanent high-water mark, so reaching 7 once keeps it unlocked
    /// even after the live streak drops.
    func testIronWillUsesBestStreakSoItSurvivesAStreakReset() throws {
        let profile = UserProfile(name: "Robin", goal: "fitness", goalDetail: "")
        profile.currentStreak = 2 // reset since the 7-day milestone
        profile.bestStreak = 7
        context.insert(profile)
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        context.insert(entry)
        try context.save()

        let unlocked = AchievementManager.shared.check(profile: profile, entry: entry, xpManager: XPManager.shared)

        XCTAssertTrue(
            unlocked.contains { $0.id == "iron_will" },
            "a currentStreak of 2 should still unlock iron_will off the permanent bestStreak of 7"
        )
    }

    /// Regression test: `perfect_week` used to be a duplicate of
    /// `iron_will` (`currentStreak >= 7`) instead of its own, stricter
    /// condition (every task done on each of the last 7 days). It's now
    /// computed by the caller and passed in as `isPerfectWeek`.
    func testPerfectWeekRequiresExplicitFlagNotJustStreak() throws {
        let profile = UserProfile(name: "Casey", goal: "fitness", goalDetail: "")
        profile.currentStreak = 10 // would have satisfied the old buggy condition
        context.insert(profile)
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        context.insert(entry)
        try context.save()

        let withoutFlag = AchievementManager.shared.check(profile: profile, entry: entry, xpManager: XPManager.shared)
        XCTAssertFalse(
            withoutFlag.contains { $0.id == "perfect_week" },
            "a high streak alone should no longer be enough to unlock perfect_week"
        )

        let withFlag = AchievementManager.shared.check(
            profile: profile, entry: entry, xpManager: XPManager.shared, isPerfectWeek: true
        )
        XCTAssertTrue(withFlag.contains { $0.id == "perfect_week" })
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
