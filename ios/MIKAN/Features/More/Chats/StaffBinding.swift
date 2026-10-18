import Foundation

/// «Это сотрудник…»: binding an ordinary chat to an employee by hand (`PUT /bot/chats/:chatId/employee`),
/// for employees who never shared their phone with the bot.
nonisolated enum StaffBinding {
    /// Only a chat that is not a staff chat yet offers the action.
    static func canBind(_ chat: BotChat) -> Bool { !chat.isStaff }

    /// Active employees to pick from: those whose first name matches the chat's Telegram name first,
    /// then the rest, alphabetically.
    static func candidates(from employees: [Employee], for chat: BotChat) -> [Employee] {
        let telegramFirstName = firstName(chat.telegramName)
        let active = employees.filter(\.active).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard let telegramFirstName else { return active }
        let matching = active.filter { firstName($0.name) == telegramFirstName }
        return matching + active.filter { firstName($0.name) != telegramFirstName }
    }

    /// Who the chat is in Telegram, for the confirmation: «Амина (@amina_k)».
    static func telegramIdentity(of chat: BotChat) -> String {
        let name = chat.telegramName.nonEmpty
        let username = chat.username.nonEmpty.map { "@\($0)" }
        switch (name, username) {
        case let (name?, username?): return "\(name) (\(username))"
        case let (name?, nil): return name
        case let (nil, username?): return username
        case (nil, nil): return "без имени"
        }
    }

    /// Staff mode opens the studio's data to this Telegram account, so the dialog says so plainly.
    static func confirmationMessage(employee: Employee, chat: BotChat) -> String {
        "Чат «\(telegramIdentity(of: chat))» станет чатом сотрудника \(employee.name): бот будет отвечать в нём "
            + "как помощник студии — записи, клиенты, выручка и остатки. Привязывайте, только если это Telegram "
            + "сотрудника. Бот пришлёт \(employee.name) приветствие и кнопки для сотрудников."
    }

    /// The first word, case- and «ё»-insensitive: «Амина К.» and «амина» match.
    private static func firstName(_ name: String?) -> String? {
        guard let word = name?.trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        return word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}
