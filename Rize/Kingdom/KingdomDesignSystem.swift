import SwiftUI

// MARK: - Kingdom Task Section

enum KingdomTaskSection: String, CaseIterable {
    case morning
    case anytime
    case evening
    case queue

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .anytime: return "Anytime"
        case .evening: return "Evening"
        case .queue: return "Queue"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .anytime: return "bolt.fill"
        case .evening: return "moon.fill"
        case .queue: return "list.bullet"
        }
    }

    static func from(taskType: String) -> KingdomTaskSection {
        switch taskType.lowercased() {
        case "physical": return .morning
        case "work": return .anytime
        case "recovery": return .evening
        default: return .queue
        }
    }
}

// MARK: - Phoenix Palette

enum PhoenixPalette {
    // Background gradient stops (bottom → top)
    static let backgroundBottom = Color(hex: "000000")
    static let backgroundLow    = Color(hex: "0D0202")   // 30%
    static let backgroundMid    = Color(hex: "1A0505")   // 60%
    static let backgroundTop    = Color(hex: "3D0A0A")   // 100%

    // Surfaces (cards, sheets, overlays)
    static let surface       = Color(red: 0.08, green: 0.02, blue: 0.02).opacity(0.85)
    static let surfaceBorder = Color(red: 0.35, green: 0.08, blue: 0.08)

    // Text
    static let textPrimary   = Color(hex: "F2EFE8")
    static let textSecondary = Color(hex: "C4967A")

    // Accents
    static let primary     = Color(hex: "F5A623")  // amber gold — primary action
    static let success     = Color(hex: "4CAF82")  // sage green
    static let destructive = Color(hex: "E8724A")  // coral

    // Tier accents
    static let ash       = Color(hex: "C8B89A")
    static let awakening = Color(hex: "F5A623")
    static let rising    = Color(hex: "E8724A")
    static let radiant   = Color(hex: "FFB830")
    static let eternal   = Color(hex: "FFD700")
}

// MARK: - Fire Gradient Background

/// Full-bleed vertical fire gradient. Applied as the base ZStack layer on every main screen.
struct PhoenixBackground: View {
    /// Higher-saturation variant used behind the low-energy celebration overlay.
    var intensified: Bool = false

    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: PhoenixPalette.backgroundBottom, location: 0.0),
                .init(color: PhoenixPalette.backgroundLow, location: 0.3),
                .init(color: PhoenixPalette.backgroundMid, location: 0.6),
                .init(color: intensified ? Color(hex: "5A0F0F") : PhoenixPalette.backgroundTop, location: 1.0),
            ]),
            startPoint: .bottom, endPoint: .top
        )
        .ignoresSafeArea()
    }
}

// MARK: - Phoenix Design

enum KingdomDesign {
    struct TierInfo {
        let minXP: Int
        let name: String
        let color: Color
        let nextMinXP: Int?
        let index: Int
    }

    static let tiers: [(minXP: Int, name: String, color: Color)] = [
        (0,    "ASH",       PhoenixPalette.ash),
        (501,  "AWAKENING", PhoenixPalette.awakening),
        (1501, "RISING",    PhoenixPalette.rising),
        (3501, "RADIANT",   PhoenixPalette.radiant),
        (7001, "ETERNAL",   PhoenixPalette.eternal)
    ]

    static func tierInfo(for totalXP: Int) -> TierInfo {
        var currentIndex = 0
        for (i, tier) in tiers.enumerated() {
            if totalXP >= tier.minXP {
                currentIndex = i
            }
        }
        let tier = tiers[currentIndex]
        let next = currentIndex + 1 < tiers.count ? tiers[currentIndex + 1].minXP : nil
        return TierInfo(minXP: tier.minXP, name: tier.name, color: tier.color, nextMinXP: next, index: currentIndex)
    }

    static func playerLevel(for totalXP: Int) -> Int {
        max(1, totalXP / 120 + 1)
    }

