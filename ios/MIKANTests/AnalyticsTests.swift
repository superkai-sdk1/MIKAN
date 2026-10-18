import XCTest
@testable import MIKAN

/// `GET /reports/analytics` as the server answers it for three studio days 13–15 Oct 2026 (Moscow); the hour and
/// weekday lists are shortened.
private let analyticsJSON = #"""
{ "from": "2026-10-12T21:00:00.000Z", "to": "2026-10-15T21:00:00.000Z",
  "previousFrom": "2026-10-09T21:00:00.000Z", "previousTo": "2026-10-12T21:00:00.000Z", "timezone": "Europe/Moscow",
  "totals": { "net": 10380, "gross": 11680, "refunds": 1300, "salesCount": 4, "averageCheck": 2920, "discounts": 420,
              "servicesRevenue": 2700, "productsRevenue": 8480, "cogs": 1900, "grossProfit": 2580, "marginPercent": 57.6,
              "stockExpenses": 850, "newClients": 1, "appointmentsCompleted": 1, "noShows": 1, "noShowLoss": 5000,
              "depositsReceived": 1000 },
  "previous": { "net": 1800, "gross": 1800, "refunds": 0, "salesCount": 2, "averageCheck": 900, "discounts": 0,
                "servicesRevenue": 0, "productsRevenue": 1000, "cogs": 400, "grossProfit": 600, "marginPercent": 60,
                "stockExpenses": 0, "newClients": 2, "appointmentsCompleted": 1, "noShows": 0, "noShowLoss": 0,
                "depositsReceived": 0 },
  "revenue": { "gross": 11680, "refunds": 1300, "refundsCount": 2, "net": 10380, "salesCount": 4, "averageCheck": 2920,
               "discounts": 420, "kept": 11180, "payments": { "cash": 6180, "card": 0, "transfer": 5500, "qr": 0, "deposit": 0 } },
  "byDay": [ { "date": "2026-10-13", "gross": 3780, "refunds": 800, "net": 2980, "salesCount": 1 },
             { "date": "2026-10-14", "gross": 2900, "refunds": 500, "net": 2400, "salesCount": 2 },
             { "date": "2026-10-15", "gross": 5000, "refunds": 0, "net": 5000, "salesCount": 1 } ],
  "byWeekday": [ { "weekday": 2, "revenue": 3780, "salesCount": 1 }, { "weekday": 4, "revenue": 5000, "salesCount": 1 } ],
  "byHour": [ { "hour": 0, "revenue": 3780, "salesCount": 1 }, { "hour": 23, "revenue": 5000, "salesCount": 1 } ],
  "services": { "quantity": 1, "revenue": 2700, "byCategory": [ { "category": "piercing", "quantity": 1, "revenue": 2700 } ],
                "top": [ { "serviceId": 1, "name": "Прокол хеликса", "category": "piercing", "quantity": 1, "revenue": 2700 } ] },
  "products": { "quantity": 6, "revenue": 8480, "revenueWithCost": 4480, "cogs": 1900, "grossProfit": 2580, "marginPercent": 57.6,
                "itemsWithoutCost": 2,
                "byKind": [ { "kind": "jewelry", "quantity": 6, "revenue": 8480, "revenueWithCost": 4480, "cogs": 1900,
                              "grossProfit": 2580, "marginPercent": 57.6, "itemsWithoutCost": 2 } ],
                "top": [ { "productId": 1, "name": "Лабрет", "kind": "jewelry", "quantity": 4, "revenue": 4480, "revenueWithCost": 4480,
                           "cogs": 1900, "grossProfit": 2580, "marginPercent": 57.6, "itemsWithoutCost": 0,
                           "variants": [ { "variantId": 2, "name": "8 мм", "quantity": 3, "revenue": 3480, "revenueWithCost": 3480,
                                           "cogs": 1500, "grossProfit": 1980, "marginPercent": 56.9, "itemsWithoutCost": 0 },
                                         { "variantId": 1, "name": "6 мм", "quantity": 1, "revenue": 1000, "revenueWithCost": 1000,
                                           "cogs": 400, "grossProfit": 600, "marginPercent": 60, "itemsWithoutCost": 0 } ] },
                         { "productId": 2, "name": "Кольцо", "kind": "jewelry", "quantity": 2, "revenue": 4000, "revenueWithCost": 0,
                           "cogs": 0, "grossProfit": 0, "marginPercent": null, "itemsWithoutCost": 2,
                           "variants": [ { "variantId": 3, "name": "", "quantity": 2, "revenue": 4000, "revenueWithCost": 0, "cogs": 0,
                                           "grossProfit": 0, "marginPercent": null, "itemsWithoutCost": 2 } ] } ] },
  "stock": { "writeoffs": { "quantity": 2, "value": 800, "unitsWithoutCost": 0 },
             "usage": { "quantity": 8, "value": 50, "unitsWithoutCost": 3 }, "expenses": 850,
             "top": [ { "productId": 1, "name": "Лабрет", "kind": "jewelry", "type": "writeoff", "quantity": 2, "value": 800 },
                      { "productId": 3, "name": "Перчатки", "kind": "consumable", "type": "usage", "quantity": 5, "value": 50 } ],
             "onHand": { "units": 118, "value": 6850, "unitsWithoutCost": 10,
                         "byKind": [ { "kind": "jewelry", "units": 16, "value": 5900, "unitsWithoutCost": 3 },
                                     { "kind": "consumable", "units": 102, "value": 950, "unitsWithoutCost": 7 } ] } },
  "deposits": { "received": 1000, "cash": 0, "card": 0, "transfer": 1000, "qr": 0, "applied": 0, "refunded": 0, "retained": 0, "held": 1000 },
  "cash": { "cashIn": 500, "cashOut": 2000, "operationsCount": 2, "shiftsClosed": 1, "closingDifference": -80, "shortage": -80,
            "surplus": 0, "openingDifference": -300,
            "shifts": [ { "id": 2, "openedAt": "2026-10-12T21:10:00.000Z", "closedAt": "2026-10-13T18:00:00.000Z",
                          "closedBy": { "id": 1, "name": "Админ", "color": "#FF7A1A" }, "openingCash": 1200, "closingCash": 2600,
                          "expectedCash": 2680, "openingDifference": -300, "difference": -80 } ] },
  "masters": [ { "employee": { "id": 2, "name": "Анна", "color": "#00AA00" }, "revenue": 3780, "salesCount": 1, "appointmentsCompleted": 1,
                 "noShows": 1, "servicesCount": 2, "averageCheck": 3780 } ],
  "clients": { "newClients": 1, "buyers": 3, "firstTime": { "count": 1, "revenue": 5000 }, "returning": { "count": 2, "revenue": 6180 },
               "anonymous": { "salesCount": 0, "revenue": 0 },
               "top": [ { "client": { "id": 1, "name": "Иван", "lastName": "Петров", "phone": "+79990000101", "telegramLinked": false },
                          "revenue": 3780, "salesCount": 1, "visits": 1 } ] },
  "appointments": { "total": 4, "open": 1, "completed": 1, "cancelled": 1, "noShow": 1, "noShowLoss": 5000, "cancelledValue": 2000 } }
