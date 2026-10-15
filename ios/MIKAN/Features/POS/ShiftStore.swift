import Foundation
import Observation

/// Current cash-register shift, shared by the POS screen and the tab bar accessory.
@Observable
final class ShiftStore {
    private let api: APIClient
    private(set) var current: CashShift?
    private(set) var hasLoaded = false
    private(set) var loadError: String?

    init(api: APIClient) {
        self.api = api
    }

    func refresh() async {
        do {
            current = try await api.currentShift()
            hasLoaded = true
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.userMessage
        }
    }

    func open(openingCash: Int) async throws {
        current = try await api.openShift(openingCash: openingCash)
        hasLoaded = true
    }

    func close(countedCash: Int, note: String?) async throws -> CashShift {
        let closed = try await api.closeShift(closingCash: countedCash, note: note)
        current = nil
        return closed
    }

    func addOperation(_ body: CashOperationBody, idempotencyKey: UUID) async throws {
        _ = try await api.addCashOperation(body, idempotencyKey: idempotencyKey)
        await refresh()
    }

    func reset() {
        current = nil
        hasLoaded = false
        loadError = nil
    }
}
