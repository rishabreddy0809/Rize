import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var showPaywall = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ZStack {
            PhoenixBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    ProStatusCard(profile: profile, showPaywall: $showPaywall)
                    phoenixStatsCard
                    settingsCard
                    #if DEBUG
                    DebugProToggle()
                    DebugLowEnergyOverlayTrigger()
                    DebugResetButton(profile: profile)
                    DebugTierSelector(profile: profile)
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(KingdomDesign.tierInfo(for: xpManager.totalXP).color.opacity(0.2))
                    .frame(width: 56, height: 56)
                Text(String(profile?.name.prefix(1) ?? "?").uppercased())
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.name ?? "Commander")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(PhoenixPalette.textPrimary)
                Text(KingdomDesign.tierInfo(for: xpManager.totalXP).name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(KingdomDesign.tierInfo(for: xpManager.totalXP).color)
            }
            Spacer()
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    // MARK: - Phoenix Stats

    private var phoenixStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PHOENIX STATS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCell("Total XP", value: "\(xpManager.totalXP)")
                statCell("Total Tasks", value: "\(profile?.entries.reduce(0) { $0 + $1.tasksCompleted } ?? 0)")
                statCell("Best Streak", value: "\(profile?.bestStreak ?? 0)d")
                statCell("Gold Earned", value: "\(xpManager.gold)")
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func statCell(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundColor(PhoenixPalette.textPrimary)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            if let profile = profile {
                // Notification time
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 24)
                    Text("Daily Reminder")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { profile.notificationTime },
                            set: { newTime in
                                profile.notificationTime = newTime
                                try? modelContext.save()
                                NotificationManager.shared.scheduleAll(profile: profile)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(Constants.accentColor)
                }

                Divider().background(Color.white.opacity(0.07))

                // HealthKit toggle
                settingToggle(
                    icon: "heart.fill",
                    color: .red,
                    label: "Apple Health Sync",
                    isOn: Binding(
                        get: { profile.healthKitEnabled },
                        set: { val in
                            profile.healthKitEnabled = val
                            if val {
                                Task { await HealthKitManager.shared.requestAuthorization() }
                            }
                            try? modelContext.save()
                        }
                    )
                )

                Divider().background(Color.white.opacity(0.07))

                // Calendar toggle
                settingToggle(
                    icon: "calendar",
                    color: Constants.accentColor,
                    label: "Calendar Sync",
                    isOn: Binding(
                        get: { profile.calendarEnabled },
                        set: { val in
                            profile.calendarEnabled = val
                            if val {
                                Task { await CalendarManager.shared.requestAuthorization() }
                            }
                            try? modelContext.save()
                        }
                    )
                )
            }
        }
        .padding(16)
        .kingdomGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func settingToggle(icon: String, color: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Constants.accentColor)
        }
    }
}

// MARK: - Pro Status Card

struct ProStatusCard: View {
    let profile: UserProfile?
    @Binding var showPaywall: Bool
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if subscriptionManager.isPro {
                HStack {
                    Text("PRO COMMANDER ✦")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.eternal)
                    Spacer()
                }

                if let start = profile?.proStartDate {
                    Text("Member since \(start.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                }

                Button("Manage Subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Constants.accentColor)
            } else {
                HStack {
                    Text("FREE COMMANDER")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Plans used this month")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 6)
                            let used = Double(profile?.monthlyPlansUsed ?? 0)
                            let limit = Double(Constants.freePlanLimitPerMonth)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(used >= limit ? PhoenixPalette.destructive : Constants.accentColor)
                                .frame(width: geo.size.width * min(1, used / limit), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(profile?.monthlyPlansUsed ?? 0) / \(Constants.freePlanLimitPerMonth) this month")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                }

                Button {
                    showPaywall = true
                } label: {
                    Text("UPGRADE PHOENIX")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PhoenixPalette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(
            subscriptionManager.isPro
                ? PhoenixPalette.eternal.opacity(0.06)
                : Color.white.opacity(0.03)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    subscriptionManager.isPro
                        ? PhoenixPalette.eternal.opacity(0.3)
                        : Color.white.opacity(0.07),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Debug Pro Toggle

#if DEBUG
struct DebugProToggle: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.6))
            HStack {
                Text("Pro Mode")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { subscriptionManager.isPro },
                    set: { val in subscriptionManager.isPro = val }
                ))
                .labelsHidden()
                .tint(.red)
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Debug Reset Button

struct DebugResetButton: View {
    let profile: UserProfile?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG — RESET")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.6))

            Button {
                showConfirmation = true
            } label: {
                Text("RESET EVERYTHING")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(
            "Reset all progress?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) { resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("XP, gold, streaks, entries, and achievements will be wiped and you'll return to onboarding.")
        }
    }

    private func resetEverything() {
        // Kingdom state (XP, gold, defense, tier index, siege)
        xpManager.resetAll()

        // Delete the profile entirely — entries and tasks cascade-delete.
        // Onboarding creates a fresh one.
        if let profile = profile {
            modelContext.delete(profile)
            try? modelContext.save()
        }

        // One-off flags stored outside the profile
        UserDefaults.standard.removeObject(forKey: "lowEnergyBonusShownDate")

        // Send the app back to onboarding
        hasCompletedOnboarding = false
    }
}

// MARK: - Debug Tier Selector

struct DebugTierSelector: View {
    let profile: UserProfile?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG — JUMP TO TIER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.6))

            HStack {
                Text("Set Tier")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Menu {
                    ForEach(Array(KingdomDesign.tiers.enumerated()), id: \.offset) { _, tier in
                        Button {
                            jumpToTier(minXP: tier.minXP)
                        } label: {
                            Text("\(tier.name) (\(tier.minXP) XP)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(KingdomDesign.tierInfo(for: xpManager.totalXP).name)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func jumpToTier(minXP: Int) {
        guard let profile = profile else { return }
        // Add the remaining XP needed to reach the selected tier's threshold.
        let remaining = minXP - profile.currentXP
        if remaining > 0 {
            profile.currentXP += remaining
        } else {
            profile.currentXP = minXP
        }
        try? modelContext.save()
        xpManager.syncTotalXP(profile.currentXP)
    }
}

// MARK: - Debug Low Energy Overlay Trigger

struct DebugLowEnergyOverlayTrigger: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG — PREVIEW")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.6))
            HStack {
                Text("Low Energy Celebration")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button("Show") {
                    NotificationCenter.default.post(name: .rizeDebugShowLowEnergyOverlay, object: nil)
                }
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(.red)
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif
