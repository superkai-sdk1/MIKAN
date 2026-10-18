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
    /// Opening time "HH:mm" in the studio time zone: the calendar grid starts here.
    var workdayStart: String
    /// Closing time "HH:mm" ("24:00" = midnight): the calendar grid ends here.
    var workdayEnd: String
}

extension StudioSettings {
    /// Tolerates `null` text fields — they become empty strings — and servers without working hours.
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
            timezone: try container.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Moscow",
            workdayStart: try container.decodeIfPresent(String.self, forKey: .workdayStart) ?? WorkdayHours.standard.startText,
            workdayEnd: try container.decodeIfPresent(String.self, forKey: .workdayEnd) ?? WorkdayHours.standard.endText
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
    /// Minutes before the appointment at which the bot sends a reminder, earliest first (1–6 values).
    var reminderOffsets: [Int]
    // Read-only (ignored by PUT).
    let botUsername: String?
    let staffChatBound: Bool
    let aiConfigured: Bool
    /// The server knows `reminderOffsets`; older servers keep a single `reminderHoursBefore`. Not sent.
    var supportsReminderOffsets = true

    private enum CodingKeys: String, CodingKey {
        case enabled, aiEnabled, greeting, extraInstructions, aftercareHour, remindersEnabled
        case reminderOffsets, reminderHoursBefore
        case botUsername, staffChatBound, aiConfigured
    }

    var reminderSchedule: ReminderSchedule {
        get { ReminderSchedule(offsets: reminderOffsets) }
        set { reminderOffsets = newValue.offsets }
    }

    /// What blocks saving the reminders, or `nil`.
    var reminderIssue: ReminderSchedule.Issue? {
        remindersEnabled ? reminderSchedule.issue : nil
    }
}

extension BotSettings {
    /// Servers without `reminderOffsets` get `[reminderHoursBefore * 60]`.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let offsets = try container.decodeIfPresent([Int].self, forKey: .reminderOffsets)
        self.init(
            enabled: try container.decode(Bool.self, forKey: .enabled),
            aiEnabled: try container.decode(Bool.self, forKey: .aiEnabled),
            greeting: try container.decodeIfPresent(String.self, forKey: .greeting) ?? "",
            extraInstructions: try container.decodeIfPresent(String.self, forKey: .extraInstructions) ?? "",
            aftercareHour: try container.decode(Int.self, forKey: .aftercareHour),
            remindersEnabled: try container.decode(Bool.self, forKey: .remindersEnabled),
            reminderOffsets: ReminderSchedule.offsets(
                decoded: offsets,
                legacyHours: try container.decodeIfPresent(Int.self, forKey: .reminderHoursBefore)
            ),
            botUsername: try container.decodeIfPresent(String.self, forKey: .botUsername),
            staffChatBound: try container.decodeIfPresent(Bool.self, forKey: .staffChatBound) ?? false,
            aiConfigured: try container.decodeIfPresent(Bool.self, forKey: .aiConfigured) ?? false,
            supportsReminderOffsets: offsets != nil
        )
    }

    /// The `PUT /settings/bot` body: editable fields only. New servers get `reminderOffsets`;
    /// older ones also get `reminderHoursBefore` (the earliest reminder), the only value they keep.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(aiEnabled, forKey: .aiEnabled)
        try container.encode(greeting, forKey: .greeting)
        try container.encode(extraInstructions, forKey: .extraInstructions)
        try container.encode(aftercareHour, forKey: .aftercareHour)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(reminderOffsets, forKey: .reminderOffsets)
        if !supportsReminderOffsets {
            try container.encode(reminderSchedule.legacyHoursBefore, forKey: .reminderHoursBefore)
        }
    }
}
