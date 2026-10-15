import Foundation

// MARK: - Auth, badges, dashboard, employees, settings

extension APIClient {
    func login(_ login: String, password: String) async throws -> LoginResponse {
        try await request(.post, "auth/login", body: LoginBody(login: login, password: password))
    }

    func me() async throws -> Employee {
        try await request(.get, "auth/me")
    }

    func badges() async throws -> Badges {
        try await request(.get, "badges")
    }

    func dashboard() async throws -> Dashboard {
        try await request(.get, "dashboard")
    }

    func employees(includeInactive: Bool = false) async throws -> [Employee] {
        let response: ItemsResponse<Employee> = try await request(
            .get, "employees",
            query: queryItems(["includeInactive": includeInactive ? "true" : nil])
        )
        return response.items
    }

    func createEmployee(_ body: EmployeeBody) async throws -> Employee {
        try await request(.post, "employees", body: body)
    }

    func updateEmployee(id: Int, _ body: EmployeeBody) async throws -> Employee {
        try await request(.patch, "employees/\(id)", body: body)
    }

    func studioSettings() async throws -> StudioSettings {
        try await request(.get, "settings/studio")
    }

    func saveStudioSettings(_ settings: StudioSettings) async throws -> StudioSettings {
        try await request(.put, "settings/studio", body: settings)
    }

    func botSettings() async throws -> BotSettings {
        try await request(.get, "settings/bot")
    }

    func saveBotSettings(_ settings: BotSettings) async throws -> BotSettings {
        try await request(.put, "settings/bot", body: settings)
    }
}
