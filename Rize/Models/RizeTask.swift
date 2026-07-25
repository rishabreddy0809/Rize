import Foundation
import SwiftData

/// `@Model` is a Swift macro (SwiftData, iOS 17+) that turns a plain class
/// into a persisted database record — it generates the storage/observation
/// machinery under the hood so every stored property here becomes a column,
/// without hand-writing any SQL or Core Data model file. It has to be a
/// `class`, not a `struct`: SwiftData needs reference semantics so that one
/// `RizeTask` object fetched in two different places is the *same* object,
/// and mutating it (e.g. `task.completed = true` in `TodayView`) is visible
/// everywhere else that same row is held, then persisted with
/// `modelContext.save()`.
///
/// Relationships between `@Model` classes are just plain properties of the
/// other model's type — `entry: DailyEntry?` below is what makes this task
/// belong to a specific day; SwiftData manages the underlying foreign key
/// itself.
@Model
final class RizeTask {
    // Every stored property below has an explicit default (`= UUID()`,
    // `= ""`, `= false`, ...) so this model qualifies for CloudKit-backed
    // SwiftData sync (turned on in `RizeApp.swift`'s `ModelConfiguration`).
    // CloudKit records don't fill in every field atomically — a row can
    // arrive from another device mid-sync, or an old app version's record
    // can be missing a column a newer version added — so every attribute
    // needs *some* value to fall back to instead of crashing or being left
    // in an invalid state. A plain `var id: UUID` with no default would
    // satisfy this file's own `init` but not CloudKit's schema requirement,
    // since the requirement is about the property declaration itself, not
    // whether callers happen to always set it. `entry: DailyEntry?` further
    // down needs no change for this — it's already optional, and CloudKit's
    // other rule (every to-one relationship must be optional) was already
    // satisfied before sync was ever added.
    var id: UUID = UUID()
    var title: String = ""
    var duration: String = ""
    var taskDescription: String = ""
    var type: String = "work" // physical / work / recovery
    var completed: Bool = false
    var completedAt: Date?
    /// Whether the "Still on your list" overdue-task alert has already been
    /// handled for this task (Mark Done / Keep on List / Remove) — persisted
    /// so re-mounting the view (e.g. switching tabs and back) can't make the
    /// alert reappear for a task the user already dealt with.
    var overdueAlertDismissed: Bool = false

    /// Persisted priority raw value. Optional for lightweight migration of
    /// stores created before this field existed. See `priority` for typed access.
    var priorityRaw: String?
    /// Optional deadline used by the planning engine.
    var dueDate: Date?

    /// Flexible, goal-derived section label (e.g. "Marathon Base", "Tennis").
    /// When set, the task groups under this heading instead of a fixed
    /// `PlanCategory` bucket. Optional for lightweight migration.
    var sectionLabel: String?

    var entry: DailyEntry?

    init(
        title: String,
        duration: String,
        taskDescription: String,
        type: String,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        sectionLabel: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.duration = duration
        self.taskDescription = taskDescription
        self.type = type
        self.completed = false
        self.completedAt = nil
        self.overdueAlertDismissed = false
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.sectionLabel = sectionLabel
    }

    /// Typed priority, defaulting to `.medium` for legacy rows.
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw ?? "") ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}

// MARK: - Domain Mapping

extension RizeTask {
    /// Project this persisted model into the engine's pure value type. This is
    /// the single boundary where SwiftData meets `PlanningEngine`.
    func asPlanningTask() -> PlanningTask {
        PlanningTask(
            id: id,
            title: title,
            priority: priority,
            dueDate: dueDate,
            isCompleted: completed,
            estimatedMinutes: RizeTask.minutes(from: duration),
            category: TaskCategory(rawValueLenient: type)
        )
    }

    /// Parse a leading integer count of minutes from a duration string such as
    /// "30 min" or "1 hr". Falls back to a sensible default.
    static func minutes(from duration: String) -> Int {
        let lower = duration.lowercased()
        let number = lower.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(number) else { return 30 }
        if lower.contains("hr") || lower.contains("hour") {
            return Int(value * 60)
        }
        return Int(value)
    }
}