"""#

private func decodeAnalytics(_ json: String = analyticsJSON) throws -> ReportAnalytics {
    try JSONCoding.makeDecoder().decode(ReportAnalytics.self, from: Data(json.utf8))
}

/// Gregorian, Monday first, Moscow time — the studio's calendar.
private func moscow() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ru_RU")
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}

private func instant(_ iso: String) throws -> Date {
    try XCTUnwrap(ISO8601.parse(iso))
}

final class AnalyticsDecodingTests: XCTestCase {
    func testDecodesTheServerAnswer() throws {
        for json in [analyticsJSON, analyticsJSON.replacingOccurrences(of: ".000Z", with: "Z")] {
            let a = try decodeAnalytics(json)
            XCTAssertEqual(ISO8601.string(from: a.from), "2026-10-12T21:00:00.000Z")
            XCTAssertEqual(ISO8601.string(from: a.previousFrom), "2026-10-09T21:00:00.000Z")
            XCTAssertEqual(a.timezone, "Europe/Moscow")
            XCTAssertEqual(a.totals.net, 10_380)
            XCTAssertEqual(a.totals.marginPercent, 57.6)
            XCTAssertEqual(a.previous.net, 1800)
            XCTAssertEqual(a.revenue.payments, Payments(cash: 6180, card: 0, transfer: 5500, qr: 0, deposit: 0))
            XCTAssertEqual(a.byDay.map(\.net), [2980, 2400, 5000])
            XCTAssertEqual(a.byWeekday.map(\.weekday), [2, 4])
            XCTAssertEqual(a.services.top.first?.name, "Прокол хеликса")
            XCTAssertEqual(a.deposits.held, 1000)
            XCTAssertEqual(a.cash.shifts.first?.closedBy?.name, "Админ")
            XCTAssertEqual(a.cash.shifts.first?.openingDifference, -300)
            XCTAssertEqual(a.masters.first?.servicesCount, 2)
            XCTAssertEqual(a.clients.top.first?.client.fullName, "Иван Петров")
            XCTAssertEqual(a.appointments.noShowLoss, 5000)
            XCTAssertFalse(a.isEmpty)
        }
    }

    func testMarginKeysSitNextToTheEntryKeys() throws {
        let products = try decodeAnalytics().products
        XCTAssertEqual(products.margin, AnalyticsMargin(quantity: 6, revenue: 8480, revenueWithCost: 4480, cogs: 1900,
                                                        grossProfit: 2580, marginPercent: 57.6, itemsWithoutCost: 2))
        XCTAssertEqual(products.byKind.map(\.kind), ["jewelry"])
        XCTAssertEqual(products.byKind.first?.margin.cogs, 1900)
        let labret = try XCTUnwrap(products.top.first)
        XCTAssertEqual(labret.productId, 1)
        XCTAssertEqual(labret.margin.grossProfit, 2580)
        XCTAssertEqual(labret.variants.map(\.name), ["8 мм", "6 мм"])
        XCTAssertEqual(labret.variants.first?.margin.marginPercent, 56.9)
        let ring = try XCTUnwrap(products.top.last)
        XCTAssertNil(ring.margin.marginPercent, "no unit with a cost sold")
        XCTAssertEqual(ring.margin.itemsWithoutCost, 2)
        XCTAssertEqual(try decodeAnalytics().stock.top.map(\.isUsage), [false, true])
    }

    func testMissingSectionsDecodeAsEmpty() throws {
        let a = try decodeAnalytics(#"{ "from": "2026-10-12T21:00:00Z", "to": "2026-10-15T21:00:00Z", "totals": { "net": 500 } }"#)
        XCTAssertEqual(a.totals.net, 500)
        XCTAssertEqual(a.totals.salesCount, 0)
        XCTAssertNil(a.totals.marginPercent)
        XCTAssertEqual(a.previous, .zero)
        XCTAssertEqual(ISO8601.string(from: a.previousFrom), "2026-10-09T21:00:00.000Z", "the same length before `from`")
        XCTAssertEqual(a.previousTo, a.from)
        XCTAssertTrue(a.byDay.isEmpty)
        XCTAssertTrue(a.masters.isEmpty)
        XCTAssertEqual(a.deposits, .zero)
        XCTAssertTrue(a.isEmpty)
    }

    func testRequiresThePeriodAndTotals() {
        XCTAssertThrowsError(try decodeAnalytics(#"{ "from": "2026-10-12T21:00:00Z", "to": "2026-10-15T21:00:00Z" }"#))
    }
}

final class AnalyticsDeltaTests: XCTestCase {
    private let nbsp = "\u{00A0}"

    func testRelativeChange() {
        XCTAssertEqual(AnalyticsDelta.of(120, previous: 100).text, "▲ 20\(nbsp)%")
        XCTAssertEqual(AnalyticsDelta.of(80, previous: 100).text, "▼ 20\(nbsp)%")
        XCTAssertEqual(AnalyticsDelta.of(1035, previous: 1000).text, "▲ 3,5\(nbsp)%", "one decimal below 10 %")
        XCTAssertEqual(AnalyticsDelta.of(10_380, previous: 1800).text, "▲ 477\(nbsp)%")
        XCTAssertEqual(AnalyticsDelta.of(100, previous: 100).text, "0\(nbsp)%")
        XCTAssertEqual(AnalyticsDelta.of(100_001, previous: 100_000).text, "0\(nbsp)%", "a change that rounds to zero")
    }

    func testDashWithoutAPreviousValue() {
        XCTAssertEqual(AnalyticsDelta.of(5000, previous: 0).text, "—")
        XCTAssertEqual(AnalyticsDelta.of(0, previous: 0).text, "—")
        XCTAssertNil(AnalyticsDelta.of(5000, previous: 0).value)
        XCTAssertEqual(AnalyticsDelta.of(5000, previous: 0).tone(), .neutral)
    }

    func testNegativeBaseCountsByMagnitude() {
        // Refunds above sales: −1000 → 500 is a rise of 150 %.
        XCTAssertEqual(AnalyticsDelta.of(500, previous: -1000).text, "▲ 150\(nbsp)%")
    }

    func testToneDependsOnWhatIsGood() {
        XCTAssertEqual(AnalyticsDelta.of(120, previous: 100).tone(), .good)
        XCTAssertEqual(AnalyticsDelta.of(80, previous: 100).tone(), .bad)
        XCTAssertEqual(AnalyticsDelta.of(120, previous: 100).tone(higherIsBetter: false), .bad, "more refunds is bad")
        XCTAssertEqual(AnalyticsDelta.of(80, previous: 100).tone(higherIsBetter: false), .good)
        XCTAssertEqual(AnalyticsDelta.of(100, previous: 100).tone(), .neutral)
    }

    func testPercentagePoints() {
        XCTAssertEqual(AnalyticsDelta.points(57.6, previous: 60).text, "▼ 2,4\(nbsp)п.п.")
        XCTAssertEqual(AnalyticsDelta.points(62.3, previous: 60).text, "▲ 2,3\(nbsp)п.п.")
        XCTAssertEqual(AnalyticsDelta.points(60, previous: 60).text, "0\(nbsp)п.п.")
        XCTAssertEqual(AnalyticsDelta.points(nil, previous: 60).text, "—")
        XCTAssertEqual(AnalyticsDelta.points(57.6, previous: nil).tone(), .neutral)
    }
}

final class AnalyticsPeriodTests: XCTestCase {
    func testNewPresetsUseLocalDayBoundaries() throws {
        let calendar = try moscow()
        // Thursday 15 October 2026, 14:00 Moscow time.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14)))
        func interval(_ period: ReportPeriod) -> (String, String) {
            let range = period.interval(now: now, customFrom: now, customTo: now, calendar: calendar)
            return (ISO8601.string(from: range.start), ISO8601.string(from: range.end))
        }
        XCTAssertTrue(interval(.yesterday) == ("2026-10-13T21:00:00.000Z", "2026-10-14T21:00:00.000Z"))
        XCTAssertTrue(interval(.quarter) == ("2026-09-30T21:00:00.000Z", "2026-10-15T21:00:00.000Z"), "Q4 starts on 1 October")
        XCTAssertTrue(interval(.year) == ("2025-12-31T21:00:00.000Z", "2026-10-15T21:00:00.000Z"))
        XCTAssertTrue(interval(.today) == ("2026-10-14T21:00:00.000Z", "2026-10-15T21:00:00.000Z"))
        XCTAssertEqual(ReportPeriod.allCases.map(\.title), ["Сегодня", "Вчера", "Неделя", "Месяц", "Квартал", "Год", "Период"])
    }

    func testQuarterStarts() throws {
        let calendar = try moscow()
        func start(_ month: Int, _ day: Int) throws -> String {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            return CalendarDay.string(from: try XCTUnwrap(ReportPeriod.quarterStart(of: date, calendar: calendar)), calendar: calendar)
        }
        XCTAssertEqual(try start(2, 10), "2026-01-01")
        XCTAssertEqual(try start(6, 30), "2026-04-01")
        XCTAssertEqual(try start(7, 1), "2026-07-01")
        XCTAssertEqual(try start(12, 31), "2026-10-01")
    }

    func testRangeText() throws {
        let calendar = try moscow()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14)))
        func text(_ from: (Int, Int, Int), _ lastDay: (Int, Int, Int)) throws -> String {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: from.0, month: from.1, day: from.2)))
            let last = try XCTUnwrap(calendar.date(from: DateComponents(year: lastDay.0, month: lastDay.1, day: lastDay.2)))
            let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: last))
            return ReportPeriod.rangeText(DateInterval(start: start, end: end), now: now, calendar: calendar)
        }
        XCTAssertEqual(try text((2026, 10, 15), (2026, 10, 15)), "15 октября")
        XCTAssertEqual(try text((2026, 10, 1), (2026, 10, 15)), "1 – 15 октября")
        XCTAssertEqual(try text((2026, 9, 28), (2026, 10, 4)), "28 сентября – 4 октября")
        let acrossYears = try text((2025, 12, 29), (2026, 1, 4))
        XCTAssertTrue(acrossYears.hasPrefix("29 декабря 2025"), acrossYears)
        XCTAssertTrue(acrossYears.hasSuffix("– 4 января"), acrossYears)
        let lastYear = try text((2025, 3, 1), (2025, 3, 7))
        XCTAssertTrue(lastYear.hasPrefix("1 – 7 марта 2025"), lastYear)
    }
}

final class AnalyticsChartDataTests: XCTestCase {
    func testDailyRevenuePoints() throws {
        let calendar = try moscow()
        let result = AnalyticsChartData.revenuePoints(try decodeAnalytics().byDay, calendar: calendar)
        XCTAssertEqual(result.granularity, .day)
        XCTAssertEqual(result.points.map(\.net), [2980, 2400, 5000])
        XCTAssertEqual(result.points.map { CalendarDay.string(from: $0.date, calendar: calendar) }, ["2026-10-13", "2026-10-14", "2026-10-15"])
    }

    func testLongRangesAreSummedByMonth() throws {
        let calendar = try moscow()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let days = (0..<70).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return AnalyticsDay(date: CalendarDay.string(from: day, calendar: calendar), gross: 100, refunds: offset == 0 ? 50 : 0, net: offset == 0 ? 50 : 100, salesCount: 1)
        }
        let result = AnalyticsChartData.revenuePoints(days, calendar: calendar)
        XCTAssertEqual(result.granularity, .month)
        XCTAssertEqual(result.points.map { CalendarDay.string(from: $0.date, calendar: calendar) }, ["2026-09-01", "2026-10-01", "2026-11-01"])
        XCTAssertEqual(result.points.map(\.net), [2950, 3100, 900])
        XCTAssertEqual(result.points.map(\.salesCount), [30, 31, 9])
        XCTAssertEqual(result.points.first?.refunds, 50)
    }

    func testPaymentSlicesSkipUnusedMethods() {
        let slices = AnalyticsChartData.paymentSlices(Payments(cash: 6000, card: 0, transfer: 3000, qr: 0, deposit: 1000))
        XCTAssertEqual(slices.map(\.id), ["cash", "transfer", "deposit"])
        XCTAssertEqual(slices.map(\.title), ["Наличные", "Перевод", "Из предоплат"])
        XCTAssertEqual(slices.map(\.share), [0.6, 0.3, 0.1])
        XCTAssertTrue(AnalyticsChartData.paymentSlices(Payments(cash: 0, card: 0, transfer: 0)).isEmpty)
    }

    func testStructureSlicesNameEveryKind() {
        let kinds = [
            AnalyticsProductKind(kind: "jewelry", margin: AnalyticsMargin(quantity: 3, revenue: 6000)),
            AnalyticsProductKind(kind: "goods", margin: AnalyticsMargin(quantity: 1, revenue: 2000)),
            AnalyticsProductKind(kind: "aftercare", margin: AnalyticsMargin(quantity: 0, revenue: 0)),
        ]
        let slices = AnalyticsChartData.structureSlices(services: 12_000, kinds: kinds)
        XCTAssertEqual(slices.map(\.title), ["Услуги", "Украшения", "Товары"])
        XCTAssertEqual(slices.map(\.share), [0.6, 0.3, 0.1])
    }

    func testWeekdayBarsAlwaysCoverTheWeek() throws {
        let bars = AnalyticsChartData.weekdayBars(try decodeAnalytics().byWeekday)
        XCTAssertEqual(bars.map(\.label), ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
        XCTAssertEqual(bars.map(\.revenue), [0, 3780, 0, 5000, 0, 0, 0])
        XCTAssertEqual(AnalyticsChartData.peak(bars)?.label, "Чт")
    }

    func testHourBarsSpanTheBusyHoursOnly() {
        let hours = (0..<24).map { AnalyticsHour(hour: $0, revenue: [11: 3000, 15: 5000][$0] ?? 0, salesCount: [11, 15].contains($0) ? 1 : 0) }
        let bars = AnalyticsChartData.hourBars(hours)
        XCTAssertEqual(bars.map(\.id), [11, 12, 13, 14, 15])
        XCTAssertEqual(bars.map(\.revenue), [3000, 0, 0, 0, 5000])
        XCTAssertEqual(AnalyticsChartData.peak(bars)?.id, 15)
        XCTAssertTrue(AnalyticsChartData.hourBars((0..<24).map { AnalyticsHour(hour: $0) }).isEmpty)
        XCTAssertNil(AnalyticsChartData.peak(AnalyticsChartData.weekdayBars([])))
    }
}

final class AnalyticsTextTests: XCTestCase {
    func testKindsAndCategoriesOfAnyServer() {
        XCTAssertEqual(ReportText.kindTitle("jewelry"), "Украшения")
        XCTAssertEqual(ReportText.kindTitle("consumable"), "Расходники")
        XCTAssertEqual(ReportText.kindTitle("goods"), "Товары")
        XCTAssertEqual(ReportText.kindTitle("aftercare"), "Aftercare", "a kind added later shows by its name")
        XCTAssertEqual(ReportText.categoryTitle("piercing"), "Пирсинг")
        XCTAssertEqual(ReportText.categoryTitle("laser"), "Laser")
        XCTAssertEqual(ReportText.productsTitle(["jewelry"]), "Украшения")
        XCTAssertEqual(ReportText.productsTitle([]), "Украшения")
        XCTAssertEqual(ReportText.productsTitle(["jewelry", "goods"]), "Товары")
    }

    func testNumbersAndHints() {
        XCTAssertEqual(ReportText.percent(57.6), "57,6\u{00A0}%")
        XCTAssertEqual(ReportText.percent(60), "60\u{00A0}%")
        XCTAssertEqual(ReportText.percent(nil), "—")
        XCTAssertEqual(ReportText.share(1, of: 4), 0.25)
        XCTAssertEqual(ReportText.share(1, of: 0), 0)
        XCTAssertNil(ReportText.missingCostHint(0))
        XCTAssertEqual(ReportText.missingCostHint(2), "2\u{00A0}шт. без себестоимости — укажите её в карточке товара, чтобы маржа была точной")
        XCTAssertEqual(ReportText.weekday(1, full: true), "Понедельник")
        XCTAssertEqual(ReportText.weekday(7), "Вс")
        XCTAssertEqual(ReportText.hour(9), "09:00")
    }

    func testPeopleLines() throws {
        let a = try decodeAnalytics()
        XCTAssertEqual(ReportText.masterLine(try XCTUnwrap(a.masters.first)), "Записей: 1 · Услуг: 2 · Неявок: 1")
        XCTAssertEqual(ReportText.noShowRate(a.appointments), "50\u{00A0}%")
        XCTAssertEqual(ReportText.noShowRate(AnalyticsAppointments()), "—")
        XCTAssertEqual(ReportText.sizeBreakdown(of: try XCTUnwrap(a.products.top.first).variants), "8 мм × 3 · 6 мм × 1")
        XCTAssertNil(ReportText.sizeBreakdown(of: try XCTUnwrap(a.products.top.last).variants), "a product without sizes")
    }
}

final class AnalyticsCSVTests: XCTestCase {
    func testEscapesFieldsForExcel() {
        XCTAssertEqual(AnalyticsCSV.escape("Лабрет"), "Лабрет")
        XCTAssertEqual(AnalyticsCSV.escape("Серьги; кольца"), "\"Серьги; кольца\"")
        XCTAssertEqual(AnalyticsCSV.escape("Кольцо \"Луна\""), "\"Кольцо \"\"Луна\"\"\"")
        XCTAssertEqual(AnalyticsCSV.row(["a", "b;c", ""]), "a;\"b;c\";")
        XCTAssertEqual(AnalyticsCSV.percent(57.6), "57,6")
        XCTAssertEqual(AnalyticsCSV.percent(nil), "")
    }

    func testTableFollowsTheScreen() throws {
        let a = try decodeAnalytics()
        let csv = AnalyticsCSV.make(a, period: "13 – 15 октября", previousPeriod: "10 – 12 октября")
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "Аналитика MIKAN STUDIO;13 – 15 октября")
        XCTAssertTrue(lines.contains("Показатель;Период;Предыдущий период;Изменение"))
        XCTAssertTrue(lines.contains("Выручка, ₽;10380;1800;" + AnalyticsDelta.of(10_380, previous: 1800).text))
        XCTAssertTrue(lines.contains("Маржа, %;57,6;60;▼ 2,4\u{00A0}п.п."))
        XCTAssertTrue(lines.contains("Возвраты (2);1300"))
        XCTAssertTrue(lines.contains("Наличные;6180"))
        XCTAssertTrue(lines.contains("2026-10-13;3780;800;2980;1"))
        XCTAssertTrue(lines.contains("Четверг;5000;1"))
        XCTAssertTrue(lines.contains("Прокол хеликса;Пирсинг;1;2700"))
        XCTAssertTrue(lines.contains("Лабрет;;4;4480;1900;2580;57,6;0"))
        XCTAssertTrue(lines.contains("Лабрет;8 мм;3;3480;1500;1980;56,9;0"))
        XCTAssertTrue(lines.contains("Кольцо;;2;4000;0;0;;2"))
        XCTAssertTrue(lines.contains("Списания;2;800;0"))
        XCTAssertTrue(lines.contains("Расхождение при открытии;-300"))
        XCTAssertTrue(lines.contains("Анна;3780;1;3780;1;1;2"))
        XCTAssertTrue(lines.contains("Иван Петров;+7 999 000-01-01;3780;1;1"))
        XCTAssertTrue(lines.contains("Неявки;1;5000"))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testExportIsUTF8WithBOM() throws {
        let calendar = try moscow()
        let interval = DateInterval(start: try instant("2026-10-12T21:00:00Z"), end: try instant("2026-10-15T21:00:00Z"))
        let export = AnalyticsExport(try decodeAnalytics(), interval: interval, calendar: calendar)
        XCTAssertEqual(export.fileName, "MIKAN аналитика 2026-10-13 — 2026-10-15.csv")
        let data = export.data
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = try XCTUnwrap(String(data: data.dropFirst(3), encoding: .utf8))
        XCTAssertEqual(text, export.csv)
        XCTAssertTrue(text.contains("Выручка и возвраты"))

        let oneDay = DateInterval(start: try instant("2026-10-14T21:00:00Z"), end: try instant("2026-10-15T21:00:00Z"))
        XCTAssertEqual(AnalyticsCSV.fileName(oneDay, calendar: calendar), "MIKAN аналитика 2026-10-15.csv")
    }
}
