import Foundation
import SwiftData

/// The one user record — see `RizeTask.swift` for what `@Model` means. In
/// practice there's exactly one `UserProfile` row per person (this app has
/// no multi-user/account system), reached via `@Query` in the views that
/// need it. With CloudKit sync on, "one row" now means one *synced* row
/// shared across every device signed into the same iCloud account, rather
/// than one row per device — which is also why it's the one model in this
/// app that needs a dedupe safety net (`RootView.dedupeProfilesIfNeeded()`
/// in `RizeApp.swift`): CloudKit can't stop two devices from each creating
/// their own `UserProfile` during onboarding before their first sync
/// completes, since SwiftData has no equivalent of a SQL unique constraint.
@Model
final class UserProfile {
    // Explicit defaults on every attribute — required for CloudKit-backed
    // SwiftData sync (see `RizeTask` for the full explanation of why).
    // `createdAt` doubles as the tiebreaker `dedupeProfilesIfNeeded()` uses
    // to decide which of two synced-in duplicate rows to keep.
    var id: UUID = UUID()
    var name: String = ""
    var goal: String = "fitness" // fitness / productivity / both
    var goalDetail: String = ""
    var hasCompletedOnboarding: Bool = false
    var currentXP: Int = 0
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var bestXPDay: Int = 0
    var bestTasksCompletedInWeek: Int = 0
    var lastCheckInDate: Date?
    var notificationTime: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    var healthKitEnabled: Bool = false
    var calendarEnabled: Bool = false
    var unlockedAchievementsJSON: String = "[]"
    var createdAt: Date = Date()

    // In-app accessibility overrides, set during onboarding or from Profile →
    // Accessibility. These OR together with the system-wide Reduce Motion /
    // Reduce Transparency settings (see `AccessibilityPreferences.swift`) —
    // either source asking for less motion/transparency wins — so someone can
    // turn off Rize's decorative animations specifically without changing
    // every other app on their phone. Synced via CloudKit like everything
    // else on this model, so the preference follows the account across devices.
    var accessibilityReduceMotion: Bool = false
    var accessibilityReduceTransparency: Bool = false
    var accessibilityHighContrast: Bool = false

    // CloudKit rejects non-optional to-many relationships outright (even
    // with an array default) — the stored property must be `Optional` for
    // NSPersistentCloudKitContainer to accept the schema. `entries` below
    // is a computed passthrough so every existing call site can keep
    // treating it as a plain non-optional array.
    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.profile)
    private var _entries: [DailyEntry]? = []

    var entries: [DailyEntry] {
        get { _entries ?? [] }
        set { _entries = newValue }
    }

    init(
        name: String = "",
        goal: String = "fitness",
        goalDetail: String = "",
        accessibilityReduceMotion: Bool = false,
        accessibilityReduceTransparency: Bool = false,
        accessibilityHighContrast: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.goal = goal
        self.goalDetail = goalDetail
        self.hasCompletedOnboarding = false
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
        self.unlockedAchievementsJSON = "[]"
        self.createdAt = Date()
        self._entries = []
        self.accessibilityReduceMotion = accessibilityReduceMotion
        self.accessibilityReduceTransparency = accessibilityReduceTransparency
        self.accessibilityHighContrast = accessibilityHighContrast
    }

    var currentLevel: String {
        PhoenixDesign.tierInfo(for: currentXP).name
    }

    var progressPercentage: Double {
        let info = PhoenixDesign.tierInfo(for: currentXP)
        let current = Double(currentXP - info.minXP)
        let next = Double((info.nextMinXP ?? (info.minXP + 1000)) - info.minXP)
        guard next > 0 else { return 1.0 }
        return min(1.0, max(0.0, current / next))
    }

    // Unlocked achievement IDs are stored as a JSON-encoded string
    // (`unlockedAchievementsJSON`) rather than a native `[String]` property,
    // so this computed property is the typed access point: decode the JSON
    // back into an array on read, and `unlockAchievement` below re-encodes
    // it on write. `Data(unlockedAchievementsJSON.utf8)` is the standard way
    // to get from a `String` to the `Data` `JSONDecoder` requires — UTF-8 is
    // the encoding JSON is defined to use.
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

    /// Whether this person indicated any interest in sports/fitness during
    /// onboarding — used to decide whether the Home Screen Sports widget
    /// (`RizeSportsWidget`) shows real activity or a "set a goal" placeholder.
    /// Two ways in: they picked "Fitness"/"Both" on the goal page
    /// (`OnboardingView.goalPage`), OR — even under a "Productivity" goal —
    /// they picked or typed something sports-flavored on the follow-up
    /// detail page (`goalDetail`, a comma-joined string of preset chips like
    /// "Running, Sports" plus anything free-typed into "Add your own").
    /// `range(of:options: .caseInsensitive)` is a simple, dependency-free
    /// substring search — good enough for this heuristic without pulling in
    /// full tokenization/NLP for what's just a UI nicety.
    var hasSportsGoal: Bool {
        if goal == "fitness" || goal == "both" { return true }
        let keywords = [
            "run", "sport", "gym", "strength", "cycle", "cycling", "bike",
            "swim", "yoga", "workout", "fitness", "training", "marathon",
            "soccer", "basketball", "tennis", "hike", "hiking", "climb",
            "row", "crossfit", "pilates", "walk"
        ]
        return keywords.contains { goalDetail.range(of: $0, options: .caseInsensitive) != nil }
    }
}
