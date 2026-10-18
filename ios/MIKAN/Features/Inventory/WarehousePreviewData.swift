#if DEBUG
import Foundation

/// Warehouse samples for previews: goods, a presence consumable, categories and a stock count.
extension PreviewData {
    static let antiseptic: Product = {
        var product = Product(
            id: 15, kind: .consumable, name: "Антисептик Октенисепт", sku: nil, category: "Дезинфекция", material: nil,
            supplier: "Медтехника", size: nil, description: nil, price: 0, cost: 450, quantity: 0, minQuantity: 0,
            unit: "фл", photoUrl: nil, active: true, lowStock: false, createdAt: now, updatedAt: now
        )
        product.stockMode = .presence
        product.presenceStatus = .low
        return product
    }()

    static let spray = Product(
        id: 21, kind: .goods, name: "Спрей для ухода за проколом", sku: "SP-01", category: "Уход", material: nil,
        supplier: "H2Ocean", size: nil, description: "Морская соль, без спирта.", price: 1200, cost: 650,
        quantity: 0, minQuantity: 0, unit: "шт", photoUrl: nil, active: true, lowStock: false,
        variants: [
            ProductVariant(id: 31, name: "50 мл", sku: nil, price: nil, cost: nil, quantity: 6, minQuantity: 2, lowStock: false),
            ProductVariant(id: 32, name: "100 мл", sku: nil, price: 1900, cost: 1000, quantity: 1, minQuantity: 2, lowStock: true),
        ],
        createdAt: now, updatedAt: now
    )

    static let warehouseProducts = [labret, ring, needles, antiseptic, spray]

    static let categories = [
        CatalogCategory(id: 1, section: .jewelry, serviceCategory: nil, name: "Лабрет", position: 0, itemCount: 12),
        CatalogCategory(id: 2, section: .jewelry, serviceCategory: nil, name: "Кольцо", position: 1, itemCount: 7),
        CatalogCategory(id: 3, section: .consumable, serviceCategory: nil, name: "Иглы", position: 0, itemCount: 5),
        CatalogCategory(id: 4, section: .consumable, serviceCategory: nil, name: "Дезинфекция", position: 1, itemCount: 3),
        CatalogCategory(id: 5, section: .goods, serviceCategory: nil, name: "Уход", position: 0, itemCount: 2),
        CatalogCategory(id: 6, section: .service, serviceCategory: .piercing, name: "Ухо", position: 0, itemCount: 9),
        CatalogCategory(id: 7, section: .service, serviceCategory: .piercing, name: "Лицо", position: 1, itemCount: 4),
        CatalogCategory(id: 8, section: .service, serviceCategory: .tattoo, name: "Тату", position: 0, itemCount: 3),
    ]

    static let revision = StockRevision(
        id: 3, number: 3, section: .consumable, note: "Конец месяца", employee: anna.ref,
        counted: 24, changed: 3, surplus: 2, shortage: 5, surplusCost: 80, shortageCost: 1200,
        presenceChanges: [
            StockRevision.PresenceChange(productId: 15, productName: "Антисептик Октенисепт", from: .ok, to: .low),
        ],
        movements: [
            StockMovement(
                id: 40, productId: 3, productName: "Иглы 1.2 мм", variantId: 3, variantName: "", delta: -5, quantityAfter: 43,
                type: .adjustment, note: "Ревизия №3 · Конец месяца", saleId: nil, appointmentId: nil, revisionId: 3,
                employee: anna.ref, createdAt: now
            ),
        ],
        createdAt: now
    )
}
#endif
