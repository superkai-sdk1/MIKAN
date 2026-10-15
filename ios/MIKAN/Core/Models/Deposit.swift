import Foundation

/// Where an appointment's prepayment stands (derived by the server from `DepositOperation`s).
nonisolated enum DepositStatus: String, Codable, Sendable {
    /// Nothing required, or nothing to wait for (appointment not open).
    case none
    /// Required, nothing received yet, appointment still open.
    case waiting
    /// Some prepayment is held for the appointment (may be less than required).
    case paid
    /// Counted in a sale.
    case applied
    /// Returned to the client.
    case refunded
    /// Kept by the studio after a cancellation / no-show.
    case retained

    /// Tolerates statuses added by a newer server.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DepositStatus(rawValue: raw) ?? .none
    }
}

/// One prepayment movement (the ledger the held amount is computed from).
nonisolated enum DepositOperationType: String, Codable, Sendable {
    /// Money taken from the client.
    case receive
    /// Counted in sale `saleId`.
    case apply
    /// Sale `saleId` was refunded: its prepayment part is held for the appointment again.
    case unapply
    /// Returned to the client.
    case refund
    /// Kept by the studio after a cancellation / no-show.
    case retain
}

nonisolated struct DepositOperation: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let appointmentId: Int
    let type: DepositOperationType
    let amount: Int
    /// `cash` / `card` / `transfer` / `qr` for `receive` and `refund`; `nil` otherwise.
    let method: PaymentMethod?
    let saleId: Int?
    let shiftId: Int?
    let qrPaymentId: Int?
    let note: String?
    /// `nil` for entries migrated from older versions.
    let employee: EmployeeRef?
    let createdAt: Date
}

/// How a prepayment QR code reaches the client.
nonisolated enum DepositDelivery: String, Codable, Sendable {
    /// Shown on the phone at the studio (valid 10 minutes).
    case screen
    /// Sent by the bot to the client's Telegram chat (valid until the appointment starts, ≤ 72 h).
    case telegram
    /// Not sent: staff share `payload` themselves (same lifetime as `telegram`).
    case link
}

/// Answer of `POST /appointments/:id/deposit/qr` and `…/deposit/remind`.
nonisolated struct DepositLinkResult: Codable, Sendable {
    let appointment: Appointment
    let payment: QrPayment
    /// Why the bot could not deliver the link; the code stays valid and can be shared another way.
    let sendError: String?
}

/// Prepayment operations recorded while a cash shift was open.
nonisolated struct ShiftDepositSummary: Codable, Hashable, Sendable {
    var received = 0
    var cash = 0
    var card = 0
    var transfer = 0
    var qr = 0
    var refunded = 0
    var cashRefunded = 0
    var retained = 0

    static let zero = ShiftDepositSummary()
}

/// Prepayments in a report period; `held` is the balance at the end of the period.
nonisolated struct ReportDeposits: Codable, Hashable, Sendable {
    var received = 0
    var cash = 0
    var card = 0
    var transfer = 0
    var qr = 0
    var applied = 0
    var refunded = 0
    var retained = 0
    var held = 0

    static let zero = ReportDeposits()
}
