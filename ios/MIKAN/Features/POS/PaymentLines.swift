import Foundation

/// One line of a sale's payment breakdown: a payment method or the appointment's prepayment.
nonisolated struct PaymentLine: Hashable, Identifiable, Sendable {
    nonisolated enum Source: Hashable, Sendable {
        case method(PaymentMethod)
        /// Covered by the appointment's prepayment (received earlier, not money taken at this checkout).
        case deposit
    }

    static let depositTitle = "Предоплата"
    static let depositSymbol = "rublesign.circle"

    let source: Source
    let amount: Int

    var id: Source { source }

    var title: String {
        switch source {
        case .method(let method): method.title
        case .deposit: Self.depositTitle
        }
    }

    var symbol: String {
        switch source {
        case .method(let method): method.symbol
        case .deposit: Self.depositSymbol
        }
    }

    /// "наличными" / "переводом" / "по QR СБП" / "предоплатой"
    var instrumental: String {
        switch source {
        case .method(let method): method.instrumental
        case .deposit: "предоплатой"
        }
    }
}

nonisolated extension Payments {
    /// Non-zero parts in display order: the methods, then the prepayment.
    var paymentLines: [PaymentLine] {
        let split = PaymentSplit(self)
        let methods = PaymentMethod.allCases.map { PaymentLine(source: .method($0), amount: split[$0]) }
        return (methods + [PaymentLine(source: .deposit, amount: deposit)]).filter { $0.amount > 0 }
    }
}

/// Texts listing how money was paid or received.
nonisolated enum PaymentText {
    /// "наличными и предоплатой", "наличными, переводом и предоплатой"; `nil` when nothing was paid.
    static func methods(_ payments: Payments) -> String? {
        let parts = payments.paymentLines.map(\.instrumental)
        return parts.isEmpty ? nil : parts.formatted(.list(type: .and).locale(.app))
    }

    /// "наличными 1 000 ₽ · переводом 2 000 ₽" — non-zero methods only; `nil` when there are none.
    static func breakdown(_ split: PaymentSplit) -> String? {
        let parts = PaymentMethod.allCases
            .filter { split[$0] > 0 }
            .map { "\($0.instrumental) \(Money.format(split[$0]))" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
