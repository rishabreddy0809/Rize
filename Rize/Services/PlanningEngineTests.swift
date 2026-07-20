import XCTest
@testable import Rize

/// Unit tests for the deterministic `PlanningEngine`.
///
/// NOTE: These require a Unit Testing bundle target. This project's Xcode
/// project is hand-maintained and currently has no test target, so this file is
/// intentionally **not** compiled into the app target. To run:
/// Xcode ▸ File ▸ New ▸ Target ▸ Unit Testing Bundle, then add this file to it.
///
/// The same scenarios are also verified headless via `swiftc` during
/// development (see the engine verification harness), so the engine's behaviour
/// is exercised even before the test target exists.
final class PlanningEngineTests: XCTestCase {

    private let engine = PlanningEngine()

    /// Fixed calendar + reference date so day math is deterministic.
    private lazy var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private lazy var now: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func task(_ title: String, _ priority: TaskPriority = .medium, due: Int? = nil, done: Bool = false) -> PlanningTask {
        PlanningTask(title: title, priority: priority, dueDate: due.map(day), isCompleted: done)
    }

    private func input(
        energy: Int,
        tasks: [PlanningTask] = [],
        sleep: Double? = nil,
        workouts: [WorkoutSummary] = [],
        streak: Int = 1
    ) -> PlanInput {
        PlanInput(
            referenceDate: now,
            energy: energy,
            tasks: tasks,
            sleep: sleep.map { SleepSummary(hours: $0) },
            recentWorkouts: workouts,
            currentStreak: streak,
            calendar: calendar
        )
    }

    // MARK: - Energy + Sleep

    func testDepletedEnergyPoorSleepProtectsUser() {
        let plan = engine.makePlan(from: input(
            energy: 2,
            tasks: [task("Overdue", .high, due: -1), task("Today", .high, due: 0), task("Next week", .low, due: 5)],
            sleep: 4
        ))
        XCTAssertEqual(plan.workload, .light)
        XCTAssertEqual(plan.workout.intent, .rest)
        XCTAssertEqual(plan.recovery.emphasis, .prioritized)
        XCTAssertEqual(plan.burnoutRisk, .high)
        // Mandatory deadlines are never postponed, even when depleted.
        XCTAssertTrue(plan.recommendedTasks.contains { $0.deadline == .overdue })
        XCTAssertTrue(plan.recommendedTasks.contains { $0.deadline == .today })
        // Optional far-out work is deferred.
        XCTAssertTrue(plan.deferredTasks.contains { $0.title == "Next week" })
    }

    func testHighEnergyAmpleSleepAllowsGettingAhead() {
        let plan = engine.makePlan(from: input(
            energy: 9,
            tasks: [task("Soon", .high, due: 2), task("Later", .medium, due: 3), task("Far", .low, due: 6)],
            sleep: 9
        ))
        XCTAssertEqual(plan.workload, .heavy)
        XCTAssertEqual(plan.workout.intent, .ambitious)
        XCTAssertEqual(plan.burnoutRisk, .low)
        XCTAssertGreaterThanOrEqual(plan.recommendedTasks.count, 1)
        XCTAssertLessThanOrEqual(plan.recommendedTasks.count, 5) // high-band capacity
    }

    // MARK: - Workouts

    func testHardWorkoutYesterdayTriggersRecovery() {
        let hardRun = WorkoutSummary(type: "Run", startDate: day(-1), distanceMeters: 15000, movingTime: 5400, source: .strava)
        let plan = engine.makePlan(from: input(
            energy: 5,
            tasks: [task("A", .high, due: 0), task("B", .medium, due: 1)],
            workouts: [hardRun]
        ))
        XCTAssertEqual(plan.workout.intent, .recovery)
        XCTAssertEqual(plan.workload, .moderate)
        XCTAssertEqual(plan.recovery.emphasis, .encouraged)
    }

    func testNoRecentWorkoutsEncouragesConsistency() {
        let plan = engine.makePlan(from: input(energy: 6))
        XCTAssertTrue(plan.workout.rationale.contains(.noRecentWorkouts))
        XCTAssertEqual(plan.workout.intent, .moderate)
    }

    // MARK: - Edge Cases

    func testEmptyTaskListIsSafe() {
        let plan = engine.makePlan(from: input(energy: 5))
        XCTAssertTrue(plan.recommendedTasks.isEmpty)
        XCTAssertTrue(plan.deferredTasks.isEmpty)
        XCTAssertLessThan(plan.confidence, 0.7) // little signal → lower confidence
    }

    func testLowEnergyNeverOverloadsWithFarFutureWork() {
        let many = (1...6).map { task("Future \($0)", .medium, due: $0 + 2) }
        let plan = engine.makePlan(from: input(energy: 3, tasks: many))
        XCTAssertLessThanOrEqual(plan.recommendedTasks.count, 3) // low-band capacity
        XCTAssertFalse(plan.recommendedTasks.contains { $0.deadline == .later })
    }

    func testCompletedTasksAreIgnored() {
        let plan = engine.makePlan(from: input(
            energy: 7,
            tasks: [task("Done", .high, due: 0, done: true), task("Open", .high, due: 0)]
        ))
        XCTAssertEqual(plan.recommendedTasks.count, 1)
        XCTAssertEqual(plan.recommendedTasks.first?.title, "Open")
    }

    // MARK: - Determinism

    func testDeterministicForIdenticalInput() {
        let tasks = [task("X", .high, due: 0), task("Y", .low, due: 4)]
        let a = engine.makePlan(from: input(energy: 7, tasks: tasks, sleep: 7))
        let b = engine.makePlan(from: input(energy: 7, tasks: tasks, sleep: 7))
        XCTAssertEqual(a, b)
    }
}
