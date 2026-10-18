import Foundation
import Testing
@testable import MIKAN

/// «Это сотрудник…»: which chats offer it, whom it offers and what the confirmation says.
@MainActor
struct StaffBindingTests {
    private func employee(_ id: Int, _ name: String, active: Bool = true) -> Employee {
        Employee(id: id, name: name, login: "e\(id)", phone: nil, color: nil, isMaster: true, active: active, createdAt: .distantPast)
    }

    private func chat(telegramName: String?, username: String? = nil, employee: EmployeeRef? = nil) throws -> BotChat {
        var chat = try Fixtures.decode(BotChat.self, Fixtures.botChat)
        chat.telegramName = telegramName
        chat.username = username
        chat.employee = employee
        return chat
    }

    private var employees: [Employee] {
        [employee(1, "Кантемир"), employee(2, "Амина Сидорова"), employee(3, "Олег", active: false), employee(4, "Алёна")]
    }

    @Test("Only a chat that is not a staff chat offers binding")
    func onlyNonStaffChats() throws {
        #expect(StaffBinding.canBind(try chat(telegramName: "Иван")))
        #expect(!StaffBinding.canBind(try Fixtures.decode(BotChat.self, Fixtures.staffBotChat)))
    }

    @Test("Active employees only, alphabetically, the Telegram first name first")
    func candidatesOrder() throws {
        let plain = StaffBinding.candidates(from: employees, for: try chat(telegramName: "Иван"))
        #expect(plain.map(\.name) == ["Алёна", "Амина Сидорова", "Кантемир"])

        let amina = StaffBinding.candidates(from: employees, for: try chat(telegramName: "  амина К."))
        #expect(amina.map(\.id) == [2, 4, 1])

        let alena = StaffBinding.candidates(from: employees, for: try chat(telegramName: "Алена"))
        #expect(alena.first?.name == "Алёна", "«ё» and «е» match")

        let unnamed = StaffBinding.candidates(from: employees, for: try chat(telegramName: nil))
        #expect(unnamed.map(\.id) == [4, 2, 1])
        #expect(StaffBinding.candidates(from: [], for: try chat(telegramName: "Иван")).isEmpty)
    }

    @Test("The confirmation names the Telegram account and what staff mode opens")
    func confirmation() throws {
        let amina = employee(2, "Амина")
        let both = try chat(telegramName: "Амина К", username: "amina_k")
        #expect(StaffBinding.telegramIdentity(of: both) == "Амина К (@amina_k)")
        #expect(StaffBinding.telegramIdentity(of: try chat(telegramName: nil, username: "amina_k")) == "@amina_k")
        #expect(StaffBinding.telegramIdentity(of: try chat(telegramName: " ", username: nil)) == "без имени")

        let message = StaffBinding.confirmationMessage(employee: amina, chat: both)
        #expect(message.hasPrefix("Чат «Амина К (@amina_k)» станет чатом сотрудника Амина"))
        #expect(message.contains("записи, клиенты, выручка и остатки"))
        #expect(message.contains("только если это Telegram сотрудника"))
    }
}