    static func defenseBarColor(_ percent: Int) -> Color {
        if percent > 60 { return PhoenixPalette.success }
        if percent >= 30 { return PhoenixPalette.primary }
        return PhoenixPalette.destructive
    }

    static func sectionColor(_ section: KingdomTaskSection) -> Color {
        switch section {
        case .morning: return .orange
        case .anytime: return Color(hex: "0A84FF")
        case .evening: return .purple
        case .queue: return .gray
        }
    }
}

// MARK: - Glass Style

struct KingdomGlassStyle: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(PhoenixPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PhoenixPalette.surfaceBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func kingdomGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(KingdomGlassStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Phoenix Tier Visuals

/// Reusable tier visual — renders the Ash/Awakening/Rising/Radiant programmatic glows
/// for tiers 0-3, or the real animated phoenix sprite for tier 4 (Eternal).
/// Each sub-visual is built at its spec'd natural size, then scaled to fit `size`.
struct PhoenixTierVisual: View {
    let tierIndex: Int
    var size: CGFloat = 220
    /// Eternal only — hides the glow rings/particles for tiny contexts (e.g. onboarding tier row).
    var decorated: Bool = true

    private var naturalSize: CGFloat {
        switch tierIndex {
        case 0: return AshVisual.naturalSize
        case 1: return AwakeningVisual.naturalSize
        case 2: return RisingVisual.naturalSize
        case 3: return RadiantVisual.naturalSize
        default: return EternalVisual.naturalSize
        }
    }

    var body: some View {
        Group {
            switch tierIndex {
            case 0: AshVisual()
            case 1: AwakeningVisual()
            case 2: RisingVisual()
            case 3: RadiantVisual()
            default: EternalVisual(decorated: decorated)
            }
        }
        .frame(width: naturalSize, height: naturalSize)
        .scaleEffect(size / naturalSize)
        .frame(width: size, height: size)
    }
}

// MARK: Tier 1 — Ash

private struct AshVisual: View {
    static let naturalSize: CGFloat = 80
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PhoenixPalette.ash, PhoenixPalette.ash.opacity(0)],
                        center: .center, startRadius: 0, endRadius: Self.naturalSize / 2
                    )
                )
                .frame(width: Self.naturalSize, height: Self.naturalSize)
                .clipShape(Circle())
                .opacity(breathe ? 0.3 : 0.15)

            Tier1AshesView()
                .frame(width: Self.naturalSize, height: Self.naturalSize)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: Tier 2 — Awakening

private struct AwakeningVisual: View {
    static let naturalSize: CGFloat = 140
    @State private var coreFlicker = false
    @State private var wingFlicker = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PhoenixPalette.awakening.opacity(0.6), PhoenixPalette.awakening.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .opacity(coreFlicker ? 1.0 : 0.72)

            ForEach([-1, 1], id: \.self) { side in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [PhoenixPalette.rising.opacity(0.4), PhoenixPalette.rising.opacity(0)],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .frame(width: 4, height: 58)
                    .rotationEffect(.degrees(Double(side) * 28))
                    .offset(x: CGFloat(side) * 20, y: -28)
                    .opacity(wingFlicker ? 0.9 : 0.45)
            }

            Tier2FlameView()
                .frame(width: Self.naturalSize, height: Self.naturalSize)
        }
        .frame(width: Self.naturalSize, height: Self.naturalSize)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { coreFlicker = true }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { wingFlicker = true }
        }
    }
}

// MARK: Tier 3 — Rising

private struct RisingVisual: View {
    static let naturalSize: CGFloat = 170

    var body: some View {
        ZStack {
            PulsingRing(color: PhoenixPalette.awakening.opacity(0.2), diameter: 160, duration: 2.5)

            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.rising.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 75))
                .frame(width: 150, height: 150)
                .clipShape(Circle())
            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.awakening.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 55))
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .offset(x: -35, y: -15)
            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.awakening.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 55))
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .offset(x: 35, y: -15)

            Tier3FlameView()
                .frame(width: Self.naturalSize, height: Self.naturalSize)
        }
        .frame(width: Self.naturalSize, height: Self.naturalSize)
    }
}

