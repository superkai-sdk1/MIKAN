import Foundation

nonisolated enum CalendarScale: String, CaseIterable, Identifiable, Sendable {
    case day
    case threeDays
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "День"
        case .threeDays: "3 дня"
        case .week: "Неделя"
        case .month: "Месяц"
        }
    }

    var symbol: String {
        switch self {
        case .day: "1.square"
        case .threeDays: "3.square"
        case .week: "7.square"
        case .month: "calendar"
        }
    }

    /// Day columns in the time grid; `nil` for the month grid.
    var dayCount: Int? {
        switch self {
        case .day: 1
        case .threeDays: 3
        case .week: 7
        case .month: nil
        }
    }
}

nonisolated enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case all
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Все записи"
        case .mine: "Мои записи"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "Все"
        case .mine: "Мои"
        }
    }
}

/// A calendar page: one day, three days, a Monday-first week or a month.
/// All boundaries are local midnights of the given calendar (device time zone in the app).
nonisolated struct CalendarPeriod: Hashable, Sendable {
    /// Month grids always show six Monday-first weeks so the page height never jumps.
    static let monthGridDays = 42

    let scale: CalendarScale
    /// First day of the period.
    let start: Date
    /// Exclusive end of the period.
    let end: Date
    /// Visible (and loaded) range — equals the period except for month grids.
    let visibleStart: Date
    let visibleEnd: Date

    var visibleInterval: DateInterval { DateInterval(start: visibleStart, end: visibleEnd) }

    static func containing(_ date: Date, scale: CalendarScale, calendar: Calendar = .app) -> CalendarPeriod {
        let day = calendar.startOfDay(for: date)
        switch scale {
        case .day:
            return spanning(scale, from: day, days: 1, calendar: calendar)
        case .threeDays:
            return spanning(scale, from: day, days: 3, calendar: calendar)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            return spanning(scale, from: start, days: 7, calendar: calendar)
        case .month:
            let start = calendar.dateInterval(of: .month, for: day)?.start ?? day
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let gridStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            let gridEnd = calendar.date(byAdding: .day, value: monthGridDays, to: gridStart) ?? end
            return CalendarPeriod(scale: .month, start: start, end: end, visibleStart: gridStart, visibleEnd: gridEnd)
        }
    }

    private static func spanning(_ scale: CalendarScale, from start: Date, days: Int, calendar: Calendar) -> CalendarPeriod {
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return CalendarPeriod(scale: scale, start: start, end: end, visibleStart: start, visibleEnd: end)
    }

    /// The period `offset` pages away (negative = earlier).
    func shifted(by offset: Int, calendar: Calendar = .app) -> CalendarPeriod {
        guard offset != 0 else { return self }
        let target: Date? = switch scale {
        case .day: calendar.date(byAdding: .day, value: offset, to: start)
        case .threeDays: calendar.date(byAdding: .day, value: 3 * offset, to: start)
        case .week: calendar.date(byAdding: .day, value: 7 * offset, to: start)
        case .month: calendar.date(byAdding: .month, value: offset, to: start)
        }
        return CalendarPeriod.containing(target ?? start, scale: scale, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Local midnights of every visible day.
    func days(calendar: Calendar = .app) -> [Date] {
        var result: [Date] = []
        var day = visibleStart
        while day < visibleEnd {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// "15 октября", "15–17 окт.", "28 сент. – 4 окт.", "Октябрь 2026".
    func title(calendar: Calendar = .app, now: Date = .now) -> String {
        let style = Date.FormatStyle(locale: .app, calendar: calendar, timeZone: calendar.timeZone)
        let currentYear = calendar.component(.year, from: now)
        switch scale {
        case .month:
            let formatter = DateFormatter()
            formatter.locale = .app
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "LLLL yyyy"
            let text = formatter.string(from: start)
            return text.prefix(1).uppercased() + text.dropFirst()
        case .day:
            let showsYear = calendar.component(.year, from: start) != currentYear
            return start.formatted(showsYear ? style.day().month(.wide).year() : style.day().month(.wide))
        case .threeDays, .week:
            let last = calendar.date(byAdding: .day, value: -1, to: end) ?? start
            let startYear = calendar.component(.year, from: start)
            let lastYear = calendar.component(.year, from: last)
            if startYear != lastYear {
                let withYear = style.day().month(.abbreviated).year()
                return "\(start.formatted(withYear)) – \(last.formatted(withYear))"
            }
            let lastStyle = lastYear == currentYear ? style.day().month(.abbreviated) : style.day().month(.abbreviated).year()
            if calendar.isDate(start, equalTo: last, toGranularity: .month) {
                return "\(start.formatted(style.day()))–\(last.formatted(lastStyle))"
            }
            return "\(start.formatted(style.day().month(.abbreviated))) – \(last.formatted(lastStyle))"
        }
    }
}
