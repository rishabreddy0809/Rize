import Foundation
import UserNotifications
import SwiftUI

extension Notification.Name {
    static let rizeOpenEnergyPicker = Notification.Name("rizeOpenEnergyPicker")
    static let rizeAddCustomTask = Notification.Name("rizeAddCustomTask")
}

/// Payload for `.rizeAddCustomTask` — posted by the floating "+" button (which
/// lives in `MainTabView`, outside any single tab) and handled by `TodayView`
/// (which owns the model context and today's `DailyEntry`).
struct CustomTaskRequest {
    let title: String
    let dueDate: Date?
    /// `Calendar` weekday numbers (Sun=1...Sat=7) to repeat on. Empty means
    /// a one-time task.
    let recurrenceDays: Set<Int>
}

/// Wraps `UNUserNotificationCenter`, the UserNotifications framework's single
/// shared object for both permission and scheduling local (on-device, no
/// server/push involved) notifications. Every scheduling method below
/// follows the same three-piece shape UserNotifications requires:
///   - `UNMutableNotificationContent` — what to show (title/body/sound).
///   - a *trigger*, deciding *when* — this file uses all three kinds:
///     `UNCalendarNotificationTrigger` (fire at specific date components,
///     optionally `repeats: true` for "every day at this time", used for the
///     morning/streak reminders), `UNTimeIntervalNotificationTrigger` (fire
///     after a relative delay, used for the siege/comeback nudges), and
///     `trigger: nil` (fire immediately once `.add()` is called — used for
///     the "this just happened" notifications like milestones).
///   - a `UNNotificationRequest` bundling content + trigger under a string
///     `identifier`. That identifier is also the dedup/cancel key: adding a
///     request with the same identifier as a pending one replaces it (see
///     `scheduleTaskDueReminder`'s doc comment), and
///     `removePendingNotificationRequests(withIdentifiers:)` is how a
///     scheduled-but-not-yet-fired notification gets cancelled outright.
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
        // Without a delegate, iOS silently drops any notification that fires
        // while the app is in the foreground (no banner, not even recorded as
        // delivered) — which is exactly when the immediate ones (milestone,
        // all-done, siege-broken) always fire, since they're triggered by
        // things the user just did in the open app. This also wires up the
        // "Log Energy" / "Not today" quick actions below, which otherwise do
        // nothing when tapped.
        UNUserNotificationCenter.current().delegate = RizeNotificationDelegate.shared

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

    /// Fires an hour after a day starts with zero tasks done and the phoenix
    /// starts losing health — gives the user a chance to feed it before
    /// nudging them, rather than notifying the instant the app detects it
    /// (which is usually while they're already looking at the in-app banner).
    func scheduleSiegeStartNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Feed your Phoenix 🔥"
        content.body = "It's losing health. Complete one task to keep it fed."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "rize_siege_start",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelSiegeNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["rize_siege_start", "rize_siege_broken"]
        )
    }

    // MARK: - Task Due Reminders

    /// Schedules a local push for the exact moment a scheduled task is due —
    /// this fires from the OS even if Rize isn't open, unlike the in-app
    /// overdue alert (`TodayView.checkOverdueTasks`), which only runs while
    /// the app is foregrounded. Call again on every reschedule; the fixed
    /// identifier (keyed to the task) replaces any prior pending request.
    func scheduleTaskDueReminder(taskID: UUID, title: String, dueDate: Date) {
        guard dueDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Still on your list"
        content.body = "\"\(title)\" was due just now. Mark it done or clear it in Rize."
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.taskDueIdentifier(taskID),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Cancels a task's pending due reminder — call when it's completed,
    /// removed, or its due date changes, so a finished task never notifies.
    func cancelTaskDueReminder(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.taskDueIdentifier(taskID)]
        )
    }

    private static func taskDueIdentifier(_ taskID: UUID) -> String {
        "rize_task_due_\(taskID.uuidString)"
    }
}

/// Lets local notifications actually present while Rize is open (iOS drops
/// them otherwise) and routes the morning check-in's quick actions.
final class RizeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RizeNotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "LOG_ENERGY" {
            NotificationCenter.default.post(name: .rizeOpenEnergyPicker, object: nil)
        }
        completionHandler()
    }
}
