import Foundation

// MARK: - Open receipts (POS)

extension APIClient {
    /// All open receipts, oldest first.
    func openReceipts() async throws -> [OpenReceipt] {
        let response: ItemsResponse<OpenReceipt> = try await request(.get, "receipts")
        return response.items
    }

    /// `404` when it was paid or deleted meanwhile.
    func openReceipt(id: Int) async throws -> OpenReceipt {
        try await request(.get, "receipts/\(id)")
    }

    /// With `appointmentId` it returns the appointment's receipt if one is already open (another device started
    /// the visit).
    func createReceipt(_ body: ReceiptBody, idempotencyKey: UUID) async throws -> OpenReceipt {
        try await request(.post, "receipts", body: body, idempotencyKey: idempotencyKey)
    }

    /// Replaces the whole receipt. `404` when it was paid or deleted on another device.
    func updateReceipt(id: Int, _ body: ReceiptBody) async throws -> OpenReceipt {
        try await request(.put, "receipts/\(id)", body: body)
    }

    /// Nothing is sold or returned: the stock and a held prepayment stay as they are. A receipt that is already gone
    /// (paid or deleted elsewhere) counts as deleted.
    func deleteReceipt(id: Int) async throws {
        do {
            try await requestVoid(.delete, "receipts/\(id)")
        } catch let error as APIError where error.status == 404 {
            return
        }
    }
}
