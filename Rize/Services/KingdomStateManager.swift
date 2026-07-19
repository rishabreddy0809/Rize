import SwiftUI

// Thin observable wrapper that aggregates kingdom display state
// so views don't import XPManager directly for read-only UI bindings.
@MainActor
final class KingdomStateManager: ObservableObject {
    static let shared = KingdomStateManager()

    @Published var showAchievementBanner: Bool = false
    @Published var achievementTitle: String = ""
    @Published var achievementIcon: String = ""
    @Published var achievementColor: Color = .orange

    private init() {}

    func showAchievement(_ def: AchievementDefinition) {
        achievementTitle = def.title
        achievementIcon = def.icon
        achievementColor = def.color
        withAnimation(Constants.springAnimation) {
            showAchievementBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { showAchievementBanner = false }
        }
    }
}