// MARK: Tier 4 — Radiant

private struct RadiantVisual: View {
    static let naturalSize: CGFloat = 260

    var body: some View {
        ZStack {
            RadiantRing(color: PhoenixPalette.radiant.opacity(0.22), diameter: 240, pulseDuration: 2.2, rotateDuration: 14, clockwise: true)
            RadiantRing(color: PhoenixPalette.rising.opacity(0.18), diameter: 210, pulseDuration: 3.0, rotateDuration: 20, clockwise: false)

            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.radiant.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 220)
                .clipShape(Circle())
            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.rising.opacity(0.65), .clear], center: .center, startRadius: 0, endRadius: 80))
                .frame(width: 160, height: 160)
                .clipShape(Circle())
                .offset(x: -50, y: -22)
            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.rising.opacity(0.65), .clear], center: .center, startRadius: 0, endRadius: 80))
                .frame(width: 160, height: 160)
                .clipShape(Circle())
                .offset(x: 50, y: -22)

            Tier4FlameView()
                .frame(width: Self.naturalSize, height: Self.naturalSize)
        }
        .frame(width: Self.naturalSize, height: Self.naturalSize)
    }
}

// MARK: Tier 5 — Eternal

private struct EternalVisual: View {
    static let naturalSize: CGFloat = 280
    var decorated: Bool

    var body: some View {
        ZStack {
            if decorated {
                Circle()
                    .fill(PhoenixPalette.primary)
                    .frame(width: 180, height: 180)
                    .blur(radius: 50)
                    .opacity(0.35)
                Circle()
                    .fill(PhoenixPalette.radiant)
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                    .opacity(0.4)

                RotatingDashedRing(color: PhoenixPalette.eternal.opacity(0.35), diameter: 260, duration: 18, clockwise: true)
                RotatingDashedRing(color: PhoenixPalette.primary.opacity(0.3), diameter: 230, duration: 24, clockwise: false)
            }

            PhoenixSpriteView()
                .frame(width: Self.naturalSize * 0.78, height: Self.naturalSize * 0.78)

            if decorated {
                ParticleEmitterView(type: .phoenixEmbers)
                    .frame(width: Self.naturalSize, height: Self.naturalSize)
            }
        }
        .frame(width: Self.naturalSize, height: Self.naturalSize)
        .shadow(color: decorated ? PhoenixPalette.primary.opacity(0.5) : .clear, radius: decorated ? 30 : 0)
        .shadow(color: decorated ? PhoenixPalette.radiant.opacity(0.35) : .clear, radius: decorated ? 50 : 0)
    }
}

// MARK: - Shared Ring Helpers

/// A ring that scales outward and fades — a single "pulse" repeating forever.
private struct PulsingRing: View {
    var color: Color
    var diameter: CGFloat
    var duration: Double
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animate ? 1.3 : 1.0)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: duration).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

/// A dashed ring that continuously rotates — dashes make the rotation visible.
private struct RotatingDashedRing: View {
    var color: Color
    var diameter: CGFloat
    var duration: Double
    var clockwise: Bool = true
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    angle = clockwise ? 360 : -360
                }
            }
    }
}

/// Radiant tier's ring: pulses/fades (ripple) AND slowly rotates (dashed for visibility).
private struct RadiantRing: View {
    var color: Color
    var diameter: CGFloat
    var pulseDuration: Double
    var rotateDuration: Double
    var clockwise: Bool
    @State private var pulsing = false
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0 : 1)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.easeOut(duration: pulseDuration).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
                withAnimation(.linear(duration: rotateDuration).repeatForever(autoreverses: false)) {
                    angle = clockwise ? 360 : -360
                }
            }
    }
}
