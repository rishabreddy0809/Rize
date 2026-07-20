import SwiftUI

struct StravaTabView: View {
    @State private var isStravaConnected = false
    @State private var workouts: [Workout] = []
    
    // Placeholder for Strava API key
    let stravaClientID = "YOUR_STRAVA_CLIENT_ID"
    let stravaRedirectURI = "YOUR_STRAVA_REDIRECT_URI"
    let stravaAuthorizationURL = "https://www.strava.com/oauth/authorize?client_id=\(stravaClientID)&response_type=code&redirect_uri=\(stravaRedirectURI)&approval_prompt=auto&scope=read_all,activity:read_all"
    
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
        // Open Strava authorization URL in Safari
        if let url = URL(string: stravaAuthorizationURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        // Handle the redirect and fetch access token
        // Fetch workouts using the access token
    }
}

struct Workout: Identifiable {
    let id = UUID()
    let name: String
    let distance: Double
}
