import SwiftUI
import UIKit

/// A compact, system-style tab bar with Apple's Liquid Glass background on iOS 26 and later.
struct MorphingTabBar<Tab: MorphingTabProtocol & CaseIterable, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    /// Which cases to show, in order. Defaults to every case; pass a filtered
    /// list to hide tabs conditionally (e.g. based on the user's onboarding
    /// goal) without touching the underlying `CaseIterable` enum.
    var tabs: [Tab] = Array(Tab.allCases)
    @ViewBuilder var expandedContent: ExpandedContent
    @State private var viewWidth: CGFloat?

    var body: some View {
        ZStack {
            let selectedIndex = Binding {
                tabs.firstIndex(where: { $0.symbolImage == activeTab.symbolImage }) ?? 0
            } set: { newIndex in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    activeTab = tabs[newIndex]
                }
            }

            if let viewWidth {
                let labelSize = CGSize(width: viewWidth, height: 52)
                let cornerRadius = labelSize.height / 2

                ZStack {
                    TabBarGlassBackground(cornerRadius: cornerRadius)

                    CustomTabBar(tabs: tabs, index: selectedIndex)
                }
                .frame(width: labelSize.width, height: labelSize.height)

                if isExpanded {
                    expandedContent
                        .padding()
                }
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { newValue in
            viewWidth = newValue
        }
        .frame(height: viewWidth == nil ? 52 : nil)
    }
}

/// Real Apple Liquid Glass background (see `glassEffect(_:in:)` in the SwiftUI docs).
/// Falls back to a material approximation on iOS versions before Liquid Glass shipped.
private struct TabBarGlassBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }
}

private struct CustomTabBar<Tab: MorphingTabProtocol & CaseIterable>: UIViewRepresentable {
    var tabs: [Tab]
    @Binding var index: Int

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: tabs.map { symbolImage(for: $0) ?? UIImage() })
        control.selectedSegmentIndex = index
        control.backgroundColor = .clear
        // Highlight pill tinted to the app's amber-gold accent instead of plain white.
        control.selectedSegmentTintColor = UIColor(PhoenixPalette.primary).withAlphaComponent(0.22)
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)

        applyIconTint(control)

        DispatchQueue.main.async {
            for view in control.subviews.dropLast() {
                if view is UIImageView {
                    view.alpha = 0
                }
            }
        }

        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }
        applyIconTint(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private func symbolImage(for tab: Tab) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 18, weight: .semibold))
        return UIImage(systemName: tab.symbolImage, withConfiguration: configuration)
    }

    private func applyIconTint(_ control: UISegmentedControl) {
        for i in tabs.indices {
            let isSelected = i == index
            // Selected icon glows in the app's amber-gold accent; unselected stays muted.
            let color: UIColor = isSelected ? UIColor(PhoenixPalette.primary) : .secondaryLabel
            if let base = symbolImage(for: tabs[i]) {
                control.setImage(base.withTintColor(color, renderingMode: .alwaysOriginal), forSegmentAt: i)
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: CustomTabBar
        init(parent: CustomTabBar) {
            self.parent = parent
        }
        @objc func valueChanged(_ sender: UISegmentedControl) {
            parent.index = sender.selectedSegmentIndex
        }
    }
}
