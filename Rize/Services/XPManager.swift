import SwiftUI
import Foundation
import WidgetKit

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
    /// Actual Phoenix Vitality (0-100) at the end of this day. `defended`
    /// alone only means "at least one task was completed that day" — not
    /// that vitality actually reached 100% — which silently broke the
    /// "realm_defender" (FLAME KEEPER) achievement's real intent ("keep
    /// vitality at 100% for 7 days"). Optional so history JSON persisted
    /// before this field existed still decodes (missing key -> nil).
    var defenseValue: Int? = nil
}

@MainActor
final class XPManager: ObservableObject {
    static let shared = XPManager()

    // MARK: - AppStorage (kingdom_ prefix)
    @AppStorage("kingdom_realmDefense") var realmDefense: Int = 100
    @AppStorage("kingdom_isUnderSiege") var isUnderSiege: Bool = false
    @AppStorage("kingdom_lastCheckedDate") var lastCheckedDate: String = ""
    /// Consecutive fully-missed days (0 tasks completed), reset the moment a
    /// day has at least one completion. Drives `isUnderSiege` — see
    /// `Self.siegeThreshold` in `processDayChange`.
    @AppStorage("kingdom_missedDayStreak") var missedDayStreak: Int = 0
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

    @Published var dailyPlan: DailyPlan = DailyPlan(
        recommendedTasks: [],
        deferredTasks: [],
        workblockTasks: [],
        workout: WorkoutRecommendation(intent: .rest, rationale: []),
        recovery: RecoveryRecommendation(emphasis: .none, rationale: []),
        workload: .light,
        confidence: 0.0,
        burnoutRisk: .low,
        rationale: [],
        generatedAt: Date()
    )

    private init() {}

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String {
        XPManager.dateFormatter.string(from: Date())
    }

    // MARK: - Daily plan

    func updateDailyPlan(_ newPlan: DailyPlan) {
        dailyPlan = newPlan
    }

    // MARK: - Debug

    /// Jumps straight to a tier for QA — sets `totalXP` to that tier's floor
    /// and `lastTierIndex` directly (no tier-up banner/animation, and no
    /// clamping to "only moves forward" the way `syncTotalXP` does, since
    /// testing needs to move down tiers too). Never called from production
    /// gameplay code paths — only the debug picker in `ProfileView`.
    func setDebugTier(index: Int) {
        let tiers = PhoenixDesign.tiers
        let clampedIndex = min(max(index, 0), tiers.count - 1)
        totalXP = tiers[clampedIndex].minXP
        lastTierIndex = clampedIndex
    }

    // MARK: - Sync XP from profile

