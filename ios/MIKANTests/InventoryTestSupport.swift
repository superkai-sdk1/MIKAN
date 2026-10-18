import Foundation
@testable import MIKAN

/// Builders for the stock tests.
enum InventoryFixtures {
    static func size(
        _ id: Int,
        _ name: String,
        quantity: Int = 0,
        min: Int = 0,
        sku: String? = nil,
        price: Int? = nil,
        cost: Int? = nil
    ) -> ProductVariant {
        ProductVariant(
            id: id, name: name, sku: sku, price: price, cost: cost,
            quantity: quantity, minQuantity: min, lowStock: quantity <= min
        )
    }

    static func product(
        id: Int = 1,
        kind: ProductKind = .jewelry,
        name: String = "Лабрет",
        sku: String? = nil,
        category: String? = nil,
        material: String? = nil,
        threadType: ThreadType? = nil,
        thicknessMm: Double? = nil,
        color: String? = nil,
        stone: String? = nil,
        supplier: String? = nil,
        price: Int = 1_500,
        cost: Int? = 600,
        unit: String? = "шт",
        photos: [String] = [],
        serviceIds: [Int] = [],
        active: Bool = true,
        variants: [ProductVariant]? = nil,
        quantity: Int = 0,
        minQuantity: Int = 0
    ) -> Product {
        Product(
            id: id, kind: kind, name: name, sku: sku, category: category, material: material,
            threadType: threadType, thicknessMm: thicknessMm, color: color, stone: stone, supplier: supplier,
            size: nil, description: nil, price: price, cost: cost, quantity: quantity, minQuantity: minQuantity,
            unit: unit, photos: photos, photoUrl: nil, serviceIds: serviceIds, active: active,
            lowStock: quantity <= minQuantity, variants: variants,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    /// A labret in three sizes: 6 мм (4, min 1), 8 мм (1, min 2 — low), 10 мм (0 — out, own SKU and price).
    static let labret = product(
        sku: "LB-12", category: "Лабрет", material: "Титан ASTM F136", threadType: .internalThread, thicknessMm: 1.2,
        color: "Серебристый", stone: "Фианит", supplier: "Industrial Strength", serviceIds: [3],
        variants: [
            size(1, "6 мм", quantity: 4, min: 1),
            size(4, "8 мм", quantity: 1, min: 2, sku: "LB-12-08"),
            size(5, "10 мм", quantity: 0, min: 0, sku: "LB-12-10", price: 1_700, cost: 700),
        ]
    )
}
