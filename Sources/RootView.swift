import SwiftUI

struct TabItem {
    let title: String
    let symbol: String
}

let TABS: [TabItem] = [
    TabItem(title: "总览", symbol: "house.fill"),
    TabItem(title: "仪表", symbol: "speedometer"),
    TabItem(title: "车况", symbol: "car.fill"),
    TabItem(title: "行程", symbol: "chart.bar.fill"),
    TabItem(title: "设置", symbol: "gearshape.fill")
]

/// 底部导航：滑块用 offset 动画（只动合成层，比 matchedGeometryEffect 省很多）
struct TabBar: View {
    @Binding var selected: Int

    private let barHeight: CGFloat = 64
    private let inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(TABS.count)
            let tileW = max(1, (geo.size.width - inset * 2) / count)
            let tileH = max(1, geo.size.height - inset * 2)

            ZStack(alignment: .topLeading) {
                // 滑块
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.blue)
                    .frame(width: tileW, height: tileH)
                    .offset(x: inset + CGFloat(selected) * tileW, y: inset)
                    .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.9), value: selected)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(0..<TABS.count, id: \.self) { i in
                        Button(action: {
                            dismissKeyboard()
                            // 不加 withAnimation：滑块自己按 value 变化做动画，
                            // 页面切换交给 TabView 的翻页动画，避免两套动画互相抢帧
                            selected = i
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: TABS[i].symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(TABS[i].title)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(i == selected ? .white : Theme.sub)
                            .frame(width: tileW, height: tileH)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(inset)
            }
        }
        .frame(height: barHeight)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card.opacity(0.96))
                .shadow(color: Theme.blueDeep.opacity(0.12), radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

struct RootView: View {
    @EnvironmentObject var store: CarStore
    @State private var tab = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            TabView(selection: $tab) {
                OverviewView().tag(0)
                DashboardView().tag(1)
                DiagnosisView().tag(2)
                TripView().tag(3)
                SettingsView().tag(4)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .padding(.bottom, 88)

            TabBar(selected: $tab)
        }
        .onAppear { store.start() }
        .onChange(of: tab) { _ in dismissKeyboard() }
    }
}
