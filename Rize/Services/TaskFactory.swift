import Foundation

/// A concrete, checkable activity to show the user. Produced deterministically
/// from a `DailyPlan` — the engine decides the shape of the day, the factory
/// turns those decisions into actionable items. No AI, no randomness.
struct PlannedActivity: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let duration: String
    let detail: String
    let category: TaskCategory
}

/// Builds the day's actionable task list from a `DailyPlan`. This is the bridge
/// between the abstract plan (workload, workout intent, recovery emphasis,
/// prioritised deadlines) and the tangible checklist the user completes.
enum TaskFactory {

    /// Produce the day's activities: one movement task, one focus task, one
    /// recovery task, plus any deadline items the engine chose to surface.
    static func activities(for plan: DailyPlan) -> [PlannedActivity] {
        var items: [PlannedActivity] = []

        items.append(movementActivity(for: plan.workout.intent))
        items.append(focusActivity(for: plan.workload))
        items.append(recoveryActivity(for: plan.recovery.emphasis))
        items.append(contentsOf: deadlineActivities(from: plan))

        return items
    }

    // MARK: - Movement

    private static func movementActivity(for intent: WorkoutIntent) -> PlannedActivity {
        switch intent {
        case .rest:
            return PlannedActivity(
                title: "Full Rest",
                duration: "—",
                detail: "No training today. Recovery is the work — you'll come back stronger.",
                category: .recovery
            )
        case .recovery:
            return PlannedActivity(
                title: "Easy Recovery Walk",
                duration: "15 min",
                detail: "Gentle movement only. Loosen up, don't push.",
                category: .physical
            )
        case .light:
            return PlannedActivity(
                title: "Light Movement",
                duration: "20 min",
                detail: "An easy walk or gentle mobility — keep the streak alive.",
                category: .physical
            )
        case .moderate:
            return PlannedActivity(
                title: "Moderate Workout",
                duration: "30 min",
                detail: "A comfortable run, ride, or session at a steady effort.",
                category: .physical
            )
        case .ambitious:
            return PlannedActivity(
                title: "Ambitious Workout",
                duration: "45 min",
                detail: "Good day to challenge yourself — strength or a harder session.",
                category: .physical
            )
        }
    }

    // MARK: - Focus

    private static func focusActivity(for workload: Workload) -> PlannedActivity {
        switch workload {
        case .light:
            return PlannedActivity(
                title: "One Small Focus Block",
                duration: "15 min",
                detail: "Just one small thing. Starting is the whole win today.",
                category: .work
            )
        case .moderate:
            return PlannedActivity(
                title: "Focused Work Block",
                duration: "45 min",
                detail: "One task, deep focus, no distractions.",
                category: .work
            )
        case .heavy:
            return PlannedActivity(
                title: "Deep Work Sprint",
                duration: "60 min",
                detail: "Hardest task first while your energy is high.",
                category: .work
            )
        }
    }

    // MARK: - Recovery

    private static func recoveryActivity(for emphasis: RecoveryEmphasis) -> PlannedActivity {
        switch emphasis {
        case .prioritized:
            return PlannedActivity(
                title: "Prioritise Recovery",
                duration: "10 min",
                detail: "Hydrate, breathe, and plan an early night. Rest is productive.",
                category: .recovery
            )
        case .encouraged:
            return PlannedActivity(
                title: "Wind-Down Routine",
                duration: "10 min",
                detail: "Stretch and reset so tomorrow starts well.",
                category: .recovery
            )
        case .none:
            return PlannedActivity(
                title: "Hydration Check",
                duration: "5 min",
                detail: "A glass of water and a quick reset.",
                category: .recovery
            )
        }
    }

    // MARK: - Deadlines

    /// Surface the deadline-bearing tasks the engine chose to recommend today,
    /// framed by how urgent they are.
    private static func deadlineActivities(from plan: DailyPlan) -> [PlannedActivity] {
        plan.recommendedTasks.compactMap { task in
            switch task.deadline {
            case .overdue:
                return PlannedActivity(title: "Catch up: \(task.title)", duration: "30 min",
                                       detail: "This is overdue — a little progress relieves the pressure.", category: .work)
            case .today:
                return PlannedActivity(title: "Due today: \(task.title)", duration: "30 min",
                                       detail: "Due today — let's get it done.", category: .work)
            case .tomorrow:
                return PlannedActivity(title: "Prep: \(task.title)", duration: "20 min",
                                       detail: "Due tomorrow — a little prep now makes it easy.", category: .work)
            case .thisWeek, .later:
                return PlannedActivity(title: "Get ahead: \(task.title)", duration: "30 min",
                                       detail: "You've got energy — use it to work ahead.", category: .work)
            case .none:
                return nil
            }
        }
    }
}
