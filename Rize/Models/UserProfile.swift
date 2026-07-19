import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var name: String
    var goal: String // fitness / productivity / both
    var goalDetail: String
    var hasCompletedOnboarding: Bool
    var isPro: Bool
    var currentXP: Int
    var currentStreak: Int
    var bestStreak: Int
    var bestXPDay: Int
    var bestTasksCompletedInWeek: Int
    var lastCheckInDate: Date?
    var notificationTime: Date
    var healthKitEnabled: Bool
    var calendarEnabled: Bool
    var monthlyPlansUsed: Int
    var monthlyPlansResetDate: Date
    var proStartDate: Date?
    var unlockedAchievementsJSON: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.profile)
    var entries: [DailyEntry]

    init(
        name: String = "",
        goal: String = "fitness",
        goalDetail: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.goal = goal
        self.goalDetail = goalDetail
        self.hasCompletedOnboarding = false
        self.isPro = false
        self.currentXP = 0
        self.currentStreak = 0
        self.bestStreak = 0
        self.bestXPDay = 0
        self.bestTasksCompletedInWeek = 0
        self.lastCheckInDate = nil
        self.notificationTime = Calendar.current.date(
            from: DateComponents(hour: 8, minute: 0)
        ) ?? Date()
        self.healthKitEnabled = false
        self.calendarEnabled = false
        self.monthlyPlansUsed = 0
        self.monthlyPlansResetDate = Date()
        self.proStartDate = nil
        self.unlockedAchievementsJSON = "[]"
        self.createdAt = Date()
        self.entries = []
    }

    var canGeneratePlan: Bool {
        if isPro { return true }
        let calendar = Calendar.current
        if !calendar.isDate(monthlyPlansResetDate, equalTo: Date(), toGranularity: .month) {
            return true
        }
        return monthlyPlansUsed < Constants.freePlanLimitPerMonth
    }

    func recordPlanGenerated() {
        let calendar = Calendar.current
        if !calendar.isDate(monthlyPlansResetDate, equalTo: Date(), toGranularity: .month) {
            monthlyPlansUsed = 1
            monthlyPlansResetDate = Date()
        } else {
            monthlyPlansUsed += 1
        }
    }

    var currentLevel: String {
        KingdomDesign.tierInfo(for: currentXP).name
    }

    var progressPercentage: Double {
        let info = KingdomDesign.tierInfo(for: currentXP)
        let current = Double(currentXP - info.minXP)
        let next = Double((info.nextMinXP ?? (info.minXP + 1000)) - info.minXP)
        guard next > 0 else { return 1.0 }
        return min(1.0, max(0.0, current / next))
    }

    var unlockedAchievements: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(unlockedAchievementsJSON.utf8))) ?? []
    }

    @discardableResult
    func unlockAchievement(_ id: String) -> Bool {
        var unlocked = unlockedAchievements
        guard !unlocked.contains(id) else { return false }
        unlocked.append(id)
        if let data = try? JSONEncoder().encode(unlocked),
           let str = String(data: data, encoding: .utf8) {
            unlockedAchievementsJSON = str
        }
        return true
    }
}
