import Foundation
import FoundationModels

/// A concrete, checkable activity to show the user. Each item is tied to the
/// person's actual goal — Rize no longer emits generic wellness filler
/// ("hydrate", "deep breathing", …). The day's list is built from exactly two
/// sources: these goal-specific tasks and the user's real EventKit calendar.
struct PlannedActivity: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let duration: String
    let detail: String
    /// Fixed category used only for the row's icon/colour.
    let category: PlanCategory
    /// Flexible, goal-derived section label (e.g. "Marathon Base", "Serve Work").
    /// This — not a hard-coded bucket — is what groups the goal tasks on screen.
    let focus: String
}

// MARK: - Generable Shapes

/// The on-device model's output: a short, goal-specific plan for today. The
/// deterministic `PlanningEngine` still decides *how hard* today should be; the
/// model only turns that decision + the user's goal into concrete actions.
@Generable
private struct GeneratedGoalPlan: Equatable {
    @Guide(description: "A short label naming today's training focus, 1-3 words, e.g. 'Marathon Base', 'Serve Work', or 'Thesis Writing'. Derived from the person's goal.")
    var focus: String

    @Guide(description: "Between 1 and 3 concrete tasks for TODAY, each directly serving the person's specific goal. Never generic wellness.")
    var tasks: [GeneratedGoalTask]
}

@Generable
private struct GeneratedGoalTask: Equatable {
    @Guide(description: "An imperative, specific task title under 8 words, e.g. 'Easy 5-mile run' or 'Serve practice, 40 serves'.")
    var title: String

    @Guide(description: "A short duration or amount, e.g. '30 min', '5 mi', or '40 reps'.")
    var duration: String

    @Guide(description: "One short sentence on how to do it well, tied to the goal. No fluff.")
    var detail: String
}

// MARK: - Goal Task Generator

/// Turns the user's free-text goal into 1-3 concrete tasks for today, using
/// Apple's on-device Foundation Models. The tasks are *grounded* by the
/// deterministic plan (today's training intensity, workload, recovery emphasis),
/// so they stay adaptive to energy while always being relevant to the goal.
///
/// Falls back to a deterministic, goal-aware template whenever the model is
/// unavailable — the fallback is still goal-specific, never generic filler.
enum GoalTaskGenerator {

    private static let model = SystemLanguageModel.default

    /// Produce today's goal tasks. Always returns at least one item; never throws.
    static func tasks(for plan: DailyPlan, context: CoachingContext) async -> [PlannedActivity] {
        let classified = classify(context)

        guard case .available = model.availability else {
            return fallback(plan: plan, classified: classified)
        }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = groundingPrompt(plan: plan, context: context, classified: classified)

        do {
            let result = try await session.respond(
                to: prompt,
                generating: GeneratedGoalPlan.self,
                options: GenerationOptions(temperature: 0.6)
            ).content

            let items = Array(result.tasks.prefix(3)).filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !items.isEmpty else { return fallback(plan: plan, classified: classified) }

            let focus = result.focus.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = focus.isEmpty ? classified.label : focus
            return items.map {
                PlannedActivity(
                    title: $0.title,
                    duration: $0.duration.isEmpty ? "—" : $0.duration,
                    detail: $0.detail,
                    category: classified.category,
                    focus: label
                )
            }
        } catch {
            // Guardrail violation, timeout, context overflow, model off — degrade.
            return fallback(plan: plan, classified: classified)
        }
    }

    // MARK: Instructions & Grounding

    private static let instructions = """
    You are the training planner inside Rize. Given a person's SPECIFIC goal and \
    how much capacity they have today, you produce 1-3 concrete tasks that move \
    them toward THAT goal today. Every task must be directly relevant to the goal: \
    if the goal is running a marathon, tasks are running, strength, or mobility \
    that serve running — NEVER generic wellness like "deep breathing", "hydrate", \
    or "recovery" unless the goal itself is about rest. Match the training \
    intensity you are told to use: on a rest or recovery day keep it gentle; on an \
    ambitious day lean in. Be specific and realistic. No hustle-culture language.
    """

    private static func groundingPrompt(plan: DailyPlan, context: CoachingContext, classified: Classified) -> String {
        var facts: [String] = []
        let goalLine = [context.goal, context.goalDetail]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        facts.append("The person's goal: \(goalLine.isEmpty ? "general fitness" : goalLine).")
        facts.append("Training focus area: \(classified.label).")
        facts.append("Today's recommended training intensity: \(intensityFact(plan.workout.intent)).")
        facts.append("Today's overall workload capacity: \(plan.workload.rawValue).")
        if plan.recovery.emphasis != .none {
            facts.append("Recovery is \(plan.recovery.emphasis.rawValue) today — do not overload.")
        }
        if plan.burnoutRisk != .low {
            facts.append("Burnout risk is \(plan.burnoutRisk.rawValue) — keep it sustainable.")
        }

        return """
        FACTS:
        \(facts.map { "- \($0)" }.joined(separator: "\n"))

        Using ONLY these facts, write today's 1-3 goal tasks for this person.
        """
    }

