import Foundation
import FoundationModels

// MARK: - Narrative Model
//
// FoundationModels (iOS 26+) is Apple's framework for talking to the small
// on-device LLM ("Apple Intelligence") built into the OS — no network call,
// no API key, and (per this app's own constraint, see the guardrail comment
// on `narrate` below) no cloud fallback. Two macros from that framework do
// the heavy lifting on `CoachingNarrative`:
//
//   - `@Generable` marks a type as something the model can produce directly,
//     as *structured* output — the model is constrained at generation time
//     to only ever emit values that satisfy this exact shape (four specific
//     string fields, in this case), never free-form text you'd have to hope
//     is valid JSON and then parse yourself. This is the actual mechanism
//     behind `session.respond(to:generating:)` down in `narrate` — passing
//     `CoachingNarrative.self` as `generating:` is what tells the model
//     "your output must conform to this."
//   - `@Guide(description:)` on each property is a per-field instruction —
//     not documentation for humans, but a prompt fragment the model reads
//     to decide what to put in that specific field (tone, length, content).
//     It's how one `@Generable` type can express "one sentence here, a
//     phoenix-themed one-liner there" instead of every field getting the
//     same generic treatment.

/// The user-facing coaching copy for a day. Produced from an already-decided
/// `DailyPlan` — the narrator phrases decisions, it never makes them.
///
/// `@Generable` lets Apple's on-device model fill these fields via guided
/// generation, guaranteeing a well-formed result (no JSON parsing, no markdown
/// scrubbing). The same shape is produced by the template fallback.
@Generable
struct CoachingNarrative: Equatable, Sendable {
    @Guide(description: "A warm, specific, one-sentence greeting/encouragement for today. Never guilt or shame. Under 20 words.")
    var encouragement: String

    @Guide(description: "Two or three short sentences explaining why today's plan fits the person's energy, sleep, and recent training. Supportive and honest.")
    var explanation: String

    @Guide(description: "One sentence about today's movement — either the recommended workout or, if recovery is advised, why resting is the strong choice.")
    var bodyNote: String

    @Guide(description: "One short phoenix-themed line reinforcing consistency over perfection. Under 15 words.")
    var phoenixMessage: String
}

// MARK: - Context

/// Lightweight, non-sensitive context to personalise narration.
struct CoachingContext: Sendable {
    var name: String
    var goal: String
    var goalDetail: String

    init(name: String = "", goal: String = "", goalDetail: String = "") {
        self.name = name
        self.goal = goal
        self.goalDetail = goalDetail
    }
}

// MARK: - Narrator

/// Turns a deterministic `DailyPlan` into supportive prose using Apple's
/// on-device Foundation Models. Falls back to templates whenever the model is
/// unavailable (device not eligible, Apple Intelligence off, model downloading)
/// or a generation error occurs — so the app is never blocked on AI.
///
/// The model is given the plan's decisions as **grounded facts** and asked only
/// to phrase them warmly. It cannot change the plan.
struct CoachingNarrator {

    static let shared = CoachingNarrator()

    // `SystemLanguageModel.default` is the single on-device model FoundationModels
    // exposes — there's no model selection the way there is with a cloud API,
    // just this one shared instance. `.availability` is why this framework
    // needs a fallback path everywhere it's used: unlike a network API call
    // (which basically always *attempts* to run and fails with an error if
    // something's wrong), this model can be entirely absent from the device's
    // capabilities before you ever try to use it — Apple Intelligence turned
    // off in Settings, an ineligible/older device, or the model still
    // downloading in the background. `.available` is the one case where
    // generation can be attempted at all; every other case (and the fallback
    // pattern below is used both here in `narrate` and in `weeklyInsight`)
    // must be handled by the deterministic `template`/`weeklyTemplate` methods
    // near the bottom of this file instead.
    private let model = SystemLanguageModel.default

    init() {}

    /// Whether on-device generation is currently possible. UI can use this to
    /// decide whether to show an "AI coach" affordance.
    var isModelAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    // MARK: Daily Narration

