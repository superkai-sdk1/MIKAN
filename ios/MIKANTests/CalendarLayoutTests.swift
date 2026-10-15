import XCTest
@testable import MIKAN

/// Lane assignment for overlapping appointments and time ↔ y math.
final class TimeGridLayoutTests: XCTestCase {
    private func segment(_ id: Int, _ start: Int, _ end: Int) -> TimeGridLayout.Segment {
        TimeGridLayout.Segment(id: id, startMinute: start, endMinute: end)
    }

    private func placement(_ placements: [TimeGridLayout.Placement], _ id: Int) throws -> TimeGridLayout.Placement {
        try XCTUnwrap(placements.first { $0.id == id })
    }

    func testSeparateAppointmentsUseOneFullWidthLane() throws {
        let result = TimeGridLayout.placements(for: [segment(1, 600, 660), segment(2, 720, 780)])
        XCTAssertEqual(try placement(result, 1).lane, 0)
        XCTAssertEqual(try placement(result, 1).laneCount, 1)
        XCTAssertEqual(try placement(result, 2).laneCount, 1)
    }

    func testBackToBackAppointmentsDoNotOverlap() throws {
        let result = TimeGridLayout.placements(for: [segment(1, 600, 660), segment(2, 660, 720)])
        XCTAssertEqual(try placement(result, 1).laneCount, 1)
        XCTAssertEqual(try placement(result, 2).lane, 0)
        XCTAssertEqual(try placement(result, 2).laneCount, 1)
    }

    func testTwoOverlappingAppointmentsSplitTheColumn() throws {
        let result = TimeGridLayout.placements(for: [segment(1, 600, 720), segment(2, 630, 690)])
        XCTAssertEqual(try placement(result, 1).lane, 0)
        XCTAssertEqual(try placement(result, 2).lane, 1)
        XCTAssertEqual(try placement(result, 1).laneCount, 2)
        XCTAssertEqual(try placement(result, 2).laneCount, 2)
    }

    func testFreedLaneIsReusedInsideACluster() throws {
        // A 10:00–13:00 overlaps B 10:00–11:00 and C 11:00–12:00; B and C share the second lane.
        let result = TimeGridLayout.placements(for: [segment(1, 600, 780), segment(2, 600, 660), segment(3, 660, 720)])
        XCTAssertEqual(try placement(result, 1).lane, 0, "longer appointment goes first")
        XCTAssertEqual(try placement(result, 2).lane, 1)
        XCTAssertEqual(try placement(result, 3).lane, 1)
        XCTAssertTrue(result.allSatisfy { $0.laneCount == 2 })
    }

    func testThreeWayOverlapAndIndependentClusters() throws {
        let result = TimeGridLayout.placements(for: [
            segment(1, 600, 720), segment(2, 610, 700), segment(3, 620, 680),
            segment(4, 900, 960),
        ])
        XCTAssertEqual(Set(try [1, 2, 3].map { try placement(result, $0).lane }), [0, 1, 2])
        XCTAssertTrue(try [1, 2, 3].allSatisfy { try placement(result, $0).laneCount == 3 })
        XCTAssertEqual(try placement(result, 4).laneCount, 1, "a later cluster is laid out independently")
    }

    func testIdenticalTimesAreOrderedById() throws {
        let result = TimeGridLayout.placements(for: [segment(7, 600, 660), segment(3, 600, 660)])
        XCTAssertEqual(try placement(result, 3).lane, 0)
        XCTAssertEqual(try placement(result, 7).lane, 1)
    }

    func testShortAppointmentsGetMinimumRoom() throws {
        // 10:00–10:05 and 10:10–10:30 don't overlap in time but would collide visually.
        let result = TimeGridLayout.placements(for: [segment(1, 600, 605), segment(2, 610, 630)], minimumDuration: 20)
        XCTAssertEqual(try placement(result, 1).laneCount, 2)
        XCTAssertEqual(try placement(result, 2).lane, 1)
        XCTAssertEqual(try placement(result, 1).endMinute, 605, "the real end is preserved for drawing")
    }

    func testEmptyInput() {
        XCTAssertTrue(TimeGridLayout.placements(for: []).isEmpty)
    }

