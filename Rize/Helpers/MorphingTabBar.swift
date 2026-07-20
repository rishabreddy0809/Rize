import SwiftUI

struct MorphingTabBar<Tab: MorphingTabProtocol & CaseIterable, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    @ViewBuilder var expandedContent: ExpandedContent
    @State private var viewWidth: CGFloat?
    
    var body: some View {
        ZStack {
            Spacer()
            let symbols = Array(Tab.allCases).compactMap({ $0.symbolImage })
            let selectedIndex = Binding {
                return symbols.firstIndex(of: activeTab.symbolImage) ?? 0
            } set: { index in
                activeTab = Array(Tab.allCases)[index]
            }
            
            if let viewWidth {
                let progress: CGFloat = isExpanded ? 1 : 0
                let labelSize: CGSize = CGSize(width: viewWidth, height: 52)
                let cornerRadius: CGFloat = labelSize.height / 2
                
                HStack(spacing: 0) {
                    ForEach(symbols.indices, id: \.self) { index in
                        TabLabel(
                            symbol: symbols[index],
                            title: Array(Tab.allCases)[index].title,
                            isSelected: selectedIndex.wrappedValue == index,
                            progress: progress,
                            labelSize: labelSize,
                            cornerRadius: cornerRadius
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                activeTab = Array(Tab.allCases)[index]
                            }
                        }
                    }
                }
                .frame(height: labelSize.height)
            }
            
            if isExpanded {
                expandedContent
                    .padding()
            }
        }
    }
}

fileprivate struct TabLabel: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let progress: CGFloat
    let labelSize: CGSize
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .frame(width: labelSize.width, height: labelSize.height)
            
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 20)
                    .foregroundColor(isSelected ? Color.white : Color.gray)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? Color.white : Color.gray)
            }
        }
    }
}
