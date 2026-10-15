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
    /// Confirmed SBP QR payment; the server rejects it in `POST /sales` (see `QrPayment`).
    var qr: Int = 0

    var total: Int { cash + card + transfer + qr }
}

extension Payments {
    /// Tolerates a server without QR payments (no `qr` key).
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cash: try container.decode(Int.self, forKey: .cash),
            card: try container.decode(Int.self, forKey: .card),
            transfer: try container.decode(Int.self, forKey: .transfer),
            qr: try container.decodeIfPresent(Int.self, forKey: .qr) ?? 0
        )
    }
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
