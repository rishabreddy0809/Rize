import SwiftUI

struct StravaTabView: View {
    @ObservedObject private var strava = StravaManager.shared
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if strava.isConnected {
                if strava.recentWorkouts.isEmpty {
                    Text("No recent workouts.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(strava.recentWorkouts) { workout in
                        HStack {
                            Text(workout.type)
                                .font(.headline)

                            Spacer()

                            Text("\(workout.distanceKilometers, specifier: "%.2f") km")
                                .font(.subheadline)
                        }
                        .padding()
                    }
                }
            } else {
                Button(action: { strava.connect() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)

                        Text("Connect to Strava")
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                }

                if !StravaConfig.isConfigured {
                    Text("Add your Strava API credentials to enable this.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Strava")
        .task {
            guard strava.isConnected else { return }
            do { try await strava.loadRecentWorkouts() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
