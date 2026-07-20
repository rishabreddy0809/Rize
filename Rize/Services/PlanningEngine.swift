import Foundation

class PlanningEngine {
    static let shared = PlanningEngine()
    
    private init() {}
    
    func generateDailyPlan(
        energyLevel: Int,
        mood: String,
        tasks: [RizeTask],
        taskDueDates: [Date],
        taskPriorities: [TaskPriority],
        calendarEvents: [RizeCalendarEvent],
        sleepData: Double?,
        stravaWorkouts: [Workout]?,
        currentStreak: Int,
        userGoals: String
    ) -> DailyPlan {
        // Sort tasks by priority and due date
        let sortedTasks = sortTasksByPriorityAndDueDate(tasks, taskPriorities)
        
        var recommendedTasks: [Task] = []
        var postponedTasks: [RizeTask] = []
        var workoutRecommendation: String?
        var restRecommendation: String?
        var estimatedWorkload: DailyPlan.Workload
        var confidenceScore: Double
        var reasoning: String
        
        // Determine workload based on energy level and sleep data
        estimatedWorkload = determineWorkload(energyLevel, sleepData)
        
        // Determine recommendations based on energy level
        (recommendedTasks, postponedTasks, workoutRecommendation, restRecommendation, confidenceScore, reasoning) = determineRecommendations(
            energyLevel,
            sortedTasks,
            taskPriorities,
            stravaWorkouts,
            estimatedWorkload
        )
        
        // Adjust recommendations based on deadlines
        recommendedTasks.append(contentsOf: tasksDueToday(tasks))
        recommendedTasks.append(contentsOf: tasksDueTomorrow(tasks))
        
        // Ensure no more than the user can realistically complete
        let maxTasks = determineMaxTasks(energyLevel)
        recommendedTasks = Array(recommendedTasks.prefix(maxTasks))
        
        return DailyPlan(
            recommendedTasks: recommendedTasks,
            postponedTasks: postponedTasks,
            workoutRecommendation: workoutRecommendation,
            restRecommendation: restRecommendation,
            estimatedWorkload: estimatedWorkload,
            confidenceScore: confidenceScore,
            reasoning: reasoning
        )
    }
    
    private func sortTasksByPriorityAndDueDate(_ tasks: [RizeTask], _ taskPriorities: [TaskPriority]) -> [RizeTask] {
        return tasks.sorted { (task1, task2) in
            if task1.completedAt == nil && task2.completedAt != nil {
                return true
            } else if task1.completedAt != nil && task2.completedAt == nil {
                return false
            }
            return taskPriorities.firstIndex(of: TaskPriority(rawValue: task1.priority ?? "") ?? .low) < taskPriorities.firstIndex(of: TaskPriority(rawValue: task2.priority ?? "") ?? .low)
        }
    }
    
    private func determineWorkload(_ energyLevel: Int, _ sleepData: Double?) -> DailyPlan.Workload {
        if let sleepData = sleepData {
            if sleepData < 5 {
                return .light
            } else if sleepData > 8 && energyLevel >= 8 {
                return .heavy
            } else {
                return energyLevel <= 4 ? .light : (energyLevel <= 7 ? .moderate : .heavy)
            }
        } else {
            return energyLevel <= 4 ? .light : (energyLevel <= 7 ? .moderate : .heavy)
        }
    }
    
