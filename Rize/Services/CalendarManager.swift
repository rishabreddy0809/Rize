import Foundation
import EventKit
import SwiftUI

struct RizeCalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let daysUntil: Int
    let isUrgent: Bool
    let mustPlanToday: Bool
    let category: PlanCategory
}

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var upcomingEvents: [RizeCalendarEvent] = []
    /// Today's timed events, classified by category — the source for the day's
    /// scheduled tasks (workouts, classes, work blocks, …).
    @Published var todaysEvents: [RizeCalendarEvent] = []
    @Published var isAuthorized: Bool = false

    private let store = EKEventStore()

    private init() {}

    private static let academicKeywords = [
        "test", "exam", "quiz", "final", "midterm", "paper", "essay",
        "project", "presentation", "deadline", "due", "homework", "assignment"
    ]

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            if granted {
                await fetchUpcomingEvents()
                await fetchTodaysEvents()
            }
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Fetch Events

    func fetchUpcomingEvents() async {
        let now = Date()
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: weekOut, calendars: nil)
        let rawEvents = store.events(matching: predicate)

        let calendar = Calendar.current
        upcomingEvents = rawEvents
            .filter { isRelevant($0) }
            .prefix(10)
            .compactMap { event -> RizeCalendarEvent? in
                let days = calendar.dateComponents([.day], from: now, to: event.startDate).day ?? 0
                let isAcademic = isAcademicEvent(event)
                return RizeCalendarEvent(
                    title: event.title ?? "Event",
                    date: event.startDate,
                    daysUntil: days,
                    isUrgent: days <= 1,
                    mustPlanToday: isAcademic && days <= 1,
                    category: PlanCategory.classify(title: event.title ?? "", calendarName: event.calendar?.title)
                )
            }
    }

    /// Fetch today's timed events and classify each into a `PlanCategory`.
    /// All-day items (birthdays, holidays) are skipped — they're not actionable
    /// time blocks. The result feeds the day's grouped task list.
    func fetchTodaysEvents() async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        todaysEvents = store.events(matching: predicate)
            .filter { event in
                guard let title = event.title, !title.isEmpty else { return false }
                return !event.isAllDay && !isHoliday(event)
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { event in
                RizeCalendarEvent(
                    title: event.title ?? "Event",
                    date: event.startDate ?? Date(),
                    daysUntil: 0,
                    isUrgent: true,
                    mustPlanToday: isAcademicEvent(event),
                    category: PlanCategory.classify(title: event.title ?? "", calendarName: event.calendar?.title)
                )
            }
    }

    private func isRelevant(_ event: EKEvent) -> Bool {
        guard let title = event.title, !title.isEmpty else { return false }
        guard !isHoliday(event) else { return false }
        return isAcademicEvent(event) || event.startDate != nil
    }

    private func isHoliday(_ event: EKEvent) -> Bool {
        event.calendar?.title.lowercased().contains("holiday") ?? false
    }

    private func isAcademicEvent(_ event: EKEvent) -> Bool {
        guard let title = event.title?.lowercased() else { return false }
        return CalendarManager.academicKeywords.contains { title.contains($0) }
    }

    // MARK: - Prompt Context

    func promptContext(for events: [RizeCalendarEvent]) -> String {
        guard !events.isEmpty else { return "" }
        return events.map { event in
            let urgency = event.isUrgent ? " (URGENT - tomorrow or today)" : " (in \(event.daysUntil) days)"
            return "- \(event.title)\(urgency)"
        }.joined(separator: "\n")
    }
}
