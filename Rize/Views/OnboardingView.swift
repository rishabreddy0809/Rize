import SwiftUI
import SwiftData
import UIKit

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var page = 0
    @State private var name = ""
    @State private var goal = "fitness"
    @State private var goalDetail = ""
    @State private var selectedGoalTags: Set<String> = []
    @State private var customGoalTags: [String] = []
    @State private var goalDetailInput = ""
    @State private var obReduceMotion = false
    @State private var obReduceTransparency = false
    @State private var obHighContrast = false
    /// Same `UserDefaults` key `MainTabView`/`ProfileView` use — a device
    /// preference, not part of the synced `UserProfile`, so it's read/written
    /// directly here rather than threaded through `finishOnboarding()`.
    @AppStorage("mascot_enabled") private var obMascotEnabled: Bool = true

    private let spring = Constants.springAnimation

    var body: some View {
        ZStack {
            PhoenixBackground()

            switch page {
            case 0: welcomePage
            case 1: energyConceptPage
            case 2: phoenixGrowthPage
            case 3: namePage
            case 4: goalPage
            case 5: goalDetailPage
            case 6: healthKitPage
            case 7: calendarPage
            case 8: notificationsPage
            case 9: accessibilityPage
            default: welcomePage
            }
        }
        .overlay(alignment: .bottomTrailing) {
            OnboardingPhoenixCompanion(message: companionMessage)
                .padding(.trailing, 12)
                .padding(.bottom, 118)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Phoenix Companion

    /// Perched idle mascot + speech bubble, present across every onboarding screen.
    private var companionMessage: String {
        switch page {
        case 0: return "Welcome. I've been waiting for you."
        case 1: return "Energy 1 to 10 — no wrong answer. Just be honest with me."
        case 2: return "Watch me grow with you. Ash to Eternal."
        case 3: return "What should I call you?"
        case 4: return "What are we building toward?"
        case 5: return "The more specific, the better I can help."
        case 6: return "This helps me build smarter plans for you."
        case 7: return "I'll help you stay ahead of what's coming."
        case 8: return "I'll remind you gently. Never spam."
        case 9: return "Set it up your way. I'll adapt."
        default: return "Ready when you are."
        }
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            PhoenixTierVisual(tierIndex: 4, size: 200)

            VStack(spacing: 12) {
                Text("Rize.")
                    .font(.phoenixHero(56))
                    .foregroundColor(PhoenixPalette.textPrimary)

                Text("Show up. Even on your worst days.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            goldButton("Begin") { withAnimation(spring) { page = 1 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Page 1: The Core Concept

    private var energyConceptPage: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("Your energy. Your plan.")
                    .font(.phoenixTitle(28))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Every morning, rate your energy from 1 to 10. We build your day around it. Low energy days earn more XP, because showing up when it's hard is the hardest thing.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 32)
            }

            EnergySliderPreview()
                .padding(.horizontal, 32)
                .padding(.top, 8)

            Spacer()

            goldButton("Got it") { withAnimation(spring) { page = 2 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Page 2: The Phoenix

    private var phoenixGrowthPage: some View {
        VStack(spacing: 28) {
            Spacer()

            HStack(spacing: 14) {
                ForEach(Array(PhoenixDesign.tiers.enumerated()), id: \.offset) { index, tier in
                    VStack(spacing: 6) {
                        PhoenixTierVisual(tierIndex: index, size: 44, decorated: false)
                        Text(tier.name)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(tier.color)
                    }
                }
            }

            VStack(spacing: 12) {
                Text("Your phoenix grows as you do.")
                    .font(.phoenixTitle(24))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Complete daily tasks to earn XP. Your phoenix evolves through 5 stages, from Ash to Eternal. Miss a day and it returns to ash. Come back and watch it rise again.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 32)
            }

            Spacer()

            goldButton("Let's go") { withAnimation(spring) { page = 3 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Page 3: Name

    private var namePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("What's your name?")
                .font(.phoenixTitle(28))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .font(.phoenixTitle(22))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
                .phoenixGlass(cornerRadius: 16)
                .padding(.horizontal, 32)

            Spacer()

            goldButton("Continue", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                withAnimation(spring) { page = 4 }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Page 4: Goal

    private var goalPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("What are you training for?")
                .font(.phoenixTitle(26))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 14) {
                goalCard("FITNESS", subtitle: "Running, gym, sports", value: "fitness", icon: "figure.run")
                goalCard("PRODUCTIVITY", subtitle: "Studying, work, habits", value: "productivity", icon: "brain.head.profile")
                goalCard("BOTH", subtitle: "The full flame", value: "both", icon: "sparkles")
            }
            .padding(.horizontal, 24)

            Spacer()

            goldButton("Continue") { withAnimation(spring) { page = 5 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func goalCard(_ label: String, subtitle: String, value: String, icon: String) -> some View {
        Button {
            withAnimation(spring) { goal = value }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(goal == value ? PhoenixPalette.primary : PhoenixPalette.textSecondary.opacity(0.6))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.phoenixHeadline())
                        .foregroundColor(PhoenixPalette.textPrimary)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                }
                Spacer()

                if goal == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PhoenixPalette.success)
                }
            }
            .padding(16)
            .background(goal == value ? PhoenixPalette.success.opacity(0.08) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(goal == value ? PhoenixPalette.success.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Page 5: Goal Detail

    /// Preset quick-pick suggestions, tailored to the selected goal. Anything the
    /// user types into the text box is appended here as an extra chip via `customGoalTags`,
    /// so the two inputs (tap vs. type) both just produce more selectable options.
    /// Skip the HealthKit permission page for a purely "productivity" goal —
    /// only fitness/both goals actually use health data for planning, so
    /// asking everyone for it made Health permission requests feel random.
    private var pageAfterGoalDetail: Int {
        (goal == "fitness" || goal == "both") ? 6 : 7
    }

    private var goalDetailPresets: [String] {
        switch goal {
        case "fitness":
            return ["Running", "Gym & Strength", "Sports", "Cycling", "Swimming", "Yoga & Flexibility"]
        case "productivity":
            return ["Coding", "Studying", "Reading", "Writing", "Work Habits", "Deep Focus"]
        default:
            return ["Running", "Sports", "Coding", "Studying", "Gym & Strength", "Work Habits"]
        }
    }

    private var allGoalDetailOptions: [String] {
        goalDetailPresets + customGoalTags.filter { !goalDetailPresets.contains($0) }
    }

    private func addCustomGoalTag() {
        let trimmed = goalDetailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goalDetailInput = ""
        withAnimation(spring) {
            if !allGoalDetailOptions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                customGoalTags.append(trimmed)
            }
            selectedGoalTags.insert(trimmed)
        }
    }

    /// Every selected option, in display order, joined for `goalDetail` — this is
    /// what's stored on the profile and sent to Foundation Models for planning.
    private func syncGoalDetail() {
        goalDetail = allGoalDetailOptions.filter(selectedGoalTags.contains).joined(separator: ", ")
    }

    private var goalDetailPage: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(spacing: 8) {
                        Text("Tell us more")
                            .font(.phoenixTitle(28))
                            .foregroundColor(PhoenixPalette.textPrimary)

                        Text("Pick as many as apply — or add your own")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(PhoenixPalette.textSecondary)
                    }

                    OnboardingFlowLayout(spacing: 10) {
                        ForEach(allGoalDetailOptions, id: \.self) { option in
                            goalDetailChip(option)
                        }
                    }
                    .padding(.horizontal, 32)

                    TextField("Type your goal", text: $goalDetailInput)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(PhoenixPalette.textPrimary)
                        .padding()
                        .phoenixGlass(cornerRadius: 16)
                        .submitLabel(.done)
                        .onSubmit { addCustomGoalTag() }
                        .padding(.horizontal, 32)

                    Spacer(minLength: 24)
                }
            }

            VStack(spacing: 12) {
                goldButton("Continue") { withAnimation(spring) { page = pageAfterGoalDetail } }
                Button("Skip") { withAnimation(spring) { page = pageAfterGoalDetail } }
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .onChange(of: selectedGoalTags) { _, _ in syncGoalDetail() }
        .onChange(of: customGoalTags) { _, _ in syncGoalDetail() }
    }

    @ViewBuilder
    private func goalDetailChip(_ label: String) -> some View {
        let isSelected = selectedGoalTags.contains(label)
        Button {
            withAnimation(spring) {
                if isSelected {
                    selectedGoalTags.remove(label)
                } else {
                    selectedGoalTags.insert(label)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(label)
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(isSelected ? PhoenixPalette.textPrimary : PhoenixPalette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? PhoenixPalette.success.opacity(0.18) : Color.white.opacity(0.03))
            .overlay(
                Capsule()
                    .stroke(isSelected ? PhoenixPalette.success.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Page 6: HealthKit

    private var healthKitPage: some View {
        permissionPage(
            icon: "heart.fill",
            iconColor: .red,
            title: "Connect Apple Health",
            description: "Rize uses your sleep, heart rate, and activity data to build smarter daily plans tailored exactly to your recovery state.",
            connectLabel: "CONNECT HEALTH",
            onConnect: {
                Task {
                    await HealthKitManager.shared.requestAuthorization()
                    withAnimation(spring) { page = 7 }
                }
            },
            onSkip: { withAnimation(spring) { page = 7 } }
        )
    }

    // MARK: - Page 7: Calendar

    private var calendarPage: some View {
        permissionPage(
            icon: "calendar",
            iconColor: Color(hex: "0A84FF"),
            title: "Connect Calendar",
            description: "Rize reads upcoming tests and deadlines so your daily plan accounts for what's coming — no surprises.",
            connectLabel: "CONNECT CALENDAR",
            onConnect: {
                Task {
                    await CalendarManager.shared.requestAuthorization()
                    withAnimation(spring) { page = 8 }
                }
            },
            onSkip: { withAnimation(spring) { page = 8 } }
        )
    }

    // MARK: - Page 8: Notifications

    private var notificationsPage: some View {
        permissionPage(
            icon: "bell.fill",
            iconColor: .yellow,
            title: "Never miss a day",
            description: "Daily reminders keep your streak alive. Rize sends smart nudges based on your energy patterns — never generic spam.",
            connectLabel: "ENABLE NOTIFICATIONS",
            onConnect: {
                Task {
                    await NotificationManager.shared.requestPermission()
                    withAnimation(spring) { page = 9 }
                }
            },
            onSkip: { withAnimation(spring) { page = 9 } }
        )
    }

    // MARK: - Page 9: Accessibility

    /// iOS has no public API for an app to toggle system VoiceOver — that
    /// switch is deliberately OS-only, for the same reason no app can flip
    /// on its own camera permission. What this page offers instead: the
    /// parts of Rize's presentation the app itself controls (its own
    /// animations, translucent cards, and text contrast), set once here and
    /// changeable later from Profile → Accessibility, plus a direct link to
    /// the system Settings that actually own VoiceOver / Larger Text / Bold
    /// Text.
    private var accessibilityPage: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    ZStack {
                        Circle()
                            .fill(Constants.accentColor.opacity(0.12))
                            .frame(width: 120, height: 120)
                        Image(systemName: "accessibility")
                            .font(.system(size: 48))
                            .foregroundColor(Constants.accentColor)
                    }

                    VStack(spacing: 12) {
                        Text("Make it yours")
                            .font(.phoenixTitle(26))
                            .foregroundColor(PhoenixPalette.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Rize supports VoiceOver, Dynamic Type, and Bold Text out of the box — those live in iOS Settings. These three are Rize's own, and you can change them anytime from your profile.")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(PhoenixPalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 14) {
                        accessibilityToggleRow(
                            icon: "figure.walk.motion",
                            label: "Reduce Motion",
                            subtitle: "Pause phoenix animations & particle effects",
                            isOn: $obReduceMotion
                        )
                        accessibilityToggleRow(
                            icon: "circle.lefthalf.filled",
                            label: "Reduce Transparency",
                            subtitle: "Solid cards instead of translucent ones",
                            isOn: $obReduceTransparency
                        )
                        accessibilityToggleRow(
                            icon: "circle.righthalf.filled",
                            label: "High Contrast Text",
                            subtitle: "Bolder, more legible text throughout",
                            isOn: $obHighContrast
                        )
                        accessibilityToggleRow(
                            icon: "bird.fill",
                            label: "Floating Mascot",
                            subtitle: "A small draggable phoenix that grows with your tier",
                            isOn: $obMascotEnabled
                        )
                    }
                    .padding(.horizontal, 24)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                            Text("Open iOS Accessibility Settings")
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Constants.accentColor)
                    }
                    .accessibilityHint("Opens Settings for VoiceOver, Larger Text, and Bold Text")

                    Spacer(minLength: 24)
                }
            }

            goldButton("Finish") { finishOnboarding() }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func accessibilityToggleRow(icon: String, label: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Constants.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.phoenixHeadline())
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .accessibilityHidden(true)
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Constants.accentColor)
                .accessibilityLabel(label)
                .accessibilityHint(subtitle)
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func permissionPage(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        connectLabel: String,
        onConnect: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.phoenixTitle(26))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                goldButton(connectLabel, action: onConnect)
                Button("Skip", action: onSkip)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func goldButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.phoenixHeadline())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(disabled ? Color.gray.opacity(0.35) : PhoenixPalette.primary)
                .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
        }
        .disabled(disabled)
    }

    // MARK: - Finish

    private func finishOnboarding() {
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            goal: goal,
            goalDetail: goalDetail,
            accessibilityReduceMotion: obReduceMotion,
            accessibilityReduceTransparency: obReduceTransparency,
            accessibilityHighContrast: obHighContrast
        )
        profile.hasCompletedOnboarding = true
        withAnimation(spring) {
            modelContext.insert(profile)
            try? modelContext.save()
        }
    }
}

// MARK: - Phoenix Companion (perched mascot + speech bubble)

private struct OnboardingPhoenixCompanion: View {
    let message: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .frame(maxWidth: 168, alignment: .leading)
                .background(SpeechBubbleShape().fill(PhoenixPalette.surface))
                .overlay(SpeechBubbleShape().stroke(PhoenixPalette.surfaceBorder, lineWidth: 1))
                .id(message)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))

            PhoenixPerchedView()
                .frame(width: 168, height: 168)
                .offset(y: -4)
        }
        .animation(Constants.springAnimation, value: message)
    }
}

