import XCTest
@testable import Rize

class PlanningEngineTests: XCTestCase {
    
    func testEnergy2Sleep4OverdueAssignment() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 2,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: 4.0,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 2)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout")
        XCTAssertEqual(plan.restRecommendation, "Rest or a very light workout")
    }
    
    func testEnergy9Sleep9NoDeadlines() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 9,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: 9.0,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 3)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional ambitious workout")
        XCTAssertEqual(plan.restRecommendation, "Complete today's tasks and get ahead on upcoming work")
    }
    
    func testEnergy5IntenseRunYesterday() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), completedAt: nil)
        ]
        
        let stravaWorkouts = [
            Workout(distance: 15.0) // Intense run
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 5,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: nil,
            stravaWorkouts: stravaWorkouts,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 3)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout for consistency")
        XCTAssertEqual(plan.restRecommendation, "Recover from intense workout")
    }
    
    func testEnergy10PoorSleep() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 10,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: 3.0,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 6)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional ambitious workout")
        XCTAssertEqual(plan.restRecommendation, "Complete today's tasks and get ahead on upcoming work")
    }
    
    func testEnergy3FiveTasksDueToday() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 3", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 4", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 5", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 3,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: nil,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 2)
        XCTAssertEqual(plan.postponedTasks.count, 3)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout")
        XCTAssertEqual(plan.restRecommendation, "Rest or a very light workout")
    }
    
    func testEmptyTaskList() {
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 5,
            mood: "",
            tasks: [],
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: nil,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 0)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout for consistency")
        XCTAssertEqual(plan.restRecommendation, "Complete today's tasks and manage workload")
    }
    
    func testNoHealthKitData() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 5,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: nil,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 3)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout for consistency")
        XCTAssertEqual(plan.restRecommendation, "Complete today's tasks and manage workload")
    }
    
    func testNoStravaData() {
        let tasks = [
            RizeTask(taskDescription: "Task 1", dueDate: Calendar.current.date(byAdding: .day, value: 0, to: Date()), completedAt: nil),
            RizeTask(taskDescription: "Task 2", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), completedAt: nil)
        ]
        
        let plan = PlanningEngine.shared.generateDailyPlan(
            energyLevel: 5,
            mood: "",
            tasks: tasks,
            taskDueDates: [],
            taskPriorities: [.high, .medium, .low],
            calendarEvents: [],
            sleepData: nil,
            stravaWorkouts: nil,
            currentStreak: 1,
            userGoals: ""
        )
        
        XCTAssertEqual(plan.recommendedTasks.count, 3)
        XCTAssertEqual(plan.postponedTasks.count, 0)
        XCTAssertEqual(plan.workoutRecommendation, "Optional light workout for consistency")
        XCTAssertEqual(plan.restRecommendation, "Complete today's tasks and manage workload")
    }
}
