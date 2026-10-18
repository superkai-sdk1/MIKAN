import Foundation

// Pure logic of the service's warehouse links: compatible jewelry (the bot offers it) and the consumption norm of one
// procedure (deducted when a visit is completed).

nonisolated extension ServiceLimits {
    /// What the server accepts in `jewelryIds` and `consumables`.
    static let maxJewelry = 100
    static let maxConsumables = 50
    static let normQuantityRange = 1...1000
}

/// Operations on the compatible jewelry ids; each returns a new array.
nonisolated enum ServiceJewelryLinks {
    static func removing(_ id: Int, from ids: [Int]) -> [Int] {
        ids.filter { $0 != id }
    }

    /// The picker's selection applied to the links: kept pieces keep their place, new ones follow in catalog order.
    static func applying(selection: Set<Int>, to ids: [Int], catalogOrder: [Int]) -> [Int] {
        let kept = ids.filter(selection.contains)
        let known = Set(kept)
        let added = catalogOrder.filter { selection.contains($0) && !known.contains($0) }
        return kept + added
    }

    static func validationMessage(_ ids: [Int]) -> String? {
        ids.count > ServiceLimits.maxJewelry ? "Не больше \(ServiceLimits.maxJewelry) совместимых украшений." : nil
    }
}

/// Operations on the consumption norm; each returns a new array.
nonisolated enum ServiceConsumptionNorms {
    /// Sets the units one procedure uses, kept within 1…1000.
    static func settingQuantity(_ quantity: Int, of productId: Int, in norms: [ServiceConsumable]) -> [ServiceConsumable] {
        let range = ServiceLimits.normQuantityRange
        let clamped = min(max(quantity, range.lowerBound), range.upperBound)
        return norms.map { $0.productId == productId ? ServiceConsumable(productId: productId, quantity: clamped) : $0 }
    }

    static func removing(_ productId: Int, from norms: [ServiceConsumable]) -> [ServiceConsumable] {
        norms.filter { $0.productId != productId }
    }

    /// The picker's selection applied to the norm: kept consumables keep their place and quantity,
    /// new ones follow in catalog order with one unit.
    static func applying(selection: Set<Int>, to norms: [ServiceConsumable], catalogOrder: [Int]) -> [ServiceConsumable] {
        let kept = norms.filter { selection.contains($0.productId) }
        let known = Set(kept.map(\.productId))
        let added = catalogOrder
            .filter { selection.contains($0) && !known.contains($0) }
            .map { ServiceConsumable(productId: $0, quantity: 1) }
        return kept + added
    }

    static func validationMessage(_ norms: [ServiceConsumable]) -> String? {
        if norms.count > ServiceLimits.maxConsumables {
            return "Не больше \(ServiceLimits.maxConsumables) расходников в норме."
        }
        if norms.contains(where: { !ServiceLimits.normQuantityRange.contains($0.quantity) }) {
            return "Количество расходника — от 1 до \(ServiceLimits.normQuantityRange.upperBound)."
        }
        return nil
    }
}

/// Whether a linked product is there: sizes in stock, or the marked presence of a consumable.
nonisolated enum StockAvailability: Equatable, Sendable {
    case inStock
    case low
    case out

    init(_ product: Product) {
        if product.isPresenceTracked {
            switch product.presenceStatus ?? .ok {
            case .ok: self = .inStock
            case .low: self = .low
            case .out: self = .out
            }
        } else if !product.isAvailable {
            self = .out
        } else if product.lowStock {
            self = .low
        } else {
            self = .inStock
        }
    }

    var title: String {
        switch self {
        case .inStock: "В наличии"
        case .low: "Мало"
        case .out: "Нет в наличии"
        }
    }
}

/// Texts of the linked products.
nonisolated enum ServiceLinkText {
    /// Sizes in stock: «6 мм · 8 мм»; «4 шт» for a piece without sizes; «Нет в наличии» when nothing is left.
    static func sizesInStock(_ product: Product) -> String {
        let available = product.availableVariants
        guard !available.isEmpty else { return StockAvailability.out.title }
        let names = available.compactMap(\.name.nonEmpty)
        guard !names.isEmpty else { return "\(product.quantity) \(product.unitLabel)" }
        return names.joined(separator: " · ")
    }

    /// «2 шт» for a counted consumable, «используется» for a presence one (never deducted).
    static func norm(quantity: Int, product: Product?) -> String {
        if product?.isPresenceTracked == true { return "используется" }
        return "\(quantity) \(product?.unitLabel ?? "шт")"
    }

    /// Stock line of a consumable: «На складе: 48 шт» or the marked presence («Заканчивается»).
    static func consumableStock(_ product: Product) -> String {
        if product.isPresenceTracked {
            return "Учёт «есть / нет» · \((product.presenceStatus ?? .ok).title.lowercased())"
        }
        return "На складе: \(product.quantity) \(product.unitLabel)"
    }

    /// One-line norm summary for the card header: «3 расходника».
    static func normsCount(_ count: Int) -> String {
        Plural.count(count, one: "расходник", few: "расходника", many: "расходников")
    }
}

/// Looking up linked products in a loaded stock list.
nonisolated enum ServiceLinkedProducts {
    /// The linked products in link order; ids that are not in `products` are skipped.
    static func resolve(_ ids: [Int], in products: [Product]) -> [Product] {
        let byId = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    /// Linked ids missing from `products` (deleted on the server).
    static func missing(_ ids: [Int], in products: [Product]) -> [Int] {
        let known = Set(products.map(\.id))
        return ids.filter { !known.contains($0) }
    }

    /// What a picker offers: active products of `kind`, plus inactive ones that are already linked,
    /// so a link is never lost silently.
    static func options(_ products: [Product], kind: ProductKind, linked: Set<Int>) -> [Product] {
        products.filter { $0.kind == kind && ($0.active || linked.contains($0.id)) }
    }
}

extension APIClient {
    /// Jewelry and consumables a service links to (inactive included, so every existing link resolves).
    func serviceLinkProducts() async throws -> [Product] {
        async let jewelry = products(kind: .jewelry, includeInactive: true)
        async let consumables = products(kind: .consumable, includeInactive: true)
        return try await jewelry + consumables
    }
}
