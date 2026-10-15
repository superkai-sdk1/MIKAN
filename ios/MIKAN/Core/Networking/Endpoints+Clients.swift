import Foundation

// MARK: - Clients and appointments

extension APIClient {
    func clients(search: String = "", archived: Bool = false, limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<Client> {
        try await request(.get, "clients", query: queryItems([
            "search": search.nonEmpty,
            "archived": archived ? "true" : "false",
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    func client(id: Int) async throws -> Client {
        try await request(.get, "clients/\(id)")
    }

    func createClient(_ body: ClientBody) async throws -> Client {
        try await request(.post, "clients", body: body)
    }

    func updateClient(id: Int, _ body: ClientBody) async throws -> Client {
        try await request(.patch, "clients/\(id)", body: body)
    }

    func setClientArchived(id: Int, archived: Bool) async throws -> Client {
        try await request(.patch, "clients/\(id)", body: ArchiveBody(archived: archived))
    }

    func clientHistory(id: Int) async throws -> ClientHistory {
        try await request(.get, "clients/\(id)/history")
    }

    /// The client's Telegram bot chat, or nil if the client has never written to the bot.
    func clientChat(clientId: Int) async throws -> BotChat? {
        let response: ClientChatResponse = try await request(.get, "clients/\(clientId)/chat")
        return response.chat
    }

    func telegramLink(clientId: Int) async throws -> LinkResponse {
        try await request(.post, "clients/\(clientId)/telegram-link")
    }

    func appointments(
        from: Date,
        to: Date,
        masterId: Int? = nil,
        clientId: Int? = nil,
        status: AppointmentStatus? = nil
    ) async throws -> [Appointment] {
        let response: ItemsResponse<Appointment> = try await request(.get, "appointments", query: queryItems([
            "from": ISO8601.string(from: from),
            "to": ISO8601.string(from: to),
            "masterId": masterId.map(String.init),
            "clientId": clientId.map(String.init),
            "status": status?.rawValue,
        ]))
        return response.items
    }

    func appointment(id: Int) async throws -> Appointment {
        try await request(.get, "appointments/\(id)")
    }

    func createAppointment(_ body: AppointmentBody) async throws -> Appointment {
        try await request(.post, "appointments", body: body)
    }

    func updateAppointment(id: Int, _ body: AppointmentBody) async throws -> Appointment {
        try await request(.patch, "appointments/\(id)", body: body)
    }

    func setAppointmentStatus(id: Int, _ status: AppointmentStatus) async throws -> Appointment {
        try await request(.patch, "appointments/\(id)", body: StatusBody(status: status))
    }

    func completeAppointment(id: Int, _ body: CompleteBody) async throws -> CompleteAppointmentResult {
        try await request(.post, "appointments/\(id)/complete", body: body)
    }
}
