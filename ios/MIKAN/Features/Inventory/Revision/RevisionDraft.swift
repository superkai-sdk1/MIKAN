import Foundation

/// One size to count: the stock the system expects and what a unit costs (for the value of differences).
nonisolated struct RevisionSize: Identifiable, Hashable, Sendable {
    /// The variant id.
    let id: Int
    let name: String
    let expected: Int
    /// `variant.cost ?? product.cost`; unknown costs count as 0, as on the server.
    let unitCost: Int

    /// «8 мм», «Без размера».
    var title: String { InventoryText.sizeTitle(name) }
}

/// A product of the count: its sizes, or the expected status of a presence consumable.
nonisolated struct RevisionProduct: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let category: String?
    let unit: String
    let photoPath: String?
    /// Empty for a presence consumable.
    let sizes: [RevisionSize]
    /// The marked status of a presence consumable; `nil` for counted products.
    let expectedStatus: PresenceStatus?

    var isPresence: Bool { expectedStatus != nil }
    var hasSeveralSizes: Bool { sizes.count > 1 }

    init(_ product: Product) {
        id = product.id
        name = product.name
        category = product.category.nonEmpty
        unit = product.unitLabel
        photoPath = product.photoUrl
        if product.isPresenceTracked {
            sizes = []
            expectedStatus = product.presenceStatus ?? .ok
        } else {
            sizes = product.variants.map {
                RevisionSize(id: $0.id, name: $0.name, expected: $0.quantity, unitCost: max(0, product.cost(of: $0) ?? 0))
            }
            expectedStatus = nil
        }
    }
}

/// Which lines the counting screen shows.
nonisolated enum RevisionLineFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unchecked
    case changed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Все"
        case .unchecked: "Не проверено"
        case .changed: "Расхождения"
        }
    }
}