    func syncTotalXP(_ xp: Int) {
        let oldTier = lastTierIndex
        totalXP = xp

        let tiers = PhoenixDesign.tiers
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
        realmDefense = 100
        isUnderSiege = false
        lastCheckedDate = ""
        missedDayStreak = 0
        fortificationPoints = 0
        defenseHistoryJSON = "[]"
        totalXP = 0
        lastTierIndex = 0
        WidgetSnapshotStore.save(.placeholder)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Widget Snapshot

    /// Publishes the current Phoenix state to the shared App Group store and
    /// nudges WidgetKit to redraw. Called on launch and after any completion
    /// that changes streak/XP/vitality — streak lives on `UserProfile`
    /// (SwiftData), not here, so callers pass it in.
    func refreshWidgetSnapshot(
        streak: Int,
        tasks: [RizeTask] = [],
        sportsGoalEnabled: Bool = false,
        recentWorkouts: [WorkoutSummary] = []
    ) {
        let tier = PhoenixDesign.tierInfo(for: totalXP)
        let hex: String
        switch tier.index {
        case 0: hex = "C8B89A" // ash
        case 1: hex = "F5A623" // awakening
        case 2: hex = "E8724A" // rising
        case 3: hex = "FFB830" // radiant
        default: hex = "FFD700" // eternal
        }
        // Incomplete tasks first (what the large widget's checklist is for),
        // capped well under the large widget's usable height. `sorted(by:)`
        // takes a closure answering "should the first argument sort before
        // the second?" — this returns true exactly when $0 is incomplete AND
        // $1 is already done, which is enough to push every incomplete task
        // ahead of every completed one without needing a full comparable key.
        let maxWidgetTasks = 6
        let sortedTasks = tasks.sorted { !$0.completed && $1.completed }
        let widgetTasks = sortedTasks.prefix(maxWidgetTasks).map {
            RizeWidgetTask(id: $0.id.uuidString, title: $0.title, completed: $0.completed)
        }
        // 8, not 4 — the large widget falls back to a longer workout list
        // (rather than a route map) when nothing recent has GPS data, so it
        // needs more than the map layout ever shows at once.
        let maxWidgetWorkouts = 8
        let widgetWorkouts = recentWorkouts
            .sorted { $0.startDate > $1.startDate }
            .prefix(maxWidgetWorkouts)
            .map { workout in
                RizeWidgetWorkout(
                    id: workout.id.uuidString,
                    type: workout.type,
                    subtitle: workoutSubtitle(workout),
                    relativeDay: relativeDayLabel(workout.startDate),
                    route: Self.thinnedRoute(workout.routeCoordinates)
                )
            }
        WidgetSnapshotStore.save(RizeWidgetSnapshot(
            streak: streak,
            totalXP: totalXP,
            vitality: realmDefense,
            isUnderSiege: isUnderSiege,
            tierName: tier.name,
            tierColorHex: hex,
            lastUpdated: Date(),
            tasksCompleted: tasks.filter(\.completed).count,
            totalTasks: tasks.count,
            tasks: Array(widgetTasks),
            sportsGoalEnabled: sportsGoalEnabled,
            recentWorkouts: Array(widgetWorkouts)
        ))
        // `reloadAllTimelines()` is the app's way of telling WidgetKit "the
        // data changed, don't wait for the reload policy date you last gave
        // me — go call every installed widget's `getTimeline` again right
        // now." Without this, a completed task would only reach the widget
        // whenever its own `.after(nextRefresh)` policy next fired (up to
        // several hours later, per `RizeWidgetProvider`), not immediately.
        // WidgetKit does cap how often an app can call this per day (an
        // undocumented, dynamic "reload budget"), but ordinary per-action
        // usage like this — a handful of times as the user completes tasks
        // in a session — comfortably stays inside it.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// e.g. "3.1 mi · 28m" for a distance-based workout, or just "45m" for
    /// one with no meaningful distance (strength training, yoga, …).
    private func workoutSubtitle(_ workout: WorkoutSummary) -> String {
        let duration = workout.formattedMovingTime
        guard workout.distanceMeters > 0 else { return duration }
        return String(format: "%.1f mi · %@", workout.distanceMiles, duration)
    }

    /// "Today" / "Yesterday" / "3d ago" — the widget's compact stand-in for
    /// a full date, sized for a small card rather than a detail screen.
    private func relativeDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days)d ago"
        }
    }

    /// Downsamples a route to a widget-appropriate point count — the shared
    /// App Group `UserDefaults` store is meant for small bits of UI state,
    /// not thousands of GPS points per workout, and a tiny widget map has no
    /// use for full route-simplification fidelity (see
    /// `HealthKitManager.fetchWorkoutRoute`'s Douglas-Peucker pass, which
    /// already ran before this) — even stride sampling reads fine at this size.
    private static let maxWidgetRoutePoints = 150
    private static func thinnedRoute(_ coordinates: [RouteCoordinate]) -> [RizeWidgetCoordinate] {
        guard coordinates.count > maxWidgetRoutePoints else {
            return coordinates.map { RizeWidgetCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
        let stride = coordinates.count / maxWidgetRoutePoints
        return coordinates.enumerated()
            .filter { $0.offset % stride == 0 }
            .map { RizeWidgetCoordinate(latitude: $0.element.latitude, longitude: $0.element.longitude) }
    }

    // MARK: - Day change

    /// How many fully-missed days in a row before the "Returning to Ash"
    /// siege banner actually shows. One missed day still costs vitality
    /// (see `processDayChange`) — this only gates the alert itself, so a
    /// single off day doesn't read as catastrophic, but a real pattern does.
    private static let siegeThreshold = 2

    /// Evaluates every calendar day from `lastCheckedDate` up to (but not
    /// including) today — usually just one day, but if the app hasn't been
    /// opened in a while, every skipped day in between gets its own
    /// `processDayChange` call instead of only the most recent one. Each
    /// missed day in that gap still had nobody around to complete anything,
    /// so it's evaluated as missed (an empty `resolveEntry` result) exactly
    /// like a day where the app *was* opened but nothing got done — a real
    /// multi-day absence should cost the same vitality/streak as being
    /// present but inactive for that many days, not less just because
    /// nobody happened to check in.
    ///
    /// `resolveEntry` is a closure, not a plain parameter, because it needs
    /// to run once per day being walked (not just once) — the caller
    /// resolves each date to that specific day's real `DailyEntry` data (see
    /// `TodayView.pendingDayChangeSnapshot`/`fetchEntry(for:)`), which
    /// `XPManager` itself can't do since it has no SwiftData access.
    func checkDayChange(resolveEntry: (Date) -> (completedCount: Int, energyScore: Int)) {
        guard !lastCheckedDate.isEmpty else {
            lastCheckedDate = todayKey
            return
        }
        guard let lastDate = XPManager.dateFormatter.date(from: lastCheckedDate) else {
            lastCheckedDate = todayKey
            return
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        var cursor = calendar.startOfDay(for: lastDate)
        guard cursor < todayStart else { return } // already evaluated through today

        while cursor < todayStart {
            let snapshot = resolveEntry(cursor)
            processDayChange(completedCount: snapshot.completedCount, energyScore: snapshot.energyScore)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? todayStart
        }
        lastCheckedDate = todayKey
    }

    private func processDayChange(completedCount: Int, energyScore: Int) {
        if completedCount == 0 {
            missedDayStreak += 1
            realmDefense = max(0, realmDefense - 25)
            appendDefenseHistory(defended: false)
            let wasAlreadyUnderSiege = isUnderSiege
            isUnderSiege = missedDayStreak >= Self.siegeThreshold
            if isUnderSiege && !wasAlreadyUnderSiege {
                // Only fire the very first time this streak crosses the
                // threshold — not every subsequent missed day after that —
                // and give them an hour to feed it in-app before nudging
                // with a push (cancelled the moment a task completes; see
                // `triggerSiegeBrokenUI`).
                NotificationManager.shared.scheduleSiegeStartNotification()
            }
        } else {
            missedDayStreak = 0
            isUnderSiege = false
            let energyBonus = energyScore <= 3 ? 15 : 0
            fortificationPoints += completedCount * 10 + energyBonus
            realmDefense = min(100, realmDefense + 10)
            appendDefenseHistory(defended: true)
        }
    }

    private func appendDefenseHistory(defended: Bool) {
        var history = defenseHistory
        // `realmDefense` has already been updated by the caller (processDayChange)
        // by the time this runs, so it reflects this day's final vitality.
        history.append(DefenseDay(date: todayKey, defended: defended, defenseValue: realmDefense))
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
            siegeBroken = true
            triggerSiegeBrokenUI(bonusXP: bonusXP, energyScore: energyScore)
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
        // The fed-your-phoenix warning is no longer relevant — they just did.
        NotificationManager.shared.cancelSiegeNotifications()
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

        updateStreak(profile: profile, completedCount: entry.tasksCompleted)

        let allDone = entry.isFullyComplete
        if allDone {
            profile.currentXP += Constants.allTasksBonus
            entry.xpEarned += Constants.allTasksBonus
        }

        // Credit the siege-break bonus to real XP too — it used to only show
        // up in the returned `xpDelta` (the toast the user sees) without
        // ever actually being added to `profile.currentXP`, so the bonus was
        // promised but never paid.
        let siegeResult = executeTaskCompletion(xp: xpForTask, energyScore: energy)
        if siegeResult.bonusXP > 0 {
            profile.currentXP += siegeResult.bonusXP
            entry.xpEarned += siegeResult.bonusXP
        }

        // Computed after every addition above (task XP + all-done bonus +
        // siege bonus) — checking this mid-way, before the later bonuses
        // land, could miss a tier-up that one of them actually caused.
        let tierBefore = PhoenixDesign.tierInfo(for: oldXP).name
        let tierAfter = PhoenixDesign.tierInfo(for: profile.currentXP).name
        let leveledUp = tierBefore != tierAfter

        // Compared against the day's final earned total, not
        // `profile.currentXP` (the all-time cumulative total, which only
        // ever grows and would make "best day" converge to "lifetime XP").
        if entry.xpEarned > profile.bestXPDay {
            profile.bestXPDay = entry.xpEarned
        }

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
