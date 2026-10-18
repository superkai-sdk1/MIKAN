import Foundation

/// Stock texts of a jewelry tile in the POS catalog: one size shows its stock, several sizes how many are in stock.
nonisolated enum ProductTileText {
    /// «4 шт» / «Нет» for one size; «3 размера» when every size is in stock, «2 из 3 размеров», «Нет» when none is.
    static func stock(_ product: Product) -> String {
        guard product.hasSeveralSizes else {
            return product.isAvailable ? "\(product.quantity) \(product.unitLabel)" : "Нет"
        }
        let total = product.variants.count
        let available = product.availableVariants.count
        if available == 0 { return "Нет" }
        if available == total { return sizes(total) }
        return "\(available) из \(total) \(Plural.word(total, one: "размера", few: "размеров", many: "размеров"))"
    }

    /// VoiceOver: «осталось 4 шт», «в наличии 2 из 3 размеров», «нет в наличии».
    static func accessibilityStock(_ product: Product) -> String {
        guard product.isAvailable else { return "нет в наличии" }
        guard product.hasSeveralSizes else { return "осталось \(product.quantity) \(product.unitLabel)" }
        return "в наличии \(stock(product))"
    }

    /// «3 размера», «5 размеров».
    static func sizes(_ count: Int) -> String {
        Plural.count(count, one: "размер", few: "размера", many: "размеров")
    }
}

/// The size of a sold item shown as a badge next to the product name.
nonisolated enum SizeLabel {
    /// «Лабрет — 8 мм» + «8 мм» → («Лабрет», «8 мм»); a name without the size stays whole, the size still comes back.
    static func split(name: String, size: String?) -> (name: String, size: String?) {
        guard let size = size.nonEmpty else { return (name, nil) }
        let suffix = " — \(size)"
        guard name.hasSuffix(suffix), name.count > suffix.count else { return (name, size) }
        return (String(name.dropLast(suffix.count)), size)
    }

    /// «Лабрет — 8 мм»: the name with its size, added only when the name does not end with it yet
    /// (the server already names sale items that way).
    static func fullName(name: String, size: String?) -> String {
        guard let size = size.nonEmpty, !name.hasSuffix(" — \(size)") else { return name }
        return "\(name) — \(size)"
    }
}

/// Stock check of a receipt: lines of one size share its stock.
nonisolated enum ReceiptStock {
    /// «На складе только 1 шт размера 8 мм», «Размера 10 мм нет на складе» — when the receipt asks for more
    /// than the size's stock; « — в чеке 2» is added when the size is spread over several lines.
    static func warning(stock: Int, inReceipt: Int, lineQuantity: Int, sizeName: String?) -> String? {
        guard inReceipt > stock else { return nil }
        let size = sizeName.nonEmpty
        let text: String
        if stock <= 0 {
            text = size.map { "Размера \($0) нет на складе" } ?? "Нет на складе"
        } else {
            text = "На складе только \(stock) шт" + (size.map { " размера \($0)" } ?? "")
        }
        return inReceipt == lineQuantity ? text : "\(text) — в чеке \(inReceipt)"
    }
}

/// «Добавлено: Лабрет — 8 мм» — the receipt hint after a size was picked.
nonisolated enum SizePicking {
    static func addedHint(product: Product, variant: ProductVariant) -> String {
        "Добавлено: \(product.lineName(variant: variant))"
    }
}
