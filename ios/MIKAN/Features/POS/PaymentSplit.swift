import Foundation

nonisolated enum PaymentMethod: String, CaseIterable, Identifiable, Sendable {
    case cash
    /// No longer taken at checkout; kept to show older sales, shifts and reports.
    case card
    case transfer
    /// SBP QR code through Tochka: counted only once the bank confirms the payment.
    case qr

    /// What the studio takes now, in display order. QR only when the server has the bank configured.
    static func accepted(qrEnabled: Bool) -> [PaymentMethod] {
        qrEnabled ? [.cash, .transfer, .qr] : [.cash, .transfer]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Наличные"
        case .card: "Карта"
        case .transfer: "Перевод"
        case .qr: "QR СБП"
        }
    }

    /// "наличными" / "картой" / "переводом" / "по QR СБП"
    var instrumental: String {
        switch self {
        case .cash: "наличными"
        case .card: "картой"
        case .transfer: "переводом"
        case .qr: "по QR СБП"
        }
    }

    /// Chip label: "Наличными" / "Картой" / "Переводом" / "По QR".
    var instrumentalTitle: String {
        self == .qr ? "По QR" : instrumental.capitalized
    }

    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .card: "creditcard"
        case .transfer: "arrow.left.arrow.right"
        case .qr: "qrcode"
        }
    }
}

/// How the checkout is paid: everything by one method (amount computed automatically) or a manual split.
nonisolated enum PaymentMode: Hashable, Sendable {
    case single(PaymentMethod)
    case split

    /// Segments of the payment picker, in display order.
    static func choices(qrEnabled: Bool) -> [PaymentMode] {
        PaymentMethod.accepted(qrEnabled: qrEnabled).map(PaymentMode.single) + [.split]
    }

    var title: String {
        switch self {
        case .single(let method): method.title
        case .split: "Разделить"
        }
    }

    var method: PaymentMethod? {
        if case .single(let method) = self { return method }
        return nil
    }
}

/// How a sale total is split between payment methods (`card` stays 0 for new sales).
nonisolated struct PaymentSplit: Equatable, Sendable {
    var cash = 0
    var card = 0
    var transfer = 0
    var qr = 0

    init(cash: Int = 0, card: Int = 0, transfer: Int = 0, qr: Int = 0) {
        self.cash = cash
        self.card = card
        self.transfer = transfer
        self.qr = qr
    }

    init(_ payments: Payments) {
        self.init(cash: payments.cash, card: payments.card, transfer: payments.transfer, qr: payments.qr)
    }

    subscript(method: PaymentMethod) -> Int {
        get {
            switch method {
            case .cash: cash
            case .card: card
            case .transfer: transfer
            case .qr: qr
            }
        }
        set {
            switch method {
            case .cash: cash = newValue
            case .card: card = newValue
            case .transfer: transfer = newValue
            case .qr: qr = newValue
            }
        }
    }

    var sum: Int { cash + card + transfer + qr }
    var hasNegative: Bool { cash < 0 || card < 0 || transfer < 0 || qr < 0 }
    var payments: Payments { Payments(cash: cash, card: card, transfer: transfer, qr: qr) }

    /// Positive: still to distribute; negative: overpaid.
    func remaining(for total: Int) -> Int { total - sum }

    func isBalanced(for total: Int) -> Bool { !hasNegative && sum == total }

    /// The whole total paid by `method`, except an already received deposit, which stays in `transfer`.
    /// A deposit covering the whole total puts everything into `transfer`.
    static func single(_ method: PaymentMethod, total: Int, deposit: Int) -> PaymentSplit {
        let total = max(0, total)
        let reserved = CheckoutRules.depositApplied(deposit, total: total)
        var split = PaymentSplit(transfer: reserved)
        split[method] += total - reserved
        return split
    }
}

/// Validation of a checkout before `POST /sales`.
nonisolated enum CheckoutRules {
    static func isDiscountValid(_ discount: Int, subtotal: Int) -> Bool {
        discount >= 0 && discount <= subtotal
    }

    static func total(subtotal: Int, discount: Int) -> Int {
        max(0, subtotal - max(0, discount))
    }

    /// Part of the deposit that counts towards this receipt (never more than the total).
    static func depositApplied(_ deposit: Int, total: Int) -> Int {
        min(max(0, deposit), max(0, total))
    }

    static func canSubmit(lineCount: Int, linesValid: Bool, subtotal: Int, discount: Int, split: PaymentSplit) -> Bool {
        guard lineCount > 0, linesValid, isDiscountValid(discount, subtotal: subtotal) else { return false }
        return split.isBalanced(for: total(subtotal: subtotal, discount: discount))
    }
}

/// Cash handed over by the client: change and quick «received» amounts. Display only, never sent to the server.
nonisolated enum CashTender {
    /// Banknote steps used to suggest a round «received» amount.
    private static let roundingSteps = [500, 1_000, 5_000]

    /// Nothing entered yet counts as enough (the field is optional).
    static func isEnough(received: Int?, due: Int) -> Bool {
        guard let received else { return true }
        return received >= due
    }

    /// Change to give back; `nil` while nothing is entered or the received amount is short.
    static func change(received: Int?, due: Int) -> Int? {
        guard let received, received >= due else { return nil }
        return received - due
    }

    /// Exact amount first, then the due rounded up to common banknotes: 4 300 → [4 300, 4 500, 5 000].
    static func suggestions(for due: Int) -> [Int] {
        guard due > 0 else { return [] }
        let rounded = roundingSteps.map { step in (due + step - 1) / step * step }
        return rounded.reduce(into: [due]) { result, amount in
            if !result.contains(amount) { result.append(amount) }
        }
    }
}
