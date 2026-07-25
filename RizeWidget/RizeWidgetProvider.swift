import WidgetKit
import SwiftUI

// MARK: - How WidgetKit actually works
//
// A widget's extension process is NOT kept running the way the main app is.
// The system launches it briefly, asks it to render some content ahead of
// time, then suspends it — there's no live loop redrawing the screen every
// frame. So instead of the widget "pulling" fresh content when it's about to
// be shown, WidgetKit flips the model: your `TimelineProvider` hands the
// system a `Timeline` — a list of `TimelineEntry` values, each stamped with
// the `Date` at which it should become the one displayed — and the system
// takes it from there, swapping between your pre-supplied entries on its own
// schedule (using a cached, pre-rendered snapshot for each), without calling
// back into your code again until the entries run out or you explicitly
// trigger a reload (see `WidgetCenter.reloadAllTimelines()` in `XPManager`).
//
// `TimelineProvider` requires three methods, each serving a different UI
// moment:
//   - `placeholder`      — an instant, data-free skeleton shown for a split
//                           second while the *real* first entry loads (e.g.
//                           right after the widget is added). Must return
//                           synchronously, so it can't do any real work.
//   - `getSnapshot`      — one single, representative entry, used by the
//                           widget gallery/picker UI when the user is
//                           browsing widgets to add — not the long-running
//                           timeline, just "what would this look like?"
//   - `getTimeline`      — the real deal: the actual sequence of entries the
//                           system will cycle through once the widget is
//                           placed, plus a `TimelineReloadPolicy` (here,
//                           `.after(date)`) telling the system when to come
//                           back and ask for a fresh batch.
struct RizeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: RizeWidgetSnapshot
    /// Which cached phoenix pose to show. WidgetKit can't run a live
    /// animation loop (the extension isn't kept running), so "movement"
    /// here means the pose changes each time the system advances to the
    /// next timeline entry rather than staying locked on one frame forever.
    var phoenixPoseIndex: Int = 0

    var tierColor: Color { Color(hex: snapshot.tierColorHex) }
}

struct RizeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RizeWidgetEntry {
        RizeWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RizeWidgetEntry) -> Void) {
        completion(RizeWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RizeWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .placeholder
        // Same underlying data across every entry — only the decorative
        // phoenix pose alternates — so the app's real reloadAllTimelines()
        // call (on task completion, launch, etc.) always supersedes this
        // with fresh data anyway. Spacing entries a few minutes apart lets
        // the phoenix visibly flap over the course of sitting on a Home
        // Screen, without needing any extra reload budget.
        let poseInterval: TimeInterval = 6 * 60
        let poseCount = 6
        let now = Date()
        let entries = (0..<poseCount).map { i in
            RizeWidgetEntry(
                date: now.addingTimeInterval(Double(i) * poseInterval),
                snapshot: snapshot,
                phoenixPoseIndex: i % 2
            )
        }
        // This periodic refresh is a fallback in case the app hasn't been
        // opened in a while — normal updates come from the app pushing a
        // fresh snapshot and reloading timelines directly.
        let nextRefresh = now.addingTimeInterval(Double(poseCount) * poseInterval)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

/// Minimal, self-contained hex-color initializer — the widget extension is a
/// separate module from the app target, so it can't reach `PhoenixPalette`
/// directly; this mirrors `Color+Hex.swift`'s behavior for the tier hex codes
/// stored in the snapshot.
extension Color {
    init(hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
