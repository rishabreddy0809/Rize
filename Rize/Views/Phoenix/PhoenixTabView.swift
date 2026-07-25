import SwiftUI
import SwiftData

/// The Phoenix tab: a home for the user's companion. Shows the current
/// evolution tier, the Phoenix's vitality (health), XP progress to the next
/// tier, and the full evolution ladder. Read-only and celebratory — never a
/// place for guilt.
struct PhoenixView: View {
    @Query private var profiles: [UserProfile]
    @Query private var entries: [DailyEntry]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var achievementManager: AchievementManager
    @State private var lowEnergyPage = 0

    private var profile: UserProfile? { profiles.first }

    /// Days the user pushed through on energy 3 or below — sorted most-recent
    /// first so the page picker starts on the freshest example.
    private var lowEnergyDays: [DailyEntry] {
        entries
            .filter { ($0.energyScore ?? .max) <= 3 && $0.tasksCompleted > 0 }
            .sorted { $0.date > $1.date }
    }

    private var tierInfo: PhoenixDesign.TierInfo {
        PhoenixDesign.tierInfo(for: xpManager.totalXP)
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
        return next < PhoenixDesign.tiers.count ? PhoenixDesign.tiers[next].name : nil
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
                    badgesCard
                    if !lowEnergyDays.isEmpty {
                        daysThatBuiltYouCard
                    }
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
                    .font(.phoenixTitle(24))
                    .foregroundColor(tierInfo.color)
            }
            Spacer()
            Text("LV \(PhoenixDesign.playerLevel(for: xpManager.totalXP))")
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
                        .fill(PhoenixDesign.defenseBarColor(xpManager.realmDefense))
                        .frame(width: geo.size.width * Double(xpManager.realmDefense) / 100.0)
                        .animation(Constants.springAnimation, value: xpManager.realmDefense)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(xpManager.realmDefense)% health")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixDesign.defenseBarColor(xpManager.realmDefense))
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
                statItem(icon: "shield.fill", value: "\(xpManager.realmDefense)%", label: "DEFENSE", color: PhoenixDesign.defenseBarColor(xpManager.realmDefense))
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 18)
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
        .phoenixGlass(cornerRadius: 18)
    }

    // MARK: - Tier Ladder

    private var tierLadder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVOLUTION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            ForEach(Array(PhoenixDesign.tiers.enumerated()), id: \.offset) { index, tier in
                tierRow(index: index, tier: tier)
                if index < PhoenixDesign.tiers.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private func tierRow(index: Int, tier: (minXP: Int, name: String, color: Color)) -> some View {
        let unlocked = xpManager.totalXP >= tier.minXP
        let isCurrent = index == tierInfo.index

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tier.color.opacity(unlocked ? 0.22 : 0.06))
                    .frame(width: 44, height: 44)

                // A dimmed preview of the tier's actual visual, not just a lock
                // icon — so locked rows show what you're working toward.
                PhoenixTierVisual(tierIndex: index, size: 34, decorated: false)
                    .saturation(unlocked ? 1 : 0)
                    .opacity(unlocked ? 1 : 0.45)
                    .allowsHitTesting(false)

                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .offset(x: 15, y: 15)
                }
            }
            .frame(width: 44, height: 44)

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

    // MARK: - Badges

    private var badgesCard: some View {
        let unlockedIDs = Set(profile?.unlockedAchievements ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BADGES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                Spacer()
                Text("\(unlockedIDs.count)/\(AchievementManager.all.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(AchievementManager.all) { badge in
                    badgeCell(badge, unlocked: unlockedIDs.contains(badge.id))
                }
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private func badgeCell(_ badge: AchievementDefinition, unlocked: Bool) -> some View {
        let lockedGray = Color(white: 0.32)

        VStack(spacing: 8) {
            ZStack {
                // Bevel — a darker, slightly-offset twin of the medallion sitting
                // "underneath" it, the classic Duolingo chunky-icon look.
                Circle()
                    .fill(unlocked ? badge.color.darker(0.4) : lockedGray.darker(0.3))
                    .frame(width: 64, height: 64)
                    .offset(y: 4)

                // Medallion face
                Circle()
                    .fill(
                        LinearGradient(
                            colors: unlocked
                                ? [badge.color.lighter(0.22), badge.color]
                                : [lockedGray.opacity(0.9), lockedGray.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle().stroke(unlocked ? Color.white.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 2)
                    )
                    .shadow(color: unlocked ? badge.color.opacity(0.45) : .clear, radius: 8, y: 3)

                // The mascot, engraved into the medallion — a distinct still
                // frame per badge (flight, ember, ash, tier form) rather than
                // one pose repeated, desaturated to a ghost when locked.
                Image(badge.mascotImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .saturation(unlocked ? 1 : 0)
                    .opacity(unlocked ? 1 : 0.3)
                    .offset(y: 2)
                    .shadow(color: .black.opacity(unlocked ? 0.2 : 0), radius: 2, y: 1)
                    .clipShape(Circle().inset(by: 3))

                // Gloss highlight arcing across the top — gives the medallion a
                // glassy pop instead of a flat painted circle.
                Circle()
                    .trim(from: 0.56, to: 0.94)
                    .stroke(Color.white.opacity(unlocked ? 0.5 : 0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(180))
                    .allowsHitTesting(false)

                // Achievement-specific glyph, as a small chip so the badge is
                // still identifiable at a glance without reading the title.
                Circle()
                    .fill(unlocked ? badge.color.darker(0.15) : lockedGray.darker(0.2))
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: unlocked ? badge.icon : "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(unlocked ? .white : .white.opacity(0.6))
                    )
                    .offset(x: 21, y: 21)

                if unlocked {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PhoenixPalette.eternal)
                        .offset(x: -22, y: -22)
                }
            }
            .frame(width: 64, height: 68)

            Text(badge.title)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(unlocked ? PhoenixPalette.textPrimary : PhoenixPalette.textSecondary.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(unlocked ? "unlocked" : "locked"). \(badge.description)")
    }

    // MARK: - Days That Built You

    private var lowEnergyPageCount: Int {
        max(1, Int(ceil(Double(lowEnergyDays.count) / 2.0)))
    }

    private var daysThatBuiltYouCard: some View {
        let start = lowEnergyPage * 2
        let pageEntries = Array(lowEnergyDays[start..<min(start + 2, lowEnergyDays.count)])

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAYS THAT BUILT YOU")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                    Text("Low-energy days you still showed up.")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
                }
                Spacer()
                if lowEnergyPageCount > 1 {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(Constants.springAnimation) { lowEnergyPage = max(0, lowEnergyPage - 1) }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(lowEnergyPage == 0)

                        Text("\(lowEnergyPage + 1)/\(lowEnergyPageCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))

                        Button {
                            withAnimation(Constants.springAnimation) { lowEnergyPage = min(lowEnergyPageCount - 1, lowEnergyPage + 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(lowEnergyPage >= lowEnergyPageCount - 1)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                }
            }

            VStack(spacing: 10) {
                ForEach(pageEntries, id: \.id) { entry in
                    lowEnergyDayRow(entry)
                }
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 18)
        .onChange(of: lowEnergyDays.count) { _, _ in
            lowEnergyPage = min(lowEnergyPage, lowEnergyPageCount - 1)
        }
    }

    private func lowEnergyDayRow(_ entry: DailyEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(PhoenixPalette.destructive.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "flame.fill")
                    .font(.system(size: 15))
                    .foregroundColor(PhoenixPalette.destructive.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(lowEnergyDayLabel(entry.date))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
                Text("Energy \(entry.energyScore ?? 0)/10 · \(entry.tasksCompleted)/\(entry.totalTasksForDay) tasks")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }

            Spacer()

            Text("+\(entry.xpEarned) XP")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.success)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lowEnergyDayLabel(entry.date)), energy \(entry.energyScore ?? 0) out of 10, completed \(entry.tasksCompleted) of \(entry.totalTasksForDay) tasks, earned \(entry.xpEarned) XP.")
    }

    private func lowEnergyDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
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
            Section(header: Text("Workblock")) {
                ForEach(CalendarManager.shared.upcomingEvents.filter { $0.isDueSoon }) { event in
                    TaskRow(event: event, task: nil)
                }
            }
            
            Section(header: Text("Recommended Tasks")) {
                ForEach(xpManager.dailyPlan.recommendedTasks) { task in
                    TaskRow(event: nil, task: task)
                }
            }
            
            Section(header: Text("Deferred Tasks")) {
                ForEach(xpManager.dailyPlan.deferredTasks) { task in
                    TaskRow(event: nil, task: task)
                }
            }
        }
    }
}

struct TaskRow: View {
    let event: RizeCalendarEvent?
    let task: PlannedTask?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let event = event {
                    Text(event.title)
                        .font(.system(size: 14, weight: .bold))
                    Text("Due in \(event.daysUntil) days")
                        .font(.system(size: 12))
                } else if let task = task {
                    Text(task.title)
                        .font(.system(size: 14, weight: .bold))
                    Text(task.reason.rawValue.capitalized)
                        .font(.system(size: 12))
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}
