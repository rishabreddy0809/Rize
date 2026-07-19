import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var selectedPlan = SubscriptionManager.yearlyID
    @State private var isPurchasing = false

    private let features = [
        "Unlimited daily AI plans",
        "Calendar intel for tests & deadlines",
        "Weekly AI insights",
        "No ads, ever",
        "Gold streak protection",
        "Priority AI responses",
        "Exclusive Pro phoenix glow"
    ]

    var body: some View {
        ZStack {
            PhoenixBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Dismiss button
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(10)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Hero
                    PhoenixTierVisual(tierIndex: 4, size: 140)
                        .modifier(FloatingModifier())

                    VStack(spacing: 6) {
                        Text("UPGRADE YOUR PHOENIX")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(PhoenixPalette.textPrimary)
                            .multilineTextAlignment(.center)
                    }

                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(features, id: \.self) { feature in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(.footnote, weight: .bold))
                                    .foregroundColor(PhoenixPalette.primary)
                                    .frame(width: 16)
                                Text(feature)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundColor(PhoenixPalette.textPrimary.opacity(0.85))
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    // Plan selector
                    VStack(spacing: 10) {
                        planCard(
                            id: SubscriptionManager.yearlyID,
                            name: "Yearly",
                            price: "$29.99 / year",
                            badge: "SAVE 50%",
                            badgeColor: PhoenixPalette.success
                        )
                        planCard(
                            id: SubscriptionManager.monthlyID,
                            name: "Monthly",
                            price: "$4.99 / month",
                            badge: nil,
                            badgeColor: .clear
                        )
                    }
                    .padding(.horizontal, 20)

                    // CTA
                    VStack(spacing: 12) {
                        Text("7-day free trial — cancel anytime")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(PhoenixPalette.textSecondary)

                        Button {
                            purchase()
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("START FREE TRIAL")
                                        .font(.system(.headline, design: .monospaced))
                                        .foregroundColor(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(PhoenixPalette.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                        }
                        .disabled(isPurchasing)

                        Button("Restore Purchases") {
                            Task { await subscriptionManager.restorePurchases() }
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))

                        Text("By continuing, you agree to our Terms of Service. Subscriptions auto-renew unless cancelled.")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(PhoenixPalette.textSecondary.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            Task { await subscriptionManager.loadProducts() }
        }
        .onChange(of: subscriptionManager.isPro) { _, newValue in
            if newValue { dismiss() }
        }
    }

    @ViewBuilder
    private func planCard(
        id: String,
        name: String,
        price: String,
        badge: String?,
        badgeColor: Color
    ) -> some View {
        let isSelected = selectedPlan == id
        Button {
            withAnimation(Constants.springAnimation) { selectedPlan = id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundColor(PhoenixPalette.textPrimary)
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(badgeColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text(price)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? PhoenixPalette.primary : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(PhoenixPalette.primary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(
                isSelected
                    ? PhoenixPalette.primary.opacity(0.07)
                    : Color.white.opacity(0.03)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? PhoenixPalette.primary.opacity(0.5) : Color.white.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func purchase() {
        isPurchasing = true
        Task {
            await subscriptionManager.purchase(productID: selectedPlan)
            isPurchasing = false
        }
    }
}

// MARK: - Plan Limit Card (shown in TodayView)

struct PlanLimitReachedCard: View {
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.circle.fill")
                .font(.largeTitle)
                .foregroundColor(PhoenixPalette.primary)

            VStack(spacing: 4) {
                Text("PLAN LIMIT REACHED")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textPrimary)
                Text("You've used all 5 free plans this month.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPaywall = true
            } label: {
                Text("UPGRADE FOR UNLIMITED")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PhoenixPalette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .kingdomGlass(cornerRadius: 16)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