    func testSegmentsAreClippedToTheDay() throws {
        let calendar = try moscowCalendar()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15 + dayOffset, hour: hour, minute: minute)))
        }
        let intervals = [
            TimeGridLayout.Interval(id: 1, start: try at(0, 11), end: try at(0, 12, 30)),
            TimeGridLayout.Interval(id: 2, start: try at(0, 23), end: try at(1, 1)),
            TimeGridLayout.Interval(id: 3, start: try at(-1, 22), end: try at(0, 1)),
            TimeGridLayout.Interval(id: 4, start: try at(1, 10), end: try at(1, 11)),
        ]
        let segments = TimeGridLayout.segments(of: intervals, dayStart: day, calendar: calendar)
        XCTAssertEqual(segments, [
            TimeGridLayout.Segment(id: 1, startMinute: 660, endMinute: 750),
            TimeGridLayout.Segment(id: 2, startMinute: 1380, endMinute: 1440),
            TimeGridLayout.Segment(id: 3, startMinute: 0, endMinute: 60),
        ])
    }

    func testTimeToYAndBack() {
        XCTAssertEqual(TimeGridLayout.y(forMinute: 90, hourHeight: 60), 90)
        XCTAssertEqual(TimeGridLayout.y(forMinute: 600, hourHeight: 48), 480)
        XCTAssertEqual(TimeGridLayout.minute(forY: 480, hourHeight: 48), 600)
        XCTAssertEqual(TimeGridLayout.minute(forY: 10, hourHeight: 0), 0)
    }

    func testTappedSlotIsFlooredToFifteenMinutes() {
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 600 + 7, hourHeight: 60), 600)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 600 + 14.9, hourHeight: 60), 600)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 600 + 16, hourHeight: 60), 615)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: -20, hourHeight: 60), 0)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 60 * 24 + 100, hourHeight: 60), 1425, "clamped to the last slot")
    }

    func testInitialScrollPosition() {
        XCTAssertEqual(TimeGridLayout.initialScrollMinute(nowMinute: 15 * 60, firstAppointmentMinute: 9 * 60), 14 * 60)
        XCTAssertEqual(TimeGridLayout.initialScrollMinute(nowMinute: 20, firstAppointmentMinute: nil), 0)
        XCTAssertEqual(TimeGridLayout.initialScrollMinute(nowMinute: nil, firstAppointmentMinute: 11 * 60), 10 * 60 + 30)
        XCTAssertEqual(TimeGridLayout.initialScrollMinute(nowMinute: nil, firstAppointmentMinute: nil), 8 * 60)
    }
}

/// Day / 3-day / week / month ranges in a fixed time zone with Monday-first weeks.
final class CalendarPeriodTests: XCTestCase {
    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func iso(_ date: Date) -> String { ISO8601.string(from: date) }

    func testDayPeriod() throws {
        let calendar = try moscowCalendar()
        let period = CalendarPeriod.containing(try date(calendar, 2026, 10, 15, 14), scale: .day, calendar: calendar)
        XCTAssertEqual(iso(period.start), "2026-10-14T21:00:00.000Z")
        XCTAssertEqual(iso(period.end), "2026-10-15T21:00:00.000Z")
        XCTAssertEqual(period.visibleInterval, DateInterval(start: period.start, end: period.end))
        XCTAssertEqual(period.days(calendar: calendar).count, 1)
        XCTAssertEqual(iso(period.shifted(by: -1, calendar: calendar).start), "2026-10-13T21:00:00.000Z")
    }

    func testThreeDayPeriodStartsOnTheAnchorAndPagesByThree() throws {
        let calendar = try moscowCalendar()
        let period = CalendarPeriod.containing(try date(calendar, 2026, 10, 15, 9), scale: .threeDays, calendar: calendar)
        XCTAssertEqual(iso(period.start), "2026-10-14T21:00:00.000Z")
        XCTAssertEqual(iso(period.end), "2026-10-17T21:00:00.000Z")
        XCTAssertEqual(period.days(calendar: calendar).count, 3)
        let next = period.shifted(by: 1, calendar: calendar)
        XCTAssertEqual(next.start, period.end)
        XCTAssertEqual(iso(period.shifted(by: -2, calendar: calendar).start), "2026-10-08T21:00:00.000Z")
    }

    func testWeekIsMondayFirst() throws {
        let calendar = try moscowCalendar()
        // Sunday 18 October still belongs to the week of Monday 12 October.
        let period = CalendarPeriod.containing(try date(calendar, 2026, 10, 18, 23), scale: .week, calendar: calendar)
        XCTAssertEqual(iso(period.start), "2026-10-11T21:00:00.000Z")
        XCTAssertEqual(iso(period.end), "2026-10-18T21:00:00.000Z")
        XCTAssertEqual(calendar.component(.weekday, from: period.start), 2, "Monday")
        XCTAssertEqual(period.days(calendar: calendar).count, 7)
        XCTAssertEqual(iso(period.shifted(by: 1, calendar: calendar).start), "2026-10-18T21:00:00.000Z")
    }

