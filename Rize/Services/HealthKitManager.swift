import Foundation
import HealthKit
import CoreLocation
import SwiftUI

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var sleepHours: Double? = nil
    @Published var restingHeartRate: Double? = nil
    @Published var stepCount: Double? = nil
    @Published var activeEnergy: Double? = nil
    @Published var standHours: Int? = nil
    @Published var recentWorkouts: [WorkoutSummary] = []
    /// Workouts for whatever month is currently selected in the Health tab —
    /// separate from `recentWorkouts` (a fixed 7-day lookback the planning
    /// engine uses) so browsing months there never affects planning decisions.
    @Published var monthlyWorkouts: [WorkoutSummary] = []
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

    /// `HKObjectType`/`HKQuantityType`/`HKCategoryType` are HealthKit's way of
    /// identifying *which* health data you want, as an actual typed handle
    /// rather than a string — `.stepCount`, `.sleepAnalysis`, etc. are static
    /// identifiers HealthKit defines for every data type it knows about, and
    /// `HKObjectType.quantityType(forIdentifier:)` looks up the concrete type
    /// object for one. `readTypes` here is the complete list of data this app
    /// ever asks to read; `toShare: []` in the call below means this app
    /// never writes anything back to Health — read-only.
    ///
    /// The privacy quirk worth knowing: for *read* access specifically,
    /// HealthKit deliberately never tells an app which individual types the
    /// user actually granted vs. silently denied in the permission sheet —
    /// only that the sheet was shown and handled without an error. That's
    /// why `isAuthorized = true` here really means "the request didn't
    /// fail," not "every type above is actually readable." The only way to
    /// find out in practice is to just run the queries and see what comes
    /// back — which is exactly why every `fetch…` method below is written to
    /// tolerate `nil`/empty results quietly rather than treating them as
    /// errors.
    func requestAuthorization() async {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .appleStandHour)!,
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
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
        standHours = await fetchStandHours()
        recentWorkouts = await fetchWorkouts()
    }

    // MARK: - Workouts

    /// Recent workouts mapped into the shared `WorkoutSummary` domain type.
    /// Returns `[]` (never throws) so planning always proceeds.
    private func fetchWorkouts() async -> [WorkoutSummary] {
        let start = Calendar.current.date(byAdding: .day, value: -workoutLookbackDays, to: Date())
        return await fetchWorkouts(start: start, end: Date())
    }

    /// Refetches `monthlyWorkouts` for whichever calendar month contains `date`
    /// — the Health tab's month dropdown drives this directly.
    func fetchWorkouts(forMonthContaining date: Date) async {
        guard let interval = Calendar.current.dateInterval(of: .month, for: date) else {
            monthlyWorkouts = []
            return
        }
        monthlyWorkouts = await fetchWorkouts(start: interval.start, end: interval.end)
    }

    /// `HKSampleQueryDescriptor` is the modern (`async`/`await`-native)
    /// way to fetch actual HealthKit *records* — as opposed to
    /// `HKStatisticsQueryDescriptor` (first used a bit further down, in
    /// `fetchWorkoutStepCount`), which computes an aggregate (sum, average,
    /// …) over records instead of handing back the records themselves. Both
    /// share the same three-piece shape: a `predicate` describing which
    /// samples qualify (`HKQuery.predicateForSamples(withStart:end:)` here
    /// means "samples whose time range overlaps this window"), a type
    /// describing *what kind* of sample (`.workout(predicate)` — the
    /// predicate is nested inside because `HKSamplePredicate` bundles both
    /// the sample type and the filter together), and for sample queries
    /// specifically, `sortDescriptors`/`limit` controlling ordering and how
    /// many results come back. `descriptor.result(for: store)` is what
    /// actually runs it against the shared `HKHealthStore`.
    private func fetchWorkouts(start: Date?, end: Date) async -> [WorkoutSummary] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        do {
            let workouts = try await descriptor.result(for: store)
            var summaries: [WorkoutSummary] = []
            for workout in workouts {
                let steps = await fetchWorkoutStepCount(workout)
                let route = await fetchWorkoutRoute(workout)
                summaries.append(workout.asWorkoutSummary(stepCount: steps, routeCoordinates: route))
            }
            return summaries
        } catch {
            return []
        }
    }

    /// Steps taken during the workout's own time window (distinct from the day's total).
    private func fetchWorkoutStepCount(_ workout: HKWorkout) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try? await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: .count())
    }

    /// The workout's GPS route (empty for indoor/manual workouts, or if route
    /// read wasn't authorized).
    ///
    /// A route isn't a regular HealthKit sample you can fetch with a normal
    /// query — HealthKit stores it as an `HKSeriesSample` (a sample that owns
    /// an ordered sub-series of data, here GPS locations, keyed to the parent
    /// workout). So this is a two-step lookup: first find the route *object*
    /// for this workout (`HKSampleQueryDescriptor` filtered to
    /// `HKSeriesType.workoutRoute()`), then separately ask for the actual
    /// locations inside it (`HKWorkoutRouteQuery` below).
    ///
    /// `HKWorkoutRouteQuery` predates Swift's `async`/`await` (structured
    /// concurrency) — it's an old-style HealthKit query that reports results
    /// through a closure, called once per internal batch of locations, with
    /// `done == true` on the final call. `AsyncThrowingStream` is the bridge
    /// Apple provides for exactly this: wrap the closure-based API in a
    /// stream initializer, `yield` each batch as it arrives, and `finish` the
    /// stream when the closure reports `done`. That turns a callback API into
    /// something you can `for try await` over like any other async sequence.
    private func fetchWorkoutRoute(_ workout: HKWorkout) async -> [RouteCoordinate] {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: routePredicate)],
            sortDescriptors: []
        )
        guard let routeSamples = try? await routeDescriptor.result(for: store),
              let route = routeSamples.first as? HKWorkoutRoute else { return [] }

        var coordinates: [RouteCoordinate] = []
        let locationBatches = AsyncThrowingStream<[CLLocation], Error> { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, errorOrNil in
                if let error = errorOrNil {
                    continuation.finish(throwing: error)
                    return
                }
                if let locations = locationsOrNil {
                    continuation.yield(locations)
                }
                if done {
                    continuation.finish()
                }
            }
            self.store.execute(query)
        }

        do {
            for try await batch in locationBatches {
                // Each CLLocation carries a `horizontalAccuracy` in meters —
                // the device's own estimate of how wrong this fix could be
                // (smaller is better; a negative value means the fix is
                // invalid and shouldn't be trusted at all). Drop low-quality
                // fixes rather than plotting every raw GPS sample — a
                // handful of noisy points (tree cover, buildings, a tunnel)
                // can visibly warp the route shape if you draw all of them.
                coordinates.append(contentsOf: batch
                    .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
                    .map { RouteCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
            }
        } catch {
            return []
        }

        // Thin dense routes (a long run/ride can have thousands of points) so
        // SwiftUI's Map polyline stays smooth to render. Douglas-Peucker keeps
        // the points that define turns/curvature and drops redundant ones
        // along straight stretches, which preserves the route's actual shape
        // far better than naively keeping every Nth point (see `simplifyRoute`
        // below for how the algorithm decides what to keep).
        let maxPoints = 1000
        if coordinates.count > maxPoints {
            coordinates = Self.simplifyRoute(coordinates, toleranceMeters: 3)
            // Very long routes may still exceed the cap after simplification;
            // fall back to even thinning as a last resort.
            if coordinates.count > maxPoints {
                let stride = coordinates.count / maxPoints
                coordinates = coordinates.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
            }
        }
        return coordinates
    }

    /// Douglas-Peucker polyline simplification. Distances are computed with a
    /// flat equirectangular projection, which is accurate enough for
    /// human-scale workout routes.
    ///
    /// The core idea: a straight stretch of road doesn't need one GPS point
    /// per second to look right on a map — a single line from its start to
    /// its end is visually identical. A turn does need points, because
    /// that's exactly where a straight line would diverge from the real
    /// path. Douglas-Peucker automates that judgment call recursively:
    ///
    /// 1. Always keep the very first and last point (they define the route's
    ///    endpoints no matter what).
    /// 2. For the points in between, find whichever one sits *farthest* from
    ///    the straight line connecting the two ends being considered.
    /// 3. If that farthest point is further than `toleranceMeters` from the
    ///    line, the line is a bad enough approximation that the point must be
    ///    kept — so keep it, and recurse into the two halves it splits the
    ///    segment into (start→point, point→end), each judged against their
    ///    own new straight line.
    /// 4. If even the farthest point is within tolerance, every point in
    ///    between is close enough to a straight line that none of them are
    ///    needed — drop the whole segment down to just its two endpoints.
    ///
    /// `nonisolated static` here just means: this is pure geometry with no
    /// dependency on `HealthKitManager`'s `@MainActor` state, so it can run
    /// off the main actor without needing `await` to call it.
    nonisolated private static func simplifyRoute(_ coordinates: [RouteCoordinate], toleranceMeters: Double) -> [RouteCoordinate] {
        guard coordinates.count > 2 else { return coordinates }
        // One "keep this point?" flag per coordinate, filled in by recursing
        // through `simplifySegment` below, then used to filter at the end.
        var keep = [Bool](repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        simplifySegment(coordinates, 0, coordinates.count - 1, toleranceMeters, &keep)
        return coordinates.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// One level of the Douglas-Peucker recursion described above: scans the
    /// open interval `(start, end)` for the single point that strays
    /// furthest from the straight line `points[start]`–`points[end]`, and —
    /// if that point is too far to ignore — marks it kept and recurses into
    /// the two sub-segments it creates.
    nonisolated private static func simplifySegment(
        _ points: [RouteCoordinate],
        _ start: Int,
        _ end: Int,
        _ toleranceMeters: Double,
        _ keep: inout [Bool]
    ) {
        // Fewer than one point strictly between start and end — nothing left
        // to decide, so this is the recursion's base case.
        guard end > start + 1 else { return }
        var maxDistance = 0.0
        var splitIndex = start
        for i in (start + 1)..<end {
            let distance = perpendicularDistanceMeters(points[i], lineStart: points[start], lineEnd: points[end])
            if distance > maxDistance {
                maxDistance = distance
                splitIndex = i
            }
        }
        if maxDistance > toleranceMeters {
            keep[splitIndex] = true
            simplifySegment(points, start, splitIndex, toleranceMeters, &keep)
            simplifySegment(points, splitIndex, end, toleranceMeters, &keep)
        }
        // else: nothing in this range strayed far enough to matter, so the
        // whole segment collapses to just its (already-kept) endpoints.
    }

    /// Perpendicular distance from `point` to the line through `lineStart`
    /// and `lineEnd`, in meters, using an equirectangular approximation.
    ///
    /// Latitude/longitude are angles on a sphere, not flat x/y coordinates,
    /// so you can't measure "distance from a line" with ordinary geometry
    /// until you convert them to a flat plane first. An equirectangular
    /// projection does that conversion the cheap way: treat degrees of
    /// latitude as a constant number of meters (111,320m per degree,
    /// everywhere on Earth), and degrees of longitude as that same constant
    /// *shrunk* by `cos(latitude)` — because lines of longitude squeeze
    /// closer together as you move away from the equator toward the poles.
    /// This distorts badly over long distances (it's not how any real map
    /// projection works globally), but a single workout route spans at most
    /// a few miles, where the distortion is negligible — cheap and accurate
    /// enough for this, without pulling in MapKit/CoreLocation's much
    /// heavier great-circle distance APIs.
    ///
    /// Once `point`, `lineStart`, and `lineEnd` are all in flat meters, this
    /// is the standard "distance from a point to a line segment" formula:
    /// project `point` onto the line via the dot product, clamp that
    /// projection to stay between the segment's two ends (`t` in `0...1`, so
    /// the closest point can't fall outside the segment), then measure the
    /// straight-line distance from `point` to that projected point.
    nonisolated private static func perpendicularDistanceMeters(
        _ point: RouteCoordinate,
        lineStart: RouteCoordinate,
        lineEnd: RouteCoordinate
    ) -> Double {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(point.latitude * .pi / 180)

        let x = point.longitude * metersPerDegreeLon
        let y = point.latitude * metersPerDegreeLat
        let x1 = lineStart.longitude * metersPerDegreeLon
        let y1 = lineStart.latitude * metersPerDegreeLat
        let x2 = lineEnd.longitude * metersPerDegreeLon
        let y2 = lineEnd.latitude * metersPerDegreeLat

        let dx = x2 - x1
        let dy = y2 - y1
        // Degenerate case: lineStart and lineEnd are the same point, so
        // there's no line to project onto — just measure straight to it.
        guard dx != 0 || dy != 0 else { return hypot(x - x1, y - y1) }

        let t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
        let projX = x1 + t * dx
        let projY = y1 + t * dy
        return hypot(x - projX, y - projY)
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

    // MARK: - Stand Hours

    /// Number of distinct hours today the user stood/moved for at least a minute.
    private func fetchStandHours() async -> Int? {
        guard isAvailable else { return Int(simulatorMock(.standHours)) }
        let type = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            return samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
        } catch {
            return Int(simulatorMock(.standHours))
        }
    }

    // MARK: - Simulator Mocks

    private enum MockMetric { case sleep, restingHR, steps, energy, standHours }

    // nonisolated: returns constants only, no actor-protected state accessed
    nonisolated private func simulatorMock(_ metric: MockMetric) -> Double {
        switch metric {
        case .sleep: return 7.2
        case .restingHR: return 62.0
        case .steps: return 6800.0
        case .energy: return 320.0
        case .standHours: return 8.0
        }
    }

    private func loadMockData() {
        sleepHours = 7.2
        restingHeartRate = 62.0
        stepCount = 6800.0
        activeEnergy = 320.0
        standHours = 8
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
    func asWorkoutSummary(stepCount: Double?, routeCoordinates: [RouteCoordinate]) -> WorkoutSummary {
        let distance = distanceMeters()
        let hr = statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        let calories = statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        let elevation = (metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter()) ?? 0

        return WorkoutSummary(
            type: workoutActivityType.displayName,
            startDate: startDate,
            distanceMeters: distance,
            movingTime: duration,
            elevationGain: elevation,
            averageHeartRate: hr,
            source: .healthKit,
            stepCount: stepCount,
            activeEnergyBurned: calories,
            deviceName: device?.name,
            routeCoordinates: routeCoordinates
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
