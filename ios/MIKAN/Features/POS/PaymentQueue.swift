import Foundation

/// Today's appointments that still wait for payment (the «К оплате по записям» list on the POS hub).
nonisolated enum PaymentQueue {
    /// Appointments that can still end in a sale (cancelled and no-show ones never do).
    static let statuses: [AppointmentStatus] = [.scheduled, .confirmed, .completed]

    /// `status` query value; the server accepts a comma-separated list.
    static var statusQuery: String { statuses.map(\.rawValue).joined(separator: ",") }

    /// The calendar day containing `date` (device time zone by default), as `[start, next day start)`.
    static func day(containing date: Date, calendar: Calendar = .app) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    /// Not paid yet, in a payable status, earliest first.
    static func unpaid(_ appointments: [Appointment]) -> [Appointment] {
        appointments
            .filter { $0.saleId == nil && statuses.contains($0.status) }
            .sorted { ($0.startsAt, $0.id) < ($1.startsAt, $1.id) }
    }

    /// Prepayment badge of a queue row: a held prepayment, or one still waited for; `nil` otherwise.
    static func depositBadge(for appointment: Appointment) -> QueueDepositBadge? {
        if appointment.deposit > 0 { return .held(appointment.deposit) }
        if appointment.depositStatus == .waiting, appointment.depositRequired > 0 {
            return .waiting(appointment.depositRequired)
        }
        return nil
    }
}

/// Prepayment state shown on a «К оплате по записям» row.
nonisolated enum QueueDepositBadge: Equatable, Sendable {
    /// Received earlier and held for the appointment: it is applied at checkout.
    case held(Int)
    /// Required but not received yet.
    case waiting(Int)

    var text: String {
        switch self {
        case .held(let amount): "Предоплата \(Money.format(amount))"
        case .waiting(let amount): "Ждём предоплату \(Money.format(amount))"
        }
    }
}

extension APIClient {
    /// Today's unpaid appointments for the POS hub.
    func appointmentsAwaitingPayment(on date: Date = .now) async throws -> [Appointment] {
        let day = PaymentQueue.day(containing: date)
        let response: ItemsResponse<Appointment> = try await request(.get, "appointments", query: queryItems([
            "from": ISO8601.string(from: day.start),
            "to": ISO8601.string(from: day.end),
            "status": PaymentQueue.statusQuery,
        ]))
        return PaymentQueue.unpaid(response.items)
    }
}
