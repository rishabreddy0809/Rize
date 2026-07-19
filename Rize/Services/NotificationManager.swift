import Foundation
import UserNotifications
import SwiftUI

extension Notification.Name {
    static let rizeOpenEnergyPicker = Notification.Name("rizeOpenEnergyPicker")
    static let rizeDebugShowLowEnergyOverlay = Notification.Name("rizeDebugShowLowEnergyOverlay")
}

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    private init() {}

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Categories

    func registerCategories() {
        let logAction = UNNotificationAction(
            identifier: "LOG_ENERGY",
            title: "Log Energy",
            options: .foreground
        )
        let skipAction = UNNotificationAction(
            identifier: "NOT_TODAY",
            title: "Not today",
            options: []
        )
        let morningCategory = UNNotificationCategory(
            identifier: "MORNING_CHECKIN",
            actions: [logAction, skipAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([morningCategory])
    }

    // MARK: - Schedule All

    func scheduleAll(profile: UserProfile) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduleMorningNotification(profile: profile)
        scheduleStreakReminder(profile: profile)
    }

    // MARK: - Morning Notification

    private func scheduleMorningNotification(profile: UserProfile) {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "MORNING_CHECKIN"
        content.sound = .default

        content.title = "Rize is waiting ☀️"
        let streak = profile.currentStreak
        if streak >= 7 {
            content.body = "🔥 \(streak) day streak. Don't stop now."
        } else {
            content.body = RyzDialogue.morningNotification(
                yesterdayEnergy: nil,
                completedTasks: 0
            )
        }

        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: profile.notificationTime
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "rize_morning",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 7pm Streak Reminder

    private func scheduleStreakReminder(profile: UserProfile) {
        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak 🔥"
        let streak = profile.currentStreak
        if streak >= 7 {
            content.body = "\(streak) days strong. Don't let it end here."
        } else if streak >= 3 {
            content.body = "\(streak) days in. Keep it going tonight."
        } else {
            content.body = "Log your energy before the day ends."
        }
        content.sound = .default

        var components = DateComponents()
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "rize_streak_reminder",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Milestone Notifications (immediate)

    func scheduleStreakMilestone(_ streak: Int) {
        guard [3, 7, 14, 30].contains(streak) else { return }
        let content = UNMutableNotificationContent()
        switch streak {
        case 3:
            content.title = "3 days with Rize ✨"
            content.body = RyzDialogue.onStreakMilestone(3)
        case 7:
            content.title = "One week straight 🔥"
            content.body = RyzDialogue.onStreakMilestone(7)
        case 14:
            content.title = "Two weeks 💪"
            content.body = RyzDialogue.onStreakMilestone(14)
        case 30:
            content.title = "30 days with Rize 🌅"
            content.body = RyzDialogue.onStreakMilestone(30)
        default: return
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rize_milestone_\(streak)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - All Tasks Complete

    func scheduleAllTasksComplete() {
        let content = UNMutableNotificationContent()
        content.title = "All done today 🌅"
        content.body = "The flame holds. See you tomorrow."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rize_all_done",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Siege Notifications

    func scheduleSiegeStartNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Your flame is fading 🔥"
        content.body = "One task will reignite it."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "rize_siege_start",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleSiegeBrokenNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Rising from ash 🔥"
        content.body = "You kept the fire alive. Bonus XP earned."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rize_siege_broken",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelSiegeNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["rize_siege_start", "rize_siege_broken"]
        )
    }

    // MARK: - Comeback

    func scheduleComebackNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Your flame needs you ☀️"
        content.body = "No judgment. Just come back."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 172800, repeats: false)
        let request = UNNotificationRequest(
            identifier: "rize_comeback",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
