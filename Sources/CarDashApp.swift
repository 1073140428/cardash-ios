import SwiftUI

@main
struct CarDashApp: App {
    @StateObject private var store = CarStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}
