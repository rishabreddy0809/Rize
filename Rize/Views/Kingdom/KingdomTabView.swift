import SwiftUI

enum KingdomTaskSection: String, CaseIterable {
    case morning
    case anytime
    case evening
    case queue
    
    var title: String {
        switch self {
        case .morning: return "Morning"
        case .anytime: return "Anytime"
        case .evening: return "Evening"
        case .queue: return "Queue"
        }
    }
}

enum KingdomTab: MorphingTabProtocol, CaseIterable {
    case phoenix
    case tasks
    case strava
    
    var symbolImage: String {
        switch self {
        case .phoenix: return "flame.fill"
        case .tasks: return "list.bullet"
        case .strava: return "figure.walk.circle.fill"
        }
    }
    
    var title: String {
        switch self {
        case .phoenix: return "Phoenix"
        case .tasks: return "Tasks"
        case .strava: return "Strava"
        }
    }
}

struct KingdomTabView: View {
    @State private var activeTab = KingdomTab.phoenix
    @State private var isExpanded = false
    
    var body: some View {
        MorphingTabBar(
            activeTab: $activeTab,
            isExpanded: $isExpanded
        ) {
            switch activeTab {
            case .phoenix:
                PhoenixView()
                    .environmentObject(XPManager.shared)
                    .environmentObject(AchievementManager.shared)
            case .tasks:
                TasksView()
                    .environmentObject(XPManager.shared)
                    .environmentObject(AchievementManager.shared)
            case .strava:
                StravaTabView()
            }
        }
    }
}

struct PhoenixView: View {
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var achievementManager: AchievementManager
    
    @State private var showMascotBubble = false
    @State private var mascotMessage = ""
    
    private var profile: UserProfile? { profiles.first }
    
    private var tierInfo: KingdomDesign.TierInfo {
        KingdomDesign.tierInfo(for: xpManager.totalXP)
    }
    
    var body: some View {
        VStack {
            // Phoenix view content
        }
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var achievementManager: AchievementManager
    
    private var profile: UserProfile? { profiles.first }
    
    var body: some View {
        VStack {
            // Tasks view content
        }
    }
}
