import Foundation
import UIKit

// MARK: - Configuration
//
// Credentials are intentionally placeholders. Fill these in from your Strava
// API application (https://www.strava.com/settings/api). Do NOT commit real
// secrets — inject them via a build configuration / xcconfig or a local,
// git-ignored file in production.

enum StravaConfig {
    static let clientID = "YOUR_STRAVA_CLIENT_ID"
    static let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
    /// Must match the Authorization Callback Domain / URL scheme registered
    /// with Strava and in the app's Info.plist URL types.
    static let redirectURI = "YOUR_STRAVA_REDIRECT_URI" // e.g. "rize://strava-callback"
    static let scope = "read,activity:read_all"

    static let authorizeEndpoint = URL(string: "https://www.strava.com/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://www.strava.com/oauth/token")!
    static let activitiesEndpoint = URL(string: "https://www.strava.com/api/v3/athlete/activities")!

    /// True once real credentials have replaced the placeholders.
    static var isConfigured: Bool {
        !clientID.hasPrefix("YOUR_") && !clientSecret.hasPrefix("YOUR_") && !redirectURI.hasPrefix("YOUR_")
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case notConfigured
    case notConnected
    case invalidAuthorizationResponse
    case tokenExchangeFailed(status: Int)
    case tokenRefreshFailed(status: Int)
    case requestFailed(status: Int)
    case decodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured:               return "Strava isn't configured yet. Add your API credentials."
        case .notConnected:                return "Not connected to Strava."
        case .invalidAuthorizationResponse: return "Couldn't read the Strava authorization response."
        case .tokenExchangeFailed(let s):  return "Strava sign-in failed (HTTP \(s))."
        case .tokenRefreshFailed(let s):   return "Couldn't refresh your Strava session (HTTP \(s))."
        case .requestFailed(let s):        return "Strava request failed (HTTP \(s))."
        case .decodingFailed:              return "Couldn't read data from Strava."
        case .keychain(let s):             return "Secure storage error (\(s))."
        }
    }
}

// MARK: - Codable Models

/// Response from Strava's OAuth token endpoint (exchange and refresh).
private struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    /// Unix epoch seconds when the access token expires.
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

/// A subset of a Strava activity. Extend as needed.
struct StravaActivity: Decodable {
    let name: String?
    let type: String?
    let sportType: String?
    let distance: Double?            // metres
    let movingTime: Double?          // seconds
    let totalElevationGain: Double?  // metres
    let startDate: Date?
    let averageHeartrate: Double?

    enum CodingKeys: String, CodingKey {
        case name, type, distance
        case sportType = "sport_type"
        case movingTime = "moving_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
        case averageHeartrate = "average_heartrate"
    }

    func asWorkoutSummary() -> WorkoutSummary {
        WorkoutSummary(
            type: sportType ?? type ?? "Workout",
            startDate: startDate ?? Date(),
            distanceMeters: distance ?? 0,
            movingTime: movingTime ?? 0,
            elevationGain: totalElevationGain ?? 0,
            averageHeartRate: averageHeartrate,
            source: .strava
        )
    }
}

/// Persisted OAuth credentials. Stored in the Keychain, never UserDefaults.
private struct StravaCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Treat as expired a minute early to avoid races on in-flight requests.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

// MARK: - Keychain

/// Minimal generic-password Keychain wrapper for a single JSON blob.
private struct KeychainStore {
    let service: String
    let account: String

    func save(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StravaError.keychain(status) }
    }

    func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Protocol

/// Abstraction so the app (and tests) can depend on Strava behaviour, not the
/// concrete manager.
@MainActor
protocol StravaProviding: AnyObject {
    var isConnected: Bool { get }
    var recentWorkouts: [WorkoutSummary] { get }
    var authorizationURL: URL? { get }
    func connect()
    func handleRedirect(_ url: URL) async throws
    func loadRecentWorkouts() async throws
    func disconnect()
}

// MARK: - Manager

@MainActor
final class StravaManager: ObservableObject, StravaProviding {
    static let shared = StravaManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var recentWorkouts: [WorkoutSummary] = []

    private let keychain = KeychainStore(service: "com.rize.strava", account: "oauth-credentials")
    private let session: URLSession
    private let decoder: JSONDecoder

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.isConnected = (loadCredentials() != nil)
    }

    // MARK: Authorization

    var authorizationURL: URL? {
        guard StravaConfig.isConfigured else { return nil }
        var components = URLComponents(url: StravaConfig.authorizeEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: StravaConfig.scope)
        ]
        return components?.url
    }

    /// Open the Strava authorization page in the browser. Completion is handled
    /// by the app's URL-scheme callback → `handleRedirect(_:)`.
    func connect() {
        guard let url = authorizationURL else { return }
        UIApplication.shared.open(url)
    }

    /// Handle the OAuth redirect and exchange the authorization code for tokens.
    func handleRedirect(_ url: URL) async throws {
        guard StravaConfig.isConfigured else { throw StravaError.notConfigured }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.invalidAuthorizationResponse
        }

        let credentials = try await exchange(parameters: [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ], failure: StravaError.tokenExchangeFailed)

        try store(credentials)
        isConnected = true
        try? await loadRecentWorkouts()
    }

    func disconnect() {
        keychain.delete()
        isConnected = false
        recentWorkouts = []
    }

    // MARK: Activities

    func loadRecentWorkouts() async throws {
        let activities = try await fetchRecentActivities()
        recentWorkouts = activities.map { $0.asWorkoutSummary() }
    }

    /// Fetch recent activities, transparently refreshing the token if needed.
    func fetchRecentActivities(perPage: Int = 20) async throws -> [StravaActivity] {
        let token = try await validAccessToken()

        var components = URLComponents(url: StravaConfig.activitiesEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: String(perPage))]
        guard let url = components?.url else { throw StravaError.requestFailed(status: -1) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw StravaError.requestFailed(status: status) }

        do {
            return try decoder.decode([StravaActivity].self, from: data)
        } catch {
            throw StravaError.decodingFailed
        }
    }

    // MARK: Tokens

    /// Return a currently-valid access token, refreshing it if it has expired.
    private func validAccessToken() async throws -> String {
        guard let credentials = loadCredentials() else { throw StravaError.notConnected }
        guard credentials.isExpired else { return credentials.accessToken }

        let refreshed = try await exchange(parameters: [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token"
        ], failure: StravaError.tokenRefreshFailed)

        try store(refreshed)
        return refreshed.accessToken
    }

    /// POST to the token endpoint (form-encoded) and decode credentials.
    private func exchange(
        parameters: [String: String],
        failure: (Int) -> StravaError
    ) async throws -> StravaCredentials {
        var request = URLRequest(url: StravaConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw failure(status) }

        guard let token = try? decoder.decode(StravaTokenResponse.self, from: data) else {
            throw StravaError.decodingFailed
        }
        return StravaCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date(timeIntervalSince1970: token.expiresAt)
        )
    }

    // MARK: Persistence

    private func store(_ credentials: StravaCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data)
    }

    private func loadCredentials() -> StravaCredentials? {
        guard let data = keychain.read() else { return nil }
        return try? JSONDecoder().decode(StravaCredentials.self, from: data)
    }
}

private extension CharacterSet {
    /// Query-value-safe set (stricter than `.urlQueryAllowed`, which permits `&` and `=`).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?/")
        return set
    }()
}
