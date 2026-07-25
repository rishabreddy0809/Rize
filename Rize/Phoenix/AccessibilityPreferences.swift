import SwiftUI

// MARK: - Environment Keys

/// Combined "should minimize motion" signal — system Reduce Motion OR-ed
/// with `UserProfile.accessibilityReduceMotion`. Views should read this
/// instead of `\.accessibilityReduceMotion` directly, since either source
/// wanting less motion should win.
private struct RizeReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

/// Combined "should minimize transparency" signal — system Reduce
/// Transparency OR-ed with `UserProfile.accessibilityReduceTransparency`.
private struct RizeReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

/// `UserProfile.accessibilityHighContrast` — there's no system-wide iOS
/// setting this needs to combine with (Increase Contrast is already applied
/// by the OS at the rendering layer before this even runs), so this one is
/// purely the in-app override.
private struct RizeHighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rizeReduceMotion: Bool {
        get { self[RizeReduceMotionKey.self] }
        set { self[RizeReduceMotionKey.self] = newValue }
    }
    var rizeReduceTransparency: Bool {
        get { self[RizeReduceTransparencyKey.self] }
        set { self[RizeReduceTransparencyKey.self] = newValue }
    }
    var rizeHighContrast: Bool {
        get { self[RizeHighContrastKey.self] }
        set { self[RizeHighContrastKey.self] = newValue }
    }
}

// MARK: - SpriteKit Bridge

/// The tier mascots (`PhoenixSprite.swift`) are plain `SKScene`/`SKSpriteNode`
/// subclasses instantiated directly, outside the SwiftUI view tree — they
/// have no way to read `@Environment(\.rizeReduceMotion)`. This process-wide
/// flag is how the SwiftUI layer hands that same combined signal down to
/// them. `RootView` keeps it in sync on every launch and whenever the
/// profile's override or the system setting changes.
enum AccessibilityState {
    static var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
}

// MARK: - Root Injection

/// Computes the combined system+override accessibility signals from the
/// current profile and injects them into the environment for every
/// descendant view, and mirrors Reduce Motion into `AccessibilityState` for
/// the SpriteKit mascots. Applied once at the root (`RizeApp.swift`).
struct RizeAccessibilityRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    let profile: UserProfile?

    private var reduceMotion: Bool {
        systemReduceMotion || (profile?.accessibilityReduceMotion ?? false)
    }
    private var reduceTransparency: Bool {
        systemReduceTransparency || (profile?.accessibilityReduceTransparency ?? false)
    }
    private var highContrast: Bool {
        profile?.accessibilityHighContrast ?? false
    }

    func body(content: Content) -> some View {
        content
            .environment(\.rizeReduceMotion, reduceMotion)
            .environment(\.rizeReduceTransparency, reduceTransparency)
            .environment(\.rizeHighContrast, highContrast)
            // A gentle, real contrast boost rather than a per-color-token
            // rewrite — bumps every secondary/translucent text label toward
            // fully opaque without touching each of the ~40 call sites that
            // use `PhoenixPalette.textSecondary.opacity(...)`.
            .contrast(highContrast ? 1.2 : 1.0)
            .onAppear { AccessibilityState.reduceMotion = reduceMotion }
            .onChange(of: reduceMotion) { _, newValue in AccessibilityState.reduceMotion = newValue }
    }
}

extension View {
    func rizeAccessibilityRoot(profile: UserProfile?) -> some View {
        modifier(RizeAccessibilityRoot(profile: profile))
    }
}
