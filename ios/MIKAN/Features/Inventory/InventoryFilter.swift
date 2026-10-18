import Foundation

/// What the stock list shows: search text, «Мало» and the category / material / size / availability facets.
/// The list loads every product of a kind once and filters on the client, so all of this is pure.
nonisolated struct InventoryFilter: Hashable, Sendable {
    /// `nil` — every kind (the screen always sets one).
    var kind: ProductKind?
    var search = ""
    /// Products with at least one size at or below its minimum, and presence consumables not marked «есть».
    var lowOnly = false
    var category: String?
    var material: String?
    /// A size name: products that have a size with this name.
    var size: String?
    /// Presence consumables marked with this status (counted products never match).
    var presence: PresenceStatus?

    init(
        kind: ProductKind? = nil,
        search: String = "",
        lowOnly: Bool = false,
        category: String? = nil,
        material: String? = nil,
        size: String? = nil,
        presence: PresenceStatus? = nil
    ) {
        self.kind = kind
        self.search = search
        self.lowOnly = lowOnly
        self.category = category
        self.material = material
        self.size = size
        self.presence = presence
    }

    // MARK: State

    /// Number of chosen facets (category, material, size, availability) — the badge on the filter button.
    var facetCount: Int { [category, material, size].compactMap(\.nonEmpty).count + (presence == nil ? 0 : 1) }

    /// Something narrows the list besides the kind.
    var isActive: Bool { facetCount > 0 || lowOnly || !search.trimmed.isEmpty }

    /// The same filter without facets, «Мало» and search (the kind stays).
    var cleared: InventoryFilter { InventoryFilter(kind: kind) }

    /// Without category, material and size; search and «Мало» stay.
    var withoutFacets: InventoryFilter { InventoryFilter(kind: kind, search: search, lowOnly: lowOnly) }

    /// Facets depend on the kind's products, so switching the kind drops them; search and «Мало» stay.
    func switching(to kind: ProductKind) -> InventoryFilter {
        InventoryFilter(kind: kind, search: search, lowOnly: lowOnly)
    }

    // MARK: Matching

    func apply(_ products: [Product]) -> [Product] {
        let words = Self.words(search)
        return products.filter { matches($0, words: words) }
    }

    func matches(_ product: Product) -> Bool {
        matches(product, words: Self.words(search))
    }

    private func matches(_ product: Product, words: [String]) -> Bool {
        if let kind, product.kind != kind { return false }
        if lowOnly && !product.lowStock { return false }
        if let category = category.nonEmpty, Self.key(product.category) != Self.key(category) { return false }
        if let material = material.nonEmpty, Self.key(product.material) != Self.key(material) { return false }
        if let size = size.nonEmpty, !product.variants.contains(where: { Self.key($0.name) == Self.key(size) }) {
            return false
        }
        if let presence, !product.isPresenceTracked || product.presenceStatus != presence { return false }
        guard !words.isEmpty else { return true }
        let haystack = Self.searchFields(of: product).map(Self.normalized)
        return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
    }

    /// Name, SKUs (product and sizes), category, material, colour, stone, supplier, size names and thickness.
    static func searchFields(of product: Product) -> [String] {
        let fixed: [String?] = [
            product.name, product.sku, product.category, product.material,
            product.color, product.stone, product.supplier, product.thicknessText,
        ]
        let sizes = product.variants.flatMap { [$0.name, $0.sku ?? ""] }
        return (fixed.compactMap { $0 } + sizes).filter { !$0.isEmpty }
    }

    // MARK: Options

    /// Categories of the loaded products, once each, in natural order.
    static func categories(in products: [Product]) -> [String] {
        uniqueSorted(products.map(\.category))
    }

    static func materials(in products: [Product]) -> [String] {
        uniqueSorted(products.map(\.material))
    }

    /// Size names of the loaded products: «6 мм», «8 мм», «10 мм» (numbers compare as numbers).
    /// Presence consumables have no sizes to count, so theirs are not offered.
    static func sizes(in products: [Product]) -> [String] {
        uniqueSorted(products.filter { !$0.isPresenceTracked }.flatMap { $0.variants.map(\.name) })
    }

    /// Whether the availability facet makes sense: some loaded product is tracked as «есть / нет».
    static func hasPresence(in products: [Product]) -> Bool {
        products.contains(where: \.isPresenceTracked)
    }

    // MARK: Text

    /// Lowercased, trimmed, «ё» read as «е».
    static func normalized(_ text: String) -> String {
        text.trimmed.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private static func key(_ text: String?) -> String { normalized(text ?? "") }

    private static func words(_ query: String) -> [String] {
        normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Distinct non-empty values (case- and «ё»-insensitive, the first spelling wins), sorted naturally.
    private static func uniqueSorted(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let value = value.nonEmpty, seen.insert(normalized(value)).inserted else { continue }
            result.append(value)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
