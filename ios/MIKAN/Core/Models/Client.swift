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
    let appointments: [Appointment]
    let sales: [Sale]
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
