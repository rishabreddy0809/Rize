import SwiftUI

/// A single celebratory overlay. Only one is ever on screen at a time — since
/// presenting several of these together (achievement unlock + all-done +
/// low-energy bonus all firing off the same task completion) is what caused
/// celebrations to visually stack and glitch.
enum DayCelebration: Identifiable {
    case allDone(xp: Int, streak: Int)
    case lowEnergy(xp: Int)
    case achievement(AchievementDefinition)

    var id: String {
        switch self {
        case .allDone:                return "allDone"
        case .lowEnergy:               return "lowEnergy"
        case .achievement(let def):    return "achievement-\(def.id)"
        }
    }
}

/// Owns the celebration queue at the app level (not per-tab) so the overlay can
/// be presented above `MainTabView`'s floating tab bar. Presenting it from
/// inside a single tab's own view (as this used to work) meant it was always
/// painted *behind* the tab bar in z-order and boxed in by that tab's content
/// padding — no `.ignoresSafeArea()` inside the celebration could undo either.
@MainActor
final class CelebrationCenter: ObservableObject {
    static let shared = CelebrationCenter()

    @Published private(set) var active: DayCelebration?
    private var queue: [DayCelebration] = []

    private init() {}

    func enqueue(_ celebration: DayCelebration) {
        queue.append(celebration)
        advance()
    }

    private func advance() {
        guard active == nil, !queue.isEmpty else { return }
        withAnimation(Constants.springAnimation) {
            active = queue.removeFirst()
        }
    }

    /// Clears the active celebration, then — after its dismiss animation has
    /// had time to finish — advances to the next queued one. The delay is what
    /// stops the next celebration's full-screen backdrop from appearing in the
    /// same frame as the previous one is still fading out.
    func dismissActive() {
        withAnimation(Constants.springAnimation) { active = nil }
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            advance()
        }
    }
}
