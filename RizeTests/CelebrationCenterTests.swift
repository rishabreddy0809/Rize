import XCTest
import SwiftUI
@testable import Rize

/// `CelebrationCenter` guarantees only one full-screen celebration is ever
/// shown at a time, queuing the rest — this is what stops an achievement
/// unlock and an all-done banner from stacking and glitching when they fire
/// off the same task completion. `.shared` is a true process-wide singleton
/// with no reset hook, so this is written as one linear sequence rather than
/// independent test methods, to avoid one test's leftover state bleeding
/// into the next.
@MainActor
final class CelebrationCenterTests: XCTestCase {

    func testCelebrationQueueHoldsOneActiveAndAdvancesInOrder() async throws {
        let center = CelebrationCenter.shared

        // Start from a clean slate regardless of what earlier tests left behind.
        while center.active != nil {
            center.dismissActive()
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        XCTAssertNil(center.active)

        let achievement = AchievementDefinition(
            id: "test_first_blood", title: "First Blood", description: "Test",
            icon: "star.fill", color: .yellow, mascotImage: "phoenix_000"
        )
        center.enqueue(.allDone(xp: 100, streak: 3))
        XCTAssertEqual(center.active?.id, "allDone", "the queue was empty, so this should become active immediately")

        center.enqueue(.achievement(achievement))
        XCTAssertEqual(center.active?.id, "allDone", "a celebration is already active — the new one must wait in the queue, not pre-empt it")

        center.dismissActive()
        XCTAssertNil(center.active, "dismissing clears the active slot immediately")

        // `advance()` to the next queued item is deliberately delayed ~350ms
        // so the next celebration's backdrop doesn't appear mid-fade of the last.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(center.active?.id, "achievement-test_first_blood", "the queued achievement should now be active")

        center.dismissActive()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(center.active, "queue is empty — nothing left to advance to")
    }

    func testDayCelebrationIdsAreStableAndDistinctPerAchievement() {
        let a = AchievementDefinition(id: "a", title: "A", description: "", icon: "star", color: .yellow, mascotImage: "phoenix_000")
        let b = AchievementDefinition(id: "b", title: "B", description: "", icon: "star", color: .yellow, mascotImage: "phoenix_000")

        XCTAssertEqual(DayCelebration.achievement(a).id, "achievement-a")
        XCTAssertNotEqual(DayCelebration.achievement(a).id, DayCelebration.achievement(b).id)
        XCTAssertEqual(DayCelebration.allDone(xp: 1, streak: 1).id, DayCelebration.allDone(xp: 999, streak: 999).id, "id should only depend on the case, not its payload")
    }
}
