import Foundation

nonisolated enum AppointmentStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case confirmed
    case completed
    case cancelled
    case noShow = "no_show"
}

nonisolated struct Appointment: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var client: ClientRef
    var master: EmployeeRef
    var service: ServiceRef?
    var title: String?
    var startsAt: Date
    var endsAt: Date
    var status: AppointmentStatus
    var price: Int
    var deposit: Int
    var notes: String?
    var saleId: Int?
    var completedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    /// Service name, falling back to the free-form title.
    var displayTitle: String { service?.name ?? title.nonEmpty ?? "Запись" }

    var durationMin: Int { max(0, Int(endsAt.timeIntervalSince(startsAt) / 60)) }

    /// Not cancelled and not a no-show.
    var isActive: Bool { status != .cancelled && status != .noShow }

    /// Can still be confirmed, completed, rescheduled or cancelled.
    var isOpen: Bool { status == .scheduled || status == .confirmed }
}

nonisolated struct CompleteAppointmentResult: Codable, Sendable {
    let appointment: Appointment
    let scheduledMessages: Int
}