    private static func intensityFact(_ intent: WorkoutIntent) -> String {
        switch intent {
        case .rest:      return "full rest — only very light mobility, if anything"
        case .recovery:  return "active recovery — easy and gentle only"
        case .light:     return "light — short and easy"
        case .moderate:  return "moderate — a solid, steady effort"
        case .ambitious: return "ambitious — a harder or longer session"
        }
    }

    // MARK: - Deterministic Fallback (goal-aware, never generic)

    private static func fallback(plan: DailyPlan, classified: Classified) -> [PlannedActivity] {
        switch classified.category {
        case .classes, .work:
            return [focusBlock(workload: plan.workload, classified: classified)]
        default:
            return [movement(intent: plan.workout.intent, classified: classified)]
        }
    }

    private static func movement(intent: WorkoutIntent, classified: Classified) -> PlannedActivity {
        let focus = classified.label
        let noun = classified.noun
        switch intent {
        case .rest:
            return PlannedActivity(title: "Mobility & stretch",
                                   duration: "15 min",
                                   detail: "Rest day. Gentle mobility keeps you loose for \(noun).",
                                   category: classified.category, focus: focus)
        case .recovery:
            return PlannedActivity(title: "Easy \(noun) recovery",
                                   duration: "20 min",
                                   detail: "Keep it light — active recovery toward your goal.",
                                   category: classified.category, focus: focus)
        case .light:
            return PlannedActivity(title: "Light \(noun) session",
                                   duration: "20 min",
                                   detail: "Short and easy today — keep the streak alive.",
                                   category: classified.category, focus: focus)
        case .moderate:
            return PlannedActivity(title: "\(noun.capitalized) session",
                                   duration: "40 min",
                                   detail: "A solid, steady effort toward your goal.",
                                   category: classified.category, focus: focus)
        case .ambitious:
            return PlannedActivity(title: "Big \(noun) session",
                                   duration: "50 min",
                                   detail: "Good energy today — push a harder effort toward your goal.",
                                   category: classified.category, focus: focus)
        }
    }

    private static func focusBlock(workload: Workload, classified: Classified) -> PlannedActivity {
        let focus = classified.label
        switch workload {
        case .light:
            return PlannedActivity(title: "One small \(classified.noun) block",
                                   duration: "20 min",
                                   detail: "Just one small step toward your goal. Starting is the win.",
                                   category: classified.category, focus: focus)
        case .moderate:
            return PlannedActivity(title: "Focused \(classified.noun) block",
                                   duration: "45 min",
                                   detail: "One focused session toward your goal — no distractions.",
                                   category: classified.category, focus: focus)
        case .heavy:
            return PlannedActivity(title: "Deep \(classified.noun) sprint",
                                   duration: "60 min",
                                   detail: "Hardest thing first while your energy is high.",
                                   category: classified.category, focus: focus)
        }
    }

    // MARK: - Goal Classification

    /// The training focus we infer from the goal, plus display metadata.
    struct Classified {
        /// Human section label, e.g. "Marathon Training", "Tennis".
        let label: String
        /// A noun used in fallback copy, e.g. "run", "tennis", "study".
        let noun: String
        /// Fixed category used only for the row icon/colour.
        let category: PlanCategory
    }

    private static func classify(_ context: CoachingContext) -> Classified {
        let hay = "\(context.goal) \(context.goalDetail)".lowercased()

        func has(_ words: [String]) -> Bool { words.contains { hay.contains($0) } }

        if has(["marathon", "5k", "10k", "half", "running", "run ", " run", "jog"]) {
            return Classified(label: "Running", noun: "run", category: .workout)
        }
        if has(["cycl", "bike", "biking", "ride "]) {
            return Classified(label: "Cycling", noun: "ride", category: .workout)
        }
        if has(["swim"]) {
            return Classified(label: "Swimming", noun: "swim", category: .workout)
        }
        if has(["tennis"]) { return Classified(label: "Tennis", noun: "tennis", category: .workout) }
        if has(["basketball", "hoops"]) { return Classified(label: "Basketball", noun: "basketball", category: .workout) }
        if has(["soccer", "football"]) { return Classified(label: "Soccer", noun: "soccer", category: .workout) }
        if has(["gym", "lift", "strength", "muscle", "bodybuild", "powerlift", "weight"]) {
            return Classified(label: "Strength", noun: "strength", category: .workout)
        }
        if has(["yoga", "flexib", "mobility", "pilates"]) {
            return Classified(label: "Yoga", noun: "yoga", category: .workout)
        }
        if has(["study", "studying", "exam", "test", "gpa", "grade", "school", "class", "degree", "course"]) {
            return Classified(label: "Studying", noun: "study", category: .classes)
        }
        if has(["writ", "novel", "book", "thesis", "essay", "blog"]) {
            return Classified(label: "Writing", noun: "writing", category: .work)
        }
        if has(["work", "career", "business", "startup", "promotion", "code", "coding", "project", "product"]) {
            return Classified(label: "Focus Work", noun: "work", category: .work)
        }

        // Fall back on the coarse onboarding goal bucket.
        switch context.goal.lowercased() {
        case "productivity":
            return Classified(label: "Focus Work", noun: "work", category: .work)
        default:
            return Classified(label: "Training", noun: "training", category: .workout)
        }
    }
}
