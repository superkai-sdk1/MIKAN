import Foundation

/// Report period; boundaries are local (device time zone) day starts sent as instants.
nonisolated enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Сегодня"
        case .week: "Неделя"
        case .month: "Месяц"
        case .custom: "Период"
        }
    }

    /// Half-open interval `[start, end)`. Week and month run from their start up to the end of today.
    func interval(now: Date = .now, customFrom: Date, customTo: Date, calendar: Calendar = .app) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .today:
            return DateInterval(start: today, end: tomorrow)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            return DateInterval(start: start, end: tomorrow)
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? today
            return DateInterval(start: start, end: tomorrow)
        case .custom:
            let from = calendar.startOfDay(for: min(customFrom, customTo))
            let lastDay = calendar.startOfDay(for: max(customFrom, customTo))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateInterval(start: from, end: end)
        }
    }
}
