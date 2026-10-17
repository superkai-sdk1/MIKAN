import Foundation

/// Screens pushed inside the «Касса» tab. The path lives in `AppState.posPath`, so other tabs can open a receipt.
nonisolated enum POSRoute: Hashable, Sendable {
    case receipt
    case clientPicker
    case salesHistory
    case shiftsHistory
}

/// Rules and texts for the receipt that is being assembled in the cart.
enum ReceiptDraft {
    /// The cart holds edits that starting another receipt would lose.
    /// An untouched appointment prefill (one line at the appointment price) can be recreated, so it does not count.
    static func hasUnsavedWork(lines: [CartLine], appointment: Appointment?) -> Bool {
        guard !lines.isEmpty else { return false }
        guard let appointment, lines.count == 1, let line = lines.first else { return true }
        let isPristine = line.name == appointment.displayTitle
            && line.unitPrice == appointment.price
            && line.quantity == 1
        return !isPristine
    }

    /// Something worth continuing: lines, a client or an appointment.
    static func isOpen(lines: [CartLine], client: ClientRef?, appointment: Appointment?) -> Bool {
        !lines.isEmpty || client != nil || appointment != nil
    }

    /// "Продолжить чек · 3 500 ₽", or without the amount while there are no lines yet.
    static func continueTitle(lineCount: Int, total: Int) -> String {
        lineCount == 0 ? "Продолжить чек" : "Продолжить чек · \(Money.format(total))"
    }

    /// "По записи · Анна", "Иван Петров · 2 позиции", "Без клиента · пусто".
    static func summary(itemCount: Int, client: ClientRef?, appointment: Appointment?) -> String {
        let who = appointment.map { "По записи · \($0.client.fullName)" } ?? client?.fullName ?? "Без клиента"
        let what = itemCount == 0 ? "пусто" : Plural.count(itemCount, one: "позиция", few: "позиции", many: "позиций")
        return "\(who) · \(what)"
    }

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

    static func apply(_ products: [Product], query: String, category: String?) -> [Product] {
        let needle = query.trimmed.lowercased()
        return products.filter { product in
            guard category == nil || product.category.nonEmpty == category else { return false }
            guard !needle.isEmpty else { return true }
            let haystack = [product.name, product.sku, product.material, product.size, product.category]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(needle)
        }
    }

    /// Splits tiles into fixed-width rows, so a `List` can lay out (and lazily load) the grid row by row.
    static func rows(_ products: [Product], columns: Int) -> [[Product]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: products.count, by: columns).map { start in
            Array(products[start..<min(start + columns, products.count)])
        }
    }
}

extension CartStore {
    /// Starts the receipt for an appointment. Reopening the same appointment keeps the edits
    /// (lines, discount, note, checkout choices) and takes the fresh copy (status, deposit).
    func open(_ appointment: Appointment) {
        guard appointmentId == appointment.id else {
            prefill(from: appointment)
            return
        }
        let kept = (
            lines: lines, discount: discount, note: note,
            paymentMode: paymentMode, manualSplit: manualSplit, cashReceived: cashReceived,
            completesAppointment: completesAppointment, sendsAftercare: sendsAftercare
        )
        prefill(from: appointment)
        lines = kept.lines
        discount = kept.discount
        note = kept.note
        selectPaymentMode(kept.paymentMode)
        manualSplit = kept.manualSplit
        cashReceived = kept.cashReceived
        completesAppointment = kept.completesAppointment
        sendsAftercare = kept.sendsAftercare
    }
}
