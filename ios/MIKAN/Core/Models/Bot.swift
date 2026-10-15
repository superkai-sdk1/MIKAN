import Foundation

nonisolated enum MessageRole: String, Codable, Sendable {
    /// Client
    case user
    /// AI
    case assistant
    /// Employee, sent from the app
    case staff
    /// Automatic: aftercare, reminders
    case system
}

nonisolated struct BotMessage: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let chatId: Int64
    let role: MessageRole
    let text: String
    let employee: EmployeeRef?
    let createdAt: Date
}

nonisolated struct BotChat: Codable, Hashable, Identifiable, Sendable {
    let chatId: Int64
    var client: ClientRef?
    var telegramName: String?
    var username: String?
    var aiPaused: Bool
    var needsAttention: Bool
    var unreadCount: Int
    var lastMessage: BotMessage?
    var updatedAt: Date

    var id: Int64 { chatId }

    var displayName: String {
        client?.name ?? telegramName.nonEmpty ?? username.nonEmpty.map { "@\($0)" } ?? "Без имени"
    }
}

/// `GET /clients/:id/chat`.
nonisolated struct ClientChatResponse: Codable, Sendable {
    let chat: BotChat?
}

nonisolated enum ScheduledKind: String, Codable, Sendable {
    case aftercare
    case reminder
}

nonisolated enum ScheduledStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case sent
    case failed
    case cancelled
}

nonisolated struct ScheduledMessage: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let chatId: Int64
    let client: ClientRef?
    let appointmentId: Int?
    let kind: ScheduledKind
    let sendAt: Date
    let text: String
    let status: ScheduledStatus
    let sentAt: Date?
    let error: String?
}

nonisolated enum BookingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case new
    case processed
    case rejected

    var id: String { rawValue }
}

nonisolated struct BookingRequest: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let chatId: Int64?
    let client: ClientRef?
    let contactName: String?
    let phone: String?
    let serviceName: String?
    let preferredTime: String?
    let comment: String?
    let status: BookingStatus
    let createdAt: Date
    let updatedAt: Date

    var displayName: String { client?.name ?? contactName.nonEmpty ?? "Без имени" }
}

nonisolated struct KnowledgeEntry: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var title: String
    var content: String
    var active: Bool
    var sort: Int
    let updatedAt: Date
}

nonisolated struct StaffCode: Codable, Sendable {
    let code: String
    let expiresAt: Date
    let instruction: String
}

nonisolated struct BotTestReply: Codable, Sendable {
    let reply: String
}
