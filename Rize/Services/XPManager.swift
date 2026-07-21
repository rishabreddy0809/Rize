import Foundation

@MainActor
final class XPManager: ObservableObject {
    @AppStorage("kingdom_realmDefense") var realmDefense: Int = 100
    @AppStorage("kingdom_isUnderSiege") var isUnderSiege: Bool = false
    
    // Add a property to store the daily plan
    @Published var dailyPlan: DailyPlan = DailyPlan(
        recommendedTasks: [],
        deferredTasks: [],
        workblockTasks: [],  // Initialize with an empty array
        workout: WorkoutRecommendation(),
        recovery: RecoveryRecommendation(),
        workload: Workload(),
        confidence: 0.0,
        burnoutRisk: BurnoutRisk()
    )
    
    // Add a method to update the daily plan
    func updateDailyPlan(_ newPlan: DailyPlan) {
        dailyPlan = newPlan
    }
}
