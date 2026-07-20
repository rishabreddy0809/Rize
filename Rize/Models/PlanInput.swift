import Foundation

// MARK: - Task Priority

/// Relative importance of a task, independent of persistence or UI.
/// `Comparable` so the engine can order deterministically (`.high > .medium > .low`).
enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low

    /// Higher value == more important. Used for deterministic ordering.
    var sortValue: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        }
    }
}

extension TaskPriority: Comparable {
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortValue < rhs.sortValue
    }
}

// MARK: - Task Category

/// The kind of work a task represents. Mirrors the persisted `RizeTask.type`
/// string values, but as a type-safe domain concept for the engine.
enum TaskCategory: String, Codable, CaseIterable, Sendable {
    case physical
    case work
    case recovery
    case other

    init(rawValueLenient raw: String?) {
        self = TaskCategory(rawValue: raw?.lowercased() ?? "") ?? .other
    }
}

// MARK: - Planning Task

/// A UI/persistence-independent value type the engine reasons over.
/// Map a SwiftData `RizeTask` into this at the call site so the engine never
/// imports SwiftData.
struct PlanningTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let priority: TaskPriority
    let dueDate: Date?
    let isCompleted: Bool
    let estimatedMinutes: Int
    let category: TaskCategory

    init(
        id: UUID = UUID(),
        title: String,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        estimatedMinutes: Int = 30,
        category: TaskCategory = .work
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.category = category
    }
}

// MARK: - Sleep

/// A night's sleep, summarised for planning.
struct SleepSummary: Equatable, Sendable {
    /// Total time asleep, in hours.
    let hours: Double

    /// Deterministic quality band used by the engine's sleep rules.
    var quality: SleepQuality {
        switch hours {
        case ..<5:  return .insufficient   // <5h  → reduce workload, prioritise recovery
        case 5..<8: return .adequate       // 5–7h → normal planning
        default:    return .ample          // 8h+  → allow increased workload
        }
    }
}

enum SleepQuality: String, Sendable {
    case insufficient
    case adequate
    case ample
}

// MARK: - Workout

/// Where a workout came from. Lets us blend HealthKit and Strava without
/// double-counting the same session downstream.
enum WorkoutSource: String, Codable, Sendable {
    case healthKit
    case strava
    case manual
}

/// Deterministic intensity classification for planning decisions.
enum WorkoutIntensity: Int, Comparable, Sendable {
    case rest = 0
    case light = 1
    case moderate = 2
    case hard = 3

    static func < (lhs: WorkoutIntensity, rhs: WorkoutIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single completed workout, unified across HealthKit and Strava so the
/// engine and UI share one model.
struct WorkoutSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Human-readable activity type, e.g. "Run", "Ride", "Strength".
    let type: String
    let startDate: Date
    let distanceMeters: Double
    let movingTime: TimeInterval
    let elevationGain: Double
    let averageHeartRate: Double?
    let source: WorkoutSource

    init(
        id: UUID = UUID(),
        type: String,
        startDate: Date,
        distanceMeters: Double = 0,
        movingTime: TimeInterval = 0,
        elevationGain: Double = 0,
        averageHeartRate: Double? = nil,
        source: WorkoutSource = .manual
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.movingTime = movingTime
        self.elevationGain = elevationGain
        self.averageHeartRate = averageHeartRate
        self.source = source
    }

    var distanceKilometers: Double { distanceMeters / 1000 }

    /// Classify effort from distance and duration. Deterministic and
    /// intentionally conservative — a "hard" day should genuinely be hard.
    var intensity: WorkoutIntensity {
        let km = distanceKilometers
        let minutes = movingTime / 60

        if km >= 10 || minutes >= 60 { return .hard }
        if km >= 5 || minutes >= 30 { return .moderate }
        if km > 0 || minutes > 0 { return .light }
        return .rest
    }
}

// MARK: - Calendar Event

/// A deadline-bearing event, decoupled from EventKit.
struct PlanningCalendarEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let date: Date
    let isAcademic: Bool

    init(id: UUID = UUID(), title: String, date: Date, isAcademic: Bool = false) {
        self.id = id
        self.title = title
        self.date = date
        self.isAcademic = isAcademic
    }
}

// MARK: - Energy

/// The four adaptive energy bands that drive planning.
enum EnergyBand: Sendable {
    case depleted   // 1–2
    case low        // 3–4
    case steady     // 5–7
    case high       // 8–10

    init(energy: Int) {
        switch max(1, min(10, energy)) {
        case 1...2:  self = .depleted
        case 3...4:  self = .low
        case 5...7:  self = .steady
        default:     self = .high
        }
    }
}

// MARK: - Plan Input

/// The complete, deterministic input to `PlanningEngine`. Everything the engine
/// needs is here — it reaches out to no singletons, frameworks, or clocks.
struct PlanInput: Sendable {
    /// "Now". Injected so planning is deterministic and testable.
    var referenceDate: Date
    /// Self-reported energy, 1–10 (clamped by the engine).
    var energy: Int
    var mood: String?
    var tasks: [PlanningTask]
    var calendarEvents: [PlanningCalendarEvent]
    var sleep: SleepSummary?
    /// Recent workouts, any order. The engine sorts internally.
    var recentWorkouts: [WorkoutSummary]
    var goals: String
    var currentStreak: Int
    /// Yesterday's plan, if any — used for continuity and confidence.
    var previousPlan: DailyPlan?
    /// Calendar used for all day-difference math. Defaults to `.current`.
    var calendar: Calendar

    init(
        referenceDate: Date = Date(),
        energy: Int,
        mood: String? = nil,
        tasks: [PlanningTask] = [],
        calendarEvents: [PlanningCalendarEvent] = [],
        sleep: SleepSummary? = nil,
        recentWorkouts: [WorkoutSummary] = [],
        goals: String = "",
        currentStreak: Int = 0,
        previousPlan: DailyPlan? = nil,
        calendar: Calendar = .current
    ) {
        self.referenceDate = referenceDate
        self.energy = energy
        self.mood = mood
        self.tasks = tasks
        self.calendarEvents = calendarEvents
        self.sleep = sleep
        self.recentWorkouts = recentWorkouts
        self.goals = goals
        self.currentStreak = currentStreak
        self.previousPlan = previousPlan
        self.calendar = calendar
    }

    /// Energy clamped to the valid 1–10 range.
    var clampedEnergy: Int { max(1, min(10, energy)) }
    var energyBand: EnergyBand { EnergyBand(energy: clampedEnergy) }
}
