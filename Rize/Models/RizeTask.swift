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

    var entry: DailyEntry?

    init(
        title: String,
        duration: String,
        taskDescription: String,
        type: String
    ) {
        self.id = UUID()
        self.title = title
        self.duration = duration
        self.taskDescription = taskDescription
        self.type = type
        self.completed = false
        self.completedAt = nil
    }
}
