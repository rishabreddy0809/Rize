import Foundation
import SwiftData

/// One row per calendar day — see `RizeTask.swift` for what `@Model` means.
@Model
final class DailyEntry {
    // Explicit defaults on every attribute — required for CloudKit-backed
    // SwiftData sync (see `RizeTask` for the full explanation of why).
    var id: UUID = UUID()
    var date: Date = Date()
    var energyScore: Int?
    var tasksCompleted: Int = 0
    var totalTasksForDay: Int = 0
    var xpEarned: Int = 0
    var planGenerated: Bool = false
    var comebackBonusApplied: Bool = false

    // The to-one side of this relationship — CloudKit requires exactly this:
    // optional, so a `DailyEntry` can exist in the synced schema even for a
    // split second before its parent `UserProfile` has arrived from another
    // device. It was already declared this way before sync was added, so no
    // change was needed here — only the plain attributes above needed one.
    var profile: UserProfile?

    // `@Relationship` is how SwiftData models a to-many link explicitly,
    // rather than just inferring one from the property's array type:
    //   - `inverse: \RizeTask.entry` tells SwiftData this array and
    //     `RizeTask.entry` are the *same* relationship seen from both sides,
    //     so setting one side (e.g. `task.entry = someEntry`, done in
    //     `TodayView.addCustomTask`) keeps this array in sync automatically
    //     — you don't have to manually append to both.
    //   - `deleteRule: .cascade` says what happens to the "many" side when
    //     the "one" side is deleted: deleting a `DailyEntry` deletes every
    //     `RizeTask` that belonged to it too, rather than orphaning them.
    // The `= []` default is the to-many equivalent of the scalar attributes'
    // defaults above — CloudKit's requirement isn't only about optionality,
    // it's that the property can never be left uninitialized when a record
    // partially arrives from sync, and an empty array is a perfectly valid
    // "no tasks synced down yet" state.
    //
    // CloudKit still rejects a non-optional array type outright, though —
    // the stored property itself must be `Optional`. `tasks` below is a
    // computed passthrough so every existing call site can keep treating
    // it as a plain non-optional array.
    @Relationship(deleteRule: .cascade, inverse: \RizeTask.entry)
    private var _tasks: [RizeTask]? = []

    var tasks: [RizeTask] {
        get { _tasks ?? [] }
        set { _tasks = newValue }
    }

    init(date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.energyScore = nil
        self.tasksCompleted = 0
        self.totalTasksForDay = 0
        self.xpEarned = 0
        self.planGenerated = false
        self.comebackBonusApplied = false
        self.tasks = []
    }

    var isFullyComplete: Bool {
        totalTasksForDay > 0 && tasksCompleted >= totalTasksForDay
    }

    var completionRate: Double {
        guard totalTasksForDay > 0 else { return 0 }
        return Double(tasksCompleted) / Double(totalTasksForDay)
    }
}
