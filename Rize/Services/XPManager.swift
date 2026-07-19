import SwiftUI
import Foundation

struct TaskCompletionResult {
    let xpDelta: Int
    let leveledUp: Bool
    let allTasksDone: Bool
    let siegeBroken: Bool
    let bonusXP: Int
}

struct DefenseDay: Codable {
    let date: String
    let defended: Bool
}

@MainActor
final class XPManager: ObservableObject {
    static let shared = XPManager()

    // MARK: - AppStorage (kingdom_ prefix)
    @AppStorage("kingdom_gold") var gold: Int = 50
    @AppStorage("kingdom_realmDefense") var realmDefense: Int = 100
    @AppStorage("kingdom_isUnderSiege") var isUnderSiege: Bool = false
    @AppStorage("kingdom_lastCheckedDate") var lastCheckedDate: String = ""
    @AppStorage("kingdom_fortificationPoints") var fortificationPoints: Int = 0
    @AppStorage("kingdom_defenseHistoryJSON") var defenseHistoryJSON: String = "[]"
    @AppStorage("kingdom_totalXP") var totalXP: Int = 0
    @AppStorage("kingdom_lastTierIndex") private var lastTierIndex: Int = 0

    // MARK: - Published
    @Published var showSiegeBrokenBanner: Bool = false
    @Published var siegeBrokenMessage: String = ""
    @Published var showSiegeFlash: Bool = false
    @Published var castleBounce: Bool = false
    @Published var triggerGoldBurst: Bool = false
    @Published var showTierUpgrade: Bool = false
    @Published var tierUpgradeName: String = ""

    private init() {}

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String {
        XPManager.dateFormatter.string(from: Date())
    }

    // MARK: - Sync XP from profile

