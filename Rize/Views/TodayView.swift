import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var achievementManager: AchievementManager

    @State private var todayEntry: DailyEntry? = nil
    @State private var isGenerating = false
    @State private var showXPToast = false
    @State private var toastXP = 0
    @State private var ryzMessage = ""
    @State private var showRyzMessage = false
    @State private var showAllDoneBanner = false
    @State private var showGoldBurst = false
    @State private var calendarEvents: [RizeCalendarEvent] = []
    @State private var currentPlan: DailyPlan? = nil
    @State private var currentNarrative: CoachingNarrative? = nil
    @State private var showLowEnergyCelebration = false
    @State private var lowEnergyCelebrationXP = 0
    @AppStorage("lowEnergyBonusShownDate") private var lowEnergyBonusShownDate: String = ""

    private var profile: UserProfile? { profiles.first }

    private var tierInfo: KingdomDesign.TierInfo {
        KingdomDesign.tierInfo(for: xpManager.totalXP)
    }

    /// Phoenix mascot is a Tier 5 (max tier) reward.
    private var showPhoenix: Bool {
        tierInfo.nextMinXP == nil
    }

    /// Calendar events due today or tomorrow — surfaced next to gold in the
    /// castle card, in the calendar glasscard, and in today's plan header.
    private var dueEvents: [RizeCalendarEvent] {
        calendarEvents.filter { $0.isUrgent }
    }

    @ViewBuilder
    private var dueSoonBadge: some View {
        if subscriptionManager.isPro && !dueEvents.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 9))
                Text(dueEvents.count == 1 ? "1 DUE SOON" : "\(dueEvents.count) DUE SOON")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(PhoenixPalette.destructive)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PhoenixPalette.destructive.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    var body: some View {
        ZStack {
            PhoenixBackground()

            // Ash-state vignette
            if xpManager.isUnderSiege {
                RadialGradient(
                    colors: [.clear, PhoenixPalette.destructive.opacity(0.18)],
                    center: .center,
                    startRadius: 150,
                    endRadius: 420
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    topBar
                    if xpManager.isUnderSiege { siegeBanner }
                    castleHero
                    calendarCard
                    mainContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            // Phoenix mascot — Tier 5 reward. Plays the fire takeoff once,
            // then loops the flight (from frame 70). Flight path is baked
            // into the frames, so this is a fixed full-width square stage.
            if showPhoenix {
                VStack {
                    PhoenixSpriteView()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Toasts
            VStack {
                if showXPToast {
                    xpToast(xp: toastXP)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 50)
                }
                if showRyzMessage {
                    ryzToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, showXPToast ? 110 : 50)
                }
                Spacer()
                if showAllDoneBanner { allDoneBanner.padding(.bottom, 100) }
            }

            // Particle burst
            if xpManager.triggerGoldBurst {
                ParticleEmitterView(type: .goldBurst)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Achievement banner
            if let achievement = achievementManager.recentlyUnlocked {
                achievementBanner(achievement)
            }

            // Siege broken banner
            if xpManager.showSiegeBrokenBanner {
                siegeBrokenBanner
            }

            // Low energy celebration overlay
            if showLowEnergyCelebration {
                LowEnergyCelebrationView(xp: lowEnergyCelebrationXP) {
                    withAnimation(Constants.springAnimation) { showLowEnergyCelebration = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            loadTodayEntry()
            loadCalendarEvents()
            xpManager.checkDayChange(
                completedCount: todayEntry?.tasksCompleted ?? 0,
                energyScore: todayEntry?.energyScore ?? 5
            )
            if let entry = todayEntry, entry.planGenerated {
                refreshCoaching(for: entry)
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .rizeDebugShowLowEnergyOverlay)) { _ in
            lowEnergyCelebrationXP = 50
            withAnimation(Constants.springAnimation) { showLowEnergyCelebration = true }
        }
        #endif
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Streak
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("\(profile?.currentStreak ?? 0)")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }

            Spacer()

            Text(tierInfo.name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(tierInfo.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            // Level badge
            Text("LV \(KingdomDesign.playerLevel(for: xpManager.totalXP))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tierInfo.color.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Siege Banner

    private var siegeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(PhoenixPalette.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text("RETURNING TO ASH")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(PhoenixPalette.destructive)
                Text("Your flame is fading. One task will reignite it.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(PhoenixPalette.destructive.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PhoenixPalette.destructive.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Castle Hero

    private var castleHero: some View {
        VStack(spacing: 16) {
            // Fire visual sits directly on the app background — no card/border
            // around it, so the animation isn't boxed in. Top padding gives every
            // tier's visual the same clearance above it (Tier3's flame overflows its
            // nominal box by design — see Tier3FlameView.contentScale — so this has to
            // be big enough for that, applied uniformly so all tiers sit at the same
            // spot rather than only pushing down the tiers that need the room).
            ZStack {
                Circle()
                    .fill(tierInfo.color.opacity(0.12))
                    .frame(width: 312, height: 312)
                    .blur(radius: 30)

                PhoenixTierVisual(tierIndex: tierInfo.index, size: 260)
                    .scaleEffect(xpManager.castleBounce ? 1.08 : 1.0)
                    .animation(
                        xpManager.castleBounce
                            ? .spring(response: 0.3, dampingFraction: 0.5)
                            : .default,
                        value: xpManager.castleBounce
                    )
                    .modifier(FloatingModifier())
                    // Tint the rendered fire itself rather than overlaying a fixed
                    // rounded-rect shape on top of it — an overlay shape is sized to the
                    // visual's nominal box and creates a visible seam now that the flame
                    // paints outside that box (see Tier3FlameView.contentScale).
                    .colorMultiply(xpManager.isUnderSiege ? PhoenixPalette.destructive : .white)
            }
            .padding(.top, 48)

            VStack(spacing: 16) {
                Text(tierInfo.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(tierInfo.color.opacity(0.8))

                // XP bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tierInfo.color)
                                .frame(width: geo.size.width * (profile?.progressPercentage ?? 0), height: 6)
                                .animation(Constants.springAnimation, value: profile?.progressPercentage)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(xpManager.totalXP) XP")
                        Spacer()
                        if let next = tierInfo.nextMinXP {
                            Text("\(next) XP")
                        } else {
                            Text("MAX TIER")
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                }
                .padding(.horizontal, 24)

                // Vitality row — pushed down below the phoenix's square stage
                // at Tier 5 so the sprite never overlaps the bars.
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("PHOENIX VITALITY")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(KingdomDesign.defenseBarColor(xpManager.realmDefense))
                                    .frame(width: geo.size.width * Double(xpManager.realmDefense) / 100.0)
                                    .animation(Constants.springAnimation, value: xpManager.realmDefense)
                            }
                        }
                        .frame(height: 5)
                        Text("\(xpManager.realmDefense)%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(KingdomDesign.defenseBarColor(xpManager.realmDefense))
                    }

                    Divider().background(Color.white.opacity(0.1)).frame(height: 30)

                    HStack(spacing: 4) {
                        Text("💰")
                        Text("\(xpManager.gold)")
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundColor(PhoenixPalette.eternal)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, showPhoenix ? 80 : 0)

                dueSoonBadge
            }
            .padding(16)
            .kingdomGlass(cornerRadius: 20)
        }
    }

    // MARK: - Calendar Card

    @ViewBuilder
    private var calendarCard: some View {
        if subscriptionManager.isPro && !calendarEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("UPCOMING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                    Spacer()
                    dueSoonBadge
                }

                ForEach(calendarEvents.prefix(3)) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.isUrgent ? PhoenixPalette.destructive : Color(hex: "0A84FF"))
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                            .lineLimit(1)
                        Spacer()
                        Text(event.isUrgent ? "TODAY" : "in \(event.daysUntil)d")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(event.isUrgent ? PhoenixPalette.destructive : PhoenixPalette.textSecondary.opacity(0.6))
                    }
                }
            }
            .padding(14)
            .kingdomGlass(cornerRadius: 14)
        } else if !subscriptionManager.isPro {
            ZStack {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(Color(hex: "0A84FF"))
                    Text("Calendar intel available with Pro")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(14)
                .kingdomGlass(cornerRadius: 14)
                .blur(radius: 2)

                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if let entry = todayEntry {
            if entry.energyScore == nil {
                // Show energy picker
                EnergyPickerCard(entry: entry, profile: profile) { energy in
                    setEnergy(energy, entry: entry)
                }
            } else if isGenerating {
                generatingCard
            } else if !entry.planGenerated {
                // Energy logged but no plan yet
                EnergyPickerCard(entry: entry, profile: profile, showBuildButton: true) { _ in
                    generatePlan(entry: entry)
                }
            } else {
                taskListSection(entry: entry)
            }
        } else {
            EnergyPickerCard(entry: nil, profile: profile) { energy in
                createEntryAndSetEnergy(energy)
            }
        }

        if let profile = profile, !profile.canGeneratePlan && !subscriptionManager.isPro {
            PlanLimitReachedCard()
        }
    }

    // MARK: - Generating Card

    private var generatingCard: some View {
        VStack(spacing: 20) {
            PhoenixTierVisual(tierIndex: tierInfo.index, size: 60, decorated: false)

            Text("Rize is building your plan...")
                .font(.system(.body, design: .rounded))
                .foregroundColor(PhoenixPalette.textSecondary)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(tierInfo.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isGenerating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                            value: isGenerating
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .kingdomGlass(cornerRadius: 20)
    }

    // MARK: - Task List

    @ViewBuilder
    private func taskListSection(entry: DailyEntry) -> some View {
        VStack(spacing: 12) {
            if let plan = currentPlan, let narrative = currentNarrative {
                coachingCard(plan: plan, narrative: narrative)
            }

            // Section header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(tierInfo.color)
                Text("TODAY'S PLAN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                dueSoonBadge
                Spacer()
                Text("\(entry.tasksCompleted)/\(entry.totalTasksForDay) done")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }

            if entry.tasks.isEmpty {
                Text("No tasks found. Try generating a new plan.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                    .padding()
            } else {
                ForEach(entry.tasks) { task in
                    TaskRowView(
                        task: task,
                        tierColor: tierInfo.color
                    ) {
                        completeTask(task, entry: entry)
                    }
                }
            }

            if entry.isFullyComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PhoenixPalette.success)
                    Text("ALL DONE ✓")
                        .font(.system(.headline, design: .monospaced, weight: .bold))
                        .foregroundColor(PhoenixPalette.success)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(PhoenixPalette.success.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(PhoenixPalette.success.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Coaching Card

    @ViewBuilder
    private func coachingCard(plan: DailyPlan, narrative: CoachingNarrative) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ryz encouragement
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(tierInfo.color)
                Text("RYZ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                Spacer()
                if plan.burnoutRisk != .low {
                    Label(plan.burnoutRisk == .high ? "Protect your energy" : "Ease in",
                          systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.destructive.opacity(0.9))
                }
            }

            Text(narrative.encouragement)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(PhoenixPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(narrative.explanation)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(PhoenixPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Decision chips
            HStack(spacing: 8) {
                coachingChip(icon: "gauge.with.dots.needle.33percent", text: workloadLabel(plan.workload))
                coachingChip(icon: "figure.run", text: workoutLabel(plan.workout.intent))
                if plan.recovery.emphasis != .none {
                    coachingChip(icon: "moon.zzz.fill", text: "Recover")
                }
            }

            // Body note + phoenix line
            Text(narrative.bodyNote)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(tierInfo.color.opacity(0.8))
                Text(narrative.phoenixMessage)
                    .font(.system(size: 11, design: .rounded))
                    .italic()
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kingdomGlass(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coaching. \(narrative.encouragement). \(narrative.explanation). \(narrative.bodyNote)")
    }

    private func coachingChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(tierInfo.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tierInfo.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func workloadLabel(_ w: Workload) -> String {
        switch w {
        case .light: return "Light day"
        case .moderate: return "Balanced"
        case .heavy: return "Full day"
        }
    }

    private func workoutLabel(_ i: WorkoutIntent) -> String {
        switch i {
        case .rest: return "Rest"
        case .recovery: return "Recovery"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .ambitious: return "Ambitious"
        }
    }

    // MARK: - Toast Views

    @ViewBuilder
    private func xpToast(xp: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(tierInfo.color)
            Text("+\(xp) XP")
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .foregroundColor(PhoenixPalette.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(tierInfo.color.opacity(0.2))
        .overlay(Capsule().stroke(tierInfo.color.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: tierInfo.color.opacity(0.3), radius: 10)
    }

    private var ryzToast: some View {
        Text(ryzMessage)
            .font(.system(.caption, design: .rounded))
            .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PhoenixPalette.surface)
            .overlay(Capsule().stroke(PhoenixPalette.surfaceBorder, lineWidth: 1))
            .clipShape(Capsule())
    }

    private var allDoneBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(PhoenixPalette.success)
            Text("All done. The flame holds. 🌅")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(PhoenixPalette.success.opacity(0.1))
        .overlay(Capsule().stroke(PhoenixPalette.success.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var siegeBrokenBanner: some View {
        VStack {
            Text(xpManager.siegeBrokenMessage)
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(20)
                .background(PhoenixPalette.primary.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PhoenixPalette.primary.opacity(0.4), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .padding(.top, 60)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func achievementBanner(_ def: AchievementDefinition) -> some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: def.icon)
                    .foregroundColor(def.color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(def.color.opacity(0.7))
                    Text(def.title)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(PhoenixPalette.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(def.color.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(def.color.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 50)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Actions

    private func setEnergy(_ energy: Int, entry: DailyEntry) {
        entry.energyScore = energy
        ryzMessage = RyzDialogue.onEnergyLog(energy)
        withAnimation(Constants.springAnimation) { showRyzMessage = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showRyzMessage = false }
        }
        generatePlan(entry: entry)
    }

    private func createEntryAndSetEnergy(_ energy: Int) {
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        modelContext.insert(entry)
        try? modelContext.save()
        todayEntry = entry
        setEnergy(energy, entry: entry)
    }

    /// The Rize planning pipeline:
    /// Tasks → HealthKit → Strava → PlanningEngine → DailyPlan → Task list +
    /// Foundation Models narration. The engine makes every decision; the model
    /// only explains it. Tasks appear immediately; coaching prose fills in when
    /// the on-device model responds (or instantly via the template fallback).
    @MainActor
    private func generatePlan(entry: DailyEntry) {
        guard let profile = profile, profile.canGeneratePlan else { return }
        isGenerating = true
        let energy = entry.energyScore ?? 5

        Task { @MainActor in
            let plan = makeDailyPlan(energy: energy, profile: profile)
            let activities = TaskFactory.activities(for: plan)

            // Persist the actionable tasks and show them right away.
            for activity in activities {
                let rt = RizeTask(
                    title: activity.title,
                    duration: activity.duration,
                    taskDescription: activity.detail,
                    type: activity.category.rawValue
                )
                rt.entry = entry
                modelContext.insert(rt)
                entry.tasks.append(rt)
            }
            entry.totalTasksForDay = activities.count
            entry.planGenerated = true
            profile.recordPlanGenerated()
            try? modelContext.save()

            currentPlan = plan
            currentNarrative = CoachingNarrator.template(for: plan, context: coachingContext(profile))
            isGenerating = false

            // Upgrade the coaching copy with on-device Foundation Models when ready.
            let narrative = await CoachingNarrator.shared.narrate(plan: plan, context: coachingContext(profile))
            currentNarrative = narrative
        }
    }

    /// Assemble the deterministic `PlanInput` from all available signals and run
    /// the engine. Pure and fast — safe to call on the main actor.
    @MainActor
    private func makeDailyPlan(energy: Int, profile: UserProfile) -> DailyPlan {
        let snapshot = HealthKitManager.shared.snapshot

        let planningEvents = calendarEvents.map {
            PlanningCalendarEvent(title: $0.title, date: $0.date, isAcademic: $0.mustPlanToday)
        }
        // Calendar deadlines are the engine's task inputs today (Rize has no
        // separate to-do list yet — that's a future surface).
        let planningTasks = calendarEvents.map {
            PlanningTask(
                title: $0.title,
                priority: $0.isUrgent ? .high : .medium,
                dueDate: $0.date,
                category: .work
            )
        }

        let input = PlanInput(
            referenceDate: Date(),
            energy: energy,
            tasks: planningTasks,
            calendarEvents: planningEvents,
            sleep: snapshot.sleep,
            recentWorkouts: snapshot.recentWorkouts,
            goals: profile.goalDetail,
            currentStreak: profile.currentStreak,
            previousPlan: currentPlan
        )

        return PlanningEngine().makePlan(from: input)
    }

    private func coachingContext(_ profile: UserProfile) -> CoachingContext {
        CoachingContext(name: profile.name, goal: profile.goal, goalDetail: profile.goalDetail)
    }

    /// Recompute the (deterministic) plan and refresh coaching copy for an
    /// already-generated day, so the coaching card survives app relaunches.
    @MainActor
    private func refreshCoaching(for entry: DailyEntry) {
        guard entry.planGenerated, let profile = profile else { return }
        let plan = makeDailyPlan(energy: entry.energyScore ?? 5, profile: profile)
        currentPlan = plan
        if currentNarrative == nil {
            currentNarrative = CoachingNarrator.template(for: plan, context: coachingContext(profile))
        }
        Task { @MainActor in
            currentNarrative = await CoachingNarrator.shared.narrate(plan: plan, context: coachingContext(profile))
        }
    }

    private func completeTask(_ task: RizeTask, entry: DailyEntry) {
        guard !task.completed else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        withAnimation(Constants.springAnimation) {
            task.completed = true
            task.completedAt = Date()
            entry.tasksCompleted += 1
        }

        guard let profile = profile else { return }
        let result = xpManager.applyTaskCompletion(entry: entry, profile: profile)

        try? modelContext.save()

        // XP toast
        toastXP = result.xpDelta
        withAnimation(Constants.springAnimation) { showXPToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showXPToast = false }
        }

        // Ryz message
        let taskNumber = entry.tasksCompleted
        ryzMessage = RyzDialogue.onTaskComplete(taskNumber, allDone: result.allTasksDone)
        withAnimation(Constants.springAnimation) { showRyzMessage = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showRyzMessage = false }
        }

        // All done
        if result.allTasksDone {
            withAnimation(Constants.springAnimation) { showAllDoneBanner = true }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { showAllDoneBanner = false }
            }
            NotificationManager.shared.scheduleAllTasksComplete()

            // Low energy celebration — all tasks done on a 1-3 energy day, once per day.
            if let energy = entry.energyScore, energy <= 3, lowEnergyBonusShownDate != TodayView.todayDateString {
                lowEnergyBonusShownDate = TodayView.todayDateString
                lowEnergyCelebrationXP = result.xpDelta
                withAnimation(Constants.springAnimation) { showLowEnergyCelebration = true }
            }
        }

        // Streak milestone
        if [3, 7, 14, 30].contains(profile.currentStreak) {
            NotificationManager.shared.scheduleStreakMilestone(profile.currentStreak)
        }

        // Achievements
        achievementManager.check(profile: profile, entry: entry, xpManager: xpManager)
    }

    private func loadTodayEntry() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        let descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        todayEntry = try? modelContext.fetch(descriptor).first
    }

    private func loadCalendarEvents() {
        calendarEvents = CalendarManager.shared.upcomingEvents
        Task {
            await CalendarManager.shared.fetchUpcomingEvents()
            calendarEvents = CalendarManager.shared.upcomingEvents
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var todayDateString: String {
        dayFormatter.string(from: Date())
    }
}

// MARK: - Low Energy Celebration Overlay

private struct LowEnergyCelebrationView: View {
    let xp: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            PhoenixBackground(intensified: true)
                .opacity(0.96)

            ParticleEmitterView(type: .goldBurst)
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                Spacer()

                PhoenixTierVisual(tierIndex: 4, size: 160)

                Text("You burned brightest in the dark.")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("+\(xp) XP")
                    .font(.system(size: 48, weight: .black, design: .monospaced))
                    .foregroundColor(PhoenixPalette.primary)

                Text("2.5x low energy bonus")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)

                Spacer()

                Button(action: onDismiss) {
                    Text("Keep rising.")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(PhoenixPalette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Energy Picker Card

struct EnergyPickerCard: View {
    let entry: DailyEntry?
    let profile: UserProfile?
    var showBuildButton: Bool = false
    let onSelect: (Int) -> Void

    @State private var selectedEnergy: Int? = nil
    @EnvironmentObject private var xpManager: XPManager

    private var tierInfo: KingdomDesign.TierInfo {
        KingdomDesign.tierInfo(for: xpManager.totalXP)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Daily word
            if let energy = selectedEnergy {
                let word = RyzDialogue.dailyWord(for: energy)
                VStack(spacing: 4) {
                    Text(word.word)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(Constants.energyColor(for: energy))
                    Text(word.subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 8) {
                Text("HOW'S YOUR ENERGY?")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary)
                Text("Be honest. There's no wrong answer.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            }

            // Energy buttons
            VStack(spacing: 8) {
                energyRow(1...5)
                energyRow(6...10)
            }

            // Multiplier hint
            if let energy = selectedEnergy {
                let mult = XPManager.shared.energyMultiplier(for: energy)
                Text(mult > 1.0 ? "×\(String(format: "%.1f", mult)) XP — showing up on a \(energy) takes guts." : "×1.0 XP — strong day. Push it.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Constants.energyColor(for: energy).opacity(0.8))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            // Build plan button
            if let energy = selectedEnergy {
                Button {
                    onSelect(energy)
                } label: {
                    Text(showBuildButton ? "REGENERATE PLAN" : "BUILD MY PLAN")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [tierInfo.color, tierInfo.color.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(20)
        .kingdomGlass(cornerRadius: 20)
        .animation(Constants.springAnimation, value: selectedEnergy)
        .onAppear {
            if let e = entry?.energyScore { selectedEnergy = e }
        }
    }

    @ViewBuilder
    private func energyRow(_ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { val in
                Button {
                    withAnimation(Constants.springAnimation) { selectedEnergy = val }
                } label: {
                    Text("\(val)")
                        .font(.system(.headline, design: .monospaced, weight: .bold))
                        .foregroundColor(selectedEnergy == val ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedEnergy == val
                                ? Constants.energyColor(for: val)
                                : Color.white.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .scaleEffect(selectedEnergy == val ? 1.1 : 1.0)
                }
            }
        }
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: RizeTask
    let tierColor: Color
    let onComplete: () -> Void

    @State private var bouncing = false

    private var section: KingdomTaskSection {
        KingdomTaskSection.from(taskType: task.type)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(KingdomDesign.sectionColor(section).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .foregroundColor(KingdomDesign.sectionColor(section))
            }

            // Title + duration
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(task.completed ? PhoenixPalette.textSecondary.opacity(0.5) : PhoenixPalette.textPrimary)
                    .strikethrough(task.completed)
                Text(task.duration)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
            }

            Spacer()

            // Checkbox
            Button {
                guard !task.completed else { return }
                withAnimation(Constants.springAnimation) { bouncing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    bouncing = false
                }
                onComplete()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            task.completed ? KingdomDesign.sectionColor(section) : Color.white.opacity(0.2),
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(
                                task.completed
                                    ? KingdomDesign.sectionColor(section)
                                    : Color.clear
                            )
                        )

                    if task.completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(bouncing ? 1.2 : 1.0)
                .animation(Constants.springAnimation, value: bouncing)
                .animation(Constants.springAnimation, value: task.completed)
            }
        }
        .padding(14)
        .kingdomGlass(cornerRadius: 14)
    }
}

// MARK: - Floating Modifier

struct FloatingModifier: ViewModifier {
    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .offset(y: floating ? -6 : 6)
            .animation(
                .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                value: floating
            )
            .onAppear { floating = true }
    }
}
