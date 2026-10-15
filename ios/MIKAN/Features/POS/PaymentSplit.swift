import Foundation

nonisolated enum PaymentMethod: String, CaseIterable, Identifiable, Sendable {
    case cash
    case card
    case transfer
    /// SBP QR code through Tochka: counted only once the bank confirms the payment.
    case qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Наличные"
        case .card: "Карта"
        case .transfer: "Перевод"
        case .qr: "QR-код"
        }
    }

    /// "наличными" / "картой" / "переводом" / "по QR-коду"
    var instrumental: String {
        switch self {
        case .cash: "наличными"
        case .card: "картой"
        case .transfer: "переводом"
        case .qr: "по QR-коду"
        }
    }

    /// One-tap button label: "Наличными" / "Картой" / "Переводом" / "По QR".
    var oneTapTitle: String {
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

/// How a sale total is split between cash, card, transfer and an SBP QR code.
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

    /// Whole total paid by one method.
    static func all(_ method: PaymentMethod, total: Int) -> PaymentSplit {
        var split = PaymentSplit()
        split[method] = max(0, total)
        return split
    }

    /// One-tap split that keeps an already received deposit in `transfer`
    /// and puts the rest of the total into `method`.
    static func oneTap(_ method: PaymentMethod, total: Int, deposit: Int) -> PaymentSplit {
        let total = max(0, total)
        let reserved = min(max(0, deposit), total)
        var split = PaymentSplit()
        split.transfer = reserved
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

    static func canSubmit(lineCount: Int, linesValid: Bool, subtotal: Int, discount: Int, split: PaymentSplit) -> Bool {
        guard lineCount > 0, linesValid, isDiscountValid(discount, subtotal: subtotal) else { return false }
        return split.isBalanced(for: total(subtotal: subtotal, discount: discount))
    }
}