/// Pure state of a stock count (ревизия) of one warehouse section (`POST /stock/revisions`).
///
/// Every size starts at its expected stock, but only lines the employee checked go to the server: a typed or stepped
/// count, a «сходится» tick, or a marked availability. So a partial count (one shelf) is a valid revision, and
/// «Остальное сходится» marks the rest in one tap.
nonisolated struct RevisionDraft: Hashable, Sendable {
    let section: CatalogSection
    var note = ""
    /// Products by category in the registry's staff order, «Без категории» last.
    let groups: [ProductGroup<RevisionProduct>]
    /// Counted stock per variant id; absent — not checked yet.
    private(set) var counts: [Int: Int] = [:]
    /// Marked status per presence product id; absent — not checked yet.
    private(set) var marks: [Int: PresenceStatus] = [:]

    /// Products of the section's kind; hidden ones only while they still have stock (they are on the shelf).
    init(section: CatalogSection, products: [Product], categories: [CatalogCategory]) {
        self.section = section
        let counted = products.filter { product in
            guard product.kind == section.productKind else { return false }
            return product.active || (!product.isPresenceTracked && product.quantity > 0)
        }
        groups = WarehouseGrouping.groups(
            counted.map(RevisionProduct.init),
            section: section,
            categories: categories,
            category: \.category,
            name: \.name
        )
    }

    var products: [RevisionProduct] { groups.flatMap(\.items) }
    var isEmpty: Bool { groups.isEmpty }

    private var allSizes: [RevisionSize] { products.flatMap(\.sizes) }
    private var presenceProducts: [RevisionProduct] { products.filter(\.isPresence) }

    // MARK: Lines

    /// The number in the size's field: the counted stock, or the expected one until checked.
    func count(for size: RevisionSize) -> Int { counts[size.id] ?? size.expected }

    func isChecked(_ size: RevisionSize) -> Bool { counts[size.id] != nil }

    /// Counted − expected of a checked size; `nil` while not checked.
    func delta(for size: RevisionSize) -> Int? { counts[size.id].map { $0 - size.expected } }

    /// The status on screen: the marked one, or the expected one until checked.
    func status(for product: RevisionProduct) -> PresenceStatus? { marks[product.id] ?? product.expectedStatus }

    func isChecked(_ product: RevisionProduct) -> Bool {
        product.isPresence ? marks[product.id] != nil : product.sizes.allSatisfy(isChecked)
    }

    /// A checked line differs from what the system expects.
    func isChanged(_ size: RevisionSize) -> Bool { (delta(for: size) ?? 0) != 0 }

    func isChanged(_ product: RevisionProduct) -> Bool {
        if product.isPresence {
            guard let mark = marks[product.id] else { return false }
            return mark != product.expectedStatus
        }
        return product.sizes.contains(where: isChanged)
    }

    // MARK: Editing (each returns a new draft)

    /// Sets the counted stock (never below 0) and marks the size checked; `nil` clears the check.
    func settingCount(_ value: Int?, for sizeId: Int) -> RevisionDraft {
        guard allSizes.contains(where: { $0.id == sizeId }) else { return self }
        var copy = self
        copy.counts[sizeId] = value.map { max(0, $0) }
        return copy
    }

    /// ± one unit from what the field shows; checks the size.
    func adjustingCount(for sizeId: Int, by step: Int) -> RevisionDraft {
        guard let size = allSizes.first(where: { $0.id == sizeId }) else { return self }
        return settingCount(count(for: size) + step, for: sizeId)
    }

    /// «Сходится»: the size is checked at its expected stock.
    func confirming(sizeId: Int) -> RevisionDraft {
        guard let size = allSizes.first(where: { $0.id == sizeId }) else { return self }
        return settingCount(size.expected, for: sizeId)
    }

    func markingStatus(_ status: PresenceStatus?, for productId: Int) -> RevisionDraft {
        guard presenceProducts.contains(where: { $0.id == productId }) else { return self }
        var copy = self
        copy.marks[productId] = status
        return copy
    }

    /// Back to «не проверено»: the sizes of the product, or its marked status.
    func clearing(productId: Int) -> RevisionDraft {
        guard let product = products.first(where: { $0.id == productId }) else { return self }
        var copy = self
        for size in product.sizes { copy.counts[size.id] = nil }
        copy.marks[productId] = nil
        return copy
    }

    /// «Остальное сходится»: every unchecked line of the group (or of the whole count) takes its expected value.
    func confirmingUnchecked(inGroup groupId: String? = nil) -> RevisionDraft {
        var copy = self
        for group in groups where groupId == nil || group.id == groupId {
            for product in group.items {
                if let expected = product.expectedStatus, copy.marks[product.id] == nil {
                    copy.marks[product.id] = expected
                }
                for size in product.sizes where copy.counts[size.id] == nil {
                    copy.counts[size.id] = size.expected
                }
            }
        }
        return copy
    }

    // MARK: Totals

    /// Sizes plus presence consumables.
    var lineCount: Int { allSizes.count + presenceProducts.count }

    var checkedCount: Int { counts.count + marks.count }

    var uncheckedCount: Int { lineCount - checkedCount }

    /// Checked lines that differ.
    var changedCount: Int {
        allSizes.filter(isChanged).count + presenceProducts.filter(isChanged).count
    }

    /// Units found above the expected stock, and their value at cost.
    var surplus: Int { allSizes.reduce(0) { $0 + max(0, delta(for: $1) ?? 0) } }
    var surplusCost: Int { allSizes.reduce(0) { $0 + max(0, delta(for: $1) ?? 0) * $1.unitCost } }

    /// Units missing against the expected stock, and their value at cost.
    var shortage: Int { allSizes.reduce(0) { $0 + max(0, -(delta(for: $1) ?? 0)) } }
    var shortageCost: Int { allSizes.reduce(0) { $0 + max(0, -(delta(for: $1) ?? 0)) * $1.unitCost } }

    /// Share of checked lines, 0…1, for the progress bar.
    var progress: Double { lineCount == 0 ? 0 : Double(checkedCount) / Double(lineCount) }

    // MARK: Request

    var canSubmit: Bool { checkedCount > 0 }

    /// Only checked lines, in list order: sizes of counted products and statuses of presence consumables.
    var body: StockRevisionBody {
        StockRevisionBody(
            section: section,
            note: note.nonEmpty,
            counts: allSizes.compactMap { size in
                counts[size.id].map { StockLineBody(variantId: size.id, quantity: $0) }
            },
            presence: presenceProducts.compactMap { product in
                marks[product.id].map { PresenceLineBody(productId: product.id, status: $0) }
            }
        )
    }

    // MARK: Filtering

    /// Groups as the counting screen shows them: matching the search and the line filter; empty groups dropped.
    func visibleGroups(search: String, filter: RevisionLineFilter) -> [ProductGroup<RevisionProduct>] {
        let words = InventoryFilter.normalized(search).split(whereSeparator: \.isWhitespace).map(String.init)
        return groups.compactMap { group in
            let items = group.items.filter { product in
                switch filter {
                case .all: break
                case .unchecked: if isChecked(product) { return false }
                case .changed: if !isChanged(product) { return false }
                }
                guard !words.isEmpty else { return true }
                let fields = ([product.name, product.category ?? ""] + product.sizes.map(\.name)).map(InventoryFilter.normalized)
                return words.allSatisfy { word in fields.contains { $0.contains(word) } }
            }
            return items.isEmpty ? nil : ProductGroup(category: group.category, items: items)
        }
    }

    /// Unchecked lines of one group: the «Сходится» button of its header is shown while there are some.
    func uncheckedCount(inGroup groupId: String) -> Int {
        guard let group = groups.first(where: { $0.id == groupId }) else { return 0 }
        return group.items.reduce(0) { sum, product in
            if product.isPresence { return sum + (marks[product.id] == nil ? 1 : 0) }
            return sum + product.sizes.filter { counts[$0.id] == nil }.count
        }
    }
}
