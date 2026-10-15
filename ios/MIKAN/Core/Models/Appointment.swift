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
    /// Legacy single service: the catalog service of the first line that has one.
    var service: ServiceRef?
    /// Booked service lines in order (snapshots of name / price / duration).
    var services: [AppointmentServiceLine] = []
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

    /// Service names, falling back to the free-form title.
    var displayTitle: String { serviceNames ?? service?.name ?? title.nonEmpty ?? "Запись" }

    /// «Хеликс, Мочка» — `nil` when no service lines.
    var serviceNames: String? {
        services.isEmpty ? nil : services.map(\.name).joined(separator: ", ")
    }

    var durationMin: Int { max(0, Int(endsAt.timeIntervalSince(startsAt) / 60)) }

    /// Not cancelled and not a no-show.
    var isActive: Bool { status != .cancelled && status != .noShow }

    /// Can still be confirmed, completed, rescheduled or cancelled.
    var isOpen: Bool { status == .scheduled || status == .confirmed }
}

nonisolated extension Appointment {
    private enum CodingKeys: String, CodingKey {
        case id, client, master, service, services, title, startsAt, endsAt, status, price, deposit, notes
        case saleId, completedAt, createdAt, updatedAt
    }

    /// Tolerates servers that predate multi-service appointments (no `services`).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        client = try c.decode(ClientRef.self, forKey: .client)
        master = try c.decode(EmployeeRef.self, forKey: .master)
        service = try c.decodeIfPresent(ServiceRef.self, forKey: .service)
        services = try c.decodeIfPresent([AppointmentServiceLine].self, forKey: .services) ?? []
        title = try c.decodeIfPresent(String.self, forKey: .title)
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
        status = try c.decode(AppointmentStatus.self, forKey: .status)
        price = try c.decode(Int.self, forKey: .price)
        deposit = try c.decode(Int.self, forKey: .deposit)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        saleId = try c.decodeIfPresent(Int.self, forKey: .saleId)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// One booked service of an appointment. `serviceId` is `nil` for a custom line.
nonisolated struct AppointmentServiceLine: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let serviceId: Int?
    let name: String
    let category: ServiceCategory?
    let price: Int
    let durationMin: Int?
}

nonisolated struct CompleteAppointmentResult: Codable, Sendable {
    let appointment: Appointment
    let scheduledMessages: Int
}
