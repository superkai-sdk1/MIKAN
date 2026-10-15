import Foundation

nonisolated struct ShiftSummary: Codable, Hashable, Sendable {
    let salesCount: Int
    let revenue: Int
    let cash: Int
    let card: Int
    let transfer: Int
    var qr: Int = 0
    let refunds: Int
    let cashRefunds: Int
    let cashIn: Int
    let cashOut: Int
}

extension ShiftSummary {
    /// Tolerates a server without QR payments (no `qr` key).
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            salesCount: try container.decode(Int.self, forKey: .salesCount),
            revenue: try container.decode(Int.self, forKey: .revenue),
            cash: try container.decode(Int.self, forKey: .cash),
            card: try container.decode(Int.self, forKey: .card),
            transfer: try container.decode(Int.self, forKey: .transfer),
            qr: try container.decodeIfPresent(Int.self, forKey: .qr) ?? 0,
            refunds: try container.decode(Int.self, forKey: .refunds),
            cashRefunds: try container.decode(Int.self, forKey: .cashRefunds),
            cashIn: try container.decode(Int.self, forKey: .cashIn),
            cashOut: try container.decode(Int.self, forKey: .cashOut)
        )
    }
}

nonisolated enum CashOperationType: String, Codable, Sendable {
    /// Внесение
    case deposit = "in"
    /// Изъятие
    case withdrawal = "out"
}

nonisolated struct CashOperation: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let shiftId: Int
    let type: CashOperationType
    let amount: Int
    let reason: String?
    let employee: EmployeeRef
    let createdAt: Date
}

nonisolated struct CashShift: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let openedAt: Date
    let openedBy: EmployeeRef
    let openingCash: Int
    let closedAt: Date?
    let closedBy: EmployeeRef?
    let closingCash: Int?
    let note: String?
    /// Live while open, frozen at close.
    let expectedCash: Int
    /// `closingCash − expectedCash` after close.
    let difference: Int?
    let summary: ShiftSummary
    /// Filled for the current shift and `GET /cash/shifts/:id`, empty in lists.
    let operations: [CashOperation]

    var isOpen: Bool { closedAt == nil }
}

nonisolated struct CurrentShiftResponse: Codable, Sendable {
    let shift: CashShift?
}
