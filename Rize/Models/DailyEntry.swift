import Foundation
import SwiftData

@Model
final class DailyEntry {
    var id: UUID
    var date: Date
    var energyScore: Int?
    var tasksCompleted: Int
    var totalTasksForDay: Int
    var xpEarned: Int
    var planGenerated: Bool
    var comebackBonusApplied: Bool

    var profile: UserProfile?

    @Relationship(deleteRule: .cascade, inverse: \RizeTask.entry)
    var tasks: [RizeTask]

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
