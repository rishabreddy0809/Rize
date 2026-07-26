import SwiftUI

// MARK: - Phoenix Task Section

enum PhoenixTaskSection: String, CaseIterable {
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

    static func from(taskType: String) -> PhoenixTaskSection {
        switch taskType.lowercased() {
        case "physical": return .morning
        case "work": return .anytime
        case "recovery": return .evening
        default: return .queue
        }
    }
}

// MARK: - Plan Category

/// The category a task belongs to in the Today plan. Real calendar events are
/// classified into these from their title/calendar name (see `classify`);
/// the adaptive wellness tasks map in from their `TaskCategory`. This drives
/// the grouped section headers in the plan ("WORKOUTS", "CLASSES", …).
enum PlanCategory: String, CaseIterable, Sendable {
    case workout
    case classes
    case work
    case recovery
    case personal

    var title: String {
        switch self {
        case .workout:  return "Workouts"
        case .classes:  return "Classes"
        case .work:     return "Work Blocks"
        case .recovery: return "Recovery"
        case .personal: return "Personal"
        }
    }

    var icon: String {
        switch self {
        case .workout:  return "figure.run"
        case .classes:  return "graduationcap.fill"
        case .work:     return "briefcase.fill"
        case .recovery: return "moon.fill"
        case .personal: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .workout:  return Color(hex: "FF6B35")    // energetic orange
        case .classes:  return Color(hex: "0A84FF")    // study blue
        case .work:     return PhoenixPalette.primary  // amber gold
        case .recovery: return Color(hex: "9B7EDE")    // calm purple
        case .personal: return PhoenixPalette.success  // sage green
        }
    }

    /// Stable order for the section headers, top to bottom.
    var sortOrder: Int {
        switch self {
        case .workout:  return 0
        case .classes:  return 1
        case .work:     return 2
        case .personal: return 3
        case .recovery: return 4
        }
    }

    /// Map a persisted `RizeTask.type` string into a display category. Handles
    /// both the new category rawValues ("workout", "classes", …) and the legacy
    /// wellness strings ("physical", "work", "recovery").
    static func from(taskType: String) -> PlanCategory {
        switch taskType.lowercased() {
        case "workout", "physical": return .workout
        case "class", "classes":    return .classes
        case "work":                return .work
        case "recovery":            return .recovery
        case "personal":            return .personal
        default:                    return .personal
        }
    }

    /// Classify a calendar event by its title and originating calendar name.
    /// Checked most-specific first: workout → classes → work → personal.
    static func classify(title: String, calendarName: String?) -> PlanCategory {
        let hay = "\(title) \(calendarName ?? "")".lowercased()
        if containsAny(hay, workoutKeywords) { return .workout }
        if containsAny(hay, classKeywords)   { return .classes }
        if containsAny(hay, workKeywords)    { return .work }
        return .personal
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static let workoutKeywords = [
        "gym", "workout", "training", "run", "ride", "cycl", "bike", "swim",
        "lift", "yoga", "pilates", "crossfit", "spin", "hiit", "cardio",
        "practice", "soccer", "basketball", "tennis", "climb", "fitness"
    ]
    private static let classKeywords = [
        "class", "lecture", "seminar", "course", "tutorial", "lesson", "study",
        "exam", "quiz", "midterm", "final", "recitation", "discussion",
        "office hours", "school", "homework", "lab "
    ]
    private static let workKeywords = [
        "meeting", "standup", "stand-up", "sync", "1:1", "one-on-one", "review",
        "call", "interview", "work", "project", "deadline", "presentation",
        "demo", "sprint", "planning", "retro", "client", "deep work", "focus"
    ]
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

// MARK: - Phoenix Typography

/// "Cinzel" is the engraved-serif display face used for titles/headers across the app,
/// giving the kingdom/castle theme a consistent regal identity. Body copy stays on the
/// system rounded font for legibility at small sizes.
extension Font {
    /// Large hero titles (onboarding wordmark, big celebration headlines).
    static func phoenixHero(_ size: CGFloat) -> Font {
        .custom("Cinzel-Black", size: size, relativeTo: .largeTitle)
    }

    /// Section/screen titles.
    static func phoenixTitle(_ size: CGFloat) -> Font {
        .custom("Cinzel-ExtraBold", size: size, relativeTo: .title)
    }

    /// Card headlines, list section headers, tier names.
    static func phoenixHeadline(_ size: CGFloat = 17) -> Font {
        .custom("Cinzel-Bold", size: size, relativeTo: .headline)
    }

    /// Small labels/badges that still want the display face.
    static func phoenixLabel(_ size: CGFloat) -> Font {
        .custom("Cinzel-Bold", size: size, relativeTo: .caption)
    }
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

enum PhoenixDesign {
    struct TierInfo {
        let minXP: Int
        let name: String
        let color: Color
        let nextMinXP: Int?
        let index: Int
    }

    static let tiers: [(minXP: Int, name: String, color: Color)] = [
        (0,    "ASH",       PhoenixPalette.ash),
        (500,  "AWAKENING", PhoenixPalette.awakening),
        (1500, "RISING",    PhoenixPalette.rising),
        (3500, "RADIANT",   PhoenixPalette.radiant),
        (7000, "ETERNAL",   PhoenixPalette.eternal)
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

    static func sectionColor(_ section: PhoenixTaskSection) -> Color {
        switch section {
        case .morning: return .orange
        case .anytime: return Color(hex: "0A84FF")
        case .evening: return .purple
        case .queue: return .gray
        }
    }
}

// MARK: - Glass Style

struct PhoenixGlassStyle: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.rizeReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            // `surface` is a translucent fill designed to sit over the fire
            // gradient background — with Reduce Transparency on, swap in an
            // opaque near-black so card contents never have to compete with
            // whatever's showing through underneath.
            .background(reduceTransparency ? Color(red: 0.08, green: 0.02, blue: 0.02) : PhoenixPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PhoenixPalette.surfaceBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func phoenixGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(PhoenixGlassStyle(cornerRadius: cornerRadius))
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
    @Environment(\.rizeReduceMotion) private var reduceMotion

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
            guard !reduceMotion else { return }
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
    @Environment(\.rizeReduceMotion) private var reduceMotion

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
            guard !reduceMotion else { return }
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
    @Environment(\.rizeReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animate ? 1.3 : 1.0)
            .opacity(animate ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
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
    @Environment(\.rizeReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
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
    @Environment(\.rizeReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0 : 1)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: pulseDuration).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
                withAnimation(.linear(duration: rotateDuration).repeatForever(autoreverses: false)) {
                    angle = clockwise ? 360 : -360
                }
            }
    }
}
