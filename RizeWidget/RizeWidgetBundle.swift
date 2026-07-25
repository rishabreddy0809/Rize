import WidgetKit
import SwiftUI

/// The widget extension's entry point — `@main` here plays the same role it
/// does on `RizeApp` in the main app target: this is the type the process
/// actually launches into. A `WidgetBundle` is just a container that lets one
/// extension expose more than one distinct widget (each with its own `kind`,
/// its own entry in the "add widget" gallery) — this one groups the Home
/// Screen widget (`RizeHomeWidget`, small/medium/large), the Lock Screen
/// widget (`RizeLockScreenWidget`, circular/rectangular/inline), and the
/// Sports/Activity widget (`RizeSportsWidget`, small/medium) so the user
/// sees all three when they search "Rize" while adding a widget.
@main
struct RizeWidgetBundle: WidgetBundle {
    var body: some Widget {
        RizeHomeWidget()
        RizeLockScreenWidget()
        RizeSportsWidget()
    }
}
