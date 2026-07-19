import SwiftUI

struct AchievementDefinition: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
}

@MainActor
final class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    @Published var recentlyUnlocked: AchievementDefinition? = nil

    private init() {}

    static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "first_task",
            title: "FIRST BLOOD",
            description: "Complete your first task.",
            icon: "bolt.fill",
            color: .orange
        ),
        AchievementDefinition(
            id: "siege_survivor",
            title: "RISING FROM ASH",
            description: "Reignite your flame by completing a task during Ash State.",
            icon: "shield.fill",
            color: PhoenixPalette.destructive
        ),
        AchievementDefinition(
            id: "low_energy_warrior",
            title: "LOW ENERGY WARRIOR",
            description: "Complete all tasks on a 1-3 energy day.",
            icon: "flame.fill",
            color: .yellow
        ),
        AchievementDefinition(
            id: "iron_will",
            title: "IRON WILL",
            description: "Reach a 7-day streak.",
            icon: "calendar.badge.checkmark",
            color: .blue
        ),
        AchievementDefinition(
            id: "realm_defender",
            title: "FLAME KEEPER",
            description: "Keep your Phoenix Vitality at 100% for 7 days.",
            icon: "shield.lefthalf.filled",
            color: PhoenixPalette.success
        ),
        AchievementDefinition(
            id: "gold_hoarder",
            title: "GOLD HOARDER",
            description: "Accumulate 500 gold.",
            icon: "dollarsign.circle.fill",
            color: .yellow
        ),
        AchievementDefinition(
            id: "unstoppable",
            title: "UNSTOPPABLE",
            description: "Reach the Eternal tier.",
            icon: "sparkles",
            color: PhoenixPalette.eternal
        ),
        AchievementDefinition(
            id: "ghost_mode",
            title: "GHOST MODE",
            description: "Log your energy after midnight.",
            icon: "moon.stars.fill",
            color: .indigo
        ),
        AchievementDefinition(
            id: "perfect_week",
            title: "PERFECT WEEK",
            description: "Complete tasks 7 days in a row.",
            icon: "star.fill",
            color: .cyan
        ),
        AchievementDefinition(
            id: "comeback_kid",
            title: "COMEBACK KID",
            description: "Earn a comeback bonus.",
            icon: "arrow.up.heart.fill",
            color: .pink
        )
    ]

    // MARK: - Check Achievements

    func check(profile: UserProfile, entry: DailyEntry?, xpManager: XPManager) {
        // First task
        if (entry?.tasksCompleted ?? 0) >= 1 {
            unlock("first_task", profile: profile)
        }

        // Siege survivor
        if xpManager.showSiegeBrokenBanner {
            unlock("siege_survivor", profile: profile)
        }

        // Low energy warrior
        if let e = entry, e.isFullyComplete, let energy = e.energyScore, energy <= 3 {
            unlock("low_energy_warrior", profile: profile)
        }

        // Iron will (7-day streak)
        if profile.currentStreak >= 7 {
            unlock("iron_will", profile: profile)
        }

        // Realm defender (defense 100% for 7 days)
        let history = xpManager.defenseHistory
        if history.count >= 7 && history.suffix(7).allSatisfy({ $0.defended }) {
            unlock("realm_defender", profile: profile)
        }

        // Gold hoarder
        if xpManager.gold >= 500 {
            unlock("gold_hoarder", profile: profile)
        }

        // Unstoppable (Eternal tier = 7001+ XP)
        if profile.currentXP >= 7001 {
            unlock("unstoppable", profile: profile)
        }

        // Ghost mode (after midnight)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 0 && hour < 4 && entry?.energyScore != nil {
            unlock("ghost_mode", profile: profile)
        }

        // Perfect week
        if profile.currentStreak >= 7 {
            unlock("perfect_week", profile: profile)
        }

        // Comeback kid
        if entry?.comebackBonusApplied == true {
            unlock("comeback_kid", profile: profile)
        }
    }

    @discardableResult
    private func unlock(_ id: String, profile: UserProfile) -> Bool {
        let wasNew = profile.unlockAchievement(id)
        if wasNew, let def = AchievementManager.all.first(where: { $0.id == id }) {
            recentlyUnlocked = def
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if recentlyUnlocked?.id == id {
                    recentlyUnlocked = nil
                }
            }
        }
        return wasNew
    }
}
