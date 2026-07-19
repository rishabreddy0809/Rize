import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var page = 0
    @State private var name = ""
    @State private var goal = "fitness"
    @State private var goalDetail = ""

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
            case 9: OnboardingPaywallView(onContinue: finishOnboarding, onTrial: {
                Task { await subscriptionManager.purchase(productID: SubscriptionManager.monthlyID) }
                finishOnboarding()
            })
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
                    .font(.system(size: 56, weight: .black, design: .rounded))
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
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
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
                ForEach(Array(KingdomDesign.tiers.enumerated()), id: \.offset) { index, tier in
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
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
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
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .font(.system(.title2, design: .monospaced))
                .foregroundColor(PhoenixPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
                .kingdomGlass(cornerRadius: 16)
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
                .font(.system(size: 26, weight: .bold, design: .monospaced))
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
                        .font(.system(.headline, design: .monospaced))
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

    private var goalDetailPage: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("Tell us more")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)

                Text("What's your specific goal?")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
            }

            TextField("e.g. make varsity tennis team", text: $goalDetail)
                .font(.system(.body, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary)
                .padding()
                .kingdomGlass(cornerRadius: 16)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                goldButton("Continue") { withAnimation(spring) { page = 6 } }
                Button("Skip") { withAnimation(spring) { page = 6 } }
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
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
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
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
                .font(.system(.headline, design: .monospaced))
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
            goalDetail: goalDetail
        )
        modelContext.insert(profile)
        try? modelContext.save()
        withAnimation(spring) {
            hasCompletedOnboarding = true
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
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .foregroundColor(Constants.energyColor(for: displayValue))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animatedValue = 8
            }
        }
    }
}

// MARK: - Onboarding Paywall

struct OnboardingPaywallView: View {
    let onContinue: () -> Void
    let onTrial: () -> Void
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            PhoenixTierVisual(tierIndex: 4, size: 160)

            VStack(spacing: 8) {
                Text("YOUR PHOENIX AWAITS")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Start your 7-day free trial")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach([
                    "Unlimited daily AI plans",
                    "Calendar intel for tests & deadlines",
                    "Weekly AI insights",
                    "Gold streak protection",
                    "Exclusive Pro phoenix glow"
                ], id: \.self) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .foregroundColor(PhoenixPalette.primary)
                            .font(.system(.footnote, weight: .bold))
                        Text(feature)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(PhoenixPalette.textPrimary.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onTrial) {
                    Text("START FREE TRIAL")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(PhoenixPalette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                }

                Button("Continue with Free", action: onContinue)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))

                Text("7-day free trial, then $4.99/month. Cancel anytime.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
