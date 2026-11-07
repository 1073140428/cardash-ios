import SwiftUI
import UIKit

@main
struct ADBTVApp: App {
    @StateObject private var adb = ADBService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(adb)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var adb: ADBService
    @State private var tab = 0

    private let items: [(title: String, icon: String)] = [
        ("连接", "bolt.horizontal.circle"),
        ("应用", "square.grid.2x2"),
        ("投屏遥控", "tv"),
        ("设置", "gearshape")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                ConnectView().tag(0)
                AppsView().tag(1)
                RemoteView().tag(2)
                SettingsView().tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            bottomBar
        }
        .background(Theme.bg.ignoresSafeArea())
        // 键盘弹出时不顶起整个页面（遥控页布局固定）
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: adb.state) { newState in
            if case .connected = newState, tab == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeInOut(duration: 0.22)) { tab = 2 }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                Button {
                    dismissKeyboard()
                    withAnimation(.easeInOut(duration: 0.22)) { tab = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 19, weight: tab == i ? .semibold : .regular))
                            .frame(height: 22)
                        Text(items[i].title)
                            .font(.system(size: 10, weight: tab == i ? .semibold : .regular))
                    }
                    .foregroundColor(tab == i ? Theme.primaryDeep : Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Color.white
                .overlay(
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 0.5),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
