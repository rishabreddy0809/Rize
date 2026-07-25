import SwiftUI

struct Constants {
    // NOTE: Rize uses only Apple's on-device Foundation Models for coaching
    // narration — no cloud AI, no API keys. Any prior OpenRouter/OpenAI/Anthropic
    // credentials have been removed. (Full AI migration lands in Phase 2.)

    static let cornerRadius: CGFloat = 20
    static let accentColor = Color(hex: "0A84FF")

    // XP
    static let baseXPPerTask = 20
    static let lowEnergyMultiplier = 2.5   // energy 1-3
    static let mediumEnergyMultiplier = 1.5 // energy 4-6
    static let highEnergyMultiplier = 1.0   // energy 7-10
    static let streakBonus = 50             // added when streak >= 7
    static let allTasksBonus = 100          // completing all tasks

    static let springAnimation = Animation.spring(response: 0.45, dampingFraction: 0.78)

    static func energyColor(for energy: Int) -> Color {
        let clamped = max(1, min(10, energy))
        let t = Double(clamped - 1) / 9.0
        let r = 1.0 - t * 0.5
        let g = t * 0.85
        return Color(red: r, green: g, blue: 0.1)
    }

    // Coaching prompts now live with the on-device narrator (`CoachingNarrator`),
    // grounded in the deterministic `DailyPlan`. No cloud prompt templates here.
}
