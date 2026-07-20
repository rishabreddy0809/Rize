import Foundation
import SwiftData

@Model
final class RizeTask {
    var id: UUID
    var title: String
    var duration: String
    var taskDescription: String
    var type: String // physical / work / recovery
    var completed: Bool
    var completedAt: Date?

    /// Persisted priority raw value. Optional for lightweight migration of
    /// stores created before this field existed. See `priority` for typed access.
    var priorityRaw: String?
    /// Optional deadline used by the planning engine.
    var dueDate: Date?

    var entry: DailyEntry?

    init(
        title: String,
        duration: String,
        taskDescription: String,
        type: String,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.duration = duration
        self.taskDescription = taskDescription
        self.type = type
        self.completed = false
        self.completedAt = nil
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
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
