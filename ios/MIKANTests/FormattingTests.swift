import XCTest
@testable import MIKAN

final class MoneyFormattingTests: XCTestCase {
    /// ru_RU grouping uses a no-break space (U+00A0) between groups and before the ruble sign.
    private let nbsp = "\u{00A0}"

    func testFormatsWithRussianGrouping() {
        XCTAssertEqual(Money.format(12_400), "12\(nbsp)400\(nbsp)₽")
        XCTAssertEqual(Money.format(0), "0\(nbsp)₽")
        XCTAssertEqual(Money.format(999), "999\(nbsp)₽")
        XCTAssertEqual(Money.format(1_000), "1\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(Money.format(2_500), "2\(nbsp)500\(nbsp)₽")
        XCTAssertEqual(Money.format(1_234_567), "1\(nbsp)234\(nbsp)567\(nbsp)₽")
    }

    func testReadsLikeTheSpecWhenSpacesAreNormalised() {
        XCTAssertEqual(Money.format(12_400).replacingOccurrences(of: nbsp, with: " "), "12 400 ₽")
    }

    func testNegativeAndSignedAmounts() {
        XCTAssertEqual(Money.format(-200), "−200\(nbsp)₽")
        XCTAssertEqual(Money.formatSigned(1_000), "+1\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(Money.formatSigned(-1_500), "−1\(nbsp)500\(nbsp)₽")
        XCTAssertEqual(Money.formatSigned(0), "0\(nbsp)₽")
    }

    func testPriceFrom() {
        XCTAssertEqual(Money.format(2_500, from: true), "от 2\(nbsp)500\(nbsp)₽")
        XCTAssertEqual(Money.format(2_500, from: false), Money.format(2_500))
    }

    func testServicePriceMatchesThePriceList() {
        XCTAssertEqual(Money.servicePrice(2_500, max: nil, from: false), "2\(nbsp)500\(nbsp)₽")
        XCTAssertEqual(Money.servicePrice(15_000, max: nil, from: true), "от 15\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(Money.servicePrice(2_000, max: 5_000, from: true), "от 2\(nbsp)000 до 5\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(Money.servicePrice(0, max: 10_000, from: true), "до 10\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(Money.servicePrice(0, max: nil, from: false), "Бесплатно")
    }

    func testParsesUserInput() {
        XCTAssertEqual(Money.parse("12 400"), 12_400)
        XCTAssertEqual(Money.parse("12\(nbsp)400 ₽"), 12_400)
        XCTAssertEqual(Money.parse("1500"), 1_500)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("₽"))
        XCTAssertEqual(Money.parse("12345678901234"), 123_456_789, "input is capped to 9 digits")
    }

    func testGrouping() {
        XCTAssertEqual(Money.group(0), "0")
        XCTAssertEqual(Money.group(100_000), "100\(nbsp)000")
    }
}

final class TextFormattingTests: XCTestCase {
    func testRussianPlurals() {
        XCTAssertEqual(Plural.appointments(1), "1 запись")
        XCTAssertEqual(Plural.appointments(2), "2 записи")
        XCTAssertEqual(Plural.appointments(5), "5 записей")
        XCTAssertEqual(Plural.appointments(11), "11 записей")
        XCTAssertEqual(Plural.appointments(21), "21 запись")
        XCTAssertEqual(Plural.appointments(112), "112 записей")
        XCTAssertEqual(Plural.days(3), "3 дня")
    }

    func testPhoneDisplay() {
        XCTAssertEqual(PhoneText.display("+79991234567"), "+7 999 123-45-67")
        XCTAssertEqual(PhoneText.display("+4915112345678"), "+4915112345678")
        XCTAssertEqual(PhoneText.display(nil), "")
        XCTAssertEqual(PhoneText.callURL("+79991234567")?.absoluteString, "tel:+79991234567")
        XCTAssertNil(PhoneText.callURL("  "))
    }

    func testInitials() {
        XCTAssertEqual(Initials.from("Иван Петров"), "ИП")
        XCTAssertEqual(Initials.from("анна"), "А")
        XCTAssertEqual(Initials.from(""), "?")
    }

    func testCalendarDayRoundTrip() throws {
        let date = try XCTUnwrap(CalendarDay.date(from: "1995-04-12"))
        XCTAssertEqual(CalendarDay.string(from: date), "1995-04-12")
        XCTAssertNil(CalendarDay.date(from: "12.04.1995"))
    }

    func testDurationText() {
        XCTAssertEqual(DateText.duration(minutes: 45), "45 мин")
        XCTAssertEqual(DateText.duration(minutes: 120), "2 ч")
        XCTAssertEqual(DateText.duration(minutes: 90), "1 ч 30 мин")
    }

    func testServerAddressNormalisation() {
        XCTAssertEqual(ServerConfig.normalize("95-170-124-192.sslip.io")?.absoluteString, "https://95-170-124-192.sslip.io")
        XCTAssertEqual(ServerConfig.normalize("https://studio.example.ru/api/")?.absoluteString, "https://studio.example.ru")
        XCTAssertEqual(ServerConfig.normalize("localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(ServerConfig.normalize("http://localhost:3000/api")?.absoluteString, "http://localhost:3000")
        XCTAssertNil(ServerConfig.normalize("   "))
        XCTAssertNil(ServerConfig.normalize("ftp://example.com"))
    }

    func testReportPeriodsUseLocalDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        calendar.firstWeekday = 2
        // Thursday 15 October 2026, 14:00 Moscow time.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14)))

        let today = ReportPeriod.today.interval(now: now, customFrom: now, customTo: now, calendar: calendar)
        XCTAssertEqual(ISO8601.string(from: today.start), "2026-10-14T21:00:00.000Z")
        XCTAssertEqual(ISO8601.string(from: today.end), "2026-10-15T21:00:00.000Z")

        let week = ReportPeriod.week.interval(now: now, customFrom: now, customTo: now, calendar: calendar)
        XCTAssertEqual(ISO8601.string(from: week.start), "2026-10-11T21:00:00.000Z", "week starts on Monday 12 October")

        let month = ReportPeriod.month.interval(now: now, customFrom: now, customTo: now, calendar: calendar)
        XCTAssertEqual(ISO8601.string(from: month.start), "2026-09-30T21:00:00.000Z")

        let from = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 18)))
        let custom = ReportPeriod.custom.interval(now: now, customFrom: now, customTo: from, calendar: calendar)
        XCTAssertEqual(ISO8601.string(from: custom.start), "2026-10-02T21:00:00.000Z", "reversed range is normalised")
        XCTAssertEqual(ISO8601.string(from: custom.end), "2026-10-15T21:00:00.000Z")
    }
}
