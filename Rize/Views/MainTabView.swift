import SwiftUI

enum RizeTab: String, CaseIterable, MorphingTabProtocol {
    case today
    case progress
    case kingdom
    case profile

    var symbolImage: String {
        switch self {
        case .today: return "bolt.fill"
        case .progress: return "chart.bar.fill"
        case .kingdom: return "flame.fill"
        case .profile: return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .progress: return "Progress"
        case .kingdom: return "Phoenix"
        case .profile: return "Profile"
        }
    }
}

// Environment key so child views can switch tabs
struct RizeTabKey: EnvironmentKey {
    static let defaultValue: Binding<RizeTab> = .constant(.today)
}

extension EnvironmentValues {
    var selectedTab: Binding<RizeTab> {
        get { self[RizeTabKey.self] }
        set { self[RizeTabKey.self] = newValue }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var xpManager: XPManager
    @State private var selected: RizeTab = .today
    @State private var isTabBarExpanded: Bool = false

    private var tierColor: Color {
        KingdomDesign.tierInfo(for: xpManager.totalXP).color
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selected {
                case .today:    TodayView()
                case .progress: RizeProgressScreen()
                case .kingdom:  PhoenixView()
                case .profile:  ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80)

            // Floating Tab Bar
            MorphingTabBar(activeTab: $selected, isExpanded: $isTabBarExpanded) {}
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .environment(\.selectedTab, $selected)
        .onReceive(NotificationCenter.default.publisher(for: .rizeOpenEnergyPicker)) { _ in
            withAnimation(Constants.springAnimation) { selected = .today }
        }
        // Tier upgrade banner
        .overlay(alignment: .top) {
            if xpManager.showTierUpgrade {
                tierUpgradeBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 50)
            }
        }
    }

    // MARK: - Tier Upgrade Banner

    private var tierUpgradeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundColor(tierColor)
            Text("TIER UP — \(xpManager.tierUpgradeName)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(PhoenixPalette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tierColor.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tierColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}
