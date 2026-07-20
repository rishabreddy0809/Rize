import Foundation

class StravaManager {
    static let shared = StravaManager()
    
    private init() {}
    
    // Placeholder for Strava API key
    let stravaClientID = "YOUR_STRAVA_CLIENT_ID"
    let stravaRedirectURI = "YOUR_STRAVA_REDIRECT_URI"
    let stravaAuthorizationURL = "https://www.strava.com/oauth/authorize?client_id=\(stravaClientID)&response_type=code&redirect_uri=\(stravaRedirectURI)&approval_prompt=auto&scope=read_all,activity:read_all"
    
    private var accessToken: String?
    private var refreshToken: String?
    private let tokenStorageKey = "StravaAccessToken"
    
    func connectToStrava() {
        if let url = URL(string: stravaAuthorizationURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    func handleRedirect(_ url: URL) async throws -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return false
        }
        
        let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": stravaClientID,
            "client_secret": "YOUR_STRAVA_CLIENT_SECRET",
            "code": code,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "StravaManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch access token"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let accessToken = json["access_token"] as? String,
           let refreshToken = json["refresh_token"] as? String {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            UserDefaults.standard.set(accessToken, forKey: tokenStorageKey)
            return true
        }
        
        throw NSError(domain: "StravaManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse access token"])
    }
    
    func fetchWorkouts() async throws -> [Workout] {
        guard let accessToken = accessToken else {
            throw NSError(domain: "StravaManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Access token not available"])
        }
        
        let workoutsURL = URL(string: "https://www.strava.com/api/v3/athlete/activities")!
        var request = URLRequest(url: workoutsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "StravaManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch workouts"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            return json.compactMap { activity in
                guard let name = activity["name"] as? String,
                      let distance = activity["distance"] as? Double else {
                    return nil
                }
                return Workout(name: name, distance: distance / 1000) // Convert meters to kilometers
            }
        }
        
        throw NSError(domain: "StravaManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse workouts"])
    }
    
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw NSError(domain: "StravaManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Refresh token not available"])
        }
        
        let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": stravaClientID,
            "client_secret": "YOUR_STRAVA_CLIENT_SECRET",
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "StravaManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh access token"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let accessToken = json["access_token"] as? String {
            self.accessToken = accessToken
            UserDefaults.standard.set(accessToken, forKey: tokenStorageKey)
        } else {
            throw NSError(domain: "StravaManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse refresh token"])
        }
    }
}