    func syncTotalXP(_ xp: Int) {
        let oldTier = lastTierIndex
        totalXP = xp

        let tiers = KingdomDesign.tiers
        var newTierIndex = 0
        for (i, tier) in tiers.enumerated() {
            if xp >= tier.minXP { newTierIndex = i }
        }

        if newTierIndex > oldTier {
            lastTierIndex = newTierIndex
            tierUpgradeName = tiers[newTierIndex].name
            withAnimation(Constants.springAnimation) {
                showTierUpgrade = true
                castleBounce = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { showTierUpgrade = false }
            }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                castleBounce = false
            }
        }
    }

    // MARK: - Reset

    /// Restores all kingdom state to a fresh install (used by the debug reset).
    func resetAll() {
        gold = 50
        realmDefense = 100
        isUnderSiege = false
        lastCheckedDate = ""
        fortificationPoints = 0
        defenseHistoryJSON = "[]"
        totalXP = 0
        lastTierIndex = 0
    }

    // MARK: - Day change

    func checkDayChange(completedCount: Int, energyScore: Int) {
        let today = todayKey
        if lastCheckedDate.isEmpty {
            lastCheckedDate = today
            return
        }
        guard lastCheckedDate != today else { return }
        processDayChange(completedCount: completedCount, energyScore: energyScore)
        lastCheckedDate = today
        realmDefense = 100
    }

    private func processDayChange(completedCount: Int, energyScore: Int) {
        if completedCount == 0 {
            isUnderSiege = true
            realmDefense = max(0, realmDefense - 25)
            gold = max(0, gold - 10)
            appendDefenseHistory(defended: false)
        } else {
            let energyBonus = energyScore <= 3 ? 15 : 0
            fortificationPoints += completedCount * 10 + energyBonus
            realmDefense = min(100, realmDefense + 10)
            appendDefenseHistory(defended: true)
        }
    }

    private func appendDefenseHistory(defended: Bool) {
        var history = defenseHistory
        history.append(DefenseDay(date: todayKey, defended: defended))
        if history.count > 7 { history = Array(history.suffix(7)) }
        if let data = try? JSONEncoder().encode(history),
           let str = String(data: data, encoding: .utf8) {
            defenseHistoryJSON = str
        }
    }

    var defenseHistory: [DefenseDay] {
        (try? JSONDecoder().decode([DefenseDay].self, from: Data(defenseHistoryJSON.utf8))) ?? []
    }

    // MARK: - Task completion

    func executeTaskCompletion(xp: Int, energyScore: Int) -> (siegeBroken: Bool, bonusXP: Int) {
        var bonusXP = 0
        var siegeBroken = false

        if isUnderSiege {
            isUnderSiege = false
            realmDefense = 100
            bonusXP = energyScore <= 3 ? 30 : 15
            gold += 20
            siegeBroken = true
            triggerSiegeBrokenUI(bonusXP: bonusXP, energyScore: energyScore)
        } else {
            gold += 5
        }

        withAnimation(Constants.springAnimation) {
            triggerGoldBurst = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            triggerGoldBurst = false
        }

        return (siegeBroken, bonusXP)
    }

    private func triggerSiegeBrokenUI(bonusXP: Int, energyScore: Int) {
        siegeBrokenMessage = RyzDialogue.siegeBrokenMessage(bonusXP: bonusXP)
        withAnimation(Constants.springAnimation) {
            showSiegeFlash = true
            showSiegeBrokenBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation { showSiegeFlash = false }
        }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { showSiegeBrokenBanner = false }
        }
    }

    // MARK: - Full task completion with profile update

    func applyTaskCompletion(entry: DailyEntry, profile: UserProfile) -> TaskCompletionResult {
        let energy = entry.energyScore ?? 5
        let xpForTask = calculateXPForTask(energyScore: energy, streak: profile.currentStreak)

        let oldXP = profile.currentXP
        profile.currentXP += xpForTask
        entry.xpEarned += xpForTask

        let tierBefore = KingdomDesign.tierInfo(for: oldXP).name
        let tierAfter = KingdomDesign.tierInfo(for: profile.currentXP).name
        let leveledUp = tierBefore != tierAfter

        updateStreak(profile: profile, completedCount: entry.tasksCompleted)

        if profile.currentXP > profile.bestXPDay {
            profile.bestXPDay = profile.currentXP
        }

        let allDone = entry.isFullyComplete
        if allDone {
            profile.currentXP += Constants.allTasksBonus
            entry.xpEarned += Constants.allTasksBonus
        }

        let siegeResult = executeTaskCompletion(xp: xpForTask, energyScore: energy)
        syncTotalXP(profile.currentXP)

        return TaskCompletionResult(
            xpDelta: xpForTask + (allDone ? Constants.allTasksBonus : 0) + siegeResult.bonusXP,
            leveledUp: leveledUp,
            allTasksDone: allDone,
            siegeBroken: siegeResult.siegeBroken,
            bonusXP: siegeResult.bonusXP
        )
    }

    // MARK: - XP Calculation

    func energyMultiplier(for energy: Int) -> Double {
        switch energy {
        case 1...3: return Constants.lowEnergyMultiplier
        case 4...6: return Constants.mediumEnergyMultiplier
        default: return Constants.highEnergyMultiplier
        }
    }

    func calculateXPForTask(energyScore: Int, streak: Int) -> Int {
        let base = Double(Constants.baseXPPerTask)
        let multiplied = Int(base * energyMultiplier(for: energyScore))
        let bonus = streak >= 7 ? Constants.streakBonus : 0
        return multiplied + bonus
    }

    // MARK: - Streak

    func updateStreak(profile: UserProfile, completedCount: Int) {
        guard completedCount >= 1 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = profile.lastCheckInDate {
            let lastDay = calendar.startOfDay(for: last)
            let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                profile.currentStreak += 1
            } else if diff > 1 {
                profile.currentStreak = 1
            }
            // diff == 0: same day, no change
        } else {
            profile.currentStreak = 1
        }

        if profile.currentStreak > profile.bestStreak {
            profile.bestStreak = profile.currentStreak
        }

        profile.lastCheckInDate = Date()
    }
}
