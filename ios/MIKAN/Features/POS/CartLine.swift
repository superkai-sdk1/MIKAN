import Foundation

struct CartLine: Identifiable, Hashable {
    enum Kind: Hashable {
        /// One size of a product (a product without sizes has one unnamed size); `stock` — that size's quantity
        /// when it was added.
        case product(id: Int, variantId: Int, stock: Int)
        case service(id: Int?)
    }

    let id: UUID
    let kind: Kind
    var name: String
    /// Size of a product line («8 мм»); `nil` for services and a product without sizes.
    let sizeName: String?
    var quantity: Int
    var unitPrice: Int
    /// Jewelry or goods for a product line (drives its icon); `nil` for services.
    let productKind: ProductKind?

    init(
        kind: Kind,
        name: String,
        sizeName: String? = nil,
        quantity: Int = 1,
        unitPrice: Int,
        productKind: ProductKind? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.name = name
        self.sizeName = sizeName.nonEmpty
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.productKind = productKind
    }

    /// A line of a saved open receipt. A product line without its product or size cannot be sold, so it is `nil`
    /// (the server always saves both); a size that is gone has no stock left.
    init?(item: OpenReceiptItem) {
        switch item.type {
        case .product:
            guard let productId = item.productId, let variantId = item.variantId else { return nil }
            self.init(
                kind: .product(id: productId, variantId: variantId, stock: item.stock ?? 0),
                name: item.name,
                sizeName: item.variantName,
                quantity: item.quantity,
                unitPrice: item.price,
                productKind: item.productKind
            )
        case .service:
            self.init(kind: .service(id: item.serviceId), name: item.name, quantity: item.quantity, unitPrice: item.price)
        }
    }

    /// Symbol of the line: a service, a piece of jewelry or other goods.
    var symbol: String {
        guard productId != nil else { return "hands.and.sparkles" }
        return productKind == .goods ? CatalogSection.goods.symbol : CatalogSection.jewelry.symbol
    }

    var total: Int { quantity * unitPrice }

    var productId: Int? {
        if case .product(let id, _, _) = kind { return id }
        return nil
    }

    var variantId: Int? {
        if case .product(_, let variantId, _) = kind { return variantId }
        return nil
    }

    /// Stock of the line's size; `nil` for services.
    var stock: Int? {
        if case .product(_, _, let stock) = kind { return stock }
        return nil
    }

    var isValid: Bool { quantity > 0 && unitPrice >= 0 && !name.trimmed.isEmpty }

    /// Lines of one size share its stock (the same size at an edited price is a separate line).
    func isSameSize(as other: CartLine) -> Bool {
        guard let productId, let variantId else { return false }
        return productId == other.productId && variantId == other.variantId
    }

    var body: SaleItemBody {
        switch kind {
        case .product(let id, let variantId, _):
            SaleItemBody(
                type: .product, productId: id, serviceId: nil, name: nil, quantity: quantity, price: unitPrice,
                variantId: variantId
            )
        case .service(let id):
            SaleItemBody(type: .service, productId: nil, serviceId: id, name: name.trimmed, quantity: quantity, price: unitPrice)
        }
    }
}
