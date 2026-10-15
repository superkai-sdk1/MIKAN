import Foundation

nonisolated struct StudioSettings: Codable, Hashable, Sendable {
    var name: String
    var address: String
    var phone: String
    var workingHours: String
    var instagram: String
    var website: String
    var about: String
    var timezone: String
}

extension StudioSettings {
    /// Tolerates `null` text fields — they become empty strings.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String {
            try container.decodeIfPresent(String.self, forKey: key) ?? ""
        }
        self.init(
            name: try text(.name),
            address: try text(.address),
            phone: try text(.phone),
            workingHours: try text(.workingHours),
            instagram: try text(.instagram),
            website: try text(.website),
            about: try text(.about),
            timezone: try container.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Moscow"
        )
    }
}

nonisolated struct BotSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var aiEnabled: Bool
    var greeting: String
    var extraInstructions: String
    /// Studio-local hour (0–23) for aftercare messages with `dayOffset > 0`.
    var aftercareHour: Int
    var remindersEnabled: Bool
    var reminderHoursBefore: Int
    // Read-only (ignored by PUT).
    let botUsername: String?
    let staffChatBound: Bool
    let aiConfigured: Bool
}

extension BotSettings {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decode(Bool.self, forKey: .enabled),
            aiEnabled: try container.decode(Bool.self, forKey: .aiEnabled),
            greeting: try container.decodeIfPresent(String.self, forKey: .greeting) ?? "",
            extraInstructions: try container.decodeIfPresent(String.self, forKey: .extraInstructions) ?? "",
            aftercareHour: try container.decode(Int.self, forKey: .aftercareHour),
            remindersEnabled: try container.decode(Bool.self, forKey: .remindersEnabled),
            reminderHoursBefore: try container.decode(Int.self, forKey: .reminderHoursBefore),
            botUsername: try container.decodeIfPresent(String.self, forKey: .botUsername),
            staffChatBound: try container.decodeIfPresent(Bool.self, forKey: .staffChatBound) ?? false,
            aiConfigured: try container.decodeIfPresent(Bool.self, forKey: .aiConfigured) ?? false
        )
    }
}
