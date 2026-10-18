import Foundation

/// Pure state of the purchase sheet of a presence consumable (`POST /products/:id/purchases`): what was paid,
/// a note and the status after the restock.
nonisolated struct ConsumablePurchaseDraft: Hashable, Sendable {
    /// The server's upper limit, rubles.
    static let maxAmount = 100_000_000

    var amount: Int?
    var note = ""
    var status: PresenceStatus = .ok

    /// `nil` when the purchase can be saved.
    var validationMessage: String? {
        guard let amount else { return "Укажите, сколько заплатили" }
        guard amount > 0 else { return "Сумма должна быть больше нуля" }
        guard amount <= Self.maxAmount else { return "Сумма не может быть больше \(Money.format(Self.maxAmount))" }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil }

    /// Nothing typed yet: the sheet holds the error back until the first input.
    var isBlank: Bool { amount == nil }

    /// What is sent; `nil` until valid.
    var body: PurchaseBody? {
        guard canSubmit, let amount else { return nil }
        return PurchaseBody(amount: amount, note: note.nonEmpty, presenceStatus: status)
    }
}

/// The money a presence consumable took, from the movements the card has loaded.
nonisolated enum PurchaseSummary {
    static let windowDays = 30

    /// Σ purchases of the last 30 days; `nil` when the loaded history may not reach that far back (`isComplete` is
    /// false and every loaded movement is inside the window).
    static func spent(
        in movements: [StockMovement],
        isComplete: Bool,
        now: Date = .now,
        calendar: Calendar = .app
    ) -> Int? {
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: now) else { return nil }
        guard isComplete || movements.contains(where: { $0.createdAt < start }) else { return nil }
        return movements
            .filter { $0.type == .purchase && $0.createdAt >= start }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    /// «Потрачено за 30 дней: 3 500 ₽».
    static func spentText(_ amount: Int) -> String {
        "Потрачено за \(Plural.days(windowDays)): \(Money.format(amount))"
    }
}
