import SwiftUI
import SwiftData

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

    private var totalTasksDone: Int {
        profiles.first?.entries.reduce(0) { $0 + $1.tasksCompleted } ?? 0
    }

    var body: some View {
        ZStack {
            PhoenixBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    phoenixHero
                    statsGrid
                    phoenixVitalitySection
                    tierProgression
                    achievementsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Phoenix Hero

    private var phoenixHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tierInfo.color.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 40)

                PhoenixTierVisual(tierIndex: tierInfo.index, size: 200)
                    .modifier(FloatingModifier())
                    .onTapGesture {
                        mascotMessage = RyzDialogue.randomIdle()
                        withAnimation(Constants.springAnimation) { showMascotBubble = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { showMascotBubble = false }
                        }
                    }

                if showMascotBubble {
                    Text(mascotMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(PhoenixPalette.textPrimary)
                        .padding(12)
                        .background(PhoenixPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PhoenixPalette.surfaceBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .offset(y: -120)
                        .frame(maxWidth: 200)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(tierInfo.name)
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(PhoenixPalette.textPrimary)

            // XP bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tierInfo.color)
                            .frame(width: geo.size.width * (profile?.progressPercentage ?? 0), height: 8)
                            .animation(Constants.springAnimation, value: profile?.progressPercentage)
                    }
                }
                .frame(height: 8)

                if let next = tierInfo.nextMinXP {
                    Text("\(xpManager.totalXP) / \(next) XP to next tier")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                } else {
                    Text("MAX TIER REACHED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(tierInfo.color)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(20)
        .kingdomGlass(cornerRadius: 20)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCell("🔥", label: "STREAK", value: "\(profile?.currentStreak ?? 0) days")
            statCell("🔥", label: "VITALITY", value: "\(xpManager.realmDefense)%")
            statCell("💰", label: "GOLD", value: "\(xpManager.gold)")
            statCell("✅", label: "TASKS DONE", value: "\(totalTasksDone)")
        }
    }

    @ViewBuilder
    private func statCell(_ emoji: String, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(emoji).font(.title)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            Text(value)
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .foregroundColor(PhoenixPalette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .kingdomGlass(cornerRadius: 14)
    }

    // MARK: - Phoenix Vitality Section

    private var phoenixVitalitySection: some View {
        VStack(spacing: 16) {
            Text("PHOENIX VITALITY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 10)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: CGFloat(xpManager.realmDefense) / 100)
                        .stroke(
                            KingdomDesign.defenseBarColor(xpManager.realmDefense),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                        .animation(Constants.springAnimation, value: xpManager.realmDefense)
                    VStack(spacing: 2) {
                        Text("\(xpManager.realmDefense)%")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(PhoenixPalette.textPrimary)
                        Text(vitalityLabel)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(KingdomDesign.defenseBarColor(xpManager.realmDefense))
                    }
                }

                // 7-day history
                VStack(alignment: .leading, spacing: 8) {
                    Text("LAST 7 DAYS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

                    HStack(spacing: 6) {
                        let history = xpManager.defenseHistory.suffix(7)
                        if history.isEmpty {
                            ForEach(0..<7, id: \.self) { _ in
                                defenseBar(defended: nil)
                            }
                        } else {
                            let padded = Array(repeating: DefenseDay?.none, count: max(0, 7 - history.count))
                                + history.map { Optional($0) }
                            ForEach(Array(padded.enumerated()), id: \.offset) { _, day in
                                defenseBar(defended: day?.defended)
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    private var vitalityLabel: String {
        if xpManager.isUnderSiege { return "ASH STATE" }
        if xpManager.realmDefense > 60 { return "BLAZING" }
        if xpManager.realmDefense >= 30 { return "FLICKERING" }
        return "CRITICAL"
    }

    @ViewBuilder
    private func defenseBar(defended: Bool?) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                defended == nil ? Color.white.opacity(0.07)
                    : defended! ? PhoenixPalette.success.opacity(0.7)
                    : PhoenixPalette.destructive.opacity(0.7)
            )
            .frame(width: 10, height: 36)
    }

    // MARK: - Tier Progression

    private var tierProgression: some View {
        VStack(spacing: 0) {
            Text("TIER PROGRESSION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            ForEach(Array(KingdomDesign.tiers.enumerated()), id: \.offset) { index, tier in
                let isCurrent = xpManager.totalXP >= tier.minXP &&
                    (index + 1 >= KingdomDesign.tiers.count ||
                        xpManager.totalXP < KingdomDesign.tiers[index + 1].minXP)
                let isPast = !isCurrent && xpManager.totalXP >= tier.minXP

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isPast || isCurrent ? tier.color.opacity(0.2) : Color.white.opacity(0.05))
                            .frame(width: 36, height: 36)
                        if isPast {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(tier.color)
                        } else if isCurrent {
                            Circle()
                                .fill(tier.color)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.name)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(isCurrent || isPast ? tier.color : PhoenixPalette.textSecondary.opacity(0.4))
                        Text("\(tier.minXP) XP")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
                    }

                    Spacer()

                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(tier.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tier.color.opacity(0.15))
                            .clipShape(Capsule())
                    } else if !isPast {
                        let needed = tier.minXP - xpManager.totalXP
                        Text("\(needed) XP")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoenixPalette.textSecondary.opacity(0.4))
                    }
                }
                .padding(.vertical, 10)

                if index < KingdomDesign.tiers.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                        .padding(.leading, 18)
                }
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACHIEVEMENTS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AchievementManager.all) { def in
                        let unlocked = profiles.first?.unlockedAchievements.contains(def.id) ?? false
                        achievementCard(def, unlocked: unlocked)
                    }
                }
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func achievementCard(_ def: AchievementDefinition, unlocked: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? def.color.opacity(0.2) : Color.white.opacity(0.04))
                    .frame(width: 54, height: 54)
                if unlocked {
                    Image(systemName: def.icon)
                        .font(.system(size: 22))
                        .foregroundColor(def.color)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .grayscale(unlocked ? 0 : 1)

            Text(def.title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(unlocked ? PhoenixPalette.textPrimary.opacity(0.8) : .white.opacity(0.2))
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .frame(width: 80)
    }
}
