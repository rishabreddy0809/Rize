// TabsView.swift

import SwiftUI

enum KingdomTab: MorphingTabProtocol & CaseIterable {
    case phoenix
    case tasks
    case strava
    
    var title: String {
        switch self {
        case .phoenix: return "Phoenix"
        case .tasks: return "Tasks"
        case .strava: return "Strava"
        }
    }
    
    var icon: String {
        switch self {
        case .phoenix: return "flame.fill"
        case .tasks: return "list.bullet"
        case .strava: return "figure.walk.circle.fill"
        }
    }
}

struct TabsView: View {
    @State private var activeTab = KingdomTab.phoenix
    @State private var isExpanded = false
    
    var body: some View {
        MorphingTabBar(
            activeTab: $activeTab,
            isExpanded: $isExpanded,
            expandedContent: {
                VStack {
                    Text(activeTab.title)
                        .font(.largeTitle)
                }
            }
        )
    }
}
