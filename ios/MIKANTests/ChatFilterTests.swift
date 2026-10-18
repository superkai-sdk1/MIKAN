import XCTest
@testable import MIKAN

/// The chats list filter: client and staff chats, and the search across names.
final class ChatFilterTests: XCTestCase {
    private func chats() throws -> [BotChat] {
        [
            try Fixtures.decode(BotChat.self, Fixtures.botChat),
            try Fixtures.decode(BotChat.self, Fixtures.staffBotChat),
        ]
    }

    func testFiltersSplitClientAndStaffChats() throws {
        let all = try chats()
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "").map(\.chatId), [123_456_789, 987_654_321])
        XCTAssertEqual(ChatFilter.clients.apply(to: all, search: "").map(\.chatId), [123_456_789])
        XCTAssertEqual(ChatFilter.staff.apply(to: all, search: "").map(\.chatId), [987_654_321])
    }

    func testSearchMatchesNamesUsernameAndPhone() throws {
        let all = try chats()
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "  АННА ").map(\.chatId), [987_654_321], "employee name")
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "аня").map(\.chatId), [987_654_321], "Telegram name")
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "ivanp").map(\.chatId), [123_456_789])
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "петров").map(\.chatId), [123_456_789])
        XCTAssertEqual(ChatFilter.all.apply(to: all, search: "9991234").map(\.chatId), [123_456_789])
        XCTAssertTrue(ChatFilter.staff.apply(to: all, search: "ivan").isEmpty, "search stays within the filter")
    }

    func testTitles() {
        XCTAssertEqual(ChatFilter.allCases.map(\.title), ["Все", "Клиенты", "Сотрудники"])
    }

    func testUnlinkedChatBecomesAClientChat() throws {
        var staff = try Fixtures.decode(BotChat.self, Fixtures.staffBotChat)
        staff.employee = nil
        XCTAssertFalse(staff.isStaff)
        XCTAssertTrue(ChatFilter.clients.includes(staff))
        XCTAssertEqual(staff.displayName, "Аня", "falls back to the Telegram name")
    }
}
