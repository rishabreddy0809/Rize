import Foundation

struct RyzDialogue {

    // MARK: - Energy Log Response

    static func onEnergyLog(_ energy: Int) -> String {
        switch energy {
        case 1...2:
            return "That's okay. I'm not going anywhere."
        case 3...4:
            return "Showing up on a \(energy) is harder than a 10. I see that."
        case 5...6:
            return "Solid. Let's make something out of today."
        case 7...8:
            return "You're locked in. Don't waste it."
        default:
            return "LET'S GO. 🔥"
        }
    }

    // MARK: - Task Complete

    static func onTaskComplete(_ taskNumber: Int, allDone: Bool) -> String {
        if allDone { return "All done. The flame holds strong. 🌅" }
        switch taskNumber {
        case 1: return "One down. That's all it takes to start."
        case 2: return "You're actually doing this."
        case 3: return "Three. Consistent. This is who you are."
        default: return "Keep going. Every rep counts."
        }
    }

    // MARK: - Streak Milestone

    static func onStreakMilestone(_ streak: Int) -> String {
        switch streak {
        case 3: return "3 days. You're building something real."
        case 7: return "A week straight. Your flame is blazing. ✨"
        case 14: return "Two weeks. This is who you are now."
        case 30: return "30 days. You changed. For real. 🌅"
        default: return "\(streak) days straight. Keep going."
        }
    }

    // MARK: - Daily Word

    static func dailyWord(for energy: Int) -> (word: String, subtitle: String) {
        switch energy {
        case 1...2:
            return ("BRAVE", "Showing up when it's hardest takes real courage.")
        case 3...4:
            return ("STEADY", "Not every day is a 10. Steady is enough.")
        case 5...6:
            return ("SOLID", "A solid day is better than no day.")
        case 7...8:
            return ("LOCKED IN", "You're in the zone. Use it.")
        default:
            return ("UNSTOPPABLE", "This is your day. Own every minute.")
        }
    }

    // MARK: - Mascot Tap

    static func mascotTap(energy: Int) -> String {
        switch energy {
        case 1...3:
            return "You showed up. That's the whole battle."
        case 4...6:
            return "Middle days become great days. Keep going."
        default:
            return "The fire is watching. Don't let it fade now."
        }
    }

    // MARK: - Random Idle

    static func randomIdle() -> String {
        let lines = [
            "Your flame grows every time you show up.",
            "Low days are the best training for high days.",
            "Consistency beats intensity. Always.",
            "The only bad workout is the one you skipped.",
            "Every rep, every task, every day — it compounds.",
            "You don't have to feel ready. You just have to start.",
            "Champions don't wait for motivation. They build it.",
            "Rize isn't about perfection. It's about persistence.",
            "One task done is infinitely better than zero.",
            "The fire remembers every day you showed up."
        ]
        return lines.randomElement() ?? lines[0]
    }

    // MARK: - Siege Messages

    static func siegeMessage() -> String {
        "Your flame is fading. One task will reignite it."
    }

    static func siegeBrokenMessage(bonusXP: Int) -> String {
        "Rising from ash. +\(bonusXP) XP earned."
    }

    // MARK: - Morning Notification

    static func morningNotification(yesterdayEnergy: Int?, completedTasks: Int) -> String {
        if completedTasks == 0 {
            return "No streak to protect. Perfect time to start."
        }
        if let energy = yesterdayEnergy, energy <= 3, completedTasks > 0 {
            return "Yesterday was hard. Today's a new one."
        }
        if completedTasks >= 3 {
            return "You crushed it yesterday. Let's go again. 🔥"
        }
        return "Hey. New day. What's your energy? 🌅"
    }
}
