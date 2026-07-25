import XCTest
@testable import Rize

/// Deterministic logic in `PhoenixDesignSystem.swift` — tier thresholds,
/// defense-bar color bands, and calendar-event classification. Nothing here
/// touches SwiftUI rendering, just the pure functions behind it.
final class PhoenixDesignSystemTests: XCTestCase {

    // MARK: - PhoenixDesign.tierInfo

    func testTierInfoBoundariesAreInclusiveOnTheLowEnd() {
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 0).name, "ASH")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 500).name, "ASH", "500 is one below the Awakening threshold")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 501).name, "AWAKENING")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 1500).name, "AWAKENING")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 1501).name, "RISING")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 3501).name, "RADIANT")
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 7001).name, "ETERNAL")
    }

    func testTierInfoNextMinXPIsNilOnlyAtMaxTier() {
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 0).nextMinXP, 501)
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 7001).nextMinXP, nil)
        XCTAssertEqual(PhoenixDesign.tierInfo(for: 999_999).nextMinXP, nil)
    }

    func testTierInfoIndexIncreasesMonotonically() {
        let xps = [0, 501, 1501, 3501, 7001]
        let indices = xps.map { PhoenixDesign.tierInfo(for: $0).index }
        XCTAssertEqual(indices, [0, 1, 2, 3, 4])
    }

    // MARK: - PhoenixDesign.playerLevel

    func testPlayerLevelStartsAtOneAndScalesWithXP() {
        XCTAssertEqual(PhoenixDesign.playerLevel(for: 0), 1)
        XCTAssertEqual(PhoenixDesign.playerLevel(for: 119), 1)
        XCTAssertEqual(PhoenixDesign.playerLevel(for: 120), 2)
        XCTAssertEqual(PhoenixDesign.playerLevel(for: 240), 3)
    }

    // MARK: - PhoenixDesign.defenseBarColor

    func testDefenseBarColorBands() {
        // Just asserting the three color identities are distinct at their
        // documented thresholds (>60 success, 30-60 primary, <30 destructive).
        XCTAssertEqual(PhoenixDesign.defenseBarColor(100), PhoenixPalette.success)
        XCTAssertEqual(PhoenixDesign.defenseBarColor(61), PhoenixPalette.success)
        XCTAssertEqual(PhoenixDesign.defenseBarColor(60), PhoenixPalette.primary)
        XCTAssertEqual(PhoenixDesign.defenseBarColor(30), PhoenixPalette.primary)
        XCTAssertEqual(PhoenixDesign.defenseBarColor(29), PhoenixPalette.destructive)
        XCTAssertEqual(PhoenixDesign.defenseBarColor(0), PhoenixPalette.destructive)
    }

    // MARK: - PlanCategory.classify

    func testClassifyPrefersWorkoutOverOtherKeywords() {
        XCTAssertEqual(PlanCategory.classify(title: "Morning gym session", calendarName: nil), .workout)
        XCTAssertEqual(PlanCategory.classify(title: "5k run", calendarName: "Fitness"), .workout)
    }

    func testClassifyDetectsClassesBeforeWork() {
        XCTAssertEqual(PlanCategory.classify(title: "CS 101 Lecture", calendarName: "School"), .classes)
        XCTAssertEqual(PlanCategory.classify(title: "Midterm review", calendarName: nil), .classes)
    }

    func testClassifyFallsBackToPersonalWhenNoKeywordMatches() {
        XCTAssertEqual(PlanCategory.classify(title: "Dentist appointment", calendarName: nil), .personal)
    }

    func testClassifyUsesCalendarNameAsWellAsTitle() {
        // Title alone has no work keyword, but the calendar name does.
        XCTAssertEqual(PlanCategory.classify(title: "Weekly sync", calendarName: "Work"), .work)
    }

    // MARK: - PlanCategory.from(taskType:) legacy mapping

    func testFromTaskTypeMapsLegacyWellnessStrings() {
        XCTAssertEqual(PlanCategory.from(taskType: "physical"), .workout)
        XCTAssertEqual(PlanCategory.from(taskType: "recovery"), .recovery)
        XCTAssertEqual(PlanCategory.from(taskType: "work"), .work)
    }

    func testFromTaskTypeMapsCurrentCategoryStrings() {
        XCTAssertEqual(PlanCategory.from(taskType: "workout"), .workout)
        XCTAssertEqual(PlanCategory.from(taskType: "classes"), .classes)
        XCTAssertEqual(PlanCategory.from(taskType: "personal"), .personal)
    }

    func testFromTaskTypeFallsBackToPersonalForUnknownString() {
        XCTAssertEqual(PlanCategory.from(taskType: "made_up_type"), .personal)
    }

    func testFromTaskTypeIsCaseInsensitive() {
        XCTAssertEqual(PlanCategory.from(taskType: "WORKOUT"), .workout)
    }
}
