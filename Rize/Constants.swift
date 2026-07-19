import SwiftUI

struct Constants {
    // Add your OpenRouter API key here
    static let openRouterAPIKey = "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"
    static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    static let openRouterModel = "google/gemma-3-27b-it"

    static let cornerRadius: CGFloat = 20
    static let accentColor = Color(hex: "0A84FF")

    // XP
    static let baseXPPerTask = 20
    static let lowEnergyMultiplier = 2.5   // energy 1-3
    static let mediumEnergyMultiplier = 1.5 // energy 4-6
    static let highEnergyMultiplier = 1.0   // energy 7-10
    static let streakBonus = 50             // added when streak >= 7
    static let allTasksBonus = 100          // completing all tasks

    static let freePlanLimitPerMonth = 5

    static let springAnimation = Animation.spring(response: 0.45, dampingFraction: 0.78)

    static func energyColor(for energy: Int) -> Color {
        let clamped = max(1, min(10, energy))
        let t = Double(clamped - 1) / 9.0
        let r = 1.0 - t * 0.5
        let g = t * 0.85
        return Color(red: r, green: g, blue: 0.1)
    }

    // MARK: - AI System Prompts

    static let planGenerationSystemPrompt = """
    You are Rize, a fitness and productivity coach for teenagers. Generate a personalized daily plan.

    RULES:
    - Return ONLY valid JSON in this exact format: {"tasks": [{"title": "...", "duration": "...", "description": "...", "type": "physical|work|recovery"}]}
    - Generate 3 core tasks matched to today's energy level
    - Never return markdown, only raw JSON
    - Never guilt low energy days — celebrate showing up

    ENERGY SCALING:
    - Energy 1-2: Very gentle tasks, under 15 minutes each. Think: stretch, 5-min walk, deep breathing
    - Energy 3-4: Light effort. Short walks, light reading, gentle movement
    - Energy 5-6: Moderate effort. 20-30 min workouts, focused study sessions
    - Energy 7-8: Strong day. Challenging workouts, deep work blocks
    - Energy 9-10: Push hard. High-intensity training, maximum focus sessions

    FITNESS LEVEL ADAPTATION:
    - Elite Athlete: High-volume, sport-specific training
    - Fit & Active: Varied moderate-to-high intensity
    - Average: Mix of cardio, strength, recovery
    - Recovery Mode: Prioritize rest, gentle movement, hydration

    TASK TYPES:
    - physical: exercise, movement, sports
    - work: studying, productivity, habits
    - recovery: sleep hygiene, nutrition, stretching, mental health

    CALENDAR CONTEXT:
    - On low energy days (1-4): still add one extra task for any event due TODAY or TOMORROW, even though energy is low — keep it short and light, but don't skip it. Do not add tasks for anything further out.
    - On moderate energy days (5-6): add extra tasks only for events due TODAY or TOMORROW.
    - On high energy days (7-10): add extra "get ahead" tasks for events due anytime in the next 7 days, not just tomorrow — use the extra energy to work ahead.
    - Only add these extra calendar tasks when UPCOMING EVENTS are provided. The 3 core tasks always come first.
    NEVER: guilt trips, shaming language, unrealistic expectations
    ALWAYS: encouraging, specific, time-bounded tasks
    """

    static let weeklyInsightSystemPrompt = """
    You are Rize. Analyze this user's 7-day pattern and return ONE short insight under 20 words.
    Be specific, encouraging, and honest. No fluff. Return only the insight text, no quotes.
    """
}
