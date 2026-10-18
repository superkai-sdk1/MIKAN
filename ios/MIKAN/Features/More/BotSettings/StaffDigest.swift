import Foundation

/// The bot's daily summaries to staff chats: `BotSettings.morningDigestAt` / `eveningDigestAt`.
nonisolated enum StaffDigest: CaseIterable, Hashable, Sendable {
    case morning
    case evening

    var title: String {
        switch self {
        case .morning: "Утренняя сводка"
        case .evening: "Вечерняя сводка"
        }
    }

    /// The time a summary gets when it is turned on (the server defaults).
    var defaultTime: String {
        switch self {
        case .morning: "09:30"
        case .evening: "21:30"
        }
    }

    var keyPath: WritableKeyPath<BotSettings, String?> {
        switch self {
        case .morning: \.morningDigestAt
        case .evening: \.eveningDigestAt
        }
    }

    /// The value after the toggle: the current time (or the default) when on, `nil` when off.
    func toggled(_ time: String?, isOn: Bool) -> String? {
        isOn ? (time ?? defaultTime) : nil
    }
}

/// "HH:MM" of a digest (studio time) ⇄ the `Date` of a time picker. The picker works on a fixed day in UTC
/// (`timeZone`), so it shows the studio's wall-clock time whatever the phone's time zone.
nonisolated enum DigestTime {
    static let timeZone = TimeZone.gmt

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// "09:30" / "9:30" → 09:30 on 2001-01-01 UTC; `nil` when malformed (or "24:00").
    static func date(from text: String) -> Date? {
        guard let minute = WorkdayHours.minute(from: text), minute < TimeGridLayout.minutesPerDay else { return nil }
        return Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60))
    }

    /// The hour and minute of `date` in UTC: "09:30" (seconds dropped).
    static func text(from date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return WorkdayHours.text(fromMinute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
