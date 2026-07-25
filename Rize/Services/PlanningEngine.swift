import Foundation

/// The decision-making core of Rize.
///
/// `PlanningEngine` is **deterministic**, **pure**, and **UI-independent**: given
/// the same `PlanInput` it always returns the same `DailyPlan`. It imports only
/// Foundation — no SwiftData, HealthKit, EventKit, or SwiftUI — so it can be
/// unit-tested in isolation and reused anywhere.
///
/// It makes *all* planning decisions but produces **no natural language**. The
/// reasoning it emits is structured (`PlanRationale`); turning that into
/// supportive prose is the narrator's job, never the engine's.
///
/// Guiding philosophy: consistency over perfection. The engine adapts to the
/// user's state, protects them from burnout, and never overloads them.
struct PlanningEngine {

    // MARK: - Tunables
    // Centralised so the behaviour is easy to audit and adjust.

    private enum Capacity {
        static let depleted = 2
        static let low = 3
        static let steady = 4
        static let high = 5
        /// Extra "get ahead" future tasks allowed per band.
        static let getAheadSteady = 1
        static let getAheadHigh = 2
    }

    /// A workout on the day before is "recent enough" to matter for recovery.
    private static let recentWorkoutWindowDays = 1
    /// "No recent workouts" is measured over this many days.
    private static let consistencyWindowDays = 4
    /// Deadlines within this horizon count as "this week".
    private static let weekHorizonDays = 7

    init() {}

    // MARK: - Entry Point

    /// Produce a full daily plan from the given input. Total function — never
    /// throws, never returns nil, safe for any input (including empty).
    ///
    /// Shape of this function: a straight-line pipeline, not a class hierarchy
    /// or strategy pattern — each numbered step below computes one piece of
    /// the plan from `input` plus whatever earlier steps already derived
    /// (e.g. `burnout` factors into task selection, which is deliberately
    /// computed *after* burnout risk so overload can be suppressed), then
    /// step 8 assembles everything into the immutable `DailyPlan` result.
    /// Every step is a private, pure function below (`determineWorkload`,
    /// `selectTasks`, etc.) — that's what keeps this readable despite doing
    /// a lot: each one is independently followable, and the pipeline itself
    /// is just wiring them together in the right order.
    func makePlan(from input: PlanInput) -> DailyPlan {
        let band = input.energyBand
        let sleepQuality = input.sleep?.quality
        let lastWorkout = mostRecentWorkout(in: input)
        let hadHardWorkoutYesterday = workedHardYesterday(input: input, lastWorkout: lastWorkout)
        let restedYesterday = didRestYesterday(input: input)
        let hasNoRecentWorkouts = noRecentWorkouts(input: input)

        // 1. Classify every incomplete task by deadline urgency.
        let incomplete = input.tasks.filter { !$0.isCompleted }
        let classified = incomplete.map { task in
            (task: task, deadline: deadlineClass(for: task.dueDate, input: input))
        }

        // 2. Workload from energy + sleep (sleep can veto energy).
        let workload = determineWorkload(band: band, sleepQuality: sleepQuality)

        // 3. Burnout risk — computed before selection so it can suppress load.
        let burnout = burnoutRisk(
            band: band,
            sleepQuality: sleepQuality,
            hadHardWorkoutYesterday: hadHardWorkoutYesterday,
            classified: classified
        )

        // 4. Select recommended vs. deferred tasks.
        let selection = selectTasks(
            classified: classified,
            band: band,
            sleepQuality: sleepQuality,
            burnout: burnout
        )

        // 5. Workout & recovery recommendations.
        let workout = workoutRecommendation(
            band: band,
            sleepQuality: sleepQuality,
            hadHardWorkoutYesterday: hadHardWorkoutYesterday,
            restedYesterday: restedYesterday,
            hasNoRecentWorkouts: hasNoRecentWorkouts,
            burnout: burnout
        )
        let recovery = recoveryRecommendation(
            band: band,
            sleepQuality: sleepQuality,
            hadHardWorkoutYesterday: hadHardWorkoutYesterday,
            burnout: burnout
        )

        // 6. Confidence from signal availability.
        let confidence = confidenceScore(input: input)

        // 7. Assemble structured, plan-level reasoning.
        let rationale = assembleRationale(
            input: input,
            band: band,
            sleepQuality: sleepQuality,
            hadHardWorkoutYesterday: hadHardWorkoutYesterday,
            restedYesterday: restedYesterday,
            hasNoRecentWorkouts: hasNoRecentWorkouts,
            classified: classified,
            burnout: burnout
        )

        // 8. "Due soon" tasks (today or tomorrow) surfaced in the workblock.
        let workblockTasks = classified
            .filter { $0.deadline == .today || $0.deadline == .tomorrow }
            .map { entry in
                WorkblockTask(
                    id: entry.task.id,
                    title: entry.task.title,
                    category: entry.task.category,
                    deadline: entry.deadline
                )
            }

        return DailyPlan(
            recommendedTasks: selection.recommended,
            deferredTasks: selection.deferred,
            workblockTasks: workblockTasks,
            workout: workout,
            recovery: recovery,
            workload: workload,
            confidence: confidence,
            burnoutRisk: burnout,
            rationale: rationale,
            generatedAt: input.referenceDate
        )
    }

