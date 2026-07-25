import Foundation

// Every type in this file is a plain Swift `struct`/`enum`, not a SwiftData
// `@Model` — unlike `RizeTask`/`DailyEntry`/`UserProfile`, none of this is
// persisted. It's the *pure* value-type output of `PlanningEngine` (see
// `PlanningEngine.swift`), built fresh each time a plan is generated and
// handed straight to the UI/narrator. `Sendable` on every type here is
// Swift's concurrency-safety marker: it's a compile-time promise that a
// value can be safely passed across actor/task boundaries (e.g. from the
// engine's computation into a SwiftUI view or an `async` narrator call)
// because it can't be mutated out from under another owner elsewhere —
// straightforward for these since they're all immutable `let`-only structs
// and simple enums.

// MARK: - Deadline Classification

/// How urgent a task's deadline is, relative to the plan's reference date.
enum DeadlineClass: Int, Comparable, Sendable {
    case overdue = 0    // due before today
    case today = 1      // due today
    case tomorrow = 2   // due tomorrow
    case thisWeek = 3   // due within the next 7 days
    case later = 4      // further out
    case none = 5       // no due date

    static func < (lhs: DeadlineClass, rhs: DeadlineClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// A deadline that cannot be postponed today.
    var isMandatoryToday: Bool { self == .overdue || self == .today }
}

// MARK: - Workload

enum Workload: String, Sendable {
    case light
    case moderate
    case heavy
}

// MARK: - Burnout Risk

enum BurnoutRisk: String, Sendable {
    case low
    case elevated
    case high
}

// MARK: - Planned Task

/// A task the engine has decided to recommend or defer, annotated with the
/// structured reason for that decision. `id` matches the source `PlanningTask`.
struct PlannedTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let priority: TaskPriority
    let category: TaskCategory
    let deadline: DeadlineClass
    let reason: TaskReason
}

/// Structured (non-prose) reason a task was recommended or deferred.
enum TaskReason: String, Sendable {
    case overdue
    case dueToday
    case dueTomorrow
    case highPriority
    case getAhead
    case requiredOnly
    case deferredLowEnergy
    case deferredFarDeadline
    case deferredCapacity
}

// MARK: - Workblock

struct WorkblockTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let category: TaskCategory
    let deadline: DeadlineClass
}

// MARK: - Workout & Recovery Recommendations

/// What kind of training the engine suggests today. Never a command — the UI
/// and narrator frame it as an invitation.
enum WorkoutIntent: String, Sendable {
    case rest       // explicitly no training
    case recovery   // gentle, active recovery
    case light
    case moderate
    case ambitious
}

struct WorkoutRecommendation: Equatable, Sendable {
    let intent: WorkoutIntent
    let rationale: [PlanRationale]
}

/// How strongly to emphasise recovery today.
enum RecoveryEmphasis: String, Sendable {
    case none
    case encouraged
    case prioritized
}

struct RecoveryRecommendation: Equatable, Sendable {
    let emphasis: RecoveryEmphasis
    let rationale: [PlanRationale]
}

// MARK: - Structured Reasoning

/// Machine-readable reasoning. The engine emits these; the Foundation Models
/// narrator (or the template fallback) turns them into supportive prose.
/// The engine itself NEVER produces natural language.
enum PlanRationale: Equatable, Sendable {
    case depletedEnergy(level: Int)
    case lowEnergy(level: Int)
    case steadyEnergy(level: Int)
    case highEnergy(level: Int)
    case insufficientSleep(hours: Double)
    case adequateSleep(hours: Double)
    case ampleSleep(hours: Double)
    case hardWorkoutYesterday
    case restedYesterday
    case noRecentWorkouts
    case overdueDeadlines(count: Int)
    case deadlinesToday(count: Int)
    case deadlinesTomorrow(count: Int)
    case protectingFromBurnout
    case buildingConsistency(streak: Int)
    case gettingAhead
    case requiredWorkOnly
}

// MARK: - Daily Plan

/// The complete, deterministic output of `PlanningEngine`.
/// Contains decisions and *structured* reasoning only — no user-facing prose.
struct DailyPlan: Equatable, Sendable {
    let recommendedTasks: [PlannedTask]
    let deferredTasks: [PlannedTask]
    let workblockTasks: [WorkblockTask]  // New property for workblock tasks
    let workout: WorkoutRecommendation
    let recovery: RecoveryRecommendation
    let workload: Workload
    /// 0…1 — how much the engine trusts this plan given available signals.
    let confidence: Double
    let burnoutRisk: BurnoutRisk
    /// Ordered, structured reasoning behind the plan as a whole.
    let rationale: [PlanRationale]
    let generatedAt: Date

    /// Number of tasks the user is being asked to take on today.
    var recommendedTaskCount: Int { recommendedTasks.count }
}
