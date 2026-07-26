import Foundation
import FoundationModels

// MARK: - Mascot Context

/// Grounded facts for a single mascot tap — mirrors `CoachingContext` in
/// `CoachingNarrator.swift`, just scoped to what the floating mascot can say.
struct MascotContext: Sendable {
    var name: String
    var tierName: String
    var streak: Int
    var realmDefensePercent: Int
    var isUnderSiege: Bool
    var sleepHours: Double?
    var lastWorkoutType: String?
}

// MARK: - Narrator

/// Produces the mascot's one-line tap response using Apple's on-device
/// Foundation Models — same availability/fallback contract as
/// `CoachingNarrator`: the model can be entirely absent (Apple Intelligence
/// off, ineligible device, still downloading), so every call must degrade to
/// a deterministic template rather than block or throw.
struct MascotNarrator {

    static let shared = MascotNarrator()

    private let model = SystemLanguageModel.default

    init() {}

    /// One short motivational line. Always returns a value — never throws.
    func line(for context: MascotContext) async -> String {
        guard case .available = model.availability else {
            return MascotNarrator.template(for: context)
        }

        let session = LanguageModelSession(instructions: MascotNarrator.instructions)
        let prompt = MascotNarrator.groundingPrompt(for: context)

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.6))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return MascotNarrator.template(for: context)
        }
    }
}

// MARK: - Instructions & Grounding

private extension MascotNarrator {

    static let instructions = """
    You are Ryz, the phoenix mascot inside Rize — an adaptive productivity and \
    fitness companion. Someone just tapped you. Say ONE short, warm, \
    phoenix-themed motivational line under 16 words, grounded ONLY in the \
    FACTS given. Never guilt or shame. Never invent facts: do not mention any \
    tier name other than the exact one given in FACTS, and do not invent \
    numbers, step counts, percentages, or XP amounts that are not explicitly \
    listed in FACTS. If FACTS don't mention something, don't reference it. \
    No quotes, no emoji, return only the sentence.
    """

    static func groundingPrompt(for context: MascotContext) -> String {
        var facts: [String] = []

        if !context.name.isEmpty { facts.append("Person's name: \(context.name).") }
        facts.append("Current tier: \(context.tierName).")
        facts.append(context.streak > 0 ? "Current streak: \(context.streak) day(s)." : "No active streak right now.")

        if context.isUnderSiege {
            facts.append("The kingdom is under siege (defense at \(context.realmDefensePercent)%) — several days missed.")
        } else {
            facts.append("Kingdom defense is holding at \(context.realmDefensePercent)%.")
        }

        if let sleep = context.sleepHours {
            facts.append(String(format: "Slept about %.1f hours last night.", sleep))
        }
        if let workout = context.lastWorkoutType {
            facts.append("Most recent workout: \(workout).")
        }

        return """
        FACTS:
        \(facts.map { "- \($0)" }.joined(separator: "\n"))

        Using ONLY these facts, say your one line.
        """
    }
}

// MARK: - Template Fallback

extension MascotNarrator {

    /// Fully deterministic line for when Foundation Models is unavailable.
    static func template(for context: MascotContext) -> String {
        let name = context.name.isEmpty ? "" : ", \(context.name)"

        if context.isUnderSiege {
            return "Even embers relight\(name) — one small win today starts the rebuild."
        }
        if context.streak >= 7 {
            return "A \(context.streak)-day flame\(name) — steady fire outlasts a blaze."
        }
        if context.streak > 0 {
            return "Keep feeding the flame\(name) — every day adds to the fire."
        }
        switch context.tierName {
        case "ETERNAL":
            return "You've become the fire itself\(name). Keep it burning."
        case "RADIANT":
            return "Your light is steady\(name) — consistency got you here."
        case "RISING":
            return "You're rising\(name) — the climb only gets easier from here."
        case "AWAKENING":
            return "The spark caught\(name). Let's build on it today."
        default:
            return "Every phoenix starts in ash\(name). Today is a good day to rise."
        }
    }
}
