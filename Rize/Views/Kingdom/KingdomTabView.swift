import SwiftUI
import SwiftData

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

/// The Phoenix tab: a home for the user's companion. Shows the current
/// evolution tier, the Phoenix's vitality (health), XP progress to the next
/// tier, and the full evolution ladder. Read-only and celebratory — never a
/// place for guilt.
struct PhoenixView: View {
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var achievementManager: AchievementManager

    private var profile: UserProfile? { profiles.first }

    private var tierInfo: KingdomDesign.TierInfo {
        KingdomDesign.tierInfo(for: xpManager.totalXP)
    }

    /// Progress through the current tier, 0…1.
    private var tierProgress: Double {
        guard let next = tierInfo.nextMinXP else { return 1.0 }
        let span = Double(next - tierInfo.minXP)
        guard span > 0 else { return 1.0 }
        return min(1, max(0, Double(xpManager.totalXP - tierInfo.minXP) / span))
    }

    private var nextTierName: String? {
        let next = tierInfo.index + 1
        return next < KingdomDesign.tiers.count ? KingdomDesign.tiers[next].name : nil
    }

    var body: some View {
        ZStack {
            PhoenixBackground()

            if xpManager.isUnderSiege {
                RadialGradient(
                    colors: [.clear, PhoenixPalette.destructive.opacity(0.18)],
                    center: .center, startRadius: 150, endRadius: 420
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    heroSection
                    vitalityCard
                    progressCard
                    tierLadder
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR PHOENIX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                Text(tierInfo.name)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(tierInfo.color)
            }
            Spacer()
            Text("LV \(KingdomDesign.playerLevel(for: xpManager.totalXP))")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tierInfo.color.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            Circle()
                .fill(tierInfo.color.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 30)

            PhoenixTierVisual(tierIndex: tierInfo.index, size: 240)
                .modifier(FloatingModifier())
                .colorMultiply(xpManager.isUnderSiege ? PhoenixPalette.destructive : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .accessibilityElement()
        .accessibilityLabel("Your phoenix is at the \(tierInfo.name) tier\(xpManager.isUnderSiege ? ", currently fading" : "").")
    }

    // MARK: - Vitality

    private var vitalityCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PHOENIX VITALITY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                Spacer()
                Text(xpManager.isUnderSiege ? "FADING" : "THRIVING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(xpManager.isUnderSiege ? PhoenixPalette.destructive : PhoenixPalette.success)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(KingdomDesign.defenseBarColor(xpManager.realmDefense))
                        .frame(width: geo.size.width * Double(xpManager.realmDefense) / 100.0)
                        .animation(Constants.springAnimation, value: xpManager.realmDefense)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(xpManager.realmDefense)% health")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(KingdomDesign.defenseBarColor(xpManager.realmDefense))
                Spacer()
                if xpManager.isUnderSiege {
                    Text("Complete one task to reignite 🔥")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                statItem(icon: "flame.fill", value: "\(profile?.currentStreak ?? 0)", label: "STREAK", color: .orange)
                divider
                statItem(icon: "crown.fill", value: "\(profile?.bestStreak ?? 0)", label: "BEST", color: PhoenixPalette.radiant)
                divider
                statItem(icon: "dollarsign.circle.fill", value: "\(xpManager.gold)", label: "GOLD", color: PhoenixPalette.eternal)
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 18)
    }

    private var divider: some View {
        Divider().background(Color.white.opacity(0.1)).frame(height: 34)
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(value)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - XP Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PROGRESS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                Spacer()
                Text(nextTierName.map { "NEXT: \($0)" } ?? "MAX TIER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(tierInfo.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tierInfo.color)
                        .frame(width: geo.size.width * tierProgress)
                        .animation(Constants.springAnimation, value: tierProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(xpManager.totalXP) XP")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary)
                Spacer()
                if let next = tierInfo.nextMinXP {
                    Text("\(max(0, next - xpManager.totalXP)) XP to \(nextTierName ?? "next")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textPrimary)
                } else {
                    Text("Fully evolved 🌟")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.eternal)
                }
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 18)
    }

    // MARK: - Tier Ladder

    private var tierLadder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVOLUTION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            ForEach(Array(KingdomDesign.tiers.enumerated()), id: \.offset) { index, tier in
                tierRow(index: index, tier: tier)
                if index < KingdomDesign.tiers.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private func tierRow(index: Int, tier: (minXP: Int, name: String, color: Color)) -> some View {
        let unlocked = xpManager.totalXP >= tier.minXP
        let isCurrent = index == tierInfo.index

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tier.color.opacity(unlocked ? 0.22 : 0.06))
                    .frame(width: 34, height: 34)
                Image(systemName: unlocked ? "flame.fill" : "lock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(unlocked ? tier.color : PhoenixPalette.textSecondary.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tier.name)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(unlocked ? PhoenixPalette.textPrimary : PhoenixPalette.textSecondary.opacity(0.5))
                Text(tier.minXP == 0 ? "Starting form" : "\(tier.minXP) XP")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }

            Spacer()

            if isCurrent {
                Text("CURRENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(tier.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tier.color.opacity(0.18))
                    .clipShape(Capsule())
            } else if unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(PhoenixPalette.success.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.name), \(isCurrent ? "current tier" : unlocked ? "unlocked" : "locked, needs \(tier.minXP) XP").")
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