    private func determineRecommendations(
        _ energyLevel: Int,
        _ sortedTasks: [RizeTask],
        _ taskPriorities: [TaskPriority],
        _ stravaWorkouts: [Workout]?,
        _ estimatedWorkload: DailyPlan.Workload
    ) -> ([Task], [RizeTask], String?, String?, Double, String) {
        var recommendedTasks: [Task] = []
        var postponedTasks: [RizeTask] = []
        var workoutRecommendation: String?
        var restRecommendation: String?
        var confidenceScore: Double
        var reasoning: String
        
        switch energyLevel {
        case 1...2:
            recommendedTasks = sortedTasks.filter { $0.completedAt == nil }.prefix(3).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
            postponedTasks = sortedTasks.filter { $0.completedAt == nil && taskPriorities.firstIndex(of: TaskPriority(rawValue: $0.priority ?? "") ?? .low) < taskPriorities.firstIndex(of: TaskPriority.high) }
            workoutRecommendation = "Optional light workout"
            restRecommendation = "Rest or a very light workout"
            confidenceScore = 0.8
            reasoning = "Low energy level, focusing on required tasks and rest."
        case 3...4:
            recommendedTasks = sortedTasks.filter { $0.completedAt == nil && taskPriorities.firstIndex(of: TaskPriority(rawValue: $0.priority ?? "") ?? .low) < taskPriorities.firstIndex(of: TaskPriority.medium) }.prefix(3).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
            postponedTasks = sortedTasks.filter { $0.completedAt == nil && taskPriorities.firstIndex(of: TaskPriority(rawValue: $0.priority ?? "") ?? .low) >= taskPriorities.firstIndex(of: TaskPriority.medium) }
            workoutRecommendation = "Optional short workout"
            restRecommendation = "Avoid adding future work"
            confidenceScore = 0.8
            reasoning = "Moderate energy level, focusing on important tasks and avoiding future work."
        case 5...7:
            recommendedTasks = sortedTasks.filter { $0.completedAt == nil }.prefix(3).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
            if estimatedWorkload == .moderate {
                let upcomingTasks = tasks.filter { Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 <= 7 && $0.completedAt == nil }
                recommendedTasks.append(contentsOf: upcomingTasks.prefix(1).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") })
            }
            postponedTasks = sortedTasks.filter { $0.completedAt == nil && Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 > 7 }
            workoutRecommendation = "Optional moderate workout"
            restRecommendation = "Complete today's tasks and manage workload"
            confidenceScore = 0.8
            reasoning = "High energy level, completing today's tasks and managing workload."
        case 8...10:
            recommendedTasks = sortedTasks.filter { $0.completedAt == nil }.prefix(3).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
            let upcomingTasks = tasks.filter { Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 <= 7 && $0.completedAt == nil }
            recommendedTasks.append(contentsOf: upcomingTasks.prefix(2).map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") })
            postponedTasks = sortedTasks.filter { $0.completedAt == nil && Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 > 7 }
            workoutRecommendation = "Optional ambitious workout"
            restRecommendation = "Complete today's tasks and get ahead on upcoming work"
            confidenceScore = 0.8
            reasoning = "Very high energy level, completing today's tasks and getting ahead on upcoming work."
        default:
            recommendedTasks = []
            postponedTasks = sortedTasks.filter { $0.completedAt == nil }
            workoutRecommendation = "Optional light workout"
            restRecommendation = "Rest or a very light workout"
            estimatedWorkload = .light
            confidenceScore = 0.8
            reasoning = "Unknown energy level, focusing on required tasks and rest."
        }
        
        // Adjust recommendations based on recent workouts
        if let stravaWorkouts = stravaWorkouts, !stravaWorkouts.isEmpty {
            let lastWorkout = stravaWorkouts.last!
            if lastWorkout.distance > 10 { // Intense workout
                recommendedTasks.append(Task(title: "Recovery", duration: "30 min", description: "Rest and recover from intense workout", type: "recovery"))
                restRecommendation = "Recover from intense workout"
            } else {
                recommendedTasks.append(Task(title: "Consistency", duration: "30 min", description: "Maintain consistency with workouts", type: "workout"))
                workoutRecommendation = "Optional light workout for consistency"
            }
        } else {
            recommendedTasks.append(Task(title: "Consistency", duration: "30 min", description: "Maintain consistency with workouts", type: "workout"))
            workoutRecommendation = "Optional light workout for consistency"
        }
        
        return (recommendedTasks, postponedTasks, workoutRecommendation, restRecommendation, confidenceScore, reasoning)
    }
    
    private func tasksDueToday(_ tasks: [RizeTask]) -> [Task] {
        return tasks.filter { Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 == 0 && $0.completedAt == nil }.map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
    }
    
    private func tasksDueTomorrow(_ tasks: [RizeTask]) -> [Task] {
        return tasks.filter { Calendar.current.dateComponents([.day], from: Date(), to: $0.dueDate ?? Date()).day ?? 0 == 1 && $0.completedAt == nil }.map { Task(title: $0.taskDescription, duration: "30 min", description: $0.taskDescription, type: "work") }
    }
    
    private func determineMaxTasks(_ energyLevel: Int) -> Int {
        return energyLevel <= 4 ? 2 : (energyLevel <= 7 ? 4 : 6)
    }
}
