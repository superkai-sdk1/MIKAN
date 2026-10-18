import Foundation

/// A section of the services list: one group of one category.
nonisolated struct ServiceCatalogSection: Identifiable, Hashable, Sendable {
    let category: ServiceCategory
    /// Group title, or `nil` when the category has no named groups (nothing to show).
    let group: String?
    /// The first section of a category carries the category header.
    let isFirstInCategory: Bool
    let services: [Service]

    var id: String { "\(category.rawValue)|\(group ?? "")" }
}

/// Pure catalog logic of the services screens: order, search, sections, group suggestions.
nonisolated enum ServiceCatalog {
    /// Section of the services without a group; it goes last in its category.
    static let ungroupedTitle = "Без группы"

    /// Catalog order, as the server sorts: `sort`, then name.
    static func sorted(_ services: [Service]) -> [Service] {
        services.sorted { ($0.sort, $0.name, $0.id) < ($1.sort, $1.name, $1.id) }
    }

    /// Replaces the service with the same id (or adds it) and keeps the catalog order.
    static func upserting(_ service: Service, into services: [Service]) -> [Service] {
        sorted(services.filter { $0.id != service.id } + [service])
    }

    /// Services whose name, description or group contain every word of the query (case- and «ё»-insensitive).
    static func filter(_ services: [Service], query: String) -> [Service] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return services }
        return services.filter { service in
            let fields = [service.name, service.description, service.group].compactMap { $0 }
            return words.allSatisfy { word in
                fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
    }

    /// Sections by category (tattoo, piercing, other), then by group in the order of the warehouse categories
    /// (`categories`; groups the registry lacks follow alphabetically), «Без группы» last. Catalog order inside a group.
    static func sections(_ services: [Service], categories: [CatalogCategory] = []) -> [ServiceCatalogSection] {
        ServiceCategory.allCases.flatMap { category in
            sections(of: category, sorted(services.filter { $0.category == category }), categories: categories)
        }
    }

    private static func sections(
        of category: ServiceCategory,
        _ items: [Service],
        categories: [CatalogCategory]
    ) -> [ServiceCatalogSection] {
        // A group literally named «Без группы» means the same as no group.
        let named = items.compactMap(\.group.nonEmpty).filter { $0 != ungroupedTitle }
        guard !named.isEmpty else {
            guard !items.isEmpty else { return [] }
            return [ServiceCatalogSection(category: category, group: nil, isFirstInCategory: true, services: items)]
        }
        let present = Set(named)
        let titles = categories
            .orderedNames(.service, serviceCategory: category, including: named)
            .filter(present.contains)
        var groups = titles.map { title in (title, items.filter { $0.group.nonEmpty == title }) }
        let ungrouped = items.filter { !present.contains($0.group.nonEmpty ?? "") }
        if !ungrouped.isEmpty { groups.append((ungroupedTitle, ungrouped)) }
        return groups.enumerated().map { index, group in
            ServiceCatalogSection(category: category, group: group.0, isFirstInCategory: index == 0, services: group.1)
        }
    }

    /// Existing group names per category, for the editor's suggestions.
    static func groupSuggestions(_ services: [Service]) -> [ServiceCategory: [String]] {
        Dictionary(grouping: services, by: \.category).mapValues { items in
            Set(items.compactMap(\.group.nonEmpty)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        .filter { !$0.value.isEmpty }
    }

    /// Next `sort` value for a new service: after the last one.
    static func nextSort(after services: [Service]) -> Int {
        (services.map(\.sort).max() ?? -1) + 1
    }
}

/// Paging of `{ items, total }` history responses.
nonisolated enum ServiceHistoryPaging {
    /// Whether another page may exist. Without `total`, a full last page means «maybe more».
    static func hasMore(loaded: Int, total: Int?, lastPageCount: Int, pageSize: Int) -> Bool {
        if let total { return loaded < total }
        return lastPageCount >= pageSize
    }

    /// Appends a page, skipping items that are already loaded.
    static func appending<Item: Identifiable>(_ page: [Item], to items: [Item]) -> [Item] {
        let known = Set(items.map(\.id))
        return items + page.filter { !known.contains($0.id) }
    }
}

extension ReferenceStore {
    /// Puts a created or edited service into the cached catalog; no-op while the catalog is not loaded yet.
    func upsertCatalogService(_ service: Service) {
        guard !services.isEmpty else { return }
        replaceServices(ServiceCatalog.upserting(service, into: services))
    }
}
