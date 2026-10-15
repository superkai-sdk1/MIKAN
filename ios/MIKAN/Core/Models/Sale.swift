import Foundation

nonisolated enum SaleItemType: String, Codable, Sendable {
    case product
    case service
}

nonisolated enum SaleStatus: String, Codable, Sendable {
    case completed
    case refunded
}

nonisolated struct Payments: Codable, Hashable, Sendable {
    var cash: Int
    var card: Int
    var transfer: Int

    var total: Int { cash + card + transfer }
}

nonisolated struct SaleItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let type: SaleItemType
    let productId: Int?
    let serviceId: Int?
    let name: String
    let quantity: Int
    let price: Int
    let total: Int
}

nonisolated struct Sale: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let number: Int
    let client: ClientRef?
    let employee: EmployeeRef
    let appointmentId: Int?
    let shiftId: Int?
    let items: [SaleItem]
    let subtotal: Int
    let discount: Int
    let total: Int
    let payments: Payments
    var status: SaleStatus
    let note: String?
    var refundedAt: Date?
    var refundReason: String?
    let createdAt: Date

    var isRefunded: Bool { status == .refunded }
    var hasProducts: Bool { items.contains { $0.type == .product } }
    var itemsSummary: String { items.map(\.name).joined(separator: ", ") }
}
