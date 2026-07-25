import Foundation

/// The slice of Phoenix state widgets need — written by the main app on every
/// state change that could affect a widget, read by the widget extension's
/// timeline provider. Foundation-only (no SwiftUI/SwiftData) so this single
/// file can compile unmodified into both the app and widget extension targets.
struct RizeWidgetTask: Codable, Identifiable {
    var id: String
    var title: String
    var completed: Bool
}

/// One recent workout, trimmed to just what `RizeSportsWidget` displays —
/// pre-formatted strings rather than raw numbers, so the widget doesn't need
/// any of `WorkoutSummary`'s formatting logic (`formattedMovingTime`,
/// `distanceMiles`, …) duplicated into the extension target.
struct RizeWidgetWorkout: Codable, Identifiable {
    var id: String
    /// Human-readable activity type, e.g. "Run", "Ride" — also used to pick
    /// an SF Symbol in the widget view.
    var type: String
    /// e.g. "3.1 mi · 28m" or, for a non-distance workout, just "45m".
    var subtitle: String
    /// e.g. "Today", "Yesterday", "3d ago".
    var relativeDay: String
}

struct RizeWidgetSnapshot: Codable {
    var streak: Int
    var totalXP: Int
    var vitality: Int // realmDefense, 0-100
    var isUnderSiege: Bool
    var tierName: String
    var tierColorHex: String
    var lastUpdated: Date
    var tasksCompleted: Int = 0
    var totalTasks: Int = 0
    /// Today's plan, trimmed to what the largest widget can show — incomplete
    /// tasks first, capped well below SwiftData's full task list.
    var tasks: [RizeWidgetTask] = []
    /// Whether this person indicated a sports/fitness interest during
    /// onboarding (`UserProfile.hasSportsGoal`) — `RizeSportsWidget` shows an
    /// empty "set a goal" state instead of `recentWorkouts` when this is
    /// false. WidgetKit itself can't hide a widget kind from the Home
    /// Screen's "Add Widget" gallery based on app data, so this only
    /// controls what the widget *shows*, not whether it can be added.
    var sportsGoalEnabled: Bool = false
    /// Most recent workouts, newest first, already trimmed to what the
    /// widget can show.
    var recentWorkouts: [RizeWidgetWorkout] = []

    static let placeholder = RizeWidgetSnapshot(
        streak: 4,
        totalXP: 620,
        vitality: 85,
        isUnderSiege: false,
        tierName: "AWAKENING",
        tierColorHex: "F5A623",
        lastUpdated: Date(),
        tasksCompleted: 2,
        totalTasks: 5,
        tasks: [
            RizeWidgetTask(id: "1", title: "Morning run — 3 mi", completed: true),
            RizeWidgetTask(id: "2", title: "Deep work block", completed: true),
            RizeWidgetTask(id: "3", title: "Mobility stretch", completed: false),
            RizeWidgetTask(id: "4", title: "Read 20 pages", completed: false),
            RizeWidgetTask(id: "5", title: "Plan tomorrow", completed: false)
        ],
        sportsGoalEnabled: true,
        recentWorkouts: [
            RizeWidgetWorkout(id: "1", type: "Run", subtitle: "3.1 mi · 28m", relativeDay: "Today"),
            RizeWidgetWorkout(id: "2", type: "Ride", subtitle: "12.4 mi · 45m", relativeDay: "Yesterday"),
            RizeWidgetWorkout(id: "3", type: "Strength", subtitle: "50m", relativeDay: "3d ago")
        ]
    )
}

/// Shared storage for the widget snapshot, backed by an App Group container so
/// both the host app and the widget extension process can read/write it.
///
/// The app (`com.RishabReddy.RizeApp`) and the widget extension
/// (`com.RishabReddy.RizeApp.RizeWidget`) are two separate processes, each
/// normally sandboxed into its own private container — `UserDefaults.standard`
/// inside the widget extension would NOT see anything the app writes to its
/// own `UserDefaults.standard`, because those resolve to two different files
/// on disk. An App Group is Apple's mechanism for punching a deliberate hole
/// in that isolation: both targets declare the same group identifier in
/// their entitlements (see `Rize.entitlements` and
/// `RizeWidgetExtension.entitlements`, both listing
/// `group.com.RishabReddy.RizeApp`), and `UserDefaults(suiteName:)` — instead
/// of `.standard` — then points at a *shared* container both processes can
/// read and write.
///
/// `UserDefaults` only natively stores simple property-list types (numbers,
/// strings, dates, arrays/dicts of those) — not arbitrary Swift structs like
/// `RizeWidgetSnapshot`. So `save`/`load` bridge that gap manually: encode
/// the whole struct to JSON `Data` (which *is* a storable type) with
/// `Codable`, and decode it back out on the other side.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.RishabReddy.RizeApp"
    private static let key = "rize_widget_snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: RizeWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> RizeWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RizeWidgetSnapshot.self, from: data)
    }
}
