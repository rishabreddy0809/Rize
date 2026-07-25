import SwiftUI

/// A dramatic, Duolingo-style full-screen celebration shown when an achievement
/// unlocks. A phoenix rises from the bonfire behind rotating golden rays, a gold
/// medallion stamps the achievement icon, and the title arrives on a spring.
/// Dismisses on tap, on the CONTINUE button, or via the manager's safety timer.
struct AchievementUnlockedView: View {
    let achievement: AchievementDefinition
    let onDismiss: () -> Void

    // Palette shorthands — the app's gold family.
    private let gold = PhoenixPalette.eternal      // #FFD700
    private let amber = PhoenixPalette.primary     // #F5A623
    private let radiant = PhoenixPalette.radiant   // #FFB830

    @State private var appeared = false
    @State private var rayRotation: Double = 0
    @State private var glowPulse = false
    @State private var phoenixRise = false
    @State private var badgeStamped = false
    @Environment(\.rizeReduceMotion) private var reduceMotion

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [gold, radiant, amber],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Fully opaque backdrop — tap anywhere to dismiss. Was translucent
            // black before, which let whatever was scrolled underneath (task
            // text, other cards) show clearly through the celebration.
            PhoenixBackground(intensified: true)
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                // Hero — the phoenix, its medallion, and every bit of
                // celebratory light (rays, glow, embers) live inside this fixed
                // box, centered on the bird. Containing them here is what stops
                // the rays and particles from stretching across the whole screen
                // and washing over the title — the "stretched / glitchy" look.
                heroSection

                // Eyebrow + title + description.
                textBlock
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .padding(.top, 24)

                Spacer(minLength: 24)

                Button(action: dismiss) {
                    Text("CONTINUE")
                        .font(.phoenixHeadline())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                        .shadow(color: gold.opacity(0.4), radius: 16, y: 6)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 44)
                .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: animateIn)
    }

    // MARK: - Pieces

    /// The phoenix + medallion and all their light, boxed to a fixed size and
    /// centered on the bird so nothing bleeds out into the title or the screen
    /// edges. The rays fade to clear (via their radial mask) and the ember
    /// burst is frame-clamped, both well inside this box.
    private var heroSection: some View {
        ZStack {
            // Rotating golden rays — a halo behind the hero.
            rays
                .opacity(appeared ? 0.5 : 0)

            // Soft radial glow that breathes.
            RadialGradient(
                colors: [gold.opacity(glowPulse ? 0.30 : 0.15), .clear],
                center: .center, startRadius: 10, endRadius: 190
            )
            .allowsHitTesting(false)

            // Gold ember burst, anchored to the hero box (not the full screen)
            // so embers spray around the phoenix instead of over everything.
            if appeared {
                ParticleEmitterView(type: .goldBurst)
                    .frame(width: 320, height: 320)
                    .allowsHitTesting(false)
            }

            // Rising phoenix above, medallion stamped at its base below.
            ZStack {
                PhoenixSpriteView()
                    .frame(width: 240, height: 240)
                    .offset(y: phoenixRise ? -40 : 20)
                    .opacity(phoenixRise ? 1 : 0)

                medallion
                    .offset(y: 56)
                    .scaleEffect(badgeStamped ? 1 : 0.3)
                    .opacity(badgeStamped ? 1 : 0)
            }
        }
        .frame(width: 360, height: 340)
    }

    private var textBlock: some View {
        VStack(spacing: 10) {
            Text("ACHIEVEMENT UNLOCKED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(gold)

            Text(achievement.title)
                .font(.phoenixHero(30))
                .foregroundColor(gold)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 2)

            Text(achievement.description)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(PhoenixPalette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var rays: some View {
        AngularGradient(gradient: Gradient(stops: rayStops), center: .center)
            .frame(width: 440, height: 440)
        .mask(
            RadialGradient(colors: [.white, .white.opacity(0.2), .clear],
                           center: .center, startRadius: 30, endRadius: 165)
        )
        .rotationEffect(.degrees(rayRotation))
        .blur(radius: 1)
        .allowsHitTesting(false)
    }

    /// 12 evenly spaced spokes of light.
    private var rayStops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let spokes = 12
        for i in 0..<spokes {
            let base = Double(i) / Double(spokes)
            let width = 0.02
            stops.append(.init(color: .clear, location: base))
            stops.append(.init(color: gold.opacity(0.85), location: base + width))
            stops.append(.init(color: .clear, location: base + width * 2))
        }
        return stops
    }

    private var medallion: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [radiant, amber],
                                   center: .center, startRadius: 0, endRadius: 52)
                )
            Circle()
                .stroke(goldGradient, lineWidth: 3)
            Image(systemName: achievement.icon)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 96, height: 96)
        .shadow(color: gold.opacity(0.65), radius: 22)
    }

    // MARK: - Animation

    private func animateIn() {
        guard !reduceMotion else {
            // Content still needs to appear — just instantly, with no spring
            // bounce and no perpetual glow/ray-rotation loops.
            appeared = true
            phoenixRise = true
            badgeStamped = true
            glowPulse = true
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            appeared = true
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.05)) {
            phoenixRise = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.35)) {
            badgeStamped = true
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
        withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
            rayRotation = 360
        }
    }

    private func dismiss() {
        withAnimation(Constants.springAnimation) {
            appeared = false
        }
        onDismiss()
    }
}
