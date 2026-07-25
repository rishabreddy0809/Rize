import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var achievementManager: AchievementManager

    @State private var todayEntry: DailyEntry? = nil
    @State private var isGenerating = false
    @State private var showXPToast = false
    @State private var toastXP = 0
    @State private var ryzMessage = ""
    @State private var showRyzMessage = false
    @State private var showGoldBurst = false
    @State private var calendarEvents: [RizeCalendarEvent] = []
    @State private var currentPlan: DailyPlan? = nil
    @State private var currentNarrative: CoachingNarrative? = nil
    @ObservedObject private var celebrationCenter = CelebrationCenter.shared
    @ObservedObject private var healthKit = HealthKitManager.shared
    @AppStorage("lowEnergyBonusShownDate") private var lowEnergyBonusShownDate: String = ""
    /// The scheduled task currently prompting "did you finish this?" — only
    /// one at a time, same pattern as the celebration queue.
    @State private var overdueTaskAlert: RizeTask? = nil

    private var profile: UserProfile? { profiles.first }

    private var tierInfo: PhoenixDesign.TierInfo {
        PhoenixDesign.tierInfo(for: xpManager.totalXP)
    }

    /// Calendar events due today or tomorrow — surfaced next to gold in the
    /// castle card, in the calendar glasscard, and in today's plan header.
    private var dueEvents: [RizeCalendarEvent] {
        calendarEvents.filter { $0.isUrgent }
    }

    @ViewBuilder
    private var dueSoonBadge: some View {
        if !dueEvents.isEmpty {
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
            }

            // Particle burst
            if xpManager.triggerGoldBurst {
                ParticleEmitterView(type: .goldBurst)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Siege broken banner
            if xpManager.showSiegeBrokenBanner {
                siegeBrokenBanner
            }
        }
        .onAppear {
            loadTodayEntry()
            loadCalendarEvents()
            xpManager.checkDayChange { date in
                let entry = fetchEntry(for: date)
                return (entry?.tasksCompleted ?? 0, entry?.energyScore ?? 5)
            }
            xpManager.refreshWidgetSnapshot(
                streak: profile?.currentStreak ?? 0,
                tasks: todayEntry?.tasks ?? [],
                sportsGoalEnabled: profile?.hasSportsGoal ?? false,
                recentWorkouts: healthKit.recentWorkouts
            )
            if let entry = todayEntry, entry.planGenerated {
                refreshCoaching(for: entry)
            }
            autoCompleteTasksFromWorkouts()
            checkOverdueTasks()
        }
        .onChange(of: healthKit.recentWorkouts) { _, _ in
            autoCompleteTasksFromWorkouts()
        }
        // Scheduled tasks can quietly slip into the past while the app just
        // sits open — a 60s tick catches that without needing a relaunch.
        // Same tick also re-polls the calendar, so a meeting accepted while
        // Rize is sitting open in the background lands on the list without
        // the user having to relaunch the app.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            checkOverdueTasks()
            loadCalendarEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rizeAddCustomTask)) { note in
            guard let request = note.object as? CustomTaskRequest else { return }
            addCustomTask(request)
        }
        .alert(
            "Still on your list",
            isPresented: Binding(
                get: { overdueTaskAlert != nil },
                set: { if !$0 { overdueTaskAlert = nil } }
            ),
            presenting: overdueTaskAlert
        ) { task in
            Button("Mark Done") {
                task.overdueAlertDismissed = true
                if let entry = todayEntry { completeTask(task, entry: entry) }
                overdueTaskAlert = nil
            }
            Button("Keep on List") {
                // Still not done, but the user just needs more time — leave the
                // task untouched and don't nag about it again.
                task.overdueAlertDismissed = true
                try? modelContext.save()
                overdueTaskAlert = nil
            }
            Button("Remove", role: .destructive) {
                task.overdueAlertDismissed = true
                removeTask(task)
                overdueTaskAlert = nil
            }
        } message: { task in
            Text("\"\(task.title)\" was due at \(TodayView.timeLabel(for: task.dueDate ?? Date())). Did you get to it?")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Streak
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("\(profile?.currentStreak ?? 0)")
                    .font(.phoenixHeadline())
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
            Text("LV \(PhoenixDesign.playerLevel(for: xpManager.totalXP))")
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

                // Vitality row
                VStack(spacing: 4) {
                    Text("PHOENIX VITALITY")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(PhoenixDesign.defenseBarColor(xpManager.realmDefense))
                                .frame(width: geo.size.width * Double(xpManager.realmDefense) / 100.0)
                                .animation(Constants.springAnimation, value: xpManager.realmDefense)
                        }
                    }
                    .frame(height: 5)
                    Text("\(xpManager.realmDefense)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixDesign.defenseBarColor(xpManager.realmDefense))
                }
                .padding(.horizontal, 24)

                dueSoonBadge
            }
            .padding(16)
            .phoenixGlass(cornerRadius: 20)
        }
    }

    // MARK: - Calendar Card

    @ViewBuilder
    private var calendarCard: some View {
        if !calendarEvents.isEmpty {
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
            .phoenixGlass(cornerRadius: 14)
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
        .phoenixGlass(cornerRadius: 20)
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
                ForEach(groupedTasks(entry.tasks)) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        groupHeader(group)
                        ForEach(group.tasks) { task in
                            TaskRowView(
                                task: task,
                                tierColor: tierInfo.color,
                                onComplete: {
                                    completeTask(task, entry: entry)
                                },
                                onDelete: {
                                    removeTask(task)
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }

            if entry.isFullyComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PhoenixPalette.success)
                    Text("ALL DONE ✓")
                        .font(.phoenixHeadline())
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

    // MARK: - Task Grouping

    /// A display section in the plan. Goal tasks group under their flexible,
    /// goal-derived label ("Marathon Base"); calendar events fall back to their
    /// fixed `PlanCategory` bucket. Icon/colour come from the task's category.
    struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let sortOrder: Int
        var tasks: [RizeTask]
    }

    /// Group the day's tasks: goal tasks first (under their focus label), then
    /// calendar categories. Each group's tasks are sorted (incomplete first,
    /// then by scheduled time).
    private func groupedTasks(_ tasks: [RizeTask]) -> [TaskGroup] {
        Dictionary(grouping: tasks) { groupKey(for: $0) }
            .map { key, value -> TaskGroup in
                let sample = value[0]
                let category = PlanCategory.from(taskType: sample.type)
                let isGoal = sample.sectionLabel?.isEmpty == false
                return TaskGroup(
                    id: key,
                    title: sample.sectionLabel?.isEmpty == false ? sample.sectionLabel! : category.title,
                    icon: category.icon,
                    color: category.color,
                    // Goal tasks lead the list; calendar buckets follow in their order.
                    sortOrder: isGoal ? -1 : category.sortOrder,
                    tasks: value.sorted(by: taskSort)
                )
            }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
    }

    private func groupKey(for task: RizeTask) -> String {
        if let label = task.sectionLabel, !label.isEmpty { return "goal:\(label)" }
        return "cat:\(PlanCategory.from(taskType: task.type).rawValue)"
    }

    private func taskSort(_ a: RizeTask, _ b: RizeTask) -> Bool {
        if a.completed != b.completed { return !a.completed } // incomplete first
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x < y
        case (_?, nil):    return true
        case (nil, _?):    return false
        case (nil, nil):   return a.title < b.title
        }
    }

    private func groupHeader(_ group: TaskGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(group.color)
            Text(group.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(group.color)
            Spacer()
            Text("\(group.tasks.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(group.color.opacity(0.6))
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
        .phoenixGlass(cornerRadius: 18)
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
                .font(.phoenixHeadline())
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

    private var siegeBrokenBanner: some View {
        VStack {
            Text(xpManager.siegeBrokenMessage)
                .font(.phoenixHeadline())
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
    /// Tasks → HealthKit → PlanningEngine → DailyPlan → Task list +
    /// Foundation Models narration. The engine makes every decision; the model
    /// only explains it. Tasks appear immediately; coaching prose fills in when
    /// the on-device model responds (or instantly via the template fallback).
    @MainActor
    private func generatePlan(entry: DailyEntry) {
        guard let profile = profile else { return }
        isGenerating = true
        let energy = entry.energyScore ?? 5

        Task { @MainActor in
            let plan = makeDailyPlan(energy: energy, profile: profile)

            // Goal-specific tasks, written on-device by Foundation Models and
            // grounded in the engine's decision for today (intensity/workload).
            // Nothing generic — the tasks always serve the user's stated goal.
            let goalTasks = await GoalTaskGenerator.tasks(for: plan, context: coachingContext(profile))

            // Clear any previously generated tasks so regenerating doesn't
            // stack duplicates.
            for old in entry.tasks {
                NotificationManager.shared.cancelTaskDueReminder(taskID: old.id)
                modelContext.delete(old)
            }
            entry.tasks.removeAll()
            entry.tasksCompleted = 0

            for activity in goalTasks {
                let rt = RizeTask(
                    title: activity.title,
                    duration: activity.duration,
                    taskDescription: activity.detail,
                    type: activity.category.rawValue,
                    sectionLabel: activity.focus
                )
                rt.entry = entry
                modelContext.insert(rt)
                entry.tasks.append(rt)
            }

            // Real scheduled tasks pulled from the user's calendar (EventKit),
            // classified into workout / class / work / personal buckets.
            await CalendarManager.shared.fetchTodaysEvents()
            for event in CalendarManager.shared.todaysEvents {
                let rt = RizeTask(
                    title: event.title,
                    duration: TodayView.scheduleLabel(daysUntil: 0, date: event.date),
                    taskDescription: "From your calendar",
                    type: event.category.rawValue,
                    priority: event.mustPlanToday ? .high : .medium,
                    dueDate: event.date
                )
                rt.entry = entry
                modelContext.insert(rt)
                entry.tasks.append(rt)
                NotificationManager.shared.scheduleTaskDueReminder(taskID: rt.id, title: rt.title, dueDate: event.date)
            }

            // On steadier/high-energy days, surface future calendar items too
            // (not just today's) — capped at a 2-month horizon so nothing a
            // year out clutters the plan. Low/depleted energy stays
            // today-only so the day doesn't feel overloaded.
            let band = EnergyBand(energy: energy)
            if band != .depleted && band != .low {
                await CalendarManager.shared.fetchUpcomingEvents()
                let todaysTitles = Set(CalendarManager.shared.todaysEvents.map { $0.title })
                for event in CalendarManager.shared.upcomingEvents where event.daysUntil >= 1 {
                    guard !todaysTitles.contains(event.title) else { continue }
                    let rt = RizeTask(
                        title: event.title,
                        duration: TodayView.scheduleLabel(daysUntil: event.daysUntil, date: event.date),
                        taskDescription: "From your calendar",
                        type: event.category.rawValue,
                        priority: event.mustPlanToday ? .high : .medium,
                        dueDate: event.date
                    )
                    rt.entry = entry
                    modelContext.insert(rt)
                    entry.tasks.append(rt)
                    NotificationManager.shared.scheduleTaskDueReminder(taskID: rt.id, title: rt.title, dueDate: event.date)
                }
            }

            entry.totalTasksForDay = entry.tasks.count
            entry.planGenerated = true
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

    /// Adds a user-authored task from the quick-add sheet, classifying it into
    /// the right section (Workouts/Classes/Work Blocks/Personal) the same way
    /// a real calendar event would be, purely from its title.
    private func addCustomTask(_ request: CustomTaskRequest) {
        let entry = todayEntry ?? makeTodayEntry()
        let category = PlanCategory.classify(title: request.title, calendarName: nil)
        let duration = request.dueDate.map {
            TodayView.scheduleLabel(daysUntil: daysUntil(for: $0), date: $0)
        } ?? "Anytime"

        let task = RizeTask(
            title: request.title,
            duration: duration,
            taskDescription: "Added by you",
            type: category.rawValue,
            dueDate: request.dueDate
        )
        task.entry = entry
        modelContext.insert(task)
        withAnimation(Constants.springAnimation) {
            entry.tasks.append(task)
            entry.totalTasksForDay = entry.tasks.count
        }
        try? modelContext.save()
        if let dueDate = request.dueDate {
            NotificationManager.shared.scheduleTaskDueReminder(taskID: task.id, title: task.title, dueDate: dueDate)
        }
    }

    /// Today's entry, created on the spot if the user adds a task before
    /// logging energy / generating a plan — normally entries are only
    /// created from the energy picker (see `createEntryAndSetEnergy`).
    private func makeTodayEntry() -> DailyEntry {
        let entry = DailyEntry(date: Date())
        entry.profile = profile
        modelContext.insert(entry)
        try? modelContext.save()
        todayEntry = entry
        return entry
    }

    private func daysUntil(for date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    private func removeTask(_ task: RizeTask) {
        guard let entry = todayEntry else { return }
        NotificationManager.shared.cancelTaskDueReminder(taskID: task.id)
        withAnimation(Constants.springAnimation) {
            entry.tasks.removeAll { $0.persistentModelID == task.persistentModelID }
            entry.totalTasksForDay = entry.tasks.count
        }
        modelContext.delete(task)
        try? modelContext.save()
    }

    /// Surfaces one "did you finish this?" prompt at a time for any scheduled
    /// (calendar-derived) task whose due time has passed without being marked
    /// done — checked on appear and every 60s while the view is on screen.
    private func checkOverdueTasks() {
        guard overdueTaskAlert == nil, let entry = todayEntry else { return }
        let now = Date()
        overdueTaskAlert = entry.tasks.first { task in
            guard !task.completed, !task.overdueAlertDismissed, let due = task.dueDate else { return false }
            return due < now
        }
    }

    /// Checks off any planned workout task that today's real Apple Health
    /// workouts already satisfy — e.g. an actual 5.1-mile run auto-completes
    /// "Easy 5-mile run" through the same `completeTask` path a manual tap
    /// uses, so XP/celebrations/achievements all fire identically.
    private func autoCompleteTasksFromWorkouts() {
        guard let entry = todayEntry else { return }
        let todaysWorkouts = healthKit.recentWorkouts.filter { Calendar.current.isDateInToday($0.startDate) }
        guard !todaysWorkouts.isEmpty else { return }

        var consumedWorkoutIDs = Set<UUID>()
        for task in entry.tasks where !task.completed {
            guard let workout = todaysWorkouts.first(where: {
                !consumedWorkoutIDs.contains($0.id) && WorkoutTaskMatcher.matches(workout: $0, task: task)
            }) else { continue }
            consumedWorkoutIDs.insert(workout.id)
            completeTask(task, entry: entry)
        }
    }

    private func completeTask(_ task: RizeTask, entry: DailyEntry) {
        guard !task.completed else { return }

        NotificationManager.shared.cancelTaskDueReminder(taskID: task.id)

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
        xpManager.refreshWidgetSnapshot(
            streak: profile.currentStreak,
            tasks: entry.tasks,
            sportsGoalEnabled: profile.hasSportsGoal,
            recentWorkouts: healthKit.recentWorkouts
        )

        if result.allTasksDone {
            // A full-screen "day complete" celebration is about to queue up —
            // skip the small per-task toasts so they don't flash in only to be
            // immediately covered by it.
            NotificationManager.shared.scheduleAllTasksComplete()
            celebrationCenter.enqueue(.allDone(xp: result.xpDelta, streak: profile.currentStreak))

            // Low energy celebration — all tasks done on a 1-3 energy day, once per day.
            if let energy = entry.energyScore, energy <= 3, lowEnergyBonusShownDate != TodayView.todayDateString {
                lowEnergyBonusShownDate = TodayView.todayDateString
                celebrationCenter.enqueue(.lowEnergy(xp: result.xpDelta))
            }
        } else {
            // XP toast
            toastXP = result.xpDelta
            withAnimation(Constants.springAnimation) { showXPToast = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { showXPToast = false }
            }

            // Ryz message
            let taskNumber = entry.tasksCompleted
            ryzMessage = RyzDialogue.onTaskComplete(taskNumber, allDone: false)
            withAnimation(Constants.springAnimation) { showRyzMessage = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { showRyzMessage = false }
            }
        }

        // Streak milestone
        if [3, 7, 14, 30].contains(profile.currentStreak) {
            NotificationManager.shared.scheduleStreakMilestone(profile.currentStreak)
        }

        // Achievements — queue any newly unlocked ones so they celebrate one at a time.
        for achievement in achievementManager.check(profile: profile, entry: entry, xpManager: xpManager) {
            celebrationCenter.enqueue(.achievement(achievement))
        }
    }

    private func loadTodayEntry() {
        todayEntry = fetchEntry(for: Date())
    }

    private func fetchEntry(for date: Date) -> DailyEntry? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return try? modelContext.fetch(descriptor).first
    }


    private func loadCalendarEvents() {
        calendarEvents = CalendarManager.shared.upcomingEvents
        Task {
            await CalendarManager.shared.fetchUpcomingEvents()
            await CalendarManager.shared.fetchTodaysEvents()
            calendarEvents = CalendarManager.shared.upcomingEvents
            syncNewCalendarEvents()
        }
    }

    /// Adds calendar events that showed up *after* today's plan was already
    /// generated — someone accepts a meeting invite, a class gets added,
    /// etc. — without touching anything already on the list. This is
    /// deliberately additive-only, unlike `generatePlan`'s calendar section
    /// (which it mirrors), which wipes and rebuilds every task from scratch:
    /// regenerating here would also re-roll the goal tasks and re-run
    /// Foundation Models narration for no reason, and would discard
    /// completion state on anything the user already checked off.
    ///
    /// No-ops until a plan exists — `generatePlan` picks up whatever's on
    /// the calendar at that point on its own, so there's nothing to merge
    /// before then.
    private func syncNewCalendarEvents() {
        guard let entry = todayEntry, entry.planGenerated else { return }

        // Calendar-sourced tasks are identifiable by this fixed description
        // (set in `generatePlan`) plus their `dueDate` — pairing that with
        // `title` gives a dedup key that matches how `generatePlan` itself
        // already avoids re-adding a today event that's also in
        // `upcomingEvents` (see `todaysTitles` there). Two different
        // real-world events could in principle collide on title+time, but
        // that's an acceptable rare edge case for a dedup heuristic.
        let existingCalendarKeys = Set(
            entry.tasks
                .filter { $0.taskDescription == "From your calendar" }
                .compactMap { task -> String? in
                    guard let due = task.dueDate else { return nil }
                    return "\(task.title)|\(due.timeIntervalSinceReferenceDate)"
                }
        )

        func isNew(_ event: RizeCalendarEvent) -> Bool {
            !existingCalendarKeys.contains("\(event.title)|\(event.date.timeIntervalSinceReferenceDate)")
        }

        var addedAny = false

        for event in CalendarManager.shared.todaysEvents where isNew(event) {
            appendCalendarTask(for: event, to: entry)
            addedAny = true
        }

        // Same energy-band gating `generatePlan` uses for future events —
        // low/depleted-energy days stay today-only, so a newly-added event
        // three weeks out shouldn't suddenly pile onto an already-light day.
        let band = EnergyBand(energy: entry.energyScore ?? 5)
        if band != .depleted && band != .low {
            for event in CalendarManager.shared.upcomingEvents where event.daysUntil >= 1 && isNew(event) {
                appendCalendarTask(for: event, to: entry)
                addedAny = true
            }
        }

        guard addedAny else { return }
        entry.totalTasksForDay = entry.tasks.count
        try? modelContext.save()
    }

    /// Builds and inserts one calendar-sourced `RizeTask`, matching the same
    /// shape `generatePlan`'s own (separate, unanimated — it's clearing and
    /// rebuilding the whole list at once, not top-up-appending one at a
    /// time) calendar loops produce, so a task added by either path looks
    /// identical.
    private func appendCalendarTask(for event: RizeCalendarEvent, to entry: DailyEntry) {
        let rt = RizeTask(
            title: event.title,
            duration: TodayView.scheduleLabel(daysUntil: event.daysUntil, date: event.date),
            taskDescription: "From your calendar",
            type: event.category.rawValue,
            priority: event.mustPlanToday ? .high : .medium,
            dueDate: event.date
        )
        rt.entry = entry
        modelContext.insert(rt)
        withAnimation(Constants.springAnimation) {
            entry.tasks.append(rt)
        }
        NotificationManager.shared.scheduleTaskDueReminder(taskID: rt.id, title: rt.title, dueDate: event.date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// A short start-time label ("9:00 AM") used as a calendar task's subtitle.
    static func timeLabel(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// A calendar task's subtitle that always states *when*, not just the
    /// clock time — a bare "1:00 PM" reads as "today" even for something
    /// scheduled weeks out, so anything beyond today leads with "Today" /
    /// "Tomorrow" / "In N days" instead.
    static func scheduleLabel(daysUntil: Int, date: Date) -> String {
        switch daysUntil {
        case 0:  return "Today, \(timeLabel(for: date))"
        case 1:  return "Tomorrow, \(timeLabel(for: date))"
        default: return "In \(daysUntil) days"
        }
    }

    private static var todayDateString: String {
        dayFormatter.string(from: Date())
    }
}

// MARK: - Day Complete Celebration

/// Full-screen celebration for finishing every task in today's plan — same
/// visual language as `AchievementUnlockedView` (gold-family palette, ember
/// burst, spring-in hero) instead of the small pill banner this used to be.
struct DayCompleteCelebrationView: View {
    let xp: Int
    let streak: Int
    let tierIndex: Int
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            PhoenixBackground(intensified: true)
                .opacity(0.97)

            RadialGradient(
                colors: [PhoenixPalette.primary.opacity(glowPulse ? 0.32 : 0.16), .clear],
                center: .center, startRadius: 20, endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if appeared {
                ParticleEmitterView(type: .goldBurst)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 20) {
                Spacer()

                PhoenixTierVisual(tierIndex: tierIndex, size: 180)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 10) {
                    Text("DAY COMPLETE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(PhoenixPalette.primary)

                    Text("Every task, done.")
                        .font(.phoenixHero(26))
                        .foregroundColor(PhoenixPalette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("+\(xp) XP")
                        .font(.phoenixHero(44))
                        .foregroundColor(PhoenixPalette.primary)

                    if streak > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("\(streak)-day streak")
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                                .foregroundColor(PhoenixPalette.textSecondary)
                        }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                Spacer()

                Button(action: onDismiss) {
                    Text("The flame holds.")
                        .font(.phoenixHeadline())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(PhoenixPalette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glowPulse = true }
        }
    }
}

// MARK: - Low Energy Celebration Overlay

struct LowEnergyCelebrationView: View {
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
                    .font(.phoenixTitle(22))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("+\(xp) XP")
                    .font(.phoenixHero(48))
                    .foregroundColor(PhoenixPalette.primary)

                Text("2.5x low energy bonus")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)

                Spacer()

                Button(action: onDismiss) {
                    Text("Keep rising.")
                        .font(.phoenixHeadline())
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

    private var tierInfo: PhoenixDesign.TierInfo {
        PhoenixDesign.tierInfo(for: xpManager.totalXP)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Daily word
            if let energy = selectedEnergy {
                let word = RyzDialogue.dailyWord(for: energy)
                VStack(spacing: 4) {
                    Text(word.word)
                        .font(.phoenixHero(22))
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
                        .font(.phoenixHeadline())
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
        .phoenixGlass(cornerRadius: 20)
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
                        .font(.phoenixHeadline())
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

/// Swipe-to-delete, built by hand rather than via `List`'s built-in
/// `.swipeActions` — this row lives in a plain `ForEach` inside a `VStack`
/// (see `taskListSection` above), not inside a `List`, and `.swipeActions`
/// only works on actual `List` rows. So this reimplements the same gesture
/// from scratch with two views stacked on top of each other:
///
///   - a red "Delete" button, always present but normally hidden entirely
///     behind the row in front of it, and
///   - the visible row content (`rowContent`), which a `DragGesture` slides
///     left/right via `.offset(x: dragOffset)` to reveal or re-hide the
///     button underneath.
///
/// `ZStack(alignment: .trailing)` is what makes "behind" mean anything here:
/// it layers its children back-to-front in declaration order (the delete
/// button is declared first, so it's the back layer) and, since the button
/// is narrower than the row, aligns it to the trailing (right) edge — so as
/// `rowContent` slides left, it un-covers the button sitting flush against
/// that right edge rather than the button appearing to move.
struct TaskRowView: View {
    let task: RizeTask
    let tierColor: Color
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var bouncing = false
    /// The row's *settled* horizontal offset — where it rests when no
    /// finger is currently touching it. `0` means fully closed (delete
    /// button hidden); `openOffset` (negative) means fully open. This only
    /// ever changes once per gesture, in `onEnded` — never live, mid-drag —
    /// which is what makes it a stable anchor (see `dragTranslation` below
    /// for why that stability matters).
    @State private var settledOffset: CGFloat = 0
    /// The live, in-progress finger movement for whichever drag is
    /// currently happening, or `0` when no drag is active. `@GestureState`
    /// (unlike plain `@State`) resets this to its default automatically the
    /// instant a gesture ends/cancels — no manual reset needed, and no risk
    /// of stale leftover state from a previous drag bleeding into the next
    /// one's calculation.
    ///
    /// This two-value split (a stable settled offset + a separately-tracked
    /// live delta) fixes a real bug an earlier version of this view had:
    /// that version tried to infer "did this drag start from an open row?"
    /// by comparing the single offset state to `openOffset` — but it
    /// re-checked that comparison on *every* `onChanged` callback, against
    /// a value that callback itself was mutating, so a drag that started
    /// open would silently flip its own reference point a few callbacks in
    /// and the row would visibly jump/snap mid-swipe. `DragGesture`'s
    /// `.translation` is always relative to *this* gesture's own start, so
    /// `settledOffset + dragTranslation` is unambiguous no matter when
    /// during the drag it's read.
    @GestureState private var dragTranslation: CGFloat = 0

    private let deleteButtonWidth: CGFloat = 76
    /// The fully-open resting position, as a negative offset — SwiftUI's
    /// `.offset(x:)` moves a view right for positive values and left for
    /// negative ones, so "shifted left by the delete button's width" is
    /// `-deleteButtonWidth`.
    private var openOffset: CGFloat { -deleteButtonWidth }

    /// Where the row is drawn right now — the settled position plus
    /// whatever the current drag (if any) has added on top, clamped so it
    /// can never overshoot fully closed/open even mid-gesture.
    private var currentOffset: CGFloat {
        min(0, max(openOffset, settledOffset + dragTranslation))
    }

    private var category: PlanCategory {
        PlanCategory.from(taskType: task.type)
    }

    /// 0 when fully closed, 1 when fully open — drives the delete button's
    /// opacity below. `rowContent`'s glass background (`phoenixGlass`, via
    /// `PhoenixPalette.surface`) is only 85% opaque by design, so simply
    /// stacking the button "behind" a closed row isn't actually enough to
    /// hide it — roughly 15% of the button's red still shows through the
    /// translucent surface, most visibly wherever the row's own content is
    /// sparse (e.g. the mostly-empty checkbox circle). Fading the button's
    /// own opacity to 0 when closed avoids depending on the row above it
    /// being opaque at all.
    private var revealProgress: CGFloat {
        min(1, max(0, currentOffset / openOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button revealed behind the row when swiped left.
            Button {
                withAnimation(Constants.springAnimation) { settledOffset = 0 }
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(width: deleteButtonWidth)
                .frame(maxHeight: .infinity)
            }
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(revealProgress)
            .allowsHitTesting(settledOffset != 0)

            rowContent
                .offset(x: currentOffset)
                // A live drag should track the finger 1:1 with no spring lag
                // (that's what makes a swipe feel direct); the settle at the
                // end is what actually gets the spring animation, applied
                // around the `settledOffset` assignment in `onEnded` below.
                .animation(nil, value: dragTranslation)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            // Finger lifted mid-drag — decide whether to snap
                            // the rest of the way open or closed based on
                            // which side of the halfway point it stopped on,
                            // the same "did you drag past the midpoint"
                            // threshold iOS's own swipe actions use.
                            let projected = settledOffset + value.translation.width
                            let shouldOpen = projected < openOffset / 2
                            withAnimation(Constants.springAnimation) {
                                settledOffset = shouldOpen ? openOffset : 0
                            }
                        }
                )
                .onTapGesture {
                    // A tap anywhere on an already-open row closes it, so the
                    // checkbox/title underneath doesn't fire an unrelated
                    // action (completing the task) as the "close" gesture.
                    if settledOffset != 0 {
                        withAnimation(Constants.springAnimation) { settledOffset = 0 }
                    }
                }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(category.color)
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
                            task.completed ? category.color : Color.white.opacity(0.2),
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(
                                task.completed
                                    ? category.color
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
        .phoenixGlass(cornerRadius: 14)
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
