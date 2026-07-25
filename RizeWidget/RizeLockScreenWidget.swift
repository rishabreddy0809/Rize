import WidgetKit
import SwiftUI

/// Lock Screen accessory widget — the system renders these families in a
/// vibrant monochrome tint (it strips custom colors), so every layout here
/// leans on `widgetAccentable()` / SF Symbol-style glyphs rather than the
/// app's own palette. All three sizes read from the same `RizeWidgetEntry`.
///
/// The three `WidgetFamily` cases handled below correspond to the three
/// distinct slots iOS offers on the Lock Screen (same "one view, switch on
/// `widgetFamily`" pattern as `RizeHomeWidgetView`):
///   - `.accessoryCircular`    — the small ring widgets flanking the clock.
///   - `.accessoryRectangular` — the wider card below the clock.
///   - `.accessoryInline`      — the single text line above the clock,
///                               shared with things like Now Playing.
struct RizeLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RizeWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularBody
        case .accessoryInline:
            inlineBody
        default:
            circularBody
        }
    }

    // MARK: - Circular

    /// `Gauge` is SwiftUI's generic "value within a range" control — normally
    /// styled as a dial or progress ring depending on platform/style. Here
    /// `.gaugeStyle(.accessoryCircular)` is what actually makes it render as
    /// the Lock Screen's signature ring: that style is only meaningful in
    /// accessory-family widgets and is what draws `value/in` as an arc, with
    /// `currentValueLabel` as the big number in the center and the plain
    /// `label` closure (first trailing closure — the phoenix, here) as a
    /// small icon above it.
    ///
    /// `.widgetAccentable()` opts specific views into the Lock Screen's
    /// accent-tint pass — the system picks one accent color per Lock Screen
    /// (from the wallpaper or user's choice) and only recolors views marked
    /// this way; everything else stays a fixed dim gray. Marking the whole
    /// `Gauge` here means both the ring and the phoenix icon pick up that
    /// live accent color instead of looking flat.
    private var circularBody: some View {
        Gauge(value: Double(entry.snapshot.vitality), in: 0...100) {
            // Same still frame as the Home Screen watermark — the system
            // renders this as a monochrome/tinted glyph here, so only the
            // phoenix's alpha silhouette matters, not its baked-in color.
            phoenixGlyph
        } currentValueLabel: {
            Text("\(entry.snapshot.streak)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Rectangular

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                phoenixGlyph
                    .frame(width: 14, height: 14)
                Text("\(entry.snapshot.streak) DAY STREAK")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            Text(entry.snapshot.tierName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .opacity(0.7)
            Gauge(value: Double(entry.snapshot.vitality), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            Text(entry.snapshot.totalTasks > 0
                 ? "\(entry.snapshot.tasksCompleted)/\(entry.snapshot.totalTasks) tasks done"
                 : "\(entry.snapshot.vitality)% vitality")
                .font(.system(size: 10, design: .rounded))
                .opacity(0.7)
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Inline

    /// `accessoryInline` is the single line above the Lock Screen clock — the
    /// system only reliably renders plain text plus an SF Symbol there, not a
    /// custom raster image, so this intentionally does NOT reuse the phoenix
    /// PNG (unlike the other two families).
    private var inlineBody: some View {
        let progress = entry.snapshot.totalTasks > 0
            ? " · \(entry.snapshot.tasksCompleted)/\(entry.snapshot.totalTasks)"
            : ""
        return Label {
            Text("\(entry.snapshot.streak)d · \(entry.snapshot.tierName.capitalized)\(progress)")
        } icon: {
            Image(systemName: "flame.fill")
        }
    }

    private var phoenixGlyph: some View {
        Image("PhoenixWidgetGlyph")
            .resizable()
            .scaledToFit()
    }
}

struct RizeLockScreenWidget: Widget {
    let kind = "RizeLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RizeWidgetProvider()) { entry in
            RizeLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Phoenix Vitality")
        .description("Streak and vitality on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
