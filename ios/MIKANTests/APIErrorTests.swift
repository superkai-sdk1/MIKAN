import XCTest
@testable import MIKAN

final class APIErrorTests: XCTestCase {
    func testEnvelopeMapsCodeAndMessageVerbatim() {
        let body = Data(#"{ "error": { "code": "validation_error", "message": "Текст для пользователя на русском" } }"#.utf8)
        let error = APIError.from(status: 400, data: body)
        XCTAssertEqual(error, .server(status: 400, code: "validation_error", message: "Текст для пользователя на русском"))
        XCTAssertEqual(error.message, "Текст для пользователя на русском")
        XCTAssertEqual(error.userMessage, "Текст для пользователя на русском")
        XCTAssertEqual(error.code, "validation_error")
        XCTAssertEqual(error.status, 400)
    }

    func testScheduleConflictIsRecognised() {
        let body = Data(#"{ "error": { "code": "schedule_conflict", "message": "У мастера уже есть запись: Иван Петров, 11:00–12:00" } }"#.utf8)
        let error = APIError.from(status: 409, data: body)
        XCTAssertTrue(error.isScheduleConflict)
        XCTAssertFalse(error.isUnauthorized)
        XCTAssertEqual(error.message, "У мастера уже есть запись: Иван Петров, 11:00–12:00")
    }

    func testInsufficientStockIsNotScheduleConflict() {
        let body = Data(#"{ "error": { "code": "insufficient_stock", "message": "Недостаточно на складе: Лабрет (осталось 0)" } }"#.utf8)
        let error = APIError.from(status: 409, data: body)
        XCTAssertFalse(error.isScheduleConflict)
        XCTAssertEqual(error.code, "insufficient_stock")
    }

    func testUnauthorized() {
        let body = Data(#"{ "error": { "code": "unauthorized", "message": "Неверный логин или пароль" } }"#.utf8)
        let error = APIError.from(status: 401, data: body)
        XCTAssertTrue(error.isUnauthorized)
        XCTAssertEqual(error.userMessage, "Неверный логин или пароль")
    }

    func testNonJSONBodyFallsBackToStatusDefaults() {
        let error = APIError.from(status: 502, data: Data("<html>Bad Gateway</html>".utf8))
        XCTAssertEqual(error.code, "internal")
        XCTAssertEqual(error.status, 502)
        XCTAssertTrue(error.message.contains("502"))

        let rateLimited = APIError.from(status: 429, data: Data())
        XCTAssertEqual(rateLimited.code, "rate_limited")
        XCTAssertFalse(rateLimited.message.isEmpty)
    }

    func testURLErrorMappingIsRussian() {
        XCTAssertEqual(APIError.from(URLError(.notConnectedToInternet)).message, "Нет подключения к интернету.")
        XCTAssertEqual(APIError.from(URLError(.timedOut)).message, "Сервер не отвечает. Попробуйте ещё раз.")
        XCTAssertEqual(
            APIError.from(URLError(.cannotFindHost)).message,
            "Не удалось подключиться к серверу. Проверьте адрес сервера."
        )
    }

    func testUserMessageForOtherErrors() {
        XCTAssertEqual(ImagePreparerError.unreadable.userMessage, "Не удалось прочитать изображение.")
        struct Opaque: Error {}
        XCTAssertEqual(Opaque().userMessage, "Что-то пошло не так. Попробуйте ещё раз.")
    }
}

/// Request bodies: explicit nulls, omitted optionals and ISO instants with milliseconds.
final class RequestEncodingTests: XCTestCase {
    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testNullableEncodesExplicitNull() throws {
        let body = ClientBody(
            name: "Иван", phone: Nullable("+79991234567"), instagram: nil, birthday: Nullable("1995-04-12"),
            notes: nil, source: nil, botEnabled: true
        )
        let json = try object(body)
        XCTAssertEqual(json["phone"] as? String, "+79991234567")
        XCTAssertEqual(json["birthday"] as? String, "1995-04-12")
        XCTAssertTrue(json["instagram"] is NSNull, "cleared fields must be sent as null")
        XCTAssertTrue(json["notes"] is NSNull)
    }

    func testAppointmentBodyEncodesInstantsAndOmitsForceByDefault() throws {
        let body = AppointmentBody(
            clientId: 1, masterId: 2, serviceId: nil, title: Nullable("Тату"),
            startsAt: Fixtures.referenceDate, endsAt: Fixtures.referenceDate.addingTimeInterval(3600),
            price: 8000, deposit: 2000, notes: nil, force: nil
        )
        let json = try object(body)
        XCTAssertEqual(json["startsAt"] as? String, "2026-10-15T11:00:00.000Z")
        XCTAssertEqual(json["endsAt"] as? String, "2026-10-15T12:00:00.000Z")
        XCTAssertNil(json["force"], "force is only sent after the user confirms")
        XCTAssertTrue(json["serviceId"] is NSNull)

        let forced = AppointmentBody(
            clientId: 1, masterId: 2, serviceId: Nullable(3), title: nil,
            startsAt: Fixtures.referenceDate, endsAt: Fixtures.referenceDate.addingTimeInterval(1800),
            price: 0, deposit: 0, notes: nil, force: true
        )
        let forcedJSON = try object(forced)
        XCTAssertEqual(forcedJSON["force"] as? Bool, true)
        XCTAssertEqual(forcedJSON["serviceId"] as? Int, 3)
    }

    func testCashOperationTypeRawValues() throws {
        XCTAssertEqual(try object(CashOperationBody(type: .deposit, amount: 500, reason: "Размен"))["type"] as? String, "in")
        XCTAssertEqual(try object(CashOperationBody(type: .withdrawal, amount: 500, reason: "Инкассация"))["type"] as? String, "out")
    }

    func testISO8601RoundTrip() {
        XCTAssertEqual(ISO8601.string(from: Fixtures.referenceDate), "2026-10-15T11:00:00.000Z")
        XCTAssertEqual(ISO8601.parse("2026-10-15T11:00:00.000Z"), Fixtures.referenceDate)
        XCTAssertEqual(ISO8601.parse("2026-10-15T11:00:00Z"), Fixtures.referenceDate)
        XCTAssertEqual(ISO8601.parse("2026-10-15T14:00:00+03:00"), Fixtures.referenceDate)
        XCTAssertNil(ISO8601.parse("not a date"))
    }
}

final class OutcomeUnknownTests: XCTestCase {
    func testTimeoutsAndDroppedConnectionsAreAmbiguous() {
        XCTAssertTrue(APIError.from(URLError(.timedOut)).isOutcomeUnknown)
        XCTAssertTrue(APIError.from(URLError(.networkConnectionLost)).isOutcomeUnknown)
    }

    func testDefiniteFailuresAreNotAmbiguous() {
        XCTAssertFalse(APIError.from(URLError(.notConnectedToInternet)).isOutcomeUnknown, "request never left the device")
        XCTAssertFalse(APIError.from(URLError(.cannotFindHost)).isOutcomeUnknown)
        XCTAssertFalse(APIError.from(status: 409, data: Data()).isOutcomeUnknown)
        XCTAssertFalse(APIError.decoding.isOutcomeUnknown)
    }
}
