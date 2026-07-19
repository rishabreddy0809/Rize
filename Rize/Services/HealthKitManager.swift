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
    @Published var isAuthorized: Bool = false

    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
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
    }
}
