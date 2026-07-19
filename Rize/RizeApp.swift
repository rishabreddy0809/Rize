import SwiftUI
import SwiftData

@main
struct RizeApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var xpManager = XPManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var achievementManager = AchievementManager.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([UserProfile.self, DailyEntry.self, RizeTask.self])
        let configuration = ModelConfiguration(schema: schema)

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
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(subscriptionManager)
            .environmentObject(xpManager)
            .environmentObject(notificationManager)
            .environmentObject(achievementManager)
            .preferredColorScheme(.dark)
            .onAppear {
                Task { @MainActor in
                    NotificationManager.shared.registerCategories()
                    await HealthKitManager.shared.requestAuthorization()
                    await CalendarManager.shared.requestAuthorization()
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                    xpManager.checkDayChange(completedCount: 0, energyScore: 5)
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
