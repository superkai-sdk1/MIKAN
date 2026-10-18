import Foundation

/// Report period; boundaries are local (device time zone) day starts sent as instants.
nonisolated enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case week
    case month
    case quarter
    case year
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Сегодня"
        case .yesterday: "Вчера"
        case .week: "Неделя"
        case .month: "Месяц"
        case .quarter: "Квартал"
        case .year: "Год"
        case .custom: "Период"
        }
    }

    /// Half-open interval `[start, end)`. Week, month, quarter and year run from their start up to the end of today.
    func interval(now: Date = .now, customFrom: Date, customTo: Date, calendar: Calendar = .app) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let toDate = { (start: Date?) in DateInterval(start: start ?? today, end: tomorrow) }
        switch self {
        case .today:
            return DateInterval(start: today, end: tomorrow)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: yesterday, end: today)
        case .week:
            return toDate(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        case .month:
            return toDate(calendar.dateInterval(of: .month, for: now)?.start)
        case .quarter:
            return toDate(Self.quarterStart(of: now, calendar: calendar))
        case .year:
            return toDate(calendar.dateInterval(of: .year, for: now)?.start)
        case .custom:
            let from = calendar.startOfDay(for: min(customFrom, customTo))
            let lastDay = calendar.startOfDay(for: max(customFrom, customTo))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateInterval(start: from, end: end)
        }
    }

    /// 1 January, 1 April, 1 July or 1 October (Foundation's `.quarter` interval is not reliable).
    static func quarterStart(of date: Date, calendar: Calendar = .app) -> Date? {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        return calendar.date(from: DateComponents(year: year, month: (month - 1) / 3 * 3 + 1, day: 1))
    }

    /// The longest range the server reports on.
    static let maxDays = 400

    /// «15 октября» for one day, «1 – 18 октября», «28 сентября – 4 октября», «1 января 2025 – 18 октября 2026»
    /// (the year only when it is not the current one).
    static func rangeText(_ interval: DateInterval, now: Date = .now, calendar: Calendar = .app) -> String {
        let first = interval.start
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end).map { max($0, first) } ?? first
        let style = Date.FormatStyle(locale: .app, calendar: calendar, timeZone: calendar.timeZone)
        let withYear = !calendar.isDate(last, equalTo: now, toGranularity: .year)
        let tail = last.formatted(withYear ? style.day().month(.wide).year() : style.day().month(.wide))
        if calendar.isDate(first, inSameDayAs: last) { return tail }
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(first.formatted(style.day())) – \(tail)"
        }
        let sameYear = calendar.isDate(first, equalTo: last, toGranularity: .year)
        let head = first.formatted(sameYear ? style.day().month(.wide) : style.day().month(.wide).year())
        return "\(head) – \(tail)"
    }
}
