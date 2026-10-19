import Foundation

/// Choices, texts and validation of «Онлайн-запись» in the studio settings (docs/API.md «StudioSettings»).
nonisolated enum OnlineBookingOptions {
    static let leadChoices = [0, 30, 60, 120, 180, 240, 360, 720, 1440, 2880]
    static let horizonChoices = [7, 14, 30, 45, 60, 90, 120, 180]
    static let holdChoices = [5, 10, 15, 20, 30, 45, 60]
    static let stepChoices = OnlineBookingSettings.steps

    private static let minutesPerDay = 1440

    /// The choices plus a value set elsewhere (so the picker can show it).
    static func leads(including current: Int) -> [Int] { merged(leadChoices, current) }
    static func horizons(including current: Int) -> [Int] { merged(horizonChoices, current) }
    static func holds(including current: Int) -> [Int] { merged(holdChoices, current) }
    static func steps(including current: Int) -> [Int] { merged(stepChoices, current) }

    /// «Без ограничения», «30 мин», «2 ч», «1 день».
    static func leadTitle(_ minutes: Int) -> String {
        minutes <= 0 ? "Без ограничения" : minutesTitle(minutes)
    }

    /// «60 дней».
    static func horizonTitle(_ days: Int) -> String { Plural.days(days) }

    /// «45 мин», «1 ч», «1 ч 30 мин», «2 дня».
    static func minutesTitle(_ minutes: Int) -> String {
        if minutes >= minutesPerDay, minutes % minutesPerDay == 0 {
            return Plural.days(minutes / minutesPerDay)
        }
        return DateText.duration(minutes: minutes)
    }

    /// What the rules mean for clients, under the section.
    static func footer(_ settings: OnlineBookingSettings) -> String {
        guard settings.enabled else {
            return "Онлайн-запись выключена: страница записи покажет «Онлайн-запись временно недоступна», а бот будет принимать заявки."
        }
        let earliest = settings.leadMinutes > 0 ? "не позже чем за \(minutesTitle(settings.leadMinutes)) до начала" : "на любое свободное время"
        return "Клиенты записываются сами — на сайте, в Mini App и через бота: \(earliest), на \(horizonTitle(settings.horizonDays)) вперёд, начало каждые \(minutesTitle(settings.stepMinutes)) по графику мастера. Если услуга с предоплатой, на оплату по QR даётся \(minutesTitle(settings.holdMinutes)) — потом время освободится. Без предоплаты запись ждёт вашего подтверждения."
    }

    private static func merged(_ choices: [Int], _ current: Int) -> [Int] {
        choices.contains(current) ? choices : (choices + [current]).sorted()
    }
}

/// What blocks saving «Онлайн-запись», mirroring the server's limits.
nonisolated enum OnlineBookingRules {
    /// A Russian message, or `nil` when the settings can be saved.
    static func issue(_ settings: OnlineBookingSettings) -> String? {
        if !OnlineBookingSettings.leadRange.contains(settings.leadMinutes) {
            return "Запись не позже чем за — от 0 минут до 2 дней."
        }
        if !OnlineBookingSettings.horizonRange.contains(settings.horizonDays) {
            return "Запись вперёд — от 1 до 180 дней."
        }
        if !OnlineBookingSettings.holdRange.contains(settings.holdMinutes) {
            return "Время на оплату — от 5 до 60 минут."
        }
        if !OnlineBookingSettings.steps.contains(settings.stepMinutes) {
            return "Шаг времени — 15, 30 или 60 минут."
        }
        // The server counts UTF-16 code units (an emoji takes two).
        if settings.note.utf16.count > OnlineBookingSettings.maxNoteLength {
            return "Заметка для клиентов — не длиннее \(OnlineBookingSettings.maxNoteLength) символов."
        }
        return nil
    }
}
