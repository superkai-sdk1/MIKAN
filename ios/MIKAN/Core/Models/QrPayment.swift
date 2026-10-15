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

/// A one-off SBP QR code (Tochka) for the QR part of a checkout. The server creates the sale itself once the bank
/// confirms the payment, so the app only shows `payload` as a QR image and polls the status.
nonisolated struct QrPayment: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let status: QrPaymentStatus
    let amount: Int
    /// `https://qr.nspk.ru/…` — encoded into the QR image; opens the client's bank app.
    let payload: String
    let expiresAt: Date
    /// A declined attempt while still pending, or why a paid cart was not sold.
    let error: String?
    let sale: Sale?
    let createdAt: Date
}

nonisolated struct QrPaymentsConfig: Codable, Sendable {
    let enabled: Bool
}
