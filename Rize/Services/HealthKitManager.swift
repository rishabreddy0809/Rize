import Foundation
import HealthKit
import SwiftUI

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var sleepHours: Double? = nil
    @Published var restingHeartRate: Double? = nil
    @Published var stepCount: Double? = nil
    @Published var activeEnergy: Double? = nil
    @Published var recentWorkouts: [WorkoutSummary] = []
    @Published var isAuthorized: Bool = false

    private let store = HKHealthStore()

    /// How far back to pull workouts for the planning engine.
    private let workoutLookbackDays = 7

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Clean Models for PlanningEngine

    /// Sleep as the engine's domain type.
    var sleepSummary: SleepSummary? {
        sleepHours.map { SleepSummary(hours: $0) }
    }

    /// A clean, framework-independent aggregate the engine and UI can consume.
    var snapshot: HealthSnapshot {
        HealthSnapshot(
            sleep: sleepSummary,
            recentWorkouts: recentWorkouts,
            restingHeartRate: restingHeartRate,
            activeEnergy: activeEnergy,
            stepCount: stepCount
        )
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.workoutType()
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await fetchAll()
        } catch {
            // Authorization denied or not available on this device
            isAuthorized = false
            loadMockData()
        }
    }

    // MARK: - Fetch All

    func fetchAll() async {
        // Sequential fetches — HealthKit queries are I/O-bound,
        // and async let with @MainActor methods causes actor-isolation warnings.
        sleepHours = await fetchSleepHours()
        restingHeartRate = await fetchRestingHeartRate()
        stepCount = await fetchStepCount()
        activeEnergy = await fetchActiveEnergy()
        recentWorkouts = await fetchWorkouts()
    }

    // MARK: - Workouts

    /// Recent workouts mapped into the shared `WorkoutSummary` domain type.
    /// Returns `[]` (never throws) so planning always proceeds.
    private func fetchWorkouts() async -> [WorkoutSummary] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -workoutLookbackDays, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 25
        )
        do {
            let workouts = try await descriptor.result(for: store)
            return workouts.map { $0.asWorkoutSummary() }
        } catch {
            return []
        }
    }

    // MARK: - Sleep

    private func fetchSleepHours() async -> Double? {
        guard isAvailable else { return simulatorMock(.sleep) }
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let start = Calendar.current.startOfDay(for: yesterday)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            let asleepSamples = samples.filter {
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            }
            let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return totalSeconds > 0 ? totalSeconds / 3600 : nil
        } catch {
            return simulatorMock(.sleep)
        }
    }

    // MARK: - Resting Heart Rate

    private func fetchRestingHeartRate() async -> Double? {
        guard isAvailable else { return simulatorMock(.restingHR) }
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            end: Date()
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        do {
            let stats = try await descriptor.result(for: store)
            return stats?.averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        } catch {
            return simulatorMock(.restingHR)
        }
    }

    // MARK: - Step Count

    private func fetchStepCount() async -> Double? {
        guard isAvailable else { return simulatorMock(.steps) }
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let stats = try await descriptor.result(for: store)
            return stats?.sumQuantity()?.doubleValue(for: .count())
        } catch {
            return simulatorMock(.steps)
        }
    }

    // MARK: - Active Energy

    private func fetchActiveEnergy() async -> Double? {
        guard isAvailable else { return simulatorMock(.energy) }
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let stats = try await descriptor.result(for: store)
            return stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
        } catch {
            return simulatorMock(.energy)
        }
    }

    // MARK: - Simulator Mocks

    private enum MockMetric { case sleep, restingHR, steps, energy }

    // nonisolated: returns constants only, no actor-protected state accessed
    nonisolated private func simulatorMock(_ metric: MockMetric) -> Double {
        switch metric {
        case .sleep: return 7.2
        case .restingHR: return 62.0
        case .steps: return 6800.0
        case .energy: return 320.0
        }
    }

    private func loadMockData() {
        sleepHours = 7.2
        restingHeartRate = 62.0
        stepCount = 6800.0
        activeEnergy = 320.0
        recentWorkouts = []
    }
}

// MARK: - Health Snapshot

/// A clean, framework-independent aggregate of a user's recent health signals,
/// suitable as input to `PlanningEngine`.
struct HealthSnapshot: Sendable {
    var sleep: SleepSummary?
    var recentWorkouts: [WorkoutSummary]
    var restingHeartRate: Double?
    var activeEnergy: Double?
    var stepCount: Double?

    static let empty = HealthSnapshot(sleep: nil, recentWorkouts: [], restingHeartRate: nil, activeEnergy: nil, stepCount: nil)
}

// MARK: - HKWorkout Mapping

private extension HKWorkout {
    /// Project a HealthKit workout into the shared domain type. Uses statistics
    /// APIs (not the deprecated `totalDistance`) and degrades gracefully when a
    /// metric isn't present for this activity type.
    func asWorkoutSummary() -> WorkoutSummary {
        let distance = distanceMeters()
        let hr = statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        let elevation = (metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter()) ?? 0

        return WorkoutSummary(
            type: workoutActivityType.displayName,
            startDate: startDate,
            distanceMeters: distance,
            movingTime: duration,
            elevationGain: elevation,
            averageHeartRate: hr,
            source: .healthKit
        )
    }

    private func distanceMeters() -> Double {
        let candidates: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming
        ]
        for id in candidates {
            if let q = statistics(for: HKQuantityType(id))?.sumQuantity() {
                return q.doubleValue(for: .meter())
            }
        }
        return 0
    }
}

private extension HKWorkoutActivityType {
    /// A short, human-readable label for the common activity types.
    var displayName: String {
        switch self {
        case .running:                                     return "Run"
        case .cycling:                                     return "Ride"
        case .walking:                                     return "Walk"
        case .swimming:                                    return "Swim"
        case .hiking:                                      return "Hike"
        case .rowing:                                      return "Row"
        case .yoga:                                        return "Yoga"
        case .highIntensityIntervalTraining:               return "HIIT"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:                  return "Strength"
        case .coreTraining:                                return "Core"
        case .elliptical:                                  return "Elliptical"
        default:                                           return "Workout"
        }
    }
}