    /// Produce coaching copy for a plan. Always returns a value — never throws.
    func narrate(plan: DailyPlan, context: CoachingContext) async -> CoachingNarrative {
        guard case .available = model.availability else {
            return CoachingNarrator.template(for: plan, context: context)
        }

        // `LanguageModelSession` is FoundationModels' unit of conversation —
        // roughly analogous to a chat thread: `instructions` is a persistent
        // system prompt applied to everything sent through this session (see
        // `dailyInstructions` below, which sets the "Ryz" persona and its
        // hard rules once rather than repeating them per call).
        let session = LanguageModelSession(instructions: CoachingNarrator.dailyInstructions)
        let prompt = CoachingNarrator.groundingPrompt(for: plan, context: context)

        do {
            // `generating: CoachingNarrative.self` is what makes this guided
            // generation rather than plain text — the model is constrained to
            // only produce values matching that `@Generable` shape (see the
            // comment on `CoachingNarrative` above), which `response.content`
            // then hands back already as a real `CoachingNarrative`, not a
            // string to parse. Compare to `weeklyInsight` below, which omits
            // `generating:` and gets plain `String` back instead — guided
            // generation is opt-in per call, not a session-wide mode.
            let response = try await session.respond(
                to: prompt,
                generating: CoachingNarrative.self,
                options: GenerationOptions(temperature: 0.7)
            )
            return response.content
        } catch {
            // Guardrail violation, timeout, context overflow, etc. — degrade gracefully.
            return CoachingNarrator.template(for: plan, context: context)
        }
    }

    // MARK: Weekly Insight

    /// One short, honest weekly insight. Falls back to a deterministic template.
    func weeklyInsight(energyHistory: [Int], completionHistory: [Double]) async -> String {
        guard case .available = model.availability,
              !energyHistory.isEmpty else {
            return CoachingNarrator.weeklyTemplate(energyHistory: energyHistory, completionHistory: completionHistory)
        }

        let session = LanguageModelSession(instructions: CoachingNarrator.weeklyInstructions)
        let energy = energyHistory.map(String.init).joined(separator: ", ")
        let completion = completionHistory.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: ", ")
        let prompt = """
        Last 7 days energy (1–10): \(energy)
        Last 7 days completion rate: \(completion)
        Give ONE insight under 20 words. Return only the sentence.
        """

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.6))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return CoachingNarrator.weeklyTemplate(energyHistory: energyHistory, completionHistory: completionHistory)
        }
    }
}

// MARK: - Instructions & Grounding

private extension CoachingNarrator {

    static let dailyInstructions = """
    You are Ryz, the phoenix coach inside Rize — an adaptive productivity and \
    fitness companion. Your philosophy is consistency over perfection. You are \
    warm, calm, and specific. You NEVER guilt, shame, or pressure. You NEVER \
    invent facts: only use the FACTS provided. You do not change the plan — it \
    has already been decided for the person's own good. Your job is only to \
    explain it kindly and make them feel supported. Keep language simple and \
    encouraging. Avoid clichés and hustle-culture language.
    """

    static let weeklyInstructions = """
    You are Ryz, a supportive coach. Analyse the person's 7-day pattern and \
    return ONE short, honest, encouraging insight under 20 words. No fluff, no \
    guilt, no quotes. Return only the insight sentence.
    """

    /// Convert the plan's *structured* rationale + decisions into plain factual
    /// lines. This is the only information the model sees, so it cannot drift.
    static func groundingPrompt(for plan: DailyPlan, context: CoachingContext) -> String {
        var facts: [String] = []

        if !context.name.isEmpty { facts.append("Person's name: \(context.name).") }
        if !context.goal.isEmpty { facts.append("Their goal: \(context.goal) — \(context.goalDetail).") }

        facts.append("Today's workload level: \(plan.workload.rawValue).")
        facts.append("Recommended movement: \(movementFact(plan)).")
        facts.append("Recovery emphasis: \(plan.recovery.emphasis.rawValue).")
        facts.append("Number of focus tasks today: \(plan.recommendedTaskCount).")
        if !plan.deferredTasks.isEmpty {
            facts.append("\(plan.deferredTasks.count) task(s) were gently deferred to protect energy.")
        }
        facts.append("Burnout risk: \(plan.burnoutRisk.rawValue).")

        for line in plan.rationale.map(phrase(_:)) where !line.isEmpty {
            facts.append(line)
        }

        return """
        FACTS:
        \(facts.map { "- \($0)" }.joined(separator: "\n"))

        Using ONLY these facts, write today's coaching for this person.
        """
    }

    static func movementFact(_ plan: DailyPlan) -> String {
        switch plan.workout.intent {
        case .rest:      return "no training today — full rest"
        case .recovery:  return "gentle active recovery"
        case .light:     return "a light workout"
        case .moderate:  return "a moderate workout"
        case .ambitious: return "an ambitious workout"
        }
    }

