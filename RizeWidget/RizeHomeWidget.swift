import WidgetKit
import SwiftUI

// Not `private` — `RizeSportsWidget.swift` reuses both so every Home Screen
// widget shares one visual identity instead of redefining these per file.
enum WidgetPalette {
    static let backgroundBottom = Color(hex: "000000")
    static let backgroundTop = Color(hex: "3D0A0A")
    static let textPrimary = Color(hex: "F2EFE8")
    static let textSecondary = Color(hex: "C4967A")
    static let destructive = Color(hex: "E8724A")
    static let success = Color(hex: "4CAF82")
    static let primary = Color(hex: "F5A623")

    static func vitalityColor(_ percent: Int) -> Color {
        if percent > 60 { return success }
        if percent >= 30 { return primary }
        return destructive
    }
}

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [WidgetPalette.backgroundBottom, WidgetPalette.backgroundTop],
            startPoint: .bottom, endPoint: .top
        )
    }
}

/// A phoenix (frames lifted from the app's flight animation — widgets can't
/// run SpriteKit, so these are stills) tucked into a corner as a mascot
/// accent, so the widget reads as unmistakably "Rize" at a glance. Alternates
/// between two wing poses as the timeline advances through its entries (see
/// `RizeWidgetProvider`) for a subtle sense of motion, and tilts oppositely
/// per pose so the swap reads as a flap rather than a static swap.
private struct PhoenixWatermark: View {
    var poseIndex: Int = 0
    // High opacity is deliberate: this composites over `WidgetBackground`'s
    // dark red gradient, and alpha blending means a lower opacity here would
    // let more of that dark red show through — muting the phoenix's actual
    // orange/gold fire colors into a duller, redder tone instead of showing
    // them as they really are.
    var opacity: Double = 0.85

    var body: some View {
        Image(poseIndex == 0 ? "PhoenixWidgetGlyph" : "PhoenixWidgetGlyphAlt")
            .resizable()
            .scaledToFit()
            .opacity(opacity)
            .rotationEffect(.degrees(poseIndex == 0 ? -4 : 4))
            .animation(.easeInOut(duration: 1.4), value: poseIndex)
    }
}

