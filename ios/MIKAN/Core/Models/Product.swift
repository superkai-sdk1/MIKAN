import Foundation

nonisolated enum ProductKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jewelry
    case consumable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jewelry: "Украшения"
        case .consumable: "Расходники"
        }
    }

    var singularTitle: String {
        switch self {
        case .jewelry: "Украшение"
        case .consumable: "Расходник"
        }
    }
}

nonisolated struct Product: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var kind: ProductKind
    var name: String
    var sku: String?
    var category: String?
    var material: String?
    var size: String?
    var description: String?
    var price: Int
    var cost: Int?
    /// Maintained only through stock movements.
    var quantity: Int
    var minQuantity: Int
    var unit: String?
    /// Path relative to the server origin, e.g. `/uploads/3f1c.jpg`.
    var photoUrl: String?
    var active: Bool
    /// Derived: `quantity <= minQuantity`.
    var lowStock: Bool
    let createdAt: Date
    var updatedAt: Date

    var unitLabel: String { unit.nonEmpty ?? "шт" }

    /// "Титан G23 · 1.2×8 мм"
    var detailLine: String {
        [material.nonEmpty, size.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }
}

nonisolated enum MovementType: String, Codable, CaseIterable, Identifiable, Sendable {
    case receipt
    case sale
    case returned = "return"
    case writeoff
    case usage
    case adjustment

    var id: String { rawValue }

    /// Movement types an employee can create manually.
    static let manual: [MovementType] = [.receipt, .writeoff, .usage, .adjustment]
}

nonisolated struct StockMovement: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let productId: Int
    let productName: String
    let delta: Int
    let quantityAfter: Int
    let type: MovementType
    let note: String?
    let saleId: Int?
    let appointmentId: Int?
    let employee: EmployeeRef?
    let createdAt: Date
}

nonisolated struct MovementResult: Codable, Sendable {
    let product: Product
    let movement: StockMovement
}
