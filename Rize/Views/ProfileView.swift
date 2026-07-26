import SwiftUI
import SwiftData
import UIKit

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var xpManager: XPManager
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var showEditProfile = false
    @State private var showResetConfirmation = false

    /// Same key `MainTabView` reads to decide whether to show `MascotOverlay`
    /// at all, and the same key the onboarding accessibility page's toggle
    /// writes to — one shared `UserDefaults` key, no extra plumbing needed.
    @AppStorage("mascot_enabled") private var mascotEnabled: Bool = true

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ZStack {
            PhoenixBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    phoenixStatsCard
                    settingsCard
                    accessibilityCard
                    #if DEBUG
                    debugTierCard
                    #endif
                    resetCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile {
                EditProfileView(profile: profile)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PhoenixDesign.tierInfo(for: xpManager.totalXP).color.opacity(0.2))
                    .frame(width: 56, height: 56)
                Text(String(profile?.name.prefix(1) ?? "?").uppercased())
                    .font(.phoenixHero(24))
                    .foregroundColor(PhoenixPalette.textPrimary)
            }
            // The avatar letter is a decorative echo of the name text right
            // next to it — without this, VoiceOver would announce the name
            // twice in a row (once for the letter, once for the full name).
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.name ?? "Commander")
                    .font(.phoenixTitle(20))
                    .foregroundColor(PhoenixPalette.textPrimary)
                Text(PhoenixDesign.tierInfo(for: xpManager.totalXP).name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PhoenixDesign.tierInfo(for: xpManager.totalXP).color)
            }
            // `.combine` merges the name + tier into one VoiceOver stop
            // ("Commander, Ash") instead of two separate swipe targets.
            .accessibilityElement(children: .combine)
            Spacer()

            Button {
                showEditProfile = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            }
            .disabled(profile == nil)
            .accessibilityLabel("Edit profile")
            .accessibilityHint("Opens name and goal settings")
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    // MARK: - Phoenix Stats

    private var phoenixStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PHOENIX STATS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCell("Total XP", value: "\(xpManager.totalXP)")
                statCell("Total Tasks", value: "\(profile?.entries.reduce(0) { $0 + $1.tasksCompleted } ?? 0)")
                statCell("Best Streak", value: "\(profile?.bestStreak ?? 0)d")
                statCell("Best Week", value: "\(profile?.bestTasksCompletedInWeek ?? 0) tasks")
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func statCell(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.phoenixTitle(20))
                .foregroundColor(PhoenixPalette.textPrimary)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // The value renders above the label visually, so `.combine` (which
        // reads top-to-bottom) would announce "142, Total XP" — backwards.
        // Overriding with an explicit label puts it in reading order instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            if let profile = profile {
                // Notification time
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 24)
                        .accessibilityHidden(true)
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
                    .accessibilityLabel("Daily reminder time")
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

                Divider().background(Color.white.opacity(0.07))
            }

            // Floating mascot toggle
            settingToggle(
                icon: "bird.fill",
                color: Constants.accentColor,
                label: "Floating Mascot",
                isOn: $mascotEnabled
            )
            .accessibilityHint("Shows a small draggable phoenix that grows with your tier and offers encouragement when tapped")
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func settingToggle(icon: String, color: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            // Visible label stays on screen for sighted users but is dropped
            // from the accessibility tree — the Toggle below carries the same
            // text as its own accessibility label, so keeping both would have
            // VoiceOver announce "Apple Health Sync, Apple Health Sync, On".
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Constants.accentColor)
                .accessibilityLabel(label)
        }
    }

    // MARK: - Accessibility

    /// iOS doesn't expose a public API for an app to flip system VoiceOver
    /// on/off — that's an OS-level toggle for privacy/security reasons (any
    /// app silently enabling an assistive service on your behalf would be a
    /// serious vulnerability). What this card offers instead: real switches
    /// for the parts of Rize's presentation this app *does* control — its
    /// own decorative animations, translucent surfaces, and contrast — plus
    /// a direct link to iOS Settings for VoiceOver, Larger Text, and the
    /// rest of the system-wide accessibility features.
    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACCESSIBILITY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            if let profile = profile {
                settingToggle(
                    icon: "figure.walk.motion",
                    color: Constants.accentColor,
                    label: "Reduce Motion",
                    isOn: Binding(
                        get: { profile.accessibilityReduceMotion },
                        set: { val in
                            profile.accessibilityReduceMotion = val
                            try? modelContext.save()
                        }
                    )
                )
                .accessibilityHint("Pauses the phoenix animations and particle effects throughout the app")

                Divider().background(Color.white.opacity(0.07))

                settingToggle(
                    icon: "circle.lefthalf.filled",
                    color: Constants.accentColor,
                    label: "Reduce Transparency",
                    isOn: Binding(
                        get: { profile.accessibilityReduceTransparency },
                        set: { val in
                            profile.accessibilityReduceTransparency = val
                            try? modelContext.save()
                        }
                    )
                )
                .accessibilityHint("Replaces translucent cards with solid backgrounds")

                Divider().background(Color.white.opacity(0.07))

                settingToggle(
                    icon: "circle.righthalf.filled",
                    color: Constants.accentColor,
                    label: "High Contrast Text",
                    isOn: Binding(
                        get: { profile.accessibilityHighContrast },
                        set: { val in
                            profile.accessibilityHighContrast = val
                            try? modelContext.save()
                        }
                    )
                )
                .accessibilityHint("Increases text contrast throughout the app")

                Divider().background(Color.white.opacity(0.07))
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(PhoenixPalette.textSecondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("VoiceOver, Larger Text & More")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Open Settings")
            .accessibilityHint("VoiceOver, Larger Text, Bold Text, and other system accessibility features live in iOS Settings, under Accessibility")
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    // MARK: - Debug

    #if DEBUG
    /// Debug-only — lets QA jump straight to any tier (mascot, phoenix
    /// visuals, tier-locked copy, etc.) without grinding XP. Stripped from
    /// release builds entirely by the `#if DEBUG`, not just hidden.
    private var debugTierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEBUG")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            Menu {
                ForEach(Array(PhoenixDesign.tiers.enumerated()), id: \.offset) { index, tier in
                    Button {
                        xpManager.setDebugTier(index: index)
                    } label: {
                        Label(tier.name.capitalized, systemImage: index == PhoenixDesign.tierInfo(for: xpManager.totalXP).index ? "checkmark" : "")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(PhoenixDesign.tierInfo(for: xpManager.totalXP).color)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Jump to Tier")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                    Spacer()
                    Text(PhoenixDesign.tierInfo(for: xpManager.totalXP).name.capitalized)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundColor(PhoenixPalette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
                }
            }
            .accessibilityLabel("Jump to tier, currently \(PhoenixDesign.tierInfo(for: xpManager.totalXP).name)")
            .accessibilityHint("Sets your XP to test any tier's visuals without playing through it")
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }
    #endif

    // MARK: - Reset

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RESET")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            Button {
                showResetConfirmation = true
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
            .accessibilityHint("Deletes XP, streaks, entries, and achievements, then returns to onboarding. This can't be undone.")
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
        .confirmationDialog(
            "Reset all progress?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) { resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("XP, streaks, entries, and achievements will be wiped and you'll return to onboarding. This can't be undone.")
        }
    }

    private func resetEverything() {
        // Phoenix state (XP, defense, tier index, siege)
        xpManager.resetAll()

        // Delete the profile entirely — entries and tasks cascade-delete.
        // Onboarding creates a fresh one.
        if let profile {
            modelContext.delete(profile)
            try? modelContext.save()
        }

        // One-off flags stored outside the profile
        UserDefaults.standard.removeObject(forKey: "lowEnergyBonusShownDate")

        // No profile left with `hasCompletedOnboarding == true` — `RootView`
        // (RizeApp.swift) routes back to onboarding automatically.
    }
}
