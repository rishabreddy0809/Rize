// TabsView.swift

import SwiftUI

struct TabsView: View {
    @State private var selectedTab = 0
    
    let tabs: [MorphingTabProtocol] = [
        TabItem(title: "Home", icon: "house"),
        TabItem(title: "Profile", icon: "person")
    ]
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabs.indices, id: \.self) { index in
                VStack {
                    Text(tabs[index].title)
                        .font(.largeTitle)
                }
                .tabItem {
                    Image(systemName: tabs[index].icon)
                    Text(tabs[index].title)
                }
                .tag(index)
            }
        }
    }
}

struct TabItem: MorphingTabProtocol {
    var title: String
    var icon: String
}