    // MARK: - Deadlines

    private func deadlineClass(for dueDate: Date?, input: PlanInput) -> DeadlineClass {
        guard let dueDate else { return .none }
        let cal = input.calendar
        let today = cal.startOfDay(for: input.referenceDate)
        let due = cal.startOfDay(for: dueDate)
        let days = cal.dateComponents([.day], from: today, to: due).day ?? 0

        switch days {
        case ..<0:               return .overdue
        case 0:                  return .today
        case 1:                  return .tomorrow
        case 2...Self.weekHorizonDays: return .thisWeek
        default:                 return .later
        }
    }

    // MARK: - Workload

    private func determineWorkload(band: EnergyBand, sleepQuality: SleepQuality?) -> Workload {
        // Insufficient sleep reduces workload and ignores high motivation.
        if sleepQuality == .insufficient { return .light }

        switch band {
        case .depleted, .low:
            return .light
        case .steady:
            return .moderate
        case .high:
            // Ample sleep unlocks a heavy day; otherwise stay moderate.
            return sleepQuality == .ample ? .heavy : .moderate
        }
    }

    // MARK: - Task Selection

    private struct Selection {
        var recommended: [PlannedTask]
        var deferred: [PlannedTask]
    }

    /// The core selection strategy, in plain terms: split tasks into
    /// "mandatory" (overdue or due today — always included, no matter how
    /// depleted the user is) and "optional" (everything else, competing for
    /// a limited budget of remaining slots). The budget itself shrinks with
    /// bad sleep or high burnout risk, then optional tasks are greedily
    /// added in rank order (nearest deadline first, then priority) until the
    /// budget, the "how many future tasks am I allowed to front-load" limit,
    /// and the energy-band gate (e.g. depleted days admit *no* optional
    /// tasks at all) all say stop. Everything that doesn't make the cut goes
    /// to `deferred` instead of just being dropped, each carrying its own
    /// `TaskReason` for why — so the UI can say *why* a task was pushed, not
    /// just that it was.
    private func selectTasks(
        classified: [(task: PlanningTask, deadline: DeadlineClass)],
        band: EnergyBand,
        sleepQuality: SleepQuality?,
        burnout: BurnoutRisk
    ) -> Selection {
        // Mandatory work (overdue + due today) can never be postponed. It is
        // always recommended, regardless of energy or capacity.
        let mandatory = classified.filter { $0.deadline.isMandatoryToday }
        let optional = classified.filter { !$0.deadline.isMandatoryToday }

        // Capacity for *optional* additions on top of the mandatory floor.
        var capacity = baseCapacity(for: band)
        if sleepQuality == .insufficient { capacity = max(1, capacity - 1) }
        if burnout == .high { capacity = max(1, capacity - 1) }
        let optionalBudget = max(0, capacity - mandatory.count)

        // Order optional candidates: nearest deadline first, then priority.
        let rankedOptional = optional.sorted { lhs, rhs in
            if lhs.deadline != rhs.deadline { return lhs.deadline < rhs.deadline }
            return lhs.task.priority > rhs.task.priority
        }

        // How many future ("get ahead") tasks the band permits.
        let getAheadAllowance: Int
        switch band {
        case .depleted, .low: getAheadAllowance = 0
        case .steady:         getAheadAllowance = Capacity.getAheadSteady
        case .high:           getAheadAllowance = Capacity.getAheadHigh
        }

        var recommended: [PlannedTask] = mandatory.map {
            PlannedTask(from: $0.task, deadline: $0.deadline, reason: reason(for: $0.deadline, isRecommended: true, band: band))
        }
        var deferred: [PlannedTask] = []
        var futureAdded = 0

        for item in rankedOptional {
            let isFuture = item.deadline == .thisWeek || item.deadline == .later
            let withinBudget = (recommended.count - mandatory.count) < optionalBudget
            let futureOK = !isFuture || futureAdded < getAheadAllowance

            // On depleted/low-energy days we protect the user: only required
            // work and, at most, tomorrow's high-priority items.
            let energyAllows: Bool
            switch band {
            case .depleted:
                energyAllows = false
            case .low:
                energyAllows = item.deadline == .tomorrow && item.task.priority >= .medium
            case .steady, .high:
                energyAllows = true
            }

            if withinBudget && futureOK && energyAllows && burnout != .high {
                recommended.append(PlannedTask(from: item.task, deadline: item.deadline,
                                               reason: reason(for: item.deadline, isRecommended: true, band: band)))
                if isFuture { futureAdded += 1 }
            } else {
                deferred.append(PlannedTask(from: item.task, deadline: item.deadline,
                                            reason: deferralReason(for: item.deadline, band: band,
                                                                   withinBudget: withinBudget)))
            }
        }

        return Selection(recommended: recommended, deferred: deferred)
    }

