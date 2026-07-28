import XCTest
@testable import Rize

/// `RecurringTemplate.latest`/`due` — the pure selection logic
/// `TodayView.generatePlan` uses to decide which repeating tasks come back
/// today. Pulled out to file scope specifically so it's testable without a
/// SwiftUI view or `ModelContext` (see the type's doc comment in
/// `TodayView.swift`).
final class RecurringTaskSchedulingTests: XCTestCase {

    private func recurringTask(
        title: String = "Gym",
        days: Set<Int>,
        groupID: UUID,
        entryDate: Date
    ) -> RizeTask {
        let task = RizeTask(
            title: title,
            duration: "30 min",
            taskDescription: "",
            type: "physical",
            recurrenceDays: days,
            recurrenceGroupID: groupID
        )
        task.entry = DailyEntry(date: entryDate)
        return task
    }

    // MARK: - latest(from:)

    func testLatestIgnoresOneTimeTasks() {
        let oneOff = RizeTask(title: "One-off", duration: "10 min", taskDescription: "", type: "work")
        XCTAssertEqual(RecurringTemplate.latest(from: [oneOff]), [])
    }

    func testLatestPicksMostRecentInstancePerGroup() {
        let groupID = UUID()
        let older = recurringTask(title: "Gym (old title)", days: [2], groupID: groupID, entryDate: .distantPast)
        let newer = recurringTask(title: "Gym (renamed)", days: [2, 4], groupID: groupID, entryDate: Date())

        let templates = RecurringTemplate.latest(from: [older, newer])

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.title, "Gym (renamed)", "the most recently created instance's edits should win")
        XCTAssertEqual(templates.first?.days, [2, 4])
    }

    func testLatestIsOrderIndependent() {
        let groupID = UUID()
        let older = recurringTask(days: [2], groupID: groupID, entryDate: .distantPast)
        let newer = recurringTask(title: "Gym (renamed)", days: [2, 4], groupID: groupID, entryDate: Date())

        // Same inputs, reversed order — the result shouldn't depend on fetch order.
        let templates = RecurringTemplate.latest(from: [newer, older])

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.title, "Gym (renamed)")
    }

    func testLatestKeepsSeparateGroupsIndependent() {
        let gymGroup = UUID()
        let studyGroup = UUID()
        let gym = recurringTask(title: "Gym", days: [2], groupID: gymGroup, entryDate: Date())
        let study = recurringTask(title: "Study block", days: [3, 5], groupID: studyGroup, entryDate: Date())

        let templates = RecurringTemplate.latest(from: [gym, study])

        XCTAssertEqual(Set(templates.map(\.groupID)), Set([gymGroup, studyGroup]))
        XCTAssertEqual(templates.first { $0.groupID == studyGroup }?.days, [3, 5])
    }

    func testLatestTreatsMissingEntryAsOldest() {
        let groupID = UUID()
        let noEntry = RizeTask(
            title: "Never persisted",
            duration: "10 min",
            taskDescription: "",
            type: "work",
            recurrenceDays: [1],
            recurrenceGroupID: groupID
        ) // entry left nil
        let withEntry = recurringTask(title: "Persisted", days: [1, 6], groupID: groupID, entryDate: Date())

        let templates = RecurringTemplate.latest(from: [noEntry, withEntry])

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.title, "Persisted", "an instance with a real entry date should always beat one with none")
    }

    // MARK: - due(_:onWeekday:)

    func testDueFiltersToMatchingWeekday() {
        let monday = RecurringTemplate(
            groupID: UUID(), title: "Monday task", duration: "30 min", type: "physical", sectionLabel: nil, days: [2]
        )
        let weekend = RecurringTemplate(
            groupID: UUID(), title: "Weekend task", duration: "30 min", type: "physical", sectionLabel: nil, days: [1, 7]
        )

        let due = RecurringTemplate.due([monday, weekend], onWeekday: 2)

        XCTAssertEqual(due.map(\.title), ["Monday task"])
    }

    func testDueReturnsEmptyWhenNoSeriesMatchesToday() {
        let monday = RecurringTemplate(
            groupID: UUID(), title: "Monday task", duration: "30 min", type: "physical", sectionLabel: nil, days: [2]
        )
        XCTAssertTrue(RecurringTemplate.due([monday], onWeekday: 5).isEmpty)
    }
}
