import Foundation

/// Pure rules for the «+ Услуга» picker: which services are «Популярные» and how search matches.
nonisolated enum ServicePicking {
    static let popularLimit = 6
    /// How far back sales count towards popularity.
    static let popularityWindowDays = 90

    /// Most sold active services first (by quantity in the report), then the catalog order fills the rest,
    /// so a new studio without sales still sees a useful shortlist.
    static func popular(services: [Service], top: [TopService], limit: Int = popularLimit) -> [Service] {
        let active = services.filter(\.active)
        let byId = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var picked: [Service] = []
        var seen = Set<Int>()
        for item in top.sorted(by: { $0.quantity > $1.quantity }) {
            guard let id = item.serviceId, let service = byId[id], !seen.contains(id) else { continue }
            picked.append(service)
            seen.insert(id)
            if picked.count == limit { return picked }
        }
        for service in catalogOrder(active) where !seen.contains(service.id) {
            picked.append(service)
            if picked.count == limit { break }
        }
        return picked
    }

    /// Active services whose name or category matches every word of the query (case- and «ё»-insensitive).
    static func search(_ services: [Service], query: String) -> [Service] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return catalogOrder(services.filter(\.active)).filter { service in
            let haystack = normalize("\(service.name) \(service.category.title)")
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    static func catalogOrder(_ services: [Service]) -> [Service] {
        services.sorted { ($0.sort, normalize($0.name)) < ($1.sort, normalize($1.name)) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
