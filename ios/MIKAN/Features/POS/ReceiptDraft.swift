import Foundation

/// Screens pushed inside the «Касса» tab. The path lives in `AppState.posPath`, so other tabs can open a receipt.
nonisolated enum POSRoute: Hashable, Sendable {
    case receipt
    case clientPicker
    case salesHistory
    case shiftsHistory
}

/// Texts for the receipt that is being assembled in the cart.
enum ReceiptDraft {
    /// "По записи · 14:00–15:00 · Анна · Хеликс"
    static func appointmentBanner(_ appointment: Appointment) -> String {
        let time = DateText.timeRange(appointment.startsAt, appointment.endsAt)
        return "По записи · \(time) · \(appointment.client.fullName) · \(appointment.displayTitle)"
    }

    /// "Мастер Анна · предоплата 2 000 ₽ зачтётся", or with a held prepayment larger than the receipt
    /// "Мастер Анна · из предоплаты 5 000 ₽ зачтётся 3 000 ₽".
    static func appointmentDetails(master: String, deposit: Int, applied: Int) -> String {
        let prefix = "Мастер \(master)"
        guard deposit > 0 else { return prefix }
        if applied > 0, applied < deposit {
            return "\(prefix) · из предоплаты \(Money.format(deposit)) зачтётся \(Money.format(applied))"
        }
        return "\(prefix) · предоплата \(Money.format(deposit)) зачтётся"
    }

    /// "внесена переводом 15 октября" — the latest prepayment receipt of the appointment; `nil` without one.
    static func depositReceivedNote(_ operations: [DepositOperation]) -> String? {
        guard let receive = operations.last(where: { $0.type == .receive }) else { return nil }
        let date = DateText.dayMonth(receive.createdAt)
        guard let method = receive.method else { return "внесена \(date)" }
        return "внесена \(method.instrumental) \(date)"
    }
}

/// Search and category filter for the jewelry catalog on the receipt screen.
nonisolated enum ProductCatalogFilter {
    static func categories(of products: [Product]) -> [String] {
        Array(Set(products.compactMap(\.category.nonEmpty))).sorted()
    }

    /// Products of `category` (all when `nil`) whose name, article, category, material, colour, insert,
    /// size names or size articles match `query`.
    static func apply(_ products: [Product], query: String, category: String?) -> [Product] {
        let needle = query.trimmed.lowercased()
        return products.filter { product in
            guard category == nil || product.category.nonEmpty == category else { return false }
            guard !needle.isEmpty else { return true }
            return searchText(of: product).contains(needle)
        }
    }

    /// Everything the search looks at, lowercased.
    static func searchText(of product: Product) -> String {
        let fields: [String?] = [product.name, product.sku, product.category, product.material, product.color, product.stone]
        let sizes: [String?] = product.variants.flatMap { [$0.name, $0.sku] }
        return (fields + sizes)
            .compactMap { $0.nonEmpty?.lowercased() }
            .joined(separator: " ")
    }

    /// Splits tiles into fixed-width rows, so a `List` can lay out (and lazily load) the grid row by row.
    static func rows(_ products: [Product], columns: Int) -> [[Product]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: products.count, by: columns).map { start in
            Array(products[start..<min(start + columns, products.count)])
        }
    }
}
