import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct HealthTabView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @Query private var profiles: [UserProfile]
    @State private var isRefreshing = false
    /// Reverse-geocoded "City, State" per workout, resolved lazily as cards appear.
    @State private var placeNames: [UUID: String] = [:]
    /// Which calendar month's workouts are currently shown — defaults to the
    /// current month, switchable via the dropdown in the header.
    @State private var selectedMonth = Date()

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header

                healthCard

                healthWorkoutsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PhoenixBackground())
        .task { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: selectedMonth) { _, newMonth in
            Task { await healthKit.fetchWorkouts(forMonthContaining: newMonth) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                Text("Health")
                    .font(.phoenixTitle(24))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            monthPicker
        }
        .padding(.horizontal, 4)
        .padding(.top, 20)
    }

    /// Every month from the current one back to the month the account was
    /// created — there's no Health data (or reason to browse) further back
    /// than when the person actually started using Rize.
    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let now = Date()
        let earliest = profile?.createdAt ?? now
        let monthCount = (calendar.dateComponents([.month], from: earliest, to: now).month ?? 0) + 1
        return (0..<monthCount).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private var monthPicker: some View {
        Menu {
            ForEach(availableMonths, id: \.self) { month in
                Button {
                    selectedMonth = month
                } label: {
                    if Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) {
                        Label(monthLabel(month), systemImage: "checkmark")
                    } else {
                        Text(monthLabel(month))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthLabel(selectedMonth))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(PhoenixPalette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .phoenixGlass(cornerRadius: 12)
        }
        .accessibilityLabel("Selected month: \(monthLabel(selectedMonth))")
        .accessibilityHint("Opens a menu to choose a different month")
    }

    // MARK: - Health

    private var healthCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("TODAY'S HEALTH")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !healthKit.isAvailable {
                    Text("UNAVAILABLE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
                } else if !healthKit.isAuthorized {
                    Text("NOT AUTHORIZED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.destructive.opacity(0.8))
                }
            }

            HStack(spacing: 0) {
                healthStatItem(
                    icon: "bed.double.fill",
                    value: healthKit.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                    label: "SLEEP",
                    color: PhoenixPalette.radiant
                )
                healthDivider
                healthStatItem(
                    icon: "figure.stand",
                    value: healthKit.standHours.map { "\($0)/12" } ?? "—",
                    label: "STAND",
                    color: PhoenixPalette.success
                )
                healthDivider
                healthStatItem(
                    icon: "shoeprints.fill",
                    value: healthKit.stepCount.map { String(format: "%.0f", $0) } ?? "—",
                    label: "STEPS",
                    color: PhoenixPalette.eternal
                )
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 18)
    }

    private var healthDivider: some View {
        Divider().background(Color.white.opacity(0.1)).frame(height: 34)
    }

    private func healthStatItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(value)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var healthWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APPLE HEALTH WORKOUTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            if healthKit.monthlyWorkouts.isEmpty {
                Text("No workouts logged in \(monthLabel(selectedMonth)).")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .phoenixGlass(cornerRadius: 18)
            } else {
                ForEach(healthKit.monthlyWorkouts) { workout in
                    workoutCard(workout)
                }
            }
        }
    }

    // MARK: - Workout Card

    private func workoutCard(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: avatar, name, date/time · device · location
            HStack(spacing: 10) {
                Circle()
                    .fill(PhoenixPalette.primary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(profile?.name.first.map(String.init) ?? "R")
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundColor(.black)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile?.name ?? "You")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundColor(PhoenixPalette.textPrimary)
                    Text(workoutSubtitle(workout))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: workoutIcon(for: workout.type))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .accessibilityHidden(true)
                Text(workout.type)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }
            .accessibilityAddTraits(.isHeader)

            workoutStatsRow(workout)

            if !workout.routeCoordinates.isEmpty {
                workoutMap(workout)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // Static, non-interactive route preview — the distance/pace
                    // stats above already say everything this map would add, so
                    // it's decorative rather than informative for VoiceOver.
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task { await resolvePlaceName(for: workout) }
    }

    /// Which stats to show is decided by whether HealthKit actually reported
    /// a distance for this workout (`hasTrackedDistance`), not by the
    /// activity type's name — a "Run" someone did on a treadmill with no GPS
    /// has no more real distance data than a strength session, and
    /// hardcoding "always show Distance" is exactly what used to print a
    /// nonsensical "0.00 mi" for workouts that were never going to track it.
    /// Duration is the one stat every workout has regardless, so it always
    /// appears — last, since it's the least likely to be `nil`/uninteresting
    /// and reads naturally as "...and it took this long."
    @ViewBuilder
    private func workoutStatsRow(_ workout: WorkoutSummary) -> some View {
        HStack(spacing: 0) {
            if workout.hasTrackedDistance {
                workoutStat(label: "Distance", value: String(format: "%.2f mi", workout.distanceMiles))
                workoutStat(label: "Pace", value: workout.formattedPace ?? "—")
                workoutStat(label: "Avg HR", value: heartRateLabel(workout.averageHeartRate))
            } else {
                workoutStat(label: "Calories", value: calorieLabel(workout.activeEnergyBurned))
                workoutStat(label: "Avg HR", value: heartRateLabel(workout.averageHeartRate))
            }
            workoutStat(label: "Duration", value: workout.formattedMovingTime)
        }
    }

    private func heartRateLabel(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "—" }
        return String(format: "%.0f bpm", bpm)
    }

    private func calorieLabel(_ kcal: Double?) -> String {
        guard let kcal, kcal > 0 else { return "—" }
        return String(format: "%.0f cal", kcal)
    }

    private func workoutStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
            Text(value)
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundColor(PhoenixPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// `Map` is MapKit's SwiftUI view (iOS 17+) — it takes a `MapCameraPosition`
    /// (here `.region(_:)`, a fixed area to frame; there are also
    /// `.userLocation()`, `.camera()` for a specific pitch/heading, etc.) plus
    /// a trailing closure that's a `MapContentBuilder`, SwiftUI's other
    /// result-builder like `ViewBuilder` but restricted to map-specific
    /// content types (`MapPolyline`, `Marker`, `Annotation`, …) instead of
    /// arbitrary views. `MapPolyline(coordinates:)` is what actually draws
    /// the workout's GPS route — the array of `CLLocationCoordinate2D` below
    /// (this is `HealthKitManager.fetchWorkoutRoute`'s already-cleaned-up,
    /// already-simplified route reaching the screen) becomes the line's
    /// points in order, and `.stroke` styles that line same as any SwiftUI
    /// `Shape`.
    ///
    /// `.mapStyle(.standard(elevation: .flat))` picks MapKit's standard
    /// street map look with no 3D building elevation (vs. `.imagery` for
    /// satellite or `.hybrid` for both). `.mapControlVisibility(.hidden)`
    /// hides MapKit's own built-in UI chrome (compass, scale, user-location
    /// button) — appropriate here since this is a small, non-interactive
    /// summary card, not a full map screen the user pans/zooms around.
    private func workoutMap(_ workout: WorkoutSummary) -> some View {
        let coordinates = workout.routeCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        return Map(initialPosition: .region(region(fitting: coordinates))) {
            MapPolyline(coordinates: coordinates)
                .stroke(PhoenixPalette.primary, lineWidth: 3)
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
    }

    /// Computes the `MKCoordinateRegion` — MapKit's "what area is the camera
    /// looking at" type — that just barely contains every point in
    /// `coordinates`, so the initial camera position above frames the whole
    /// route instead of, say, defaulting to null island or requiring the
    /// route's real-world GPS center to be hardcoded somewhere. A region is
    /// two pieces: `center` (a single lat/lon "look here") and `span` (an
    /// `MKCoordinateSpan` — how many degrees of latitude/longitude are
    /// visible, which is MapKit's stand-in for "zoom level"; a smaller span
    /// means zoomed in tighter).
    ///
    /// The approach: find the smallest bounding box around every coordinate
    /// (min/max lat, min/max lon — the four `guard let` bindings below),
    /// center on that box's middle, and size the span to the box's
    /// dimensions. `* 1.4` pads that span by 40% so the route's edges don't
    /// touch the map view's border, and `max(…, 0.01)` puts a floor under
    /// the span so a route with almost no spread (e.g. a stationary workout,
    /// or literally one GPS point) still gets a sane, zoomed-out-enough view
    /// instead of an near-zero span that would zoom in absurdly far.
    private func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let firstLat = coordinates.map(\.latitude).min(),
              let lastLat = coordinates.map(\.latitude).max(),
              let firstLon = coordinates.map(\.longitude).min(),
              let lastLon = coordinates.map(\.longitude).max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        let center = CLLocationCoordinate2D(latitude: (firstLat + lastLat) / 2, longitude: (firstLon + lastLon) / 2)
        // Pad the bounding box so the route doesn't touch the card's edges.
        let span = MKCoordinateSpan(
            latitudeDelta: max((lastLat - firstLat) * 1.4, 0.01),
            longitudeDelta: max((lastLon - firstLon) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func workoutIcon(for type: String) -> String {
        switch type {
        case "Run":       return "figure.run"
        case "Ride":      return "bicycle"
        case "Walk":      return "figure.walk"
        case "Swim":      return "figure.pool.swim"
        case "Hike":      return "figure.hiking"
        case "Row":       return "figure.rower"
        case "Yoga":      return "figure.yoga"
        case "HIIT":      return "figure.highintensity.intervaltraining"
        case "Strength":  return "dumbbell.fill"
        case "Core":      return "figure.core.training"
        case "Elliptical": return "figure.elliptical"
        default:          return "figure.mixed.cardio"
        }
    }

    private func workoutSubtitle(_ workout: WorkoutSummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        var parts = [formatter.string(from: workout.startDate)]
        if let device = workout.deviceName { parts.append(device) }
        if let place = placeNames[workout.id] { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// Reverse-geocodes the route's starting point once per workout and caches
    /// the result — HealthKit gives raw coordinates, not a place name.
    private func resolvePlaceName(for workout: WorkoutSummary) async {
        guard placeNames[workout.id] == nil, let first = workout.routeCoordinates.first else { return }
        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
        guard !parts.isEmpty else { return }
        placeNames[workout.id] = parts.joined(separator: ", ")
    }

    // MARK: - Refresh

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        if healthKit.isAuthorized {
            await healthKit.fetchAll()
            await healthKit.fetchWorkouts(forMonthContaining: selectedMonth)
        }
    }
}
