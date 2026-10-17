import XCTest
@testable import MIKAN

/// Client card: first and last name, required phone, Telegram nick.
final class ClientCardTests: XCTestCase {
    private func client(phone: String?, lastName: String? = nil, telegramNick: String? = nil, telegramUsername: String? = nil) -> Client {
        Client(
            id: 7, name: "Борис", lastName: lastName, phone: phone, instagram: nil, telegramNick: telegramNick,
            birthday: "1990-03-08", notes: "Постоянный клиент", source: "yclients", telegramLinked: false,
            telegramUsername: telegramUsername, botEnabled: false, archived: false,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate, stats: nil
        )
    }

    private func json(_ body: ClientBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFullNameJoinsFirstAndLastName() {
        XCTAssertEqual(PersonName.full("Иван", "Петров"), "Иван Петров")
        XCTAssertEqual(PersonName.full("Иван Петров", nil), "Иван Петров", "older cards keep the full name in `name`")
        XCTAssertEqual(PersonName.full(" Иван ", "  "), "Иван")
        XCTAssertEqual(client(phone: nil, lastName: "Ёлкин").fullName, "Борис Ёлкин")
        XCTAssertEqual(client(phone: nil, lastName: "Ёлкин").ref.fullName, "Борис Ёлкин")
    }

    func testOneLineNameSplitsIntoFirstAndLastName() {
        XCTAssertTrue(PersonName.split("Анна Смирнова") == ("Анна", "Смирнова"))
        XCTAssertTrue(PersonName.split("  Анна   Мария  Смирнова ") == ("Анна", "Мария Смирнова"))
        XCTAssertTrue(PersonName.split("Анна") == ("Анна", ""))
        XCTAssertTrue(PersonName.split("   ") == ("", ""))
    }

    func testTelegramHandlePrefersTheTypedNick() {
        XCTAssertEqual(client(phone: nil, telegramNick: "boris_e", telegramUsername: "bot_seen").telegramHandle, "boris_e")
        XCTAssertEqual(client(phone: nil, telegramNick: "", telegramUsername: "bot_seen").telegramHandle, "bot_seen")
        XCTAssertNil(client(phone: nil).telegramHandle)
    }

    func testNewClientNeedsNameAndPhone() {
        var draft = ClientDraft()
        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.missingFieldsHint, "Укажите имя и телефон.")
        draft.name = "Иван"
        XCTAssertEqual(draft.missingFieldsHint, "Укажите телефон.")
        draft.phone = "   "
        XCTAssertFalse(draft.canSave, "a blank phone is no phone")
        draft.phone = "+7 999 123-45-67"
        XCTAssertTrue(draft.canSave)
        XCTAssertNil(draft.missingFieldsHint)
        draft.name = " "
        XCTAssertEqual(draft.missingFieldsHint, "Укажите имя.")
    }

    func testLastNameBirthdayAndNickAreOptional() throws {
        var draft = ClientDraft()
        draft.name = " Иван "
        draft.phone = "89991234567"
        XCTAssertTrue(draft.canSave)

        let body = try json(draft.body())
        XCTAssertEqual(body["name"] as? String, "Иван")
        XCTAssertEqual(body["phone"] as? String, "89991234567")
        for key in ["lastName", "telegramNick", "birthday", "instagram", "notes", "source"] {
            XCTAssertTrue(body[key] is NSNull, "\(key) is sent as null")
        }
    }

    func testBodyCarriesLastNameNickAndBirthday() throws {
        var draft = ClientDraft()
        draft.name = "Иван"
        draft.lastName = " Петров "
        draft.phone = "+79991234567"
        draft.telegramNick = " https://t.me/ivan_petrov/ "
        draft.instagram = "@ivan.p"
        draft.hasBirthday = true
        draft.birthday = try XCTUnwrap(Calendar.app.date(from: DateComponents(year: 1995, month: 4, day: 12)))

        let body = try json(draft.body())
        XCTAssertEqual(body["lastName"] as? String, "Петров")
        XCTAssertEqual(body["telegramNick"] as? String, "ivan_petrov")
        XCTAssertEqual(body["instagram"] as? String, "ivan.p")
        XCTAssertEqual(body["birthday"] as? String, "1995-04-12")
        XCTAssertEqual(draft.fullName, "Иван Петров")
    }

    func testCardImportedWithoutPhoneStaysEditable() throws {
        var draft = ClientDraft(client: client(phone: nil))
        XCTAssertFalse(draft.requiresPhone)
        XCTAssertTrue(draft.canSave, "other fields can be changed without adding a phone")
        draft.notes = "Новая заметка"
        let body = try json(draft.body())
        XCTAssertTrue(body["phone"] is NSNull)
        XCTAssertEqual(body["notes"] as? String, "Новая заметка")
        XCTAssertEqual(body["birthday"] as? String, "1990-03-08")
        XCTAssertEqual(body["botEnabled"] as? Bool, false)
    }

    func testPhoneOfAnExistingCardCannotBeRemoved() {
        var draft = ClientDraft(client: client(phone: "+79991234567", lastName: "Ёлкин", telegramNick: "boris_e"))
        XCTAssertTrue(draft.requiresPhone)
        XCTAssertEqual(draft.lastName, "Ёлкин")
        XCTAssertEqual(draft.telegramNick, "boris_e")
        XCTAssertTrue(draft.canSave)
        draft.phone = ""
        XCTAssertFalse(draft.canSave)
    }

    func testBookingRequestNamePrefillsFirstAndLastName() {
        let draft = ClientDraft(suggestedName: "Анна Смирнова", phone: "+79990000001")
        XCTAssertEqual(draft.name, "Анна")
        XCTAssertEqual(draft.lastName, "Смирнова")
        XCTAssertEqual(draft.phone, "+79990000001")
        XCTAssertTrue(draft.canSave)
    }

    func testHandlesAreCleanedOfAtSignsAndLinks() {
        XCTAssertEqual(ClientDraft.handle("@nick"), "nick")
        XCTAssertEqual(ClientDraft.handle("t.me/nick"), "nick")
        XCTAssertEqual(ClientDraft.handle("https://telegram.me/nick/"), "nick")
        XCTAssertEqual(ClientDraft.handle("https://www.instagram.com/ivan.p/"), "ivan.p")
        XCTAssertNil(ClientDraft.handle(" @ "))
    }
}
