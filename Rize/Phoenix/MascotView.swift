import SwiftUI

// MARK: - Mascot Badge

/// A small mascot that grows up alongside the player's tier — reuses the
/// app's existing per-tier animations (`PhoenixTierVisual`'s Ash/Awakening/
/// Rising particle visuals, already shown in the Kingdom tab) rather than
/// new art, and the real perched idle phoenix (`PhoenixPerchedView`, already
/// used in onboarding) for both Radiant and Eternal. No backdrop circle —
/// just the animation itself.
struct MascotBadge: View {
    let tierIndex: Int
    var size: CGFloat = 56

    @State private var pulse = false
    @Environment(\.rizeReduceMotion) private var reduceMotion

    private var clampedTier: Int { min(max(tierIndex, 0), PhoenixDesign.tiers.count - 1) }
    private var usesPerchedPhoenix: Bool { clampedTier >= 3 }

    /// How strongly the glow breathes — later tiers feel more alive.
    private var pulseStrength: CGFloat {
        switch clampedTier {
        case 0: return 0.03
        case 1: return 0.05
        case 2: return 0.07
        case 3: return 0.09
        default: return 0.12
        }
    }

    var body: some View {
        creature
            // Ash and the perched phoenix render nothing but a bare
            // `allowsHitTesting(false)` SpriteKit view with no sibling
            // SwiftUI shape alongside it (unlike Awakening/Rising, which
            // layer plain SwiftUI circles/glows next to their sprite) — with
            // no native-SwiftUI content in that subtree at all, the drag
            // gesture on the ancestor overlay doesn't reliably bind to it.
            // `.contentShape` makes the hit-test region explicit and
            // guaranteed, independent of what's actually drawn inside.
            .contentShape(Rectangle())
            .scaleEffect(pulse && !reduceMotion ? 1 + pulseStrength : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityLabel("\(PhoenixDesign.tiers[clampedTier].name.capitalized) mascot")
            .accessibilityHint("Double tap for a word of encouragement")
    }

    /// The actual rendered footprint of `creature` at a given `size` — the
    /// tiers were each hand-tuned to different zoom/crop factors (see
    /// `creature` below), so a caller positioning something relative to the
    /// mascot (the speech bubble) needs this instead of assuming `size`.
    static func visualHeight(tierIndex: Int, size: CGFloat) -> CGFloat {
        let clamped = min(max(tierIndex, 0), PhoenixDesign.tiers.count - 1)
        if clamped >= 3 { return size * 2.1 }
        if clamped == 0 { return size * 1.7 * 0.6 }
        if clamped == 1 { return size * 2.2 }
        return size * 1.4
    }

    @ViewBuilder
    private var creature: some View {
        if usesPerchedPhoenix {
            PhoenixPerchedView()
                .frame(width: size * 2.1, height: size * 2.1)
        } else if clampedTier == 0 {
            // `AshVisual` (via `PhoenixTierVisual`) adds its own ambient
            // RadialGradient halo behind the pile, which is centered in the
            // same square as the pile and only fades to transparent right at
            // that square's true edge — cropping tighter than that cuts
            // through the still-visible glow and leaves a hard seam. So skip
            // that wrapper here and crop the bare sprite instead: the pile is
            // deliberately anchored low with real (non-gradient) transparent
            // padding above it — see the `contentScale`/anchor comment on
            // `Tier1AshesNode` in PhoenixSprite.swift — so cropping into that
            // padding just removes empty pixels, nothing visible to seam.
            Tier1AshesView()
                .frame(width: size * 2.6, height: size * 2.6)
                .frame(width: size * 1.7, height: size * 1.7 * 0.6, alignment: .bottom)
                .clipped()
        } else if clampedTier == 1 {
            PhoenixTierVisual(tierIndex: clampedTier, size: size * 2.2)
        } else {
            PhoenixTierVisual(tierIndex: clampedTier, size: size * 1.4)
        }
    }
}

// MARK: - Speech Bubble

private struct MascotSpeechBubble: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 220, alignment: .leading)
            .phoenixGlass(cornerRadius: 16)
    }
}

// MARK: - Draggable Overlay

