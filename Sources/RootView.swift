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

struct TabBar: View {
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<TABS.count, id: \.self) { i in
                Button(action: {
                    selected = i
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: TABS[i].symbol)
                            .font(.system(size: 18, weight: .semibold))
                        Text(TABS[i].title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(i == selected ? .white : Theme.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(i == selected ? Theme.blue : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(6)
        .animation(.easeInOut(duration: 0.3), value: selected)
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
    }
}
