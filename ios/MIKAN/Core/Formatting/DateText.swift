import Foundation

nonisolated extension Locale {
    static let app = Locale(identifier: "ru_RU")
}

nonisolated extension Calendar {
    /// Gregorian, Monday-first, Russian, device time zone.
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .app
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }
}

/// Russian date/time strings in the device time zone.
nonisolated enum DateText {
    private static var base: Date.FormatStyle {
        Date.FormatStyle(locale: .app, calendar: .app, timeZone: .current)
    }

    /// "09:30"
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .app, calendar: .app, timeZone: .current))
    }

    /// "11:00–12:30"
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start))–\(time(end))"
    }

    /// "15 октября"
    static func dayMonth(_ date: Date) -> String {
        date.formatted(base.day().month(.wide))
    }

    /// "15 октября 2026"
    static func fullDate(_ date: Date) -> String {
        date.formatted(base.day().month(.wide).year())
    }

    /// "четверг, 15 октября"
    static func weekdayDayMonth(_ date: Date) -> String {
        date.formatted(base.weekday(.wide).day().month(.wide))
    }

    /// "Чт"
    static func shortWeekday(_ date: Date) -> String {
        capitalized(date.formatted(base.weekday(.abbreviated)))
    }

    /// "15"
    static func dayNumber(_ date: Date) -> String {
        date.formatted(base.day())
    }

    /// "15 окт., 11:00" (adds the year when not the current one)
    static func dateTime(_ date: Date) -> String {
        let calendar = Calendar.app
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        let style = sameYear ? base.day().month(.abbreviated) : base.day().month(.abbreviated).year()
        return "\(date.formatted(style)), \(time(date))"
    }

    /// "Октябрь 2026"
    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.calendar = .app
        formatter.timeZone = .current
        formatter.dateFormat = "LLLL yyyy"
        return capitalized(formatter.string(from: date))
    }

    /// Chat-list style: today → "11:00", yesterday → "Вчера", this week → "Пн", otherwise "15.10.26".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.app
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return shortWeekday(date)
        }
        return date.formatted(base.day(.twoDigits).month(.twoDigits).year(.twoDigits))
    }

    /// "Сегодня", "Вчера", "Завтра" or "четверг, 15 октября".
    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.app
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        if calendar.isDateInTomorrow(date) { return "Завтра" }
        return weekdayDayMonth(date)
    }

    /// "1 ч 30 мин", "45 мин", "2 ч"
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) мин"
        case (_, 0): return "\(hours) ч"
        default: return "\(hours) ч \(rest) мин"
        }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// `YYYY-MM-DD` calendar dates (birthdays, report days) ↔ `Date` at local midnight.
nonisolated enum CalendarDay {
    static func string(from date: Date, calendar: Calendar = .app) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String, calendar: Calendar = .app) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
