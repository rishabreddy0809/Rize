import SwiftUI

/// A compact, system-style tab bar with Apple's Liquid Glass background on iOS 26 and later.
struct MorphingTabBar<Tab: MorphingTabProtocol & CaseIterable, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    @ViewBuilder var expandedContent: ExpandedContent

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let tabs = Array(Tab.allCases)
                let tabWidth = geometry.size.width / CGFloat(max(tabs.count, 1))

                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { index in
                        let tab = tabs[index]

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                activeTab = tab
                            }
                        } label: {
                            Image(systemName: tab.symbolImage)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: tabWidth, height: 52)
                                .foregroundStyle(activeTab.symbolImage == tab.symbolImage ? .primary : .secondary)
                                .background {
                                    if activeTab.symbolImage == tab.symbolImage {
                                        Capsule(style: .continuous)
                                            .fill(Color.primary.opacity(0.12))
                                            .padding(4)
                                    }
                                }
                                .accessibilityLabel(tab.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 52)
            .padding(4)
            .background(TabBarGlassBackground())

            if isExpanded {
                expandedContent
                    .padding()
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
    }
}

private struct TabBarGlassBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }
}
