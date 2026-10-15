import Foundation

// MARK: - Sales, cash register, reports

extension APIClient {
    func sales(from: Date? = nil, to: Date? = nil, clientId: Int? = nil, limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<Sale> {
        try await request(.get, "sales", query: queryItems([
            "from": from.map(ISO8601.string(from:)),
            "to": to.map(ISO8601.string(from:)),
            "clientId": clientId.map(String.init),
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    func sale(id: Int) async throws -> Sale {
        try await request(.get, "sales/\(id)")
    }

    func createSale(_ body: SaleBody, idempotencyKey: UUID) async throws -> Sale {
        try await request(.post, "sales", body: body, idempotencyKey: idempotencyKey)
    }

    func refundSale(id: Int, _ body: RefundBody, idempotencyKey: UUID) async throws -> Sale {
        try await request(.post, "sales/\(id)/refund", body: body, idempotencyKey: idempotencyKey)
    }

    func currentShift() async throws -> CashShift? {
        let response: CurrentShiftResponse = try await request(.get, "cash/shift/current")
        return response.shift
    }

    func openShift(openingCash: Int) async throws -> CashShift {
        try await request(.post, "cash/shift/open", body: OpenShiftBody(openingCash: openingCash))
    }

    func closeShift(closingCash: Int, note: String?) async throws -> CashShift {
        try await request(.post, "cash/shift/close", body: CloseShiftBody(closingCash: closingCash, note: note))
    }

    func addCashOperation(_ body: CashOperationBody, idempotencyKey: UUID) async throws -> CashOperation {
        try await request(.post, "cash/operations", body: body, idempotencyKey: idempotencyKey)
    }

    func shifts(limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<CashShift> {
        try await request(.get, "cash/shifts", query: queryItems([
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    func shift(id: Int) async throws -> CashShift {
        try await request(.get, "cash/shifts/\(id)")
    }

    func reportSummary(from: Date, to: Date) async throws -> ReportSummary {
        try await request(.get, "reports/summary", query: queryItems([
            "from": ISO8601.string(from: from),
            "to": ISO8601.string(from: to),
        ]))
    }
}
