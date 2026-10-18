import Foundation

/// When the bot reminds a client about an appointment: minutes before its start, earliest reminder first.
/// Mirrors the server limits of `BotSettings.reminderOffsets`: 1–6 distinct values from 15 minutes to 14 days.
nonisolated struct ReminderSchedule: Hashable, Sendable {
    static let minMinutes = 15
    static let maxMinutes = 14 * ReminderParts.minutesPerDay
    static let maxCount = 6
    /// The server default: a day before.
    static let standard = ReminderSchedule(offsets: [ReminderParts.minutesPerDay])
    /// Quick picks of the «add» menu: 15 minutes … a week.
    static let presets = [15, 30, 60, 120, 180, 360, 720, 1440, 2880, 4320, 10_080]

    /// Distinct offsets in minutes, earliest reminder (largest offset) first.
    let offsets: [Int]

    init(offsets: [Int]) {
        self.offsets = Array(Set(offsets)).sorted(by: >)
    }

    var canAdd: Bool { offsets.count < Self.maxCount }
    /// At least one reminder stays while reminders are on.
    var canRemove: Bool { offsets.count > 1 }

    /// Presets that are not in the schedule yet.
    var availablePresets: [Int] { Self.presets.filter { !offsets.contains($0) }.sorted(by: >) }

    // MARK: - Editing

    func adding(_ minutes: Int) -> Result<ReminderSchedule, Issue> {
        if let issue = addIssue(for: minutes) { return .failure(issue) }
        return .success(ReminderSchedule(offsets: offsets + [minutes]))
    }

    /// Why `minutes` cannot be added, or `nil` when it can.
    func addIssue(for minutes: Int) -> Issue? {
        if let issue = Self.issue(forOffset: minutes) { return issue }
        if offsets.contains(minutes) { return .duplicate }
        return canAdd ? nil : .tooMany
    }

    /// Removes a reminder; the last one stays.
    func removing(_ minutes: Int) -> ReminderSchedule {
        guard canRemove else { return self }
        return ReminderSchedule(offsets: offsets.filter { $0 != minutes })
    }

    // MARK: - Validation

    nonisolated enum Issue: Error, Hashable, Sendable {
        case empty
        case tooMany
        case tooSoon
        case tooFar
        case duplicate

        var message: String {
            switch self {
            case .empty: "Добавьте хотя бы одно напоминание."
            case .tooMany: "Не больше \(ReminderSchedule.maxCount) напоминаний."
            case .tooSoon: "Самое позднее напоминание — \(ReminderSchedule.label(ReminderSchedule.minMinutes)) до записи."
            case .tooFar: "Самое раннее напоминание — \(ReminderSchedule.label(ReminderSchedule.maxMinutes)) до записи."
            case .duplicate: "Такое напоминание уже есть."
            }
        }
    }

    /// «Не позже чем за 15 минут и не раньше чем за 14 дней до записи.»
    static var limitsHint: String {
        "Не позже чем \(label(minMinutes)) и не раньше чем \(label(maxMinutes)) до записи."
    }

    static func issue(forOffset minutes: Int) -> Issue? {
        if minutes < minMinutes { return .tooSoon }
        if minutes > maxMinutes { return .tooFar }
        return nil
    }

    /// What the server would reject, or `nil` when the schedule can be saved.
    var issue: Issue? {
        if offsets.isEmpty { return .empty }
        if offsets.count > Self.maxCount { return .tooMany }
        return offsets.lazy.compactMap(Self.issue(forOffset:)).first
    }

    // MARK: - Labels

    /// «за 1 день», «за 2 часа», «за 1 час 30 минут»; whole weeks read as weeks: «за 1 неделю».
    static func label(_ minutes: Int) -> String {
        let week = 7 * ReminderParts.minutesPerDay
        if minutes > 0, minutes.isMultiple(of: week) {
            return "за " + Plural.count(minutes / week, one: "неделю", few: "недели", many: "недель")
        }
        let parts = ReminderParts(totalMinutes: minutes)
        var words: [String] = []
        if parts.days > 0 { words.append(Plural.days(parts.days)) }
        if parts.hours > 0 { words.append(Plural.count(parts.hours, one: "час", few: "часа", many: "часов")) }
        if parts.minutes > 0 || words.isEmpty {
            // Accusative after «за»: «за 1 минуту», «за 21 минуту».
            words.append(Plural.count(parts.minutes, one: "минуту", few: "минуты", many: "минут"))
        }
        return "за " + words.joined(separator: " ")
    }

    /// The label as a row title: «За 1 день».
    static func title(_ minutes: Int) -> String {
        let text = label(minutes)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var labels: [String] { offsets.map(Self.label) }

    /// «за 3 дня, за 1 день и за 2 часа»; `nil` when empty.
    var summary: String? {
        guard let last = labels.last else { return nil }
        let head = labels.dropLast()
        return head.isEmpty ? last : head.joined(separator: ", ") + " и " + last
    }

    /// «Клиент получит: за 1 день и за 2 часа до записи — с кнопками «Приду» и «Перенести»».
    var preview: String? {
        summary.map { "Клиент получит: \($0) до записи — с кнопками «Приду» и «Перенести»" }
    }

    // MARK: - Wire format

    /// Offsets from `GET /settings/bot`: `reminderOffsets`, else the single `reminderHoursBefore` of older servers,
    /// else the server default.
    static func offsets(decoded: [Int]?, legacyHours: Int?) -> [Int] {
        if let decoded, !decoded.isEmpty { return ReminderSchedule(offsets: decoded).offsets }
        if let legacyHours, legacyHours > 0 { return [legacyHours * 60] }
        return standard.offsets
    }

    /// `reminderHoursBefore` for servers that keep a single reminder: the earliest one in whole hours (1…168).
    var legacyHoursBefore: Int {
        let earliest = offsets.first ?? Self.standard.offsets[0]
        let hours = Int((Double(earliest) / 60).rounded())
        return min(max(hours, 1), 168)
    }
}

/// Days, hours and minutes of an offset: the custom value picker and the labels.
nonisolated struct ReminderParts: Hashable, Sendable {
    static let minutesPerDay = 24 * 60

    var days: Int
    var hours: Int
    var minutes: Int

    init(days: Int, hours: Int, minutes: Int) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
    }

    init(totalMinutes: Int) {
        let total = max(0, totalMinutes)
        self.init(days: total / Self.minutesPerDay, hours: total % Self.minutesPerDay / 60, minutes: total % 60)
    }

    var totalMinutes: Int { days * Self.minutesPerDay + hours * 60 + minutes }
}
