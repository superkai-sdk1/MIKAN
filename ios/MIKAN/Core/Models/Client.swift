import Foundation

nonisolated struct Client: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var phone: String?
    var instagram: String?
    /// Calendar date `YYYY-MM-DD`.
    var birthday: String?
    var notes: String?
    var source: String?
    var telegramLinked: Bool
    var telegramUsername: String?
    var botEnabled: Bool
    var archived: Bool
    let createdAt: Date
    var updatedAt: Date
    /// `nil` in lists, filled by `GET /clients/:id`.
    var stats: ClientStats?

    var ref: ClientRef { ClientRef(id: id, name: name, phone: phone, telegramLinked: telegramLinked) }
}

nonisolated struct ClientStats: Codable, Hashable, Sendable {
    let visits: Int
    let totalSpent: Int
    let lastVisitAt: Date?
    let upcomingAppointments: Int
}

/// Embedded client summary used inside other entities.
nonisolated struct ClientRef: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let phone: String?
    let telegramLinked: Bool
}

nonisolated struct ClientHistory: Codable, Sendable {
    /// Services done and products bought, newest first.
    var items: [HistoryEntry] = []
    let appointments: [Appointment]
    let sales: [Sale]
}

nonisolated extension ClientHistory {
    private enum CodingKeys: String, CodingKey { case items, appointments, sales }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([HistoryEntry].self, forKey: .items) ?? []
        appointments = try c.decode([Appointment].self, forKey: .appointments)
        sales = try c.decode([Sale].self, forKey: .sales)
    }
}

nonisolated enum HistoryEntryKind: String, Codable, Sendable {
    case service
    case product
}

/// One thing done for or sold to a client: a service line of a completed appointment, or a sale item.
nonisolated struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    /// `as<line>`, `at<appointment>` or `si<sale item>`.
    let id: String
    let kind: HistoryEntryKind
    let date: Date
    let name: String
    let serviceId: Int?
    let productId: Int?
    let quantity: Int
    let price: Int
    let total: Int
    let client: ClientRef?
    /// Master (services) or seller (products).
    let employee: EmployeeRef?
    let appointmentId: Int?
    let saleId: Int?
    let saleNumber: Int?
    let refunded: Bool
}

/// Suggested `source` values. The field itself is free text.
nonisolated enum ClientSource {
    static let suggestions = ["instagram", "telegram", "рекомендация", "с улицы", "другое"]

    static func title(for source: String) -> String {
        switch source {
        case "instagram": "Instagram"
        case "telegram": "Telegram"
        default: source.prefix(1).uppercased() + source.dropFirst()
        }
    }
}
