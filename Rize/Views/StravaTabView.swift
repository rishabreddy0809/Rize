import SwiftUI

struct StravaTabView: View {
    @State private var isStravaConnected = false
    @State private var workouts: [Workout] = []
    
    var body: some View {
        VStack {
            if isStravaConnected {
                List(workouts) { workout in
                    HStack {
                        Text(workout.name)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(workout.distance, specifier: "%.2f") km")
                            .font(.subheadline)
                    }
                    .padding()
                }
            } else {
                Button(action: connectToStrava) {
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
            }
        }
        .navigationTitle("Strava")
    }
    
    private func connectToStrava() {
        StravaManager.shared.connectToStrava()
    }
}

struct Workout: Identifiable {
    let id = UUID()
    let name: String
    let distance: Double
}
