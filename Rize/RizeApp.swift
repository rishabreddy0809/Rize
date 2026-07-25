import SwiftUI
import SwiftData

/// The app's entry point — `@main` is what tells Swift "start the program by
/// creating this type," the same role `RizeWidgetBundle` plays over in the
/// widget extension. Conforming to `App` (rather than a UIKit
/// `AppDelegate`/`SceneDelegate` pair) is SwiftUI's app lifecycle: you
/// describe the app as data (a `Scene` graph) instead of imperatively
/// wiring up a window yourself, and SwiftUI drives the actual UIKit/AppKit
/// machinery underneath.
@main
struct RizeApp: App {
    // `@StateObject` here (as opposed to `@ObservedObject`) is what tells
    // SwiftUI "this app instance owns these objects' lifetimes" — each is
    // created exactly once, when `RizeApp` itself is created, and survives
    // for the whole run of the app rather than being recreated whenever this
    // struct's `body` re-evaluates (which happens often; SwiftUI `App`/`View`
    // types are lightweight value types re-created on every relevant state
    // change, but `@StateObject`'s underlying storage persists across that).
    // `.shared` on each manager is the actual singleton; wrapping it in
    // `@StateObject` is what makes SwiftUI watch it via `ObservableObject`
    // and re-render dependent views when its `@Published` properties change.
    @StateObject private var xpManager = XPManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var achievementManager = AchievementManager.shared

    // SwiftData's `ModelContainer` is the actual on-disk database — the
    // thing that owns the SQLite store backing every `@Model` class (see
    // `RizeTask.swift`, `DailyEntry.swift`, `UserProfile.swift`). `Schema`
    // lists which `@Model` types that store needs to have tables for, and
    // `ModelConfiguration` describes *how* to store them (in-memory vs. on
    // disk, which file, etc.).
    //
    // --- CloudKit sync, in plain terms ---
    // `cloudKitDatabase: .automatic` is the one line that turns this from a
    // device-only SQLite file into a synced store. Under the hood, SwiftData
    // is layering Core Data's `NSPersistentCloudKitContainer` machinery on
    // top of the same store: every local write is queued and mirrored up to
    // this app's **private CloudKit database** (one per iCloud account, not
    // shared between users — nobody else can read it), and a background
    // long-lived CloudKit subscription pushes down changes made from any
    // other device signed into that same account. `.automatic` just means
    // "use the container named after this app's bundle ID" (here,
    // `iCloud.com.RishabReddy.RizeApp`, declared in `Rize.entitlements`) —
    // the alternative is passing an explicit `CKContainer` if you needed a
    // custom or shared container name.
    // Conflict resolution is field-level, not row-level: if the same
    // `UserProfile` row is edited offline on two devices, CloudKit doesn't
    // pick "device A's whole row" or "device B's whole row" — it merges
    // per-property using last-writer-wins timestamps, so a name change on
    // one device and an XP change on another both survive. What it can't
    // resolve is two *separate rows* meaning the same thing (e.g. two
    // `UserProfile`s from onboarding on two devices) — that's a duplicate,
    // not a conflict, and `RootView.dedupeProfilesIfNeeded()` below handles
    // it by hand.
    // Sync requires every `@Model` attribute to be optional or have a
    // default value, and every to-one relationship to be optional —
    // CloudKit's schema has no concept of a required field the way SQL
    // does, since a row can always arrive from another device mid-sync
    // before every property has been filled in. That's why
    // `RizeTask`/`DailyEntry`/`UserProfile` all declare defaults inline now
    // instead of leaving that to their `init`s.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([UserProfile.self, DailyEntry.self, RizeTask.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Schema changed and the on-disk store can't be lightweight-migrated.
            // Wipe the stale store and recreate it rather than crashing.
            let storeURL = configuration.url
            for path in [storeURL.path, storeURL.path + "-wal", storeURL.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(xpManager)
                .environmentObject(notificationManager)
                .environmentObject(achievementManager)
                .preferredColorScheme(.dark)
                .onAppear {
                Task { @MainActor in
                    NotificationManager.shared.registerCategories()
                    // Health data only powers planning for fitness/both goals — a
                    // "productivity" goal never asked for it during onboarding, so
                    // re-requesting it on every relaunch would surface the same
                    // permission prompt out of nowhere.
                    let goal = (try? sharedModelContainer.mainContext.fetch(FetchDescriptor<UserProfile>()))?.first?.goal
                    if goal == "fitness" || goal == "both" {
                        await HealthKitManager.shared.requestAuthorization()
                    }
                    await CalendarManager.shared.requestAuthorization()
                    // Day-change evaluation happens in `TodayView.onAppear`,
                    // not here — it needs to fetch the actual previous day's
                    // `DailyEntry` from SwiftData to know whether that day was
                    // really completed, which requires being in a view with
                    // a `modelContext`. Calling `checkDayChange` here too,
                    // with fabricated data, would just win the race (this
                    // runs before Today's tab appears) and permanently mark
                    // every day transition as a miss regardless of what
                    // actually happened.
                }
            }
        }
        // `.modelContainer(_:)` is what actually connects the container built
        // above to the view hierarchy — it injects the container's
        // `mainContext` into the SwiftUI environment, which is how views
        // deeper in the tree get their `@Environment(\.modelContext)` and
        // `@Query` property wrappers wired up for free, without every view
        // needing the container passed to it explicitly.
        .modelContainer(sharedModelContainer)
    }
}

/// Routes between onboarding and the main app. Reads straight off the
/// `UserProfile` model (`hasCompletedOnboarding`) instead of an
/// `@AppStorage`/`UserDefaults` flag, since `UserDefaults` is per-device and
/// wouldn't reflect onboarding completed on another synced device — the
/// model field syncs via CloudKit along with everything else.
private struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if profiles.first(where: { $0.hasCompletedOnboarding }) != nil {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .rizeAccessibilityRoot(profile: profiles.first(where: { $0.hasCompletedOnboarding }) ?? profiles.first)
        .onAppear { dedupeProfilesIfNeeded() }
        .onChange(of: profiles.count) { _, _ in dedupeProfilesIfNeeded() }
    }

    /// CloudKit sync can briefly leave more than one `UserProfile` row on a
    /// device — e.g. onboarding completed on two devices before their first
    /// sync — since SwiftData/CloudKit doesn't support unique constraints to
    /// prevent that at write time. This reconciles after the fact: the
    /// oldest profile (first created) wins, every other row's entries are
    /// folded into it (rather than dropped) and its best-of stats are
    /// merged in, then the stray row is deleted.
    private func dedupeProfilesIfNeeded() {
        guard profiles.count > 1 else { return }
        let sorted = profiles.sorted { $0.createdAt < $1.createdAt }
        guard let keeper = sorted.first else { return }

        for stray in sorted.dropFirst() {
            for entry in stray.entries {
                entry.profile = keeper
            }
            keeper.currentXP = max(keeper.currentXP, stray.currentXP)
            keeper.bestStreak = max(keeper.bestStreak, stray.bestStreak)
            keeper.bestXPDay = max(keeper.bestXPDay, stray.bestXPDay)
            keeper.bestTasksCompletedInWeek = max(keeper.bestTasksCompletedInWeek, stray.bestTasksCompletedInWeek)
            modelContext.delete(stray)
        }
        try? modelContext.save()
    }
}
