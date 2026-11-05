import SwiftUI

@main
struct CarDashApp: App {
    @StateObject private var store = CarStore()
    @StateObject private var appearance = Appearance()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.mode.scheme)
        }
    }
}