/// Rounded rectangle with a small tail pointing down toward the phoenix.
private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 12
    var tailSize: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailSize)
        var path = Path(roundedRect: bubbleRect, cornerRadius: cornerRadius)
        let tailStartX = bubbleRect.maxX - cornerRadius - tailSize * 2
        path.move(to: CGPoint(x: tailStartX, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: tailStartX + tailSize, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailStartX + tailSize * 2, y: bubbleRect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Energy Slider Preview (non-interactive)

private struct EnergySliderPreview: View {
    @State private var animatedValue: Double = 3

    private var displayValue: Int {
        Int(animatedValue.rounded())
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Constants.energyColor(for: displayValue))
                        .frame(width: max(10, geo.size.width * CGFloat((animatedValue - 1) / 9)), height: 10)
                    Circle()
                        .fill(Constants.energyColor(for: displayValue))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(PhoenixPalette.textPrimary.opacity(0.4), lineWidth: 2))
                        .offset(x: geo.size.width * CGFloat((animatedValue - 1) / 9) - 11)
                }
                .frame(height: 22)
            }
            .frame(height: 22)

            Text("\(displayValue)")
                .font(.phoenixHeadline())
                .foregroundColor(Constants.energyColor(for: displayValue))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animatedValue = 8
            }
        }
    }
}

// MARK: - Wrapping chip layout

/// Wraps chip-style subviews left-to-right, moving to a new row when they'd overflow.
/// Also reused by `EditProfileView` for the same goal-tag chip picker.
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
