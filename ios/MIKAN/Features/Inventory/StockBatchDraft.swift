import Foundation

/// One size as the movement sheet sees it: its stock before the operation.
nonisolated struct StockSize: Identifiable, Hashable, Sendable {
    /// The variant id.
    let id: Int
    let name: String
    let quantity: Int
    let minQuantity: Int

    /// «8 мм», «Без размера».
    var title: String { InventoryText.sizeTitle(name) }
}

/// Pure state of the movement sheet: one operation over several sizes (`POST /products/:id/movements/batch`).
/// Receipt / write-off / usage take the amount moved; a stock count (adjustment) takes the counted stock. A receipt
/// also carries what one unit cost on this delivery.
nonisolated struct StockBatchDraft: Hashable, Sendable {
    /// The server's upper limit of a unit cost, rubles.
    static let maxUnitCost = 100_000_000

    private(set) var type: MovementType
    var note: String
    /// Receipts: what one unit cost, for all lines; pre-filled with the current cost when the sizes share it.
    var unitCost: Int?
    /// The operations offered for the product's kind.
    let availableTypes: [MovementType]
    let productName: String
    let unit: String
    let sizes: [StockSize]
    /// A size the sheet was opened for: only it is shown until the user asks for all sizes.
    let preselectedId: Int?
    /// Entered per variant id: the amount moved, or the counted stock for `adjustment`.
    private(set) var amounts: [Int: Int]

    init(product: Product, type: MovementType, preselected variantId: Int? = nil, note: String = "") {
        self.type = type
        self.note = note
        productName = product.name
        unit = product.unitLabel
        sizes = product.variants.map {
            StockSize(id: $0.id, name: $0.name, quantity: $0.quantity, minQuantity: $0.minQuantity)
        }
        preselectedId = variantId.flatMap { id in product.variant(id: id) == nil ? nil : id }
        amounts = Self.startingAmounts(for: type, sizes: sizes)
        availableTypes = MovementType.manual(for: product.kind)
        unitCost = Self.currentUnitCost(of: product, preselected: preselectedId)
    }

    /// The cost of the preselected size (its own, else the product's), or the cost every size shares; `nil` when the
    /// sizes differ or no cost is set.
    static func currentUnitCost(of product: Product, preselected variantId: Int?) -> Int? {
        if let variant = variantId.flatMap(product.variant(id:)) { return product.cost(of: variant) }
        let costs = Set(product.variants.map(product.cost(of:)))
        return costs.count == 1 ? costs.first.flatMap { $0 } : nil
    }

    /// «Цена закупки за шт.», «Цена закупки за уп».
    var unitCostTitle: String {
        unit == ProductLimits.defaultUnit ? "Цена закупки за шт." : "Цена закупки за \(unit)"
    }

    /// A stock count starts from the current stock of every size, so only differing sizes need typing.
    private static func startingAmounts(for type: MovementType, sizes: [StockSize]) -> [Int: Int] {
        guard type == .adjustment else { return [:] }
        return Dictionary(sizes.map { ($0.id, $0.quantity) }, uniquingKeysWith: { first, _ in first })
    }

    var hasSeveralSizes: Bool { sizes.count > 1 }

    /// The sizes on screen: the preselected one, or all of them.
    func visibleSizes(showingAll: Bool) -> [StockSize] {
        guard !showingAll, let preselectedId else { return sizes }
        return sizes.filter { $0.id == preselectedId }
    }

    // MARK: Editing (each returns a new draft)

    /// Another operation starts over: amounts are cleared (a count is pre-filled again).
    func switching(to type: MovementType) -> StockBatchDraft {
        guard type != self.type else { return self }
        var copy = self
        copy.type = type
        copy.amounts = Self.startingAmounts(for: type, sizes: sizes)
        return copy
    }

    func settingAmount(_ amount: Int?, for id: Int) -> StockBatchDraft {
        guard sizes.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.amounts[id] = amount
        return copy
    }

    func amount(for id: Int) -> Int? { amounts[id] }

    // MARK: Result

    /// The size takes part in the operation: a positive amount, or a count that differs from the stock.
    func isTouched(_ size: StockSize) -> Bool {
        guard let amount = amounts[size.id] else { return false }
        return type == .adjustment ? amount != size.quantity : amount != 0
    }

    /// Stock of the size after the operation; `nil` when the size is not touched.
    func resulting(for size: StockSize) -> Int? {
        guard isTouched(size), let amount = amounts[size.id] else { return nil }
        switch type {
        case .receipt: return size.quantity + amount
        case .writeoff, .usage: return size.quantity - amount
        case .adjustment: return amount
        case .sale, .returned, .purchase, .other: return nil
        }
    }

    /// Lines of the request, in size order; untouched sizes are left out.
    var lines: [StockLineBody] {
        sizes.compactMap { size in
            guard isTouched(size), let amount = amounts[size.id] else { return nil }
            return StockLineBody(variantId: size.id, quantity: amount)
        }
    }

    /// Change of the total stock: «Итого +7 шт».
    var totalDelta: Int {
        sizes.reduce(0) { sum, size in
            guard let after = resulting(for: size) else { return sum }
            return sum + after - size.quantity
        }
    }

    /// Nothing typed yet (or a count equal to the stock): the button is off, but this is not an error to show.
    var isBlank: Bool { lines.isEmpty && negativeSize == nil }

    private var negativeSize: StockSize? {
        sizes.first { (amounts[$0.id] ?? 0) < 0 }
    }

    /// Why the operation cannot be sent, or `nil` when it can.
    var validationMessage: String? {
        if negativeSize != nil {
            return type == .adjustment ? "Количество не может быть меньше нуля." : "Количество должно быть больше нуля."
        }
        if lines.isEmpty {
            if type == .adjustment { return "Остатки не изменились." }
            return hasSeveralSizes ? "Укажите количество хотя бы для одного размера." : "Укажите количество."
        }
        if type == .receipt, let unitCost, unitCost > Self.maxUnitCost {
            return "Цена закупки не может быть больше \(Money.format(Self.maxUnitCost))."
        }
        if type == .writeoff || type == .usage, let short = sizes.first(where: { (resulting(for: $0) ?? 0) < 0 }) {
            let stock = InventoryText.quantity(short.quantity, unit: unit)
            return hasSeveralSizes
                ? "Нельзя списать больше, чем есть: \(short.title) — \(stock)."
                : "Нельзя списать больше, чем есть на складе (\(stock))."
        }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil }

    var body: StockBatchBody {
        StockBatchBody(type: type, note: note.nonEmpty, unitCost: type == .receipt ? unitCost : nil, lines: lines)
    }
}
