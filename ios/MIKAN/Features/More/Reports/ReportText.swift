import Foundation

/// Texts of the report and analytics cards.
nonisolated enum ReportText {
    /// «8 мм × 4 · 6 мм × 3» — how a top product sold by size, in the server's order; `nil` without named sizes
    /// (a product without sizes, or a server that predates them).
    static func sizeBreakdown(_ variants: [TopProductVariant]) -> String? {
        sizes(variants.map { ($0.name, $0.quantity) })
    }

    /// The same for an analytics top product.
    static func sizeBreakdown(of variants: [AnalyticsProductVariant]) -> String? {
        sizes(variants.map { ($0.name, $0.margin.quantity) })
    }

    private static func sizes(_ parts: [(name: String, quantity: Int)]) -> String? {
        let named = parts
            .filter { $0.quantity > 0 }
            .compactMap { part in part.name.nonEmpty.map { "\($0) × \(part.quantity)" } }
        return named.isEmpty ? nil : named.joined(separator: " · ")
    }

    /// Product kind of the server: «Украшения», «Расходники», «Товары», or the raw name of a kind added later.
    static func kindTitle(_ kind: String) -> String {
        if let known = ProductKind(rawValue: kind) { return known.title }
        switch kind {
        case "goods": return "Товары"
        case "other": return "Другое"
        default: return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }

    /// Title of the products card: «Украшения» while only jewelry sells, «Товары» once other kinds do.
    static func productsTitle(_ kinds: [String]) -> String {
        Set(kinds).isSubset(of: [ProductKind.jewelry.rawValue]) ? ProductKind.jewelry.title : "Товары"
    }

    /// Service category: «Пирсинг», «Тату», «Другое», or the raw name of a category added later.
    static func categoryTitle(_ category: String) -> String {
        ServiceCategory(rawValue: category)?.title ?? (category.prefix(1).uppercased() + category.dropFirst())
    }

    static func categorySymbol(_ category: String) -> String {
        ServiceCategory(rawValue: category)?.symbol ?? "square.grid.2x2"
    }

    /// «57,6 %», «—» when unknown.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)).locale(.app)) + "\u{00A0}%"
    }

    /// Share of `part` in `whole`, 0…1 (0 when the whole is not positive).
    static func share(_ part: Int, of whole: Int) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }

    /// «12 шт.»
    static func units(_ count: Int) -> String {
        "\(count)\u{00A0}шт."
    }

    /// «1 покупка», «3 покупки», «5 покупок».
    static func purchases(_ count: Int) -> String {
        Plural.count(count, one: "покупка", few: "покупки", many: "покупок")
    }

    /// Operation of a stock expense row: «Списание · 2 шт.», «Расход · 5 шт.», «Покупка · 3 раза» (a purchase counts
    /// purchases, not units).
    static func stockExpenseLine(_ expense: AnalyticsStockExpense) -> String {
        if expense.isPurchase {
            return "Покупка · " + Plural.count(expense.quantity, one: "раз", few: "раза", many: "раз")
        }
        return "\(expense.isUsage ? "Расход" : "Списание") · \(units(expense.quantity))"
    }

    /// The operation column of the export: «Списание», «Расход на процедуры», «Покупка».
    static func stockExpenseTitle(_ expense: AnalyticsStockExpense) -> String {
        if expense.isPurchase { return "Покупка" }
        return expense.isUsage ? "Расход на процедуры" : "Списание"
    }

    /// «3 шт. без себестоимости — укажите её в карточке товара, чтобы маржа была точной», or `nil` when all have it.
    static func missingCostHint(_ units: Int) -> String? {
        guard units > 0 else { return nil }
        return "\(Self.units(units)) без себестоимости — укажите её в карточке товара, чтобы маржа была точной"
    }

    static let weekdayShort = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    static let weekdayFull = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]

    /// ISO weekday 1…7 → «Пн»…«Вс».
    static func weekday(_ weekday: Int, full: Bool = false) -> String {
        let names = full ? weekdayFull : weekdayShort
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : "\(weekday)"
    }

    /// «09:00»
    static func hour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    /// «Записей: 10 · Услуг: 14 · Неявок: 1» (zero no-shows are left out).
    static func masterLine(_ master: AnalyticsMaster) -> String {
        var parts = ["Записей: \(master.appointmentsCompleted)", "Услуг: \(master.servicesCount)"]
        if master.noShows > 0 { parts.append("Неявок: \(master.noShows)") }
        return parts.joined(separator: " · ")
    }

    /// Share of no-shows among appointments that were due (completed + no-show), «—» without any.
    static func noShowRate(_ appointments: AnalyticsAppointments) -> String {
        let due = appointments.completed + appointments.noShow
        return due > 0 ? percent((Double(appointments.noShow) / Double(due) * 1000).rounded() / 10) : "—"
    }
}