    /// Deterministic English for a single structured rationale (used to ground
    /// the model — NOT shown directly to the user).
    static func phrase(_ r: PlanRationale) -> String {
        switch r {
        case .depletedEnergy(let l):    return "Energy is very low today (\(l)/10)."
        case .lowEnergy(let l):         return "Energy is low today (\(l)/10)."
        case .steadyEnergy(let l):      return "Energy is steady today (\(l)/10)."
        case .highEnergy(let l):        return "Energy is high today (\(l)/10)."
        case .insufficientSleep(let h): return h > 0 ? String(format: "Slept only %.1f hours.", h) : "Sleep was short."
        case .adequateSleep(let h):     return String(format: "Slept about %.1f hours.", h)
        case .ampleSleep(let h):        return String(format: "Slept well, about %.1f hours.", h)
        case .hardWorkoutYesterday:     return "Did a hard workout yesterday."
        case .restedYesterday:          return "Yesterday was a rest day."
        case .noRecentWorkouts:         return "No workouts in the last few days."
        case .overdueDeadlines(let c):  return "\(c) task(s) are overdue."
        case .deadlinesToday(let c):    return "\(c) task(s) are due today."
        case .deadlinesTomorrow(let c): return "\(c) task(s) are due tomorrow."
        case .protectingFromBurnout:    return "The plan is intentionally lighter to prevent burnout."
        case .buildingConsistency(let s): return s > 0 ? "Current streak: \(s) day(s)." : ""
        case .gettingAhead:             return "There is room to get ahead on future work."
        case .requiredWorkOnly:         return "Only essential work is included today."
        }
    }
}

// MARK: - Template Fallback

extension CoachingNarrator {

    /// Fully deterministic narration for when Foundation Models is unavailable.
    /// Keyed off the same structured plan, so tone stays consistent.
    static func template(for plan: DailyPlan, context: CoachingContext) -> CoachingNarrative {
        let name = context.name.isEmpty ? "" : ", \(context.name)"

        let encouragement: String
        let phoenix: String
        switch plan.burnoutRisk {
        case .high:
            encouragement = "Take it gently today\(name) — showing up is the win."
            phoenix = "Even embers relight. Consistency beats intensity."
        case .elevated:
            encouragement = "Steady wins today\(name). Small steps still count."
            phoenix = "A calm flame lasts longest."
        case .low:
            encouragement = "Good energy to build on today\(name)."
            phoenix = "Feed the flame — one task at a time."
        }

        let explanation: String
        switch plan.workload {
        case .light:
            explanation = "Today's plan is intentionally light so you can recover and stay consistent. \(plan.recommendedTaskCount) focus task\(plan.recommendedTaskCount == 1 ? "" : "s") is plenty right now."
        case .moderate:
            explanation = "A balanced day: \(plan.recommendedTaskCount) focus task\(plan.recommendedTaskCount == 1 ? "" : "s") that match your energy, with room to breathe."
        case .heavy:
            explanation = "You've got capacity today, so the plan leans in with \(plan.recommendedTaskCount) focus task\(plan.recommendedTaskCount == 1 ? "" : "s") — including a chance to get ahead."
        }

        let bodyNote: String
        switch plan.workout.intent {
        case .rest:      bodyNote = "Rest is the workout today — your body earns more from recovery than from pushing."
        case .recovery:  bodyNote = "Keep movement gentle today — light active recovery only."
        case .light:     bodyNote = "A short, easy workout will keep the momentum going."
        case .moderate:  bodyNote = "A moderate workout fits your energy well today."
        case .ambitious: bodyNote = "Great day to challenge yourself with an ambitious workout."
        }

        return CoachingNarrative(
            encouragement: encouragement,
            explanation: explanation,
            bodyNote: bodyNote,
            phoenixMessage: phoenix
        )
    }

    static func weeklyTemplate(energyHistory: [Int], completionHistory: [Double]) -> String {
        guard !energyHistory.isEmpty else {
            return "Log a few days and I'll spot your patterns."
        }
        let avgEnergy = Double(energyHistory.reduce(0, +)) / Double(energyHistory.count)
        let avgCompletion = completionHistory.isEmpty ? 0 : completionHistory.reduce(0, +) / Double(completionHistory.count)

        if avgCompletion >= 0.8 {
            return "Strong, consistent week — you showed up even on lower-energy days."
        } else if avgEnergy < 4 {
            return "Lower-energy week; gentler days still keep your streak alive."
        } else {
            return "Solid week overall — small, steady wins are adding up."
        }
    }
}
