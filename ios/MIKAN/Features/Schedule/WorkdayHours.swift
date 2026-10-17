import Foundation

/// Studio working hours («с 10:00 до 21:00») in the studio time zone. They only set the calendar's default
/// range: appointments may start earlier or end later, and the calendar widens to show them.
nonisolated struct WorkdayHours: Hashable, Sendable {
    /// The server's default, used until the settings load (and by servers that predate working hours).
    static let standard = WorkdayHours(startMinute: 11 * 60, endMinute: 21 * 60, timeZone: .current)

    /// Minutes since the studio's midnight.
    let startMinute: Int
    /// Minutes since the studio's midnight; up to 1440 ("24:00").
    let endMinute: Int
    let timeZone: TimeZone

    init(startMinute: Int, endMinute: Int, timeZone: TimeZone) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.timeZone = timeZone
    }

    /// `nil` for malformed or reversed times. An unknown time zone falls back to the device's.
    init?(start: String, end: String, timeZoneIdentifier: String) {
        guard let startMinute = Self.minute(from: start), let endMinute = Self.minute(from: end), startMinute < endMinute
        else { return nil }
        self.init(startMinute: startMinute, endMinute: endMinute, timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current)
    }

    /// Hours from the studio settings; malformed or reversed times fall back to the `standard` hours.
    init(settings: StudioSettings) {
        self = WorkdayHours(start: settings.workdayStart, end: settings.workdayEnd, timeZoneIdentifier: settings.timezone)
            ?? WorkdayHours(
                startMinute: Self.standard.startMinute,
                endMinute: Self.standard.endMinute,
                timeZone: TimeZone(identifier: settings.timezone) ?? .current
            )
    }

    var startText: String { Self.text(fromMinute: startMinute) }
    var endText: String { Self.text(fromMinute: endMinute) }
    /// "10:00–21:00"
    var title: String { "\(startText)–\(endText)" }

    /// "9:30" / "09:30" → 570; "24:00" → 1440; nil when malformed.
    static func minute(from text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0...24).contains(hours), (0...59).contains(minutes), hours < 24 || minutes == 0
        else { return nil }
        return hours * 60 + minutes
    }

    /// 570 → "09:30"; 1440 → "24:00".
    static func text(fromMinute minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// Picker choices "HH:mm" every `step` minutes within `bounds`, plus `current` when it falls between steps.
    static func timeOptions(in bounds: ClosedRange<Int>, step: Int = 30, including current: String) -> [String] {
        var minutes = Array(stride(from: bounds.lowerBound, through: bounds.upperBound, by: step))
        if let extra = minute(from: current), bounds.contains(extra), !minutes.contains(extra) {
            minutes.append(extra)
            minutes.sort()
        }
        return minutes.map(text(fromMinute:))
    }

    /// The working hours of `day` (a local midnight of `calendar`) as minutes since that midnight.
    /// The studio's date with the same day number is used, so a phone in another time zone sees the hours shifted.
    func window(on day: Date, calendar: Calendar) -> Range<Int> {
        var studioCalendar = calendar
        studioCalendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = 0
        parts.minute = 0
        guard let studioMidnight = studioCalendar.date(from: parts) else {
            return startMinute..<endMinute
        }
        let offset = Int((studioMidnight.timeIntervalSince(day) / 60).rounded())
        let lower = min(max(0, startMinute + offset), TimeGridLayout.minutesPerDay)
        let upper = min(max(lower, endMinute + offset), TimeGridLayout.minutesPerDay)
        return lower..<upper
    }

    /// Whether `start…end` lies inside the working hours of the studio day it starts on.
    func contains(start: Date, end: Date, calendar: Calendar) -> Bool {
        var studioCalendar = calendar
        studioCalendar.timeZone = timeZone
        let dayStart = studioCalendar.startOfDay(for: start)
        let startOffset = start.timeIntervalSince(dayStart) / 60
        let endOffset = end.timeIntervalSince(dayStart) / 60
        return startOffset >= Double(startMinute) && endOffset <= Double(endMinute)
    }
}
