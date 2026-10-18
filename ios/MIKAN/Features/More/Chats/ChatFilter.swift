import Foundation

/// Which chats the list shows: all, client chats or staff chats (recognised by the shared phone).
nonisolated enum ChatFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case clients
    case staff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Все"
        case .clients: "Клиенты"
        case .staff: "Сотрудники"
        }
    }

    func includes(_ chat: BotChat) -> Bool {
        switch self {
        case .all: true
        case .clients: !chat.isStaff
        case .staff: chat.isStaff
        }
    }

    /// Chats of this kind matching the search text, in the given order.
    func apply(to chats: [BotChat], search: String) -> [BotChat] {
        let query = search.trimmed.lowercased()
        return chats.filter { includes($0) && (query.isEmpty || $0.matches(query: query)) }
    }
}

extension BotChat {
    /// `query` is lowercased: matches the shown name, Telegram name and username, the client's phone
    /// and the employee's name.
    nonisolated func matches(query: String) -> Bool {
        [displayName, username, telegramName, client?.phone, client?.fullName, employee?.name]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
    }
}
