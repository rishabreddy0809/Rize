import SwiftUI

struct AchievementDefinition: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    /// Asset name of a still frame lifted from the phoenix's own animations
    /// (flight, idle, tier-evolution, ember/ash), picked per-badge so the
    /// badge grid reads as a set of distinct moments, not one mascot repeated.
    let mascotImage: String
}

@MainActor
final class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    private init() {}

    static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "first_task",
            title: "FIRST BLOOD",
            description: "Complete your first task.",
            icon: "bolt.fill",
            color: .orange,
            mascotImage: "PhoenixBadge_FirstBlood"
        ),
        AchievementDefinition(
            id: "siege_survivor",
            title: "RISING FROM ASH",
            description: "Reignite your flame by completing a task during Ash State.",
            icon: "shield.fill",
            color: PhoenixPalette.destructive,
            mascotImage: "PhoenixBadge_RisingFromAsh"
        ),
        AchievementDefinition(
            id: "low_energy_warrior",
            title: "LOW ENERGY WARRIOR",
            description: "Complete all tasks on a 1-3 energy day.",
            icon: "flame.fill",
            color: .yellow,
            mascotImage: "PhoenixBadge_LowEnergy"
        ),
        AchievementDefinition(
            id: "iron_will",
            title: "IRON WILL",
            description: "Reach a 7-day streak.",
            icon: "calendar.badge.checkmark",
            color: .blue,
            mascotImage: "PhoenixBadge_IronWill"
        ),
        AchievementDefinition(
            id: "realm_defender",
            title: "FLAME KEEPER",
            description: "Keep your Phoenix Vitality at 100% for 7 days.",
            icon: "shield.lefthalf.filled",
            color: PhoenixPalette.success,
            mascotImage: "PhoenixBadge_FlameKeeper"
        ),
        AchievementDefinition(
            id: "gold_hoarder",
            title: "PRODUCTIVITY SURGE",
            description: "Complete 25 tasks in a single week.",
            icon: "bolt.badge.clock.fill",
            color: .yellow,
            mascotImage: "PhoenixBadge_ProductivitySurge"
        ),
        AchievementDefinition(
            id: "unstoppable",
            title: "UNSTOPPABLE",
            description: "Reach the Eternal tier.",
            icon: "sparkles",
            color: PhoenixPalette.eternal,
            mascotImage: "PhoenixBadge_Unstoppable"
        ),
        AchievementDefinition(
            id: "ghost_mode",
            title: "GHOST MODE",
            description: "Log your energy after midnight.",
            icon: "moon.stars.fill",
            color: .indigo,
            mascotImage: "PhoenixBadge_GhostMode"
        ),
        AchievementDefinition(
            id: "perfect_week",
            title: "PERFECT WEEK",
            description: "Complete tasks 7 days in a row.",
            icon: "star.fill",
            color: .cyan,
            mascotImage: "PhoenixBadge_PerfectWeek"
        ),
        AchievementDefinition(
            id: "comeback_kid",
            title: "COMEBACK KID",
            description: "Earn a comeback bonus.",
            icon: "arrow.up.heart.fill",
            color: .pink,
            mascotImage: "PhoenixBadge_ComebackKid"
        )
    ]

    // MARK: - Check Achievements

    /// Evaluates every achievement condition and unlocks any newly-earned ones.
    /// Returns them in a stable order — the caller (TodayView) is responsible for
    /// celebrating them one at a time, since presenting multiple full-screen
    /// unlock celebrations at once is what caused the overlapping-overlay glitch.
    @discardableResult
    func check(profile: UserProfile, entry: DailyEntry?, xpManager: XPManager) -> [AchievementDefinition] {
        var newlyUnlocked: [AchievementDefinition] = []

        func consider(_ id: String, _ condition: Bool) {
            guard condition, profile.unlockAchievement(id) else { return }
            if let def = AchievementManager.all.first(where: { $0.id == id }) {
                newlyUnlocked.append(def)
            }
        }

        consider("first_task", (entry?.tasksCompleted ?? 0) >= 1)
        consider("siege_survivor", xpManager.showSiegeBrokenBanner)

        let lowEnergyDayDone = entry.map { $0.isFullyComplete && ($0.energyScore ?? .max) <= 3 } ?? false
        consider("low_energy_warrior", lowEnergyDayDone)

        consider("iron_will", profile.currentStreak >= 7)

        let history = xpManager.defenseHistory
        consider("realm_defender", history.count >= 7 && history.suffix(7).allSatisfy { $0.defended })

        consider("gold_hoarder", profile.bestTasksCompletedInWeek >= 25)
        consider("unstoppable", profile.currentXP >= 7001)

        let hour = Calendar.current.component(.hour, from: Date())
        consider("ghost_mode", hour >= 0 && hour < 4 && entry?.energyScore != nil)

        consider("perfect_week", profile.currentStreak >= 7)
        consider("comeback_kid", entry?.comebackBonusApplied == true)

        return newlyUnlocked
    }
}
