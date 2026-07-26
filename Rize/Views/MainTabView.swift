import SwiftUI
import SwiftData

enum RizeTab: String, CaseIterable, MorphingTabProtocol {
    case today
    case progress
    case kingdom
    case health
    case profile

    var symbolImage: String {
        switch self {
        case .today: return "bolt.fill"
        case .progress: return "chart.bar.fill"
        case .kingdom: return "flame.fill"
        // Apple Watch's Workout app icon — a running figure, not a heart —
        // since this tab is about activity/workouts, not just vitals.
        case .health: return "figure.run.circle.fill"
        case .profile: return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .progress: return "Progress"
        case .kingdom: return "Phoenix"
        case .health: return "Health"
        case .profile: return "Profile"
        }
    }
}

// A custom `EnvironmentKey` is how you add your *own* value to SwiftUI's
// environment, the same mechanism `\.widgetFamily` or `\.modelContext` use —
// it's not limited to Apple's built-in keys. `RizeTabKey` piggybacks the
// selected-tab `Binding` (set once, below, via `.environment(\.selectedTab,
// $selected)`) onto that same mechanism, so any view anywhere further down
// the tree — no matter how deeply nested inside `TodayView`, `ProfileView`,
// etc. — can read `@Environment(\.selectedTab)` and both see and *change*
// which tab is active, without `MainTabView` having to pass that binding
// down explicitly through every intermediate view's initializer.
struct RizeTabKey: EnvironmentKey {
    static let defaultValue: Binding<RizeTab> = .constant(.today)
}

extension EnvironmentValues {
    var selectedTab: Binding<RizeTab> {
        get { self[RizeTabKey.self] }
        set { self[RizeTabKey.self] = newValue }
    }
}

/// The app's root screen after onboarding. Notably, this is NOT built on
/// SwiftUI's built-in `TabView` — the floating, morphing pill-shaped tab bar
/// (`MorphingTabBar`, in `Helpers/MorphingTabBar.swift`) is a fully custom
/// control, so tab *content* here is just a plain `switch` over `selected`
/// inside a `ZStack`, with the custom bar floating on top as its own
/// separately-positioned layer — `TabView` bundles its own fixed-style tab
/// bar with no comparable way to swap in a custom one.
struct MainTabView: View {
    // `@EnvironmentObject`, unlike `@StateObject` (used for these same
    // managers over in `RizeApp.swift`), doesn't create or own the object —
    // it looks one up from the environment that an ancestor view already
    // injected via `.environmentObject(...)`. `RizeApp` is that ancestor
    // here; if this view were shown without going through `RizeApp`'s setup
    // (e.g. in an isolated preview with no injected object), it would crash
    // at runtime, since there'd be nothing of the right type to find.
    @EnvironmentObject private var xpManager: XPManager
    // `@Query` is SwiftData's live-fetch property wrapper — declaring it
    // this way (no explicit predicate/sort) fetches every `UserProfile` row
    // and, unlike a one-time fetch, keeps `profiles` automatically in sync
    // as the underlying data changes for as long as this view exists.
    @Query private var profiles: [UserProfile]
    @State private var selected: RizeTab = .today
    @State private var isTabBarExpanded: Bool = false
    @State private var showAddTaskSheet = false
    @ObservedObject private var celebrationCenter = CelebrationCenter.shared
    /// Toggled from Profile → Settings, or set during onboarding.
    @AppStorage("mascot_enabled") private var mascotEnabled: Bool = true

    private var tierInfo: PhoenixDesign.TierInfo {
        PhoenixDesign.tierInfo(for: xpManager.totalXP)
    }

    private var tierColor: Color { tierInfo.color }

    private var mascotContext: MascotContext {
        let profile = profiles.first
        let snapshot = HealthKitManager.shared.snapshot
        return MascotContext(
            name: profile?.name ?? "",
            tierName: tierInfo.name,
            streak: profile?.currentStreak ?? 0,
            realmDefensePercent: xpManager.realmDefense,
            isUnderSiege: xpManager.isUnderSiege,
            sleepHours: snapshot.sleep?.hours,
            lastWorkoutType: snapshot.recentWorkouts.first?.type
        )
    }

    /// Health only matters to people training for something — hide it for a
    /// purely "productivity" goal instead of showing an empty-feeling tab.
    private var visibleTabs: [RizeTab] {
        let goal = profiles.first?.goal ?? "both"
        guard goal != "fitness" && goal != "both" else { return RizeTab.allCases }
        return RizeTab.allCases.filter { $0 != .health }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed base gradient so the reddish → black background always
            // reaches the very bottom of the screen, including behind the
            // floating tab bar (the per-screen background is inset by the
            // content padding below and would otherwise leave a cutoff strip).
            PhoenixBackground()

            // Content
            Group {
                switch selected {
                case .today:    TodayView()
                case .progress: RizeProgressScreen()
                case .kingdom:  PhoenixView()
                case .health:   HealthTabView()
                case .profile:  ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A `.safeAreaInset` (not `.padding`) so scrollable content still
            // clears the floating tab bar, but full-screen overlays nested inside
            // (achievement/celebration views, which call `.ignoresSafeArea()`)
            // can still paint all the way to the true screen bottom instead of
            // being boxed in by a fixed padding no child can escape.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 96)
            }

            // Floating Tab Bar + quick-add button
            HStack(spacing: 12) {
                MorphingTabBar(activeTab: $selected, isExpanded: $isTabBarExpanded, tabs: visibleTabs) {}
                addTaskButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Draggable tier mascot — persists across tab switches since it
            // lives in this root ZStack, not inside any one tab's content.
            if mascotEnabled {
                MascotOverlay(tierIndex: tierInfo.index, context: mascotContext)
                    .zIndex(15)
            }

            // Celebrations — presented above the tab bar (not nested inside a
            // tab's own content) so the overlay truly covers the whole screen,
            // tab bar included, instead of being clipped by that tab's layout
            // and painted underneath the floating tab bar's z-order.
            if let celebration = celebrationCenter.active {
                celebrationView(for: celebration)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .environment(\.selectedTab, $selected)
        .onReceive(NotificationCenter.default.publisher(for: .rizeOpenEnergyPicker)) { _ in
            withAnimation(Constants.springAnimation) { selected = .today }
        }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet { request in
                NotificationCenter.default.post(name: .rizeAddCustomTask, object: request)
            }
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

    // MARK: - Quick Add

    private var addTaskButton: some View {
        Button {
            showAddTaskSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PhoenixPalette.textPrimary)
                .frame(width: 52, height: 52)
        }
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.interactive(), in: Circle())
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            }
        }
        .accessibilityLabel("Add task")
    }

    // MARK: - Celebrations

    @ViewBuilder
    private func celebrationView(for celebration: DayCelebration) -> some View {
        switch celebration {
        case .allDone(let xp, let streak):
            DayCompleteCelebrationView(xp: xp, streak: streak, tierIndex: tierInfo.index, onDismiss: celebrationCenter.dismissActive)
        case .lowEnergy(let xp):
            LowEnergyCelebrationView(xp: xp, onDismiss: celebrationCenter.dismissActive)
        case .achievement(let achievement):
            AchievementUnlockedView(
                achievement: achievement,
                onDismiss: celebrationCenter.dismissActive,
                streak: profiles.first?.currentStreak ?? 0
            )
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
