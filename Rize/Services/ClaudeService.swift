import Foundation
import NaturalLanguage

// MARK: - Models

struct PlanTask: Codable, Identifiable {
    var id = UUID()
    let title: String
    let duration: String
    let description: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case title, duration, description, type
    }
}

struct TaskPlan: Codable {
    let tasks: [PlanTask]
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidURL
    case notRunning
    case emptyResponse
    case requestTimedOut
    case invalidResponse(statusCode: Int?)
    case invalidPlanResponse
    case modelNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .notRunning: return "Could not connect to OpenRouter."
        case .emptyResponse: return "No response received."
        case .requestTimedOut: return "Request timed out."
        case .invalidResponse(let code): return "Invalid response (HTTP \(code ?? -1))."
        case .invalidPlanResponse: return "Could not parse the generated plan."
        case .modelNotSupported: return "The generative model is not supported on this device."
        }
    }
}

// MARK: - Service

final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    // MARK: - Generate Daily Plan

    func generateDailyPlan(
        energyScore: Int,
        goal: String,
        goalDetail: String,
        sleepHours: Double?,
        restingHeartRate: Double?,
        stepCount: Double?,
        activeEnergy: Double?,
        calendarEvents: String,
        calendarEnabled: Bool
    ) async throws -> [PlanTask] {
        let fitnessLevel = analyzeFitnessLevel(
            restingHR: restingHeartRate,
            steps: stepCount,
            sleep: sleepHours
        )

        let healthContext = buildHealthContext(
            sleep: sleepHours,
            hr: restingHeartRate,
            steps: stepCount,
            energy: activeEnergy,
            fitnessLevel: fitnessLevel
        )

        let calendarContext = calendarEnabled && !calendarEvents.isEmpty
            ? "UPCOMING EVENTS:\n\(calendarEvents)"
            : ""

        let userMessage = """
        Energy today: \(energyScore)/10
        Goal: \(goal) — \(goalDetail)
        Fitness level: \(fitnessLevel)
        \(healthContext)
        \(calendarContext)

        Generate 3 core tasks for today based on this energy level, then apply the CALENDAR CONTEXT rules to decide whether to add any extra tasks.
        """

        do {
            let content = try await callFoundationModel(
                userMessage: userMessage
            )
            return try parsePlanFromContent(content)
        } catch {
            return fallbackTasks(energyScore: energyScore, calendarEvents: await CalendarManager.shared.upcomingEvents)
        }
    }

    // MARK: - Generate Weekly Insight

    func generateWeeklyInsight(
        energyHistory: [Int],
        completionHistory: [Double]
    ) async throws -> String {
        let userMessage = """
        Last 7 days energy: \(energyHistory.map(String.init).joined(separator: ", "))
        Last 7 days completion rate: \(completionHistory.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: ", "))
        """

        let content = try await callFoundationModel(
            userMessage: userMessage
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Foundation Model Call

    private func callFoundationModel(userMessage: String) async throws -> String {
        if !supportsGenerativeModel() {
            throw OllamaError.modelNotSupported
        }

        let prompt = """
        Rewrite the following text in a warm, encouraging phoenix-themed tone:
        \(userMessage)
        """

        // Simulate calling Apple's Foundation Model
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let response = try await generateTextWithFoundationModel(prompt: prompt)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parsePlanFromContent(_ content: String) throws -> [PlanTask] {
        // Strip markdown code fences if present
        var cleaned = content
        if let start = cleaned.range(of: "```json") {
            cleaned = String(cleaned[start.upperBound...])
        } else if let start = cleaned.range(of: "```") {
            cleaned = String(cleaned[start.upperBound...])
        }
        if let end = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<end.lowerBound])
        }

        // Find JSON object
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw OllamaError.invalidPlanResponse
        }

        do {
            let plan = try JSONDecoder().decode(TaskPlan.self, from: data)
            guard !plan.tasks.isEmpty else { throw OllamaError.invalidPlanResponse }
            return plan.tasks
        } catch {
            throw OllamaError.invalidPlanResponse
        }
    }

    // MARK: - Fitness Level Analysis

    private func analyzeFitnessLevel(
        restingHR: Double?,
        steps: Double?,
        sleep: Double?
    ) -> String {
        var score = 0

        if let hr = restingHR {
            if hr < 50 { score += 3 }
            else if hr < 60 { score += 2 }
            else if hr < 70 { score += 1 }
        }

        if let s = steps {
            if s > 10000 { score += 3 }
            else if s > 7000 { score += 2 }
            else if s > 4000 { score += 1 }
        }

        if let sl = sleep {
            if sl >= 8 { score += 2 }
            else if sl >= 7 { score += 1 }
            else if sl < 5 { score -= 1 }
        }

        switch score {
        case 6...: return "Elite Athlete"
        case 4...5: return "Fit & Active"
        case 2...3: return "Average"
        default: return "Recovery Mode"
        }
    }

    private func buildHealthContext(
        sleep: Double?,
        hr: Double?,
        steps: Double?,
        energy: Double?,
        fitnessLevel: String
    ) -> String {
        var parts: [String] = []
        if let s = sleep { parts.append(String(format: "Sleep: %.1f hours", s)) }
        if let h = hr { parts.append(String(format: "Resting HR: %.0f bpm", h)) }
        if let st = steps { parts.append(String(format: "Steps yesterday: %.0f", st)) }
        if let e = energy { parts.append(String(format: "Active energy: %.0f cal", e)) }
        return parts.isEmpty ? "" : parts.joined(separator: "\n")
    }

    // MARK: - Fallback Tasks

    func fallbackTasks(energyScore: Int, calendarEvents: [RizeCalendarEvent] = []) -> [PlanTask] {
        var tasks = coreFallbackTasks(energyScore: energyScore)
        tasks += calendarFallbackTasks(energyScore: energyScore, calendarEvents: calendarEvents)
        return tasks
    }

    private func calendarFallbackTasks(energyScore: Int, calendarEvents: [RizeCalendarEvent]) -> [PlanTask] {
        switch energyScore {
        case 7...10:
            return calendarEvents
                .filter { $0.daysUntil <= 7 }
                .map { event in
                    PlanTask(
                        title: "Get Ahead: \(event.title)",
                        duration: "30 min",
                        description: event.daysUntil <= 1
                            ? "Due \(event.daysUntil <= 0 ? "today" : "tomorrow") — knock it out now."
                            : "Due in \(event.daysUntil) days — use today's energy to get ahead.",
                        type: "work"
                    )
                }
        default:
            return calendarEvents
                .filter { $0.daysUntil <= 1 }
                .map { event in
                    PlanTask(
                        title: "Prep: \(event.title)",
                        duration: "20 min",
                        description: event.daysUntil <= 0
                            ? "Due today — quick, light prep."
                            : "Due tomorrow — quick, light prep.",
                        type: "work"
                    )
                }
        }
    }

    private func coreFallbackTasks(energyScore: Int) -> [PlanTask] {
        switch energyScore {
        case 1...2:
            return [
                PlanTask(title: "Gentle Stretch", duration: "5 min", description: "Light stretching, no pressure.", type: "physical"),
                PlanTask(title: "One Page of Reading", duration: "10 min", description: "Just one page. That's it.", type: "work"),
                PlanTask(title: "Deep Breathing", duration: "5 min", description: "4-7-8 breathing to reset.", type: "recovery")
            ]
        case 3...4:
            return [
                PlanTask(title: "Easy Walk", duration: "15 min", description: "Fresh air, slow pace.", type: "physical"),
                PlanTask(title: "Review Notes", duration: "20 min", description: "Look over recent material.", type: "work"),
                PlanTask(title: "Hydration Check", duration: "5 min", description: "Drink water, prep for tomorrow.", type: "recovery")
            ]
        case 5...6:
            return [
                PlanTask(title: "30-Min Run or Bike", duration: "30 min", description: "Moderate pace, stay comfortable.", type: "physical"),
                PlanTask(title: "Focused Study Block", duration: "45 min", description: "One subject, deep focus.", type: "work"),
                PlanTask(title: "Wind-Down Routine", duration: "10 min", description: "Prep for tomorrow.", type: "recovery")
            ]
        case 7...8:
            return [
                PlanTask(title: "Strength Training", duration: "45 min", description: "Push your limits today.", type: "physical"),
                PlanTask(title: "Deep Work Sprint", duration: "60 min", description: "Hardest task first, no distractions.", type: "work"),
                PlanTask(title: "Cold Shower", duration: "5 min", description: "Build mental toughness.", type: "recovery")
            ]
        default:
            return [
                PlanTask(title: "High-Intensity Workout", duration: "60 min", description: "Max effort. Today is yours.", type: "physical"),
                PlanTask(title: "Productive Sprint Session", duration: "90 min", description: "Peak state — use it.", type: "work"),
                PlanTask(title: "Mobility & Recovery", duration: "15 min", description: "Recover right to stay consistent.", type: "recovery")
            ]
        }
    }

    // MARK: - Generative Model Support

    private func supportsGenerativeModel() -> Bool {
        // Check if the device supports Apple's Foundation Models
        return NLLanguageTag.phoenix != nil
    }

    private func generateTextWithFoundationModel(prompt: String) async throws -> String {
        // Simulate generating text with Apple's Foundation Model
        let templateResponse = """
        Phoenix-themed response:
        \(prompt)
        """
        return templateResponse
    }
}