    private func baseCapacity(for band: EnergyBand) -> Int {
        switch band {
        case .depleted: return Capacity.depleted
        case .low:      return Capacity.low
        case .steady:   return Capacity.steady
        case .high:     return Capacity.high
        }
    }

    private func reason(for deadline: DeadlineClass, isRecommended: Bool, band: EnergyBand) -> TaskReason {
        switch deadline {
        case .overdue:  return .overdue
        case .today:    return .dueToday
        case .tomorrow: return .dueTomorrow
        case .thisWeek, .later: return .getAhead
        case .none:     return band == .depleted ? .requiredOnly : .highPriority
        }
    }

    private func deferralReason(for deadline: DeadlineClass, band: EnergyBand, withinBudget: Bool) -> TaskReason {
        if band == .depleted || band == .low { return .deferredLowEnergy }
        if deadline == .later || deadline == .thisWeek { return .deferredFarDeadline }
        return withinBudget ? .deferredFarDeadline : .deferredCapacity
    }

    // MARK: - Workouts

    private func mostRecentWorkout(in input: PlanInput) -> WorkoutSummary? {
        input.recentWorkouts.max { $0.startDate < $1.startDate }
    }

    private func workedHardYesterday(input: PlanInput, lastWorkout: WorkoutSummary?) -> Bool {
        guard let lastWorkout else { return false }
        return isWithinDays(lastWorkout.startDate, days: Self.recentWorkoutWindowDays, input: input)
            && lastWorkout.intensity >= .hard
    }

    /// True when there's no workout in the recent window — i.e. yesterday looks
    /// like a rest day but the user has been active lately (worth a nudge).
    private func didRestYesterday(input: PlanInput) -> Bool {
        let hasRecent = input.recentWorkouts.contains {
            isWithinDays($0.startDate, days: Self.recentWorkoutWindowDays, input: input)
        }
        return !hasRecent && !noRecentWorkouts(input: input)
    }

    private func noRecentWorkouts(input: PlanInput) -> Bool {
        !input.recentWorkouts.contains {
            isWithinDays($0.startDate, days: Self.consistencyWindowDays, input: input)
        }
    }

