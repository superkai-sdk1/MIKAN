import Foundation

// MARK: - Moving an appointment in the calendar

/// `PATCH /appointments/:id` after a drop in the calendar (docs/API.md «Moving an appointment in the calendar»).
nonisolated struct AppointmentMoveBody: Encodable, Equatable, Sendable {
    let startsAt: Date
    let endsAt: Date
    /// Only when the appointment goes to another master.
    var masterId: Int?
    /// The server tells the client the new time in Telegram (when they have it linked).
    let notifyClient: Bool
    /// Omitted unless the user confirmed moving despite a schedule conflict.
    var force: Bool?
}

extension APIClient {
    func moveAppointment(id: Int, _ body: AppointmentMoveBody) async throws -> Appointment {
        try await request(.patch, "appointments/\(id)", body: body)
    }
}
