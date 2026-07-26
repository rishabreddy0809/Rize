import WidgetKit
import SwiftUI
import MapKit

/// A Home Screen widget surfacing recent workouts — only meaningful for
/// people who actually have a sports/fitness goal (see
/// `UserProfile.hasSportsGoal`, mirrored into `RizeWidgetSnapshot.sportsGoalEnabled`
/// by `XPManager.refreshWidgetSnapshot`). WidgetKit itself can't remove a
/// widget kind from the Home Screen's "Add Widget" gallery based on app
/// state — that gallery is always populated from every `Widget` a
/// `WidgetBundle` declares, full stop — so "only enable this for sports
/// users" is implemented the only way it can be: the widget is always
/// addable, but renders an empty/explanatory state instead of workout data
/// whenever `sportsGoalEnabled` is false, rather than showing something
/// irrelevant or blank.
struct RizeSportsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RizeWidgetEntry

    var body: some View {
        Group {
            if !entry.snapshot.sportsGoalEnabled {
                emptyStateBody
            } else if family == .systemLarge {
                largeBody
            } else if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    // MARK: - Empty State

    private var emptyStateBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 26))
                .foregroundStyle(WidgetPalette.textSecondary.opacity(0.5))
            Text("Set a fitness goal in Rize to track activity here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Small

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "figure.run")
                    .foregroundStyle(WidgetPalette.primary)
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
            }

            if let workout = entry.snapshot.recentWorkouts.first {
                workoutRow(workout, compact: true)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("No recent workouts.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Medium
    //
    // Split horizontally: the left half is the most recent workout's name
    // and details (same list the small widget shows), the right half is a
    // static MapKit render of that same workout's route — falling back to
    // the plain list-only layout when there's no route to show (indoor/
    // manual workouts), since an empty map half would just be dead space.

    private var mediumBody: some View {
        Group {
            if let workout = entry.snapshot.recentWorkouts.first, !workout.route.isEmpty {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        header("RECENT ACTIVITY")
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(entry.snapshot.recentWorkouts.prefix(3)) { workout in
                                workoutRow(workout, compact: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    routeMap(workout.route)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header("RECENT ACTIVITY")
                    if entry.snapshot.recentWorkouts.isEmpty {
                        Spacer(minLength: 0)
                        Text("No recent workouts — get moving to see them here.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(WidgetPalette.textSecondary.opacity(0.6))
                        Spacer(minLength: 0)
                    } else {
                        // No route to show alongside the list (see the guard
                        // above) — use the width that would've gone to the
                        // map to show more of the user's recent workouts
                        // instead, rather than leaving it blank.
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(entry.snapshot.recentWorkouts.prefix(5)) { workout in
                                workoutRow(workout, compact: false)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Large
    //
    // The full workout list plus a route map for the most recent workout
    // that actually has one — the large widget is the only size with room
    // for both without cramming either.

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("RECENT ACTIVITY")

            if entry.snapshot.recentWorkouts.isEmpty {
                Spacer(minLength: 0)
                Text("No recent workouts — get moving to see them here.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.6))
                Spacer(minLength: 0)
            } else if let routed = entry.snapshot.recentWorkouts.first(where: { !$0.route.isEmpty }) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.snapshot.recentWorkouts.prefix(4)) { workout in
                        workoutRow(workout, compact: false)
                    }
                }

                routeMap(routed.route)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120, maxHeight: .infinity)
            } else {
                // Nothing recent has a route — use the space a map would've
                // taken to show more of the workout list instead.
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.snapshot.recentWorkouts.prefix(8)) { workout in
                        workoutRow(workout, compact: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Route Map

    private func routeMap(_ route: [RizeWidgetCoordinate]) -> some View {
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        return Map(initialPosition: .region(region(fitting: coordinates))) {
            MapPolyline(coordinates: coordinates)
                .stroke(WidgetPalette.primary, lineWidth: 3)
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
    }

    /// Same bounding-box-fit approach as `HealthTabView.region(fitting:)` —
    /// duplicated rather than shared since the widget extension and app are
    /// separate compiled modules.
    private func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let minLat = coordinates.map(\.latitude).min(),
              let maxLat = coordinates.map(\.latitude).max(),
              let minLon = coordinates.map(\.longitude).min(),
              let maxLon = coordinates.map(\.longitude).max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
                .foregroundStyle(WidgetPalette.primary)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
        }
    }

    // MARK: - Shared Row

    private func workoutRow(_ workout: RizeWidgetWorkout, compact: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(WidgetPalette.primary.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: workoutIcon(for: workout.type))
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetPalette.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(workout.type)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text(workout.subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
            }
            if !compact {
                Spacer()
                Text(workout.relativeDay)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.5))
            }
        }
    }

    /// Same activity-type → SF Symbol mapping as `HealthTabView.workoutIcon`
    /// — duplicated rather than shared, since the widget extension and app
    /// are separate compiled modules (see `Color(hex:)` in
    /// `RizeWidgetProvider.swift` for the same reasoning applied there).
    private func workoutIcon(for type: String) -> String {
        switch type {
        case "Run":        return "figure.run"
        case "Ride":       return "bicycle"
        case "Walk":       return "figure.walk"
        case "Swim":       return "figure.pool.swim"
        case "Hike":       return "figure.hiking"
        case "Row":        return "figure.rower"
        case "Yoga":       return "figure.yoga"
        case "HIIT":       return "figure.highintensity.intervaltraining"
        case "Strength":   return "dumbbell.fill"
        case "Core":       return "figure.core.training"
        case "Elliptical": return "figure.elliptical"
        default:           return "figure.mixed.cardio"
        }
    }
}

struct RizeSportsWidget: Widget {
    let kind = "RizeSportsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RizeWidgetProvider()) { entry in
            RizeSportsWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Activity")
        .description("Your recent workouts, at a glance. Shows up once you set a fitness goal in Rize.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
