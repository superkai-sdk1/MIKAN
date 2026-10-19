import Foundation

// MARK: - Push notifications (docs/API.md «Push notifications»)

extension AppState {
    /// After sign-in and on every launch while signed in: asks for permission once, registers with APNs and sends
    /// the token to the server (a new token arrives through the app delegate and is sent from there).
    func activatePush() async {
        guard phase == .signedIn else { return }
        await push.requestAuthorization()
        await registerPushDevice()
    }

    /// `POST /devices` for the signed-in employee once iOS gave a device token.
    func registerPushDevice() async {
        guard phase == .signedIn else { return }
        await push.register(with: api)
    }

    /// A tapped notification: its screen opens over the tabs. Ignored while signed out or for unknown events.
    func open(_ route: PushRoute?) {
        guard phase == .signedIn, let route else { return }
        pushRoute = route
        Task { await refreshBadges() }
    }
}
