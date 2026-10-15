import Foundation

nonisolated enum QrPaymentStatus: String, Codable, Sendable {
    /// Waiting for the client to pay.
    case pending
    /// The bank confirmed the money; `sale` is the created sale, or `error` says why it could not be created.
    case paid
    /// Not paid in time.
    case expired
    /// Staff stopped waiting (the client paid another way).
    case cancelled
}

nonisolated enum QrPaymentKind: String, Codable, Sendable {
    /// QR part of a checkout: the server sells the cart once paid.
    case sale
    /// An appointment's prepayment: once paid the server records it (`DepositOperation` `receive`, method `qr`).
    case deposit
}

/// A one-off SBP QR code (Tochka): the QR part of a checkout, or an appointment's prepayment. The server records the
/// result itself once the bank confirms the payment, so the app only shows `payload` as a QR image and polls the status.
nonisolated struct QrPayment: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var kind: QrPaymentKind = .sale
    /// The appointment of a `deposit` code.
    var appointmentId: Int?
    let status: QrPaymentStatus
    let amount: Int
    /// `https://qr.nspk.ru/…` — encoded into the QR image; opens the client's bank app.
    let payload: String
    let expiresAt: Date
    /// When the bot last sent this link to the client in Telegram (`deposit` only).
    var sentAt: Date?
    /// A declined attempt while still pending, or why a paid cart was not sold / a paid prepayment needs a look.
    let error: String?
    let sale: Sale?
    let createdAt: Date

    var isDeposit: Bool { kind == .deposit }
}

nonisolated extension QrPayment {
    private enum CodingKeys: String, CodingKey {
        case id, kind, appointmentId, status, amount, payload, expiresAt, sentAt, error, sale, createdAt
    }

    /// Tolerates servers that predate prepayment codes (no `kind`, `appointmentId`, `sentAt`).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(QrPaymentKind.self, forKey: .kind) ?? .sale
        appointmentId = try c.decodeIfPresent(Int.self, forKey: .appointmentId)
        status = try c.decode(QrPaymentStatus.self, forKey: .status)
        amount = try c.decode(Int.self, forKey: .amount)
        payload = try c.decode(String.self, forKey: .payload)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        sale = try c.decodeIfPresent(Sale.self, forKey: .sale)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

nonisolated struct QrPaymentsConfig: Codable, Sendable {
    let enabled: Bool
}
