import Foundation

extension POSCatalog {
    /// The product kind the segment sells; `nil` for services.
    var productKind: ProductKind? {
        switch self {
        case .jewelry: .jewelry
        case .goods: .goods
        case .services: nil
        }
    }
}

/// Products of one category under its title (pickers list them this way).
nonisolated struct ProductCategoryGroup: Identifiable, Hashable, Sendable {
    let title: String
    let products: [Product]

    var id: String { title }
}

/// Segments and category order of the product catalogs (POS jewelry and goods, the service editor's pickers).
nonisolated extension ProductCatalogFilter {
    /// Group of the products without a category; it goes last.
    static let uncategorizedTitle = "Без категории"

    static func products(_ products: [Product], kind: ProductKind) -> [Product] {
        products.filter { $0.kind == kind }
    }

    /// Categories the products of `kind` carry, in the warehouse order of that section;
    /// names the registry lacks follow alphabetically, empty categories are left out.
    static func categories(of products: [Product], kind: ProductKind, registry: [CatalogCategory]) -> [String] {
        let names = Self.products(products, kind: kind).compactMap(\.category.nonEmpty)
        let present = Set(names)
        return registry.orderedNames(CatalogSection(kind: kind), including: names).filter(present.contains)
    }

    /// One segment of the catalog: products of `kind` in `category` (all when `nil` or no longer present)
    /// that match `query`.
    static func apply(_ products: [Product], kind: ProductKind, query: String, category: String?) -> [Product] {
        let segment = Self.products(products, kind: kind)
        let isPresent = category.map { name in segment.contains { $0.category.nonEmpty == name } } ?? false
        return apply(segment, query: query, category: isPresent ? category : nil)
    }

    /// Products grouped by category in the order of `categories`, «Без категории» last; the input order is kept
    /// inside a group.
    static func grouped(_ products: [Product], categories: [String]) -> [ProductCategoryGroup] {
        let named = categories.compactMap { title -> ProductCategoryGroup? in
            let items = products.filter { $0.category.nonEmpty == title }
            return items.isEmpty ? nil : ProductCategoryGroup(title: title, products: items)
        }
        let listed = Set(categories)
        let rest = products.filter { !listed.contains($0.category.nonEmpty ?? "") }
        return rest.isEmpty ? named : named + [ProductCategoryGroup(title: uncategorizedTitle, products: rest)]
    }
}

#if DEBUG
extension PreviewData {
    static let aftercareSpray = Product(
        id: 21, kind: .goods, name: "Спрей для ухода", sku: "SPR-50", category: "Уход", material: nil,
        size: nil, description: "Солевой спрей для заживающих проколов.", price: 900, cost: 350,
        quantity: 0, minQuantity: 0, unit: "шт", photoUrl: nil, active: true, lowStock: false,
        variants: [
            ProductVariant(id: 31, name: "50 мл", sku: nil, price: nil, cost: nil, quantity: 6, minQuantity: 2, lowStock: false),
            ProductVariant(id: 32, name: "100 мл", sku: nil, price: 1400, cost: 520, quantity: 1, minQuantity: 2, lowStock: true),
        ],
        createdAt: now, updatedAt: now
    )
}
#endif
