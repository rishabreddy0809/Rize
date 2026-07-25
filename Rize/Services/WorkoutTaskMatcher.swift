import Foundation

/// Decides whether a real HealthKit workout satisfies a planned "workout"
/// task — e.g. a logged 5.1-mile run should check off "Easy 5-mile run"
/// without the user tapping it. Matching requires both a plausible activity
/// type (from the task's own title/description) and the task's stated
/// distance or duration to be within tolerance of what was actually logged,
/// so an unrelated workout can't accidentally complete the wrong task.
enum WorkoutTaskMatcher {
    private static let typeKeywords: [String: [String]] = [
        "Run": ["run", "jog"],
        "Ride": ["ride", "bike", "cycl"],
        "Walk": ["walk"],
        "Swim": ["swim"],
        "Hike": ["hike", "hiking"],
        "Row": ["row"],
        "Yoga": ["yoga"],
        "Strength": ["strength", "lift", "gym", "weight"],
        "HIIT": ["hiit", "interval"],
        "Elliptical": ["elliptical"]
    ]

    static func matches(workout: WorkoutSummary, task: RizeTask) -> Bool {
        guard task.type == PlanCategory.workout.rawValue, !task.completed else { return false }
        let haystack = "\(task.title) \(task.taskDescription)".lowercased()

        // If we recognize the workout type, require the task to actually be
        // about that activity — a bike ride shouldn't complete a run task.
        if let keywords = typeKeywords[workout.type], !keywords.contains(where: haystack.contains) {
            return false
        }

        if let targetMiles = distanceMiles(from: task.duration) {
            guard workout.distanceMiles > 0 else { return false }
            let tolerance = max(targetMiles * 0.15, 0.25)
            return abs(workout.distanceMiles - targetMiles) <= tolerance
        }

        if let targetMinutes = minutes(from: task.duration) {
            let actualMinutes = workout.movingTime / 60
            guard actualMinutes > 0 else { return false }
            let tolerance = max(targetMinutes * 0.25, 5)
            return abs(actualMinutes - targetMinutes) <= tolerance
        }

        return false
    }

    /// Parses "5 mi", "5 miles", or "8 km" into miles. `nil` if the string
    /// doesn't state a distance at all (so callers fall back to duration).
    private static func distanceMiles(from duration: String) -> Double? {
        let lower = duration.lowercased()
        guard let value = leadingNumber(lower) else { return nil }
        if lower.contains("km") || lower.contains("kilomet") { return value / 1.609344 }
        // Word-boundary match, not a bare substring check — "40 min" contains
        // "mi" too (as the first two letters of "min"), which used to make
        // every plain-minutes duration misparse as a mile distance and skip
        // straight to the distance branch below. Since that branch then
        // requires `workout.distanceMiles > 0`, any distance-less workout
        // (strength training, yoga, anything indoor) could never match a task
        // like "40 min" at all — this regex requires "mi"/"mile"/"miles" as
        // its own word so "min" no longer qualifies.
        if lower.range(of: #"\bmi(le)?s?\b"#, options: .regularExpression) != nil { return value }
        return nil
    }

    /// Parses "40 min" or "1 hr" into minutes. `nil` unless the string
    /// explicitly states a time unit.
    private static func minutes(from duration: String) -> Double? {
        let lower = duration.lowercased()
        guard lower.contains("min") || lower.contains("hr") || lower.contains("hour") else { return nil }
        guard let value = leadingNumber(lower) else { return nil }
        return (lower.contains("hr") || lower.contains("hour")) ? value * 60 : value
    }

    private static func leadingNumber(_ string: String) -> Double? {
        let numberString = string.prefix { $0.isNumber || $0 == "." }
        return Double(numberString)
    }
}
