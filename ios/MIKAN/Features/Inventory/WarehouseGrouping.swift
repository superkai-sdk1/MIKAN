import Foundation

/// Products of one category on the warehouse list (or in a stock count).
nonisolated struct ProductGroup<Item: Identifiable & Hashable & Sendable>: Identifiable, Hashable, Sendable {
    /// The category name; `nil` — «Без категории».
    let category: String?
    let items: [Item]

    var id: String { category.map { "c:" + InventoryFilter.normalized($0) } ?? "none" }
    var title: String { category ?? WarehouseGrouping.uncategorizedTitle }
}

/// Splits a section's items by category in the registry's staff order (see «CatalogCategory» in docs/API.md):
/// registered categories first, then names items carry that are not registered yet, «Без категории» last.
nonisolated enum WarehouseGrouping {
    static let uncategorizedTitle = "Без категории"

    /// Groups in category order; inside a group items keep the natural order of their names. Empty groups are left out.
    static func groups<Item>(
        _ items: [Item],
        section: CatalogSection,
        categories: [CatalogCategory],
        category: (Item) -> String?,
        name: (Item) -> String
    ) -> [ProductGroup<Item>] {
        let order = categories.orderedNames(section, including: items.compactMap { category($0).nonEmpty })
        var byKey: [String: [Item]] = [:]
        var uncategorized: [Item] = []
        for item in items {
            if let value = category(item).nonEmpty {
                byKey[InventoryFilter.normalized(value), default: []].append(item)
            } else {
                uncategorized.append(item)
            }
        }
        func sortedByName(_ group: [Item]) -> [Item] {
            group.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        }
        var seen = Set<String>()
        var result: [ProductGroup<Item>] = []
        for title in order {
            let key = InventoryFilter.normalized(title)
            // A registry name and the same name in another case are one group, under the registry's spelling.
            guard seen.insert(key).inserted, let members = byKey[key], !members.isEmpty else { continue }
            result.append(ProductGroup(category: title, items: sortedByName(members)))
        }
        if !uncategorized.isEmpty {
            result.append(ProductGroup(category: nil, items: sortedByName(uncategorized)))
        }
        return result
    }

    /// The warehouse list of a product section.
    static func groups(_ products: [Product], section: CatalogSection, categories: [CatalogCategory]) -> [ProductGroup<Product>] {
        groups(products, section: section, categories: categories, category: \.category, name: \.name)
    }

    /// Category names for the editor's picker and the list filter: the registry order, then names the products carry.
    static func categoryOptions(section: CatalogSection, categories: [CatalogCategory], products: [Product], extra: [String] = []) -> [String] {
        let names = products.compactMap(\.category.nonEmpty) + extra.compactMap(\.nonEmpty)
        var seen = Set<String>()
        return categories.orderedNames(section, including: names).filter { seen.insert(InventoryFilter.normalized($0)).inserted }
    }
}