/// One `Widget` (see `RizeHomeWidget` at the bottom of this file) can offer
/// several sizes at once — this view is reused for all of them, and
/// `@Environment(\.widgetFamily)` is how it finds out which size the system
/// is currently asking it to render. `WidgetFamily` is WidgetKit's name for
/// "which physical size/slot this is" (`.systemSmall`/`.systemMedium`/
/// `.systemLarge` for the Home Screen; `.accessoryCircular`/etc. for the
/// Lock Screen, used over in `RizeLockScreenWidget.swift`). The system reads
/// `supportedFamilies` below to know which sizes to even offer the user in
/// the widget gallery, then sets this environment value to match whichever
/// one the user actually placed.
struct RizeHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RizeWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBody
        case .systemLarge:
            largeBody
        default:
            smallBody
        }
    }

    // MARK: - Small

    private var smallBody: some View {
        ZStack(alignment: .bottomTrailing) {
            PhoenixWatermark(poseIndex: entry.phoenixPoseIndex)
                .frame(width: 116, height: 116)
                .padding(.trailing, -16)
                .padding(.bottom, -12)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(entry.snapshot.isUnderSiege ? WidgetPalette.destructive : .orange)
                    Text("\(entry.snapshot.streak)")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundStyle(WidgetPalette.textPrimary)
                    Text("DAY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.textSecondary)
                }

                Text(entry.snapshot.tierName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.tierColor)

                Spacer(minLength: 4)

                vitalityBar

                HStack {
                    Text("VITALITY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
                    Spacer()
                    Text("\(entry.snapshot.vitality)%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.vitalityColor(entry.snapshot.vitality))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `containerBackground(for: .widget)` — not a plain `.background()`
        // modifier — is how a widget declares its background since iOS 17.
        // The system needs it as a distinct, named layer (rather than an
        // arbitrary view buried in the hierarchy) because it composites
        // things on top of/behind it in contexts this code never runs in
        // directly: dimming it for StandBy mode, applying tint/vibrancy when
        // the user picks a tinted Home Screen icon theme, etc. Every family
        // body below sets this exactly once, at the outermost layer.
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    // MARK: - Medium

    private var mediumBody: some View {
        ZStack(alignment: .topTrailing) {
            PhoenixWatermark(poseIndex: entry.phoenixPoseIndex, opacity: 0.85)
                .frame(width: 160, height: 160)
                .padding(.trailing, -24)
                .padding(.top, -28)

            mediumContent
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private var mediumContent: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(entry.snapshot.isUnderSiege ? WidgetPalette.destructive : .orange)
                    Text("\(entry.snapshot.streak)")
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .foregroundStyle(WidgetPalette.textPrimary)
                }
                Text("DAY STREAK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary)
                Text(entry.snapshot.tierName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.tierColor)
            }

            Divider().background(WidgetPalette.textSecondary.opacity(0.2))

            VStack(alignment: .leading, spacing: 6) {
                Text("PHOENIX VITALITY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
                vitalityBar
                Text(entry.snapshot.isUnderSiege ? "Under siege — feed the flame" : "\(entry.snapshot.vitality)% · \(entry.snapshot.totalXP) XP")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(WidgetPalette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Large

    private var largeBody: some View {
        ZStack(alignment: .topTrailing) {
            PhoenixWatermark(poseIndex: entry.phoenixPoseIndex, opacity: 0.85)
                .frame(width: 230, height: 230)
                .padding(.trailing, -34)
                .padding(.top, -30)

            largeContent
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(entry.snapshot.isUnderSiege ? WidgetPalette.destructive : .orange)
                Text("\(entry.snapshot.streak)")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text("DAY STREAK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary)
                Spacer()
                Text(entry.snapshot.tierName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.tierColor)
            }

            vitalityBar
            Text(entry.snapshot.isUnderSiege ? "Under siege — feed the flame" : "\(entry.snapshot.vitality)% vitality · \(entry.snapshot.totalXP) XP")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(WidgetPalette.textSecondary)

            Divider().background(WidgetPalette.textSecondary.opacity(0.2))

            HStack {
                Text("TODAY'S PLAN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
                Spacer()
                Text("\(entry.snapshot.tasksCompleted)/\(entry.snapshot.totalTasks)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.7))
            }

            if entry.snapshot.tasks.isEmpty {
                Text("No tasks yet — open Rize to generate today's plan.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetPalette.textSecondary.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.snapshot.tasks) { task in
                        HStack(spacing: 8) {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(task.completed ? WidgetPalette.success : WidgetPalette.textSecondary.opacity(0.5))
                            Text(task.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(task.completed ? WidgetPalette.textSecondary.opacity(0.5) : WidgetPalette.textPrimary)
                                .strikethrough(task.completed)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var vitalityBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 3)
                    .fill(WidgetPalette.vitalityColor(entry.snapshot.vitality))
                    .frame(width: geo.size.width * Double(entry.snapshot.vitality) / 100.0)
            }
        }
        .frame(height: 5)
    }
}

/// The actual widget declaration WidgetKit discovers and registers — this is
/// the type listed in `RizeWidgetBundle.swift`'s `@main` bundle. `kind` is
/// this widget's stable identity string: WidgetKit uses it to remember which
/// widget a user has placed across app updates and relaunches, so it must
/// never change once shipped, or existing placements orphan.
///
/// `StaticConfiguration` is the simplest of WidgetKit's configuration types —
/// it means this widget has no user-facing settings (compare to
/// `AppIntentConfiguration`, which lets the user long-press → Edit Widget to
/// pick options; not needed here since there's nothing to configure beyond
/// which entry/family to show, which the provider and environment already
/// handle). It wires together the `provider` (supplies the data timeline)
/// and a closure that turns each `RizeWidgetEntry` into a view.
struct RizeHomeWidget: Widget {
    let kind = "RizeHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RizeWidgetProvider()) { entry in
            RizeHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Phoenix Status")
        .description("Your streak and Phoenix vitality, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
