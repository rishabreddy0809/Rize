//
//  MorphingTabBar.swift
//  Rize
//

import SwiftUI
import UIKit

protocol MorphingTabProtocol: CaseIterable, Hashable {
    var symbolImage: String { get }
}

struct MorphingTabBar<Tab: MorphingTabProtocol, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    @ViewBuilder var expandedContent: ExpandedContent
    @State private var viewWidth: CGFloat?
    var body: some View {

        ZStack {
            Spacer()
            let symbols = Array(Tab.allCases).compactMap({ $0.symbolImage})
            let selectedIndex = Binding {
                return symbols.firstIndex(of: activeTab.symbolImage) ?? 0
            } set: { Index in
                activeTab = Array(Tab.allCases)[Index]
            }


            if let viewWidth {

                let progress: CGFloat = isExpanded ? 1 : 0
                let labelSize: CGSize = CGSize(width: viewWidth, height: 52)
                let cornerRadius: CGFloat = labelSize.height / 2
                let activeCenterX = (CGFloat(selectedIndex.wrappedValue) + 0.5) / CGFloat(max(symbols.count, 1)) * labelSize.width

                ZStack {
                    GlassEffectPlaceholder(
                        alignment: .center,
                        progress: CGFloat(progress),
                        labelSize: labelSize,
                        cornerRadius: cornerRadius
                    )

                    // Subtle upward glow behind the active tab icon
                    RadialGradient(
                        colors: [PhoenixPalette.primary.opacity(0.05), .clear],
                        center: .center, startRadius: 0, endRadius: labelSize.height * 0.9
                    )
                    .frame(width: labelSize.height * 1.8, height: labelSize.height * 1.8)
                    .position(x: activeCenterX, y: labelSize.height / 2)
                    .allowsHitTesting(false)
                    .animation(Constants.springAnimation, value: selectedIndex.wrappedValue)

                    CustomTabBar(symbols: symbols, index: selectedIndex) { image in
                        let font = UIFont.systemFont(ofSize: 21)
                        let configuration = UIImage.SymbolConfiguration(font: font)
                        return UIImage(systemName: image, withConfiguration: configuration)
                    }
                }
                .frame(width: labelSize.width, height: labelSize.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(PhoenixPalette.surfaceBorder, lineWidth: 1) // fire-toned glass border
                )
                .shadow(color: Color.black.opacity(0.03), radius: 14, x: 0, y: 10) // stronger drop shadow under
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1) // subtle contact shadow


            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { newValue in
            viewWidth = newValue
        }
        .frame(height: viewWidth == nil ? 52 : nil)

    }
}

fileprivate struct CustomTabBar: UIViewRepresentable {
    var tint: Color = .gray.opacity(0.15)
    var symbols: [String]
    @Binding var index: Int
    var image: (String) -> UIImage?

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: symbols.map { title in
            if let img = image(title) {
                return img
            } else {
                return UIImage(systemName: title) ?? UIImage()
            }
        })

        control.selectedSegmentIndex = index
        control.backgroundColor = .clear
        control.selectedSegmentTintColor = UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.18) // F5A623 @ 18%
        // Increase vertical padding to make the control appear taller
        control.setContentOffset(.zero, forSegmentAt: 0) // no-op safeguard
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 18, weight: .medium)], for: .normal)
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
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

    private func applyIconTint(_ control: UISegmentedControl) {
        for i in symbols.indices {
            let isSelected = i == index
            let color = isSelected ? UIColor.label : UIColor.secondaryLabel
            if let base = image(symbols[i]) ?? UIImage(systemName: symbols[i]) {
                let tinted = base.withTintColor(color, renderingMode: .alwaysOriginal)
                control.setImage(tinted, forSegmentAt: i)
            }
        }
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        // Keep selection in sync
        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }
        applyIconTint(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: CustomTabBar
        init(parent: CustomTabBar) {
            self.parent = parent
        }
        @objc func valueChanged(_ sender: UISegmentedControl) {
            parent.index = sender.selectedSegmentIndex
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        return proposal.replacingUnspecifiedDimensions()
    }
}

fileprivate struct GlassEffectPlaceholder: View {
    var alignment: Alignment
    var progress: CGFloat
    var labelSize: CGSize
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Real Liquid Glass material per Apple's SwiftUI API:
                // https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
                GlassEffectContainer {
                    Color.clear
                        .frame(width: labelSize.width, height: labelSize.height, alignment: alignment)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PhoenixPalette.surface)
                    .frame(width: labelSize.width, height: labelSize.height, alignment: alignment)
            }
        }
        .opacity(Double(max(min(progress, 1), 0.35)))
        .allowsHitTesting(false)
    }
}

#Preview {
    MainTabView()
}