    func testMonthGridCoversSixMondayFirstWeeks() throws {
        let calendar = try moscowCalendar()
        let period = CalendarPeriod.containing(try date(calendar, 2026, 10, 15), scale: .month, calendar: calendar)
        XCTAssertEqual(iso(period.start), "2026-09-30T21:00:00.000Z", "1 October")
        XCTAssertEqual(iso(period.end), "2026-10-31T21:00:00.000Z", "1 November")
        XCTAssertEqual(iso(period.visibleStart), "2026-09-27T21:00:00.000Z", "Monday 28 September")
        XCTAssertEqual(period.days(calendar: calendar).count, CalendarPeriod.monthGridDays)
        XCTAssertEqual(calendar.component(.weekday, from: period.visibleStart), 2)
        XCTAssertTrue(period.contains(try date(calendar, 2026, 10, 31, 23)))
        XCTAssertFalse(period.contains(try date(calendar, 2026, 11, 1)))
    }

    func testMonthPagingClampsShortMonths() throws {
        let calendar = try moscowCalendar()
        let january = CalendarPeriod.containing(try date(calendar, 2027, 1, 31), scale: .month, calendar: calendar)
        let february = january.shifted(by: 1, calendar: calendar)
        XCTAssertEqual(iso(february.start), "2027-01-31T21:00:00.000Z", "1 February")
        XCTAssertEqual(iso(february.end), "2027-02-28T21:00:00.000Z", "1 March")
        XCTAssertEqual(iso(january.shifted(by: -3, calendar: calendar).start), "2026-09-30T21:00:00.000Z", "1 October")
    }

    func testTitles() throws {
        let calendar = try moscowCalendar()
        let now = try date(calendar, 2026, 10, 15, 12)
        XCTAssertEqual(CalendarPeriod.containing(now, scale: .day, calendar: calendar).title(calendar: calendar, now: now), "15 октября")
        XCTAssertEqual(CalendarPeriod.containing(now, scale: .threeDays, calendar: calendar).title(calendar: calendar, now: now), "15–17 окт.")
        XCTAssertEqual(CalendarPeriod.containing(now, scale: .week, calendar: calendar).title(calendar: calendar, now: now), "12–18 окт.")
        XCTAssertEqual(CalendarPeriod.containing(now, scale: .month, calendar: calendar).title(calendar: calendar, now: now), "Октябрь 2026")
        let crossMonth = CalendarPeriod.containing(try date(calendar, 2026, 10, 1), scale: .week, calendar: calendar)
        XCTAssertEqual(crossMonth.title(calendar: calendar, now: now), "28 сент. – 4 окт.")
    }

    func testScheduleQueryIncludesOverlappingAppointmentsOfTheMaster() throws {
        let calendar = try moscowCalendar()
        let period = CalendarPeriod.containing(try date(calendar, 2026, 10, 15), scale: .day, calendar: calendar)
        let query = ScheduleQuery(period: period, masterId: 2)
        func appointment(master: Int, start: Date, minutes: Int) -> Appointment {
            Appointment(
                id: 1, client: ClientRef(id: 1, name: "Иван", phone: nil, telegramLinked: false),
                master: EmployeeRef(id: master, name: "Мастер", color: nil), service: nil, title: nil,
                startsAt: start, endsAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                status: .scheduled, price: 0, deposit: 0, notes: nil, saleId: nil, completedAt: nil,
                createdAt: start, updatedAt: start
            )
        }
        XCTAssertTrue(query.includes(appointment(master: 2, start: try date(calendar, 2026, 10, 15, 11), minutes: 60)))
        XCTAssertFalse(query.includes(appointment(master: 3, start: try date(calendar, 2026, 10, 15, 11), minutes: 60)))
        XCTAssertTrue(query.includes(appointment(master: 2, start: try date(calendar, 2026, 10, 14, 23), minutes: 120)), "starts the day before")
        XCTAssertFalse(query.includes(appointment(master: 2, start: try date(calendar, 2026, 10, 16), minutes: 60)))
    }
}

/// Gregorian, Monday-first, Moscow time — deterministic regardless of the simulator's zone.
func moscowCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
    calendar.locale = Locale(identifier: "ru_RU")
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}
