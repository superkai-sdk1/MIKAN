import Foundation
import Observation
import os

enum AppTab: Hashable {
    case schedule
    case clients
    case pos
    case inventory
    case more
}

/// Session, badges, tab selection and the app-wide stores.
@Observable
final class AppState {
    enum Phase: Equatable {
        case signedOut
        case signedIn
    }

    static let badgePollInterval: Duration = .seconds(30)

    let api: APIClient
    let shift: ShiftStore
    let cart: CartStore
    let schedule: ScheduleStore
    let reference: ReferenceStore

    private(set) var phase: Phase
    private(set) var employee: Employee?
    private(set) var badges = Badges.zero
    var selectedTab: AppTab = .schedule
    /// Navigation inside «Касса»: other tabs land on the receipt screen by setting it.
    var posPath: [POSRoute] = []
    /// Shown on the login screen after a forced sign-out.
    var signOutNotice: String?

    @ObservationIgnored private let logger = Logger(subsystem: "com.mikanstudio.crm", category: "session")

    init(api: APIClient, employee: Employee?, phase: Phase) {
        self.api = api
        self.shift = ShiftStore(api: api)
        self.cart = CartStore()
        self.schedule = ScheduleStore(api: api)
        self.reference = ReferenceStore(api: api)
        self.employee = employee
        self.phase = phase
        api.onUnauthorized = { [weak self] in
            self?.handleUnauthorized()
        }
    }

    /// Restores the persisted session (token from the Keychain, server from UserDefaults).
    static func live() -> AppState {
        let token = Keychain.string(for: Keychain.tokenAccount)
        let api = APIClient(serverURL: ServerConfig.url, token: token)
        return AppState(api: api, employee: SessionCache.employee, phase: token == nil ? .signedOut : .signedIn)
    }

    /// «Ещё» tab badge.
    var moreBadge: Int { badges.unreadChats + badges.newBookingRequests }

    func signIn(login: String, password: String, server: String) async throws {
        guard let url = ServerConfig.normalize(server) else { throw APIError.invalidServerAddress }
        api.updateServer(url)
        let response = try await api.login(login.trimmed, password: password)
        ServerConfig.save(url)
        Keychain.set(response.token, for: Keychain.tokenAccount)
        api.updateToken(response.token)
        employee = response.employee
        SessionCache.employee = response.employee
        signOutNotice = nil
        selectedTab = .schedule
        phase = .signedIn
    }

    func signOut(notice: String? = nil) {
        Keychain.set(nil, for: Keychain.tokenAccount)
        api.updateToken(nil)
        employee = nil
        SessionCache.employee = nil
        badges = .zero
        cart.clear()
        cart.isCheckoutPresented = false
        posPath = []
        shift.reset()
        schedule.reset()
        reference.reset()
        signOutNotice = notice
        phase = .signedOut
    }

    private func handleUnauthorized() {
        guard phase == .signedIn, !isReauthenticating else { return }
        signOut(notice: "Сессия завершена. Войдите снова.")
    }

    @ObservationIgnored private var isReauthenticating = false

    /// The server revokes all tokens of an employee whose password changed.
    /// After changing your own password, sign in again with the new one (or sign out with a clear message).
    func reauthenticate(login: String, password: String) async {
        isReauthenticating = true
        defer { isReauthenticating = false }
        do {
            let response = try await api.login(login, password: password)
            Keychain.set(response.token, for: Keychain.tokenAccount)
            api.updateToken(response.token)
            employee = response.employee
            SessionCache.employee = response.employee
        } catch {
            signOut(notice: "Пароль изменён. Войдите с новым паролем.")
        }
    }

    /// Refreshes the current employee (also validates the token).
    func refreshSession() async {
        do {
            let current = try await api.me()
            employee = current
            SessionCache.employee = current
        } catch is CancellationError {
            return
        } catch {
            logger.notice("Session refresh failed: \(error.userMessage, privacy: .public)")
        }
    }

    func refreshBadges() async {
        do {
            badges = try await api.badges()
        } catch is CancellationError {
            return
        } catch {
            logger.notice("Badges refresh failed: \(error.userMessage, privacy: .public)")
        }
    }

    /// Polls badges and the cash shift while the app is active (cancelled with the calling task).
    func runPolling() async {
        while !Task.isCancelled, phase == .signedIn {
            async let badgesRefresh: Void = refreshBadges()
            async let shiftRefresh: Void = shift.refresh()
            _ = await (badgesRefresh, shiftRefresh)
            try? await Task.sleep(for: Self.badgePollInterval)
        }
    }

    /// Opens the receipt for an appointment in «Касса» (jewelry can still be added before paying).
    func startCheckout(for appointment: Appointment) {
        cart.open(appointment)
        openReceipt()
    }

    /// Opens the receipt in «Касса» with the client attached. A receipt for another client's appointment
    /// is replaced; other lines stay.
    func startSale(for client: ClientRef) {
        if let appointment = cart.appointment, appointment.client.id != client.id {
            cart.clear()
        }
        cart.client = client
        openReceipt()
    }

    /// Back to the POS hub (after a sale).
    func closeReceipt() {
        posPath = []
    }

    private func openReceipt() {
        cart.isCheckoutPresented = false
        selectedTab = .pos
        posPath = [.receipt]
    }
}
