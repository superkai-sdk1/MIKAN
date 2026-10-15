import SwiftUI

@main
struct MIKANApp: App {
    @State private var appState = AppState.live()

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