    private func isWithinDays(_ date: Date, days: Int, input: PlanInput) -> Bool {
        let cal = input.calendar
        let today = cal.startOfDay(for: input.referenceDate)
        let then = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: then, to: today).day ?? Int.max
        return diff >= 0 && diff <= days
    }

    private func workoutRecommendation(
        band: EnergyBand,
        sleepQuality: SleepQuality?,
        hadHardWorkoutYesterday: Bool,
        restedYesterday: Bool,
        hasNoRecentWorkouts: Bool,
        burnout: BurnoutRisk
    ) -> WorkoutRecommendation {
        var rationale: [PlanRationale] = []

        // Recovery overrides: poor sleep, depletion, a hard session yesterday,
        // or high burnout risk all mean back off today.
        if sleepQuality == .insufficient || band == .depleted || burnout == .high {
            if let s = sleepQuality, s == .insufficient { rationale.append(.insufficientSleep(hours: 0)) }
            if band == .depleted { rationale.append(.depletedEnergy(level: 0)) }
            return WorkoutRecommendation(intent: .rest, rationale: rationale)
        }
        if hadHardWorkoutYesterday {
            rationale.append(.hardWorkoutYesterday)
            return WorkoutRecommendation(intent: .recovery, rationale: rationale)
        }

        // Otherwise scale ambition with energy.
        let intent: WorkoutIntent
        switch band {
        case .depleted: intent = .rest       // (already handled above)
        case .low:      intent = .light
        case .steady:   intent = .moderate
        case .high:     intent = .ambitious
        }

        if restedYesterday { rationale.append(.restedYesterday) }
        if hasNoRecentWorkouts { rationale.append(.noRecentWorkouts) }

        return WorkoutRecommendation(intent: intent, rationale: rationale)
    }

    // MARK: - Recovery

    private func recoveryRecommendation(
        band: EnergyBand,
        sleepQuality: SleepQuality?,
        hadHardWorkoutYesterday: Bool,
        burnout: BurnoutRisk
    ) -> RecoveryRecommendation {
        var rationale: [PlanRationale] = []
        var emphasis: RecoveryEmphasis = .none

        if sleepQuality == .insufficient || band == .depleted || burnout == .high {
            emphasis = .prioritized
            if sleepQuality == .insufficient { rationale.append(.insufficientSleep(hours: 0)) }
            if band == .depleted { rationale.append(.depletedEnergy(level: 0)) }
            if burnout == .high { rationale.append(.protectingFromBurnout) }
        } else if hadHardWorkoutYesterday || band == .low {
            emphasis = .encouraged
            if hadHardWorkoutYesterday { rationale.append(.hardWorkoutYesterday) }
        }

        return RecoveryRecommendation(emphasis: emphasis, rationale: rationale)
    }

    // MARK: - Burnout Risk

    private func burnoutRisk(
        band: EnergyBand,
        sleepQuality: SleepQuality?,
        hadHardWorkoutYesterday: Bool,
        classified: [(task: PlanningTask, deadline: DeadlineClass)]
    ) -> BurnoutRisk {
        let overdueCount = classified.filter { $0.deadline == .overdue }.count
        let mandatoryLoad = classified.filter { $0.deadline.isMandatoryToday }.count

        // Compounding stressors: poor recovery + heavy demands.
        let poorRecovery = (sleepQuality == .insufficient) || hadHardWorkoutYesterday
        let depleted = band == .depleted

        if depleted && (poorRecovery || mandatoryLoad >= 4) { return .high }
        if sleepQuality == .insufficient && (mandatoryLoad >= 3 || overdueCount >= 2) { return .high }

        if depleted || sleepQuality == .insufficient || overdueCount >= 3 || hadHardWorkoutYesterday {
            return .elevated
        }
        return .low
    }

    // MARK: - Confidence

    /// Deterministic 0…1 confidence based on how many signals we actually have.
    private func confidenceScore(input: PlanInput) -> Double {
        var score = 0.5
        if input.sleep != nil { score += 0.15 }
        if !input.recentWorkouts.isEmpty { score += 0.15 }
        if !input.tasks.isEmpty { score += 0.10 }
        if !input.calendarEvents.isEmpty { score += 0.05 }
        if input.previousPlan != nil { score += 0.05 }
        return min(1.0, max(0.0, score))
    }

    // MARK: - Rationale Assembly

    private func assembleRationale(
        input: PlanInput,
        band: EnergyBand,
        sleepQuality: SleepQuality?,
        hadHardWorkoutYesterday: Bool,
        restedYesterday: Bool,
        hasNoRecentWorkouts: Bool,
        classified: [(task: PlanningTask, deadline: DeadlineClass)],
        burnout: BurnoutRisk
    ) -> [PlanRationale] {
        var out: [PlanRationale] = []
        let energy = input.clampedEnergy

        switch band {
        case .depleted: out.append(.depletedEnergy(level: energy))
        case .low:      out.append(.lowEnergy(level: energy))
        case .steady:   out.append(.steadyEnergy(level: energy))
        case .high:     out.append(.highEnergy(level: energy))
        }

        if let sleep = input.sleep {
            switch sleep.quality {
            case .insufficient: out.append(.insufficientSleep(hours: sleep.hours))
            case .adequate:     out.append(.adequateSleep(hours: sleep.hours))
            case .ample:        out.append(.ampleSleep(hours: sleep.hours))
            }
        }

        if hadHardWorkoutYesterday { out.append(.hardWorkoutYesterday) }
        if restedYesterday { out.append(.restedYesterday) }
        if hasNoRecentWorkouts { out.append(.noRecentWorkouts) }

        let overdue = classified.filter { $0.deadline == .overdue }.count
        let today = classified.filter { $0.deadline == .today }.count
        let tomorrow = classified.filter { $0.deadline == .tomorrow }.count
        if overdue > 0 { out.append(.overdueDeadlines(count: overdue)) }
        if today > 0 { out.append(.deadlinesToday(count: today)) }
        if tomorrow > 0 { out.append(.deadlinesTomorrow(count: tomorrow)) }

        switch burnout {
        case .high, .elevated: out.append(.protectingFromBurnout)
        case .low: break
        }

        if band == .high { out.append(.gettingAhead) }
        if band == .depleted { out.append(.requiredWorkOnly) }
        if input.currentStreak > 0 { out.append(.buildingConsistency(streak: input.currentStreak)) }

        return out
    }
}

// MARK: - PlannedTask Convenience

private extension PlannedTask {
    init(from task: PlanningTask, deadline: DeadlineClass, reason: TaskReason) {
        self.init(
            id: task.id,
            title: task.title,
            priority: task.priority,
            category: task.category,
            deadline: deadline,
            reason: reason
        )
    }
}