/// A freely-draggable, tier-skinned mascot that persists across tab switches
/// (host it once in `MainTabView`'s root `ZStack`). Tapping it asks
/// `MascotNarrator` for a short, grounded motivational line and shows it in
/// a speech bubble beside the mascot.
struct MascotOverlay: View {
    let tierIndex: Int
    let context: MascotContext

    /// Normalized position (0...1 of the safe content area) so the mascot
    /// stays on-screen across device sizes/orientations.
    @AppStorage("mascot_x") private var storedX: Double = 0.85
    @AppStorage("mascot_y") private var storedY: Double = 0.78

    @GestureState private var dragOffset: CGSize = .zero
    @State private var bubbleMessage: String?
    @State private var bubbleTask: Task<Void, Never>?

    private let badgeSize: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let basePosition = CGPoint(x: storedX * bounds.width, y: storedY * bounds.height)
            let liveX = basePosition.x + dragOffset.width
            let liveY = basePosition.y + dragOffset.height
            let bubbleOnLeft = liveX > bounds.width * 0.6
            let visualHeight = MascotBadge.visualHeight(tierIndex: tierIndex, size: badgeSize)

            ZStack {
                if let message = bubbleMessage {
                    MascotSpeechBubble(message: message)
                        // Clears the top of whatever creature is currently
                        // showing — the tiers render at very different sizes
                        // (a cropped ash pile vs. the full perched phoenix),
                        // so this can't be a fixed offset without the bubble
                        // overlapping the bigger ones.
                        .offset(x: bubbleOnLeft ? -140 : 140, y: -(visualHeight / 2 + 20))
                        .transition(.scale(scale: 0.85, anchor: bubbleOnLeft ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                }

                MascotBadge(tierIndex: tierIndex, size: badgeSize)
            }
            .position(x: liveX, y: liveY)
            .highPriorityGesture(
                // `highPriorityGesture` (not plain `.gesture`) so this wins
                // against the ScrollView pan gesture running underneath it in
                // every tab — with a plain `.gesture`, touches starting on
                // the mascot could get claimed by the ScrollView's own pan
                // recognizer instead, which is what made the drag feel like
                // it wasn't responding and taps land inconsistently.
                //
                // `minimumDistance: 0` so this single gesture captures both a
                // tap and a drag — `onEnded` tells them apart by how far the
                // touch actually travelled, rather than racing a separate
                // `TapGesture` against the drag for the same touch. The
                // threshold is generous (a real finger, unlike a mouse click,
                // always has a few points of jitter) so a tap doesn't
                // misfire as a micro-drag.
                DragGesture(minimumDistance: 0)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        guard distance > 14 else {
                            handleTap()
                            return
                        }
                        // Half the badge (not the full width) as the edge
                        // margin, so it can be dragged flush into any corner
                        // of the screen rather than stopping a full badge-
                        // width short of the edge.
                        let margin = badgeSize / 2
                        let clampedX = min(max(basePosition.x + value.translation.width, margin), bounds.width - margin)
                        let clampedY = min(max(basePosition.y + value.translation.height, margin), bounds.height - margin)
                        storedX = bounds.width > 0 ? clampedX / bounds.width : storedX
                        storedY = bounds.height > 0 ? clampedY / bounds.height : storedY
                    }
            )
            // Deliberately NOT animating `dragOffset` — it updates on every
            // touch-move frame, and spring-animating a value that already
            // changes 60-120 times a second just fights the finger with lag
            // and overshoot instead of tracking it. Only the bubble (which
            // changes rarely, not per-frame) gets an implicit animation.
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bubbleMessage)
        }
        // Full-bleed bounds — including under the status bar/notch and past
        // the home indicator — so the mascot can be dragged anywhere on the
        // physical screen, not just the safe area.
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private func handleTap() {
        bubbleTask?.cancel()

        if bubbleMessage != nil {
            bubbleMessage = nil
            return
        }

        bubbleTask = Task {
            let line = await MascotNarrator.shared.line(for: context)
            guard !Task.isCancelled else { return }
            bubbleMessage = line

            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            bubbleMessage = nil
        }
    }
}
