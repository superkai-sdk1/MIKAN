import SwiftUI

@main
struct MIKANApp: App {
    @State private var appState = AppState.live()

    init() {
        // Service covers and work photos (AsyncImage → URLSession.shared) repeat across the catalog, POS grid and
        // cards; the server marks uploads immutable, so a larger shared cache avoids re-downloading them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(appState)
        }
    }
}

extension View {
    /// Injects the app state, its stores and the Russian locale/calendar.
    func appEnvironment(_ state: AppState) -> some View {
        environment(state)
            .environment(state.api)
            .environment(state.shift)
            .environment(state.cart)
            .environment(state.schedule)
            .environment(state.reference)
            .environment(\.locale, .app)
            .environment(\.calendar, .app)
    }
}
