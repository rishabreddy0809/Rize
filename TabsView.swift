// TabsView.swift

import SwiftUI

struct TabsView: View {
    @State private var selectedTab = 0
    
    let tabs: [MorphingTabProtocol] = [
        TabItem(title: "Home", icon: "house"),
        TabItem(title: "Profile", icon: "person")
    ]
    
    var body: some View {
        MorphingTabBar(
            activeTab: Binding<Tab> {
                return tabs[selectedTab]
            } set: { tab in
                selectedTab = tabs.firstIndex(of: tab) ?? 0
            },
            isExpanded: $selectedTab != 0,
            expandedContent: {
                VStack {
                    Text(tabs[selectedTab].title)
                        .font(.largeTitle)
                }
            }
        )
    }
}

struct TabItem: MorphingTabProtocol {
    var title: String
    var icon: String
    
    var symbolImage: String {
        return icon
    }
}
