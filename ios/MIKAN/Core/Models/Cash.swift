import Foundation

nonisolated struct ShiftSummary: Codable, Hashable, Sendable {
    let salesCount: Int
    let revenue: Int
    let cash: Int
    let card: Int
    let transfer: Int
    let refunds: Int
    let cashRefunds: Int
    let cashIn: Int
    let cashOut: Int
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
