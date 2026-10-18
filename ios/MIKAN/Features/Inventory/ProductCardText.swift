import Foundation

// Pure texts and lists of the product card: size names, markup, suitable services.

/// Size names typed at once in «Добавить размеры…».
nonisolated enum ProductSizeNames {
    /// "6, 8, 10 мм" → «6 мм», «8 мм», «10 мм»: the unit of the last name is added to the bare numbers before it.
    /// Separators: comma, semicolon, new line (decimals are written with a dot: «1.2×8 мм»). Repeats are dropped.
    static func parse(_ text: String) -> [String] {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .compactMap { String($0).nonEmpty }
        guard let last = parts.last else { return [] }
        let suffix = unitSuffix(of: last)
        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            let name = part.last?.isNumber == true ? part + suffix : part
            guard seen.insert(InventoryFilter.normalized(name)).inserted else { continue }
            result.append(name)
        }
        return result
    }

    /// What follows the last digit: " мм" in «10 мм», "" in «L» or «12».
    private static func unitSuffix(of name: String) -> String {
        guard let lastDigit = name.lastIndex(where: \.isNumber) else { return "" }
        return String(name[name.index(after: lastDigit)...])
    }
}

/// Markup = price − cost, with its share of the cost.
nonisolated enum ProductMarkup {
    /// «+900 ₽ · 150%»; just the amount when the cost is 0; `nil` without a cost or a price.
    static func text(price: Int, cost: Int?) -> String? {
        guard let cost, price > 0 else { return nil }
        let markup = price - cost
        let amount = Money.formatSigned(markup)
        guard cost > 0 else { return amount }
        let percent = Int((Double(markup) / Double(cost) * 100).rounded())
        let percentText = percent < 0 ? Money.minus + String(-percent) : String(percent)
        return "\(amount) · \(percentText)%"
    }
}

/// Catalog services a piece of jewelry suits («Хеликс», «Септум»).
nonisolated enum ProductServiceOptions {
    /// Piercing first: those are the zones jewelry is for.
    static let categoryOrder: [ServiceCategory] = [.piercing, .other, .tattoo]

    /// In `categoryOrder`, catalog order inside a category.
    /// Hidden services are offered only when already linked, so a link is never lost silently.
    static func options(_ services: [Service], selected: [Int]) -> [Service] {
        let visible = services.filter { $0.active || selected.contains($0.id) }
        return categoryOrder.flatMap { category in
            ServiceCatalog.sorted(visible.filter { $0.category == category })
        }
    }

    /// Names of the linked services in the order they were linked; unknown ids are skipped.
    static func names(of ids: [Int], in services: [Service]) -> [String] {
        ids.compactMap { id in services.first { $0.id == id }?.name }
    }
}

/// Small texts shared by the stock screens.
nonisolated enum InventoryText {
    /// The size's name, or «Без размера» for the only size of a product without sizes.
    static func sizeTitle(_ name: String?) -> String {
        name.nonEmpty ?? "Без размера"
    }

    /// «4 шт».
    static func quantity(_ quantity: Int, unit: String) -> String {
        "\(quantity) \(unit)"
    }
}
