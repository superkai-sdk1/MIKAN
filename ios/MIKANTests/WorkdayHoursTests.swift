import XCTest
@testable import MIKAN

/// Studio working hours and the calendar range built from them.
final class WorkdayHoursTests: XCTestCase {
    private func zone(_ id: String) throws -> TimeZone { try XCTUnwrap(TimeZone(identifier: id)) }

    private func calendar(_ id: String) throws -> Calendar {
        var calendar = try moscowCalendar()
        calendar.timeZone = try zone(id)
        return calendar
    }

    private func settings(start: String, end: String, timezone: String = "Europe/Moscow") -> StudioSettings {
        StudioSettings(
            name: "MIKAN", address: "", phone: "", workingHours: "", instagram: "", website: "", about: "",
            timezone: timezone, workdayStart: start, workdayEnd: end
        )
    }

    func testParsesAndFormatsTimesOfDay() {
        XCTAssertEqual(WorkdayHours.minute(from: "10:00"), 600)
        XCTAssertEqual(WorkdayHours.minute(from: "9:30"), 570)
        XCTAssertEqual(WorkdayHours.minute(from: " 21:15 "), 1275)
        XCTAssertEqual(WorkdayHours.minute(from: "24:00"), 1440)
        for bad in ["24:30", "12:60", "1200", "12:5", "", "вечер", "-1:00"] {
            XCTAssertNil(WorkdayHours.minute(from: bad), bad)
        }
        XCTAssertEqual(WorkdayHours.text(fromMinute: 570), "09:30")
        XCTAssertEqual(WorkdayHours.text(fromMinute: 1440), "24:00")
    }

    func testHoursComeFromSettingsWithAFallbackForBrokenValues() throws {
        let hours = WorkdayHours(settings: settings(start: "10:00", end: "21:00", timezone: "Asia/Tomsk"))
        XCTAssertEqual(hours.startMinute, 600)
        XCTAssertEqual(hours.endMinute, 1260)
        XCTAssertEqual(hours.timeZone, try zone("Asia/Tomsk"))
        XCTAssertEqual(hours.title, "10:00–21:00")

        let reversed = WorkdayHours(settings: settings(start: "21:00", end: "10:00"))
        XCTAssertEqual(reversed.title, WorkdayHours.standard.title)
        XCTAssertNil(WorkdayHours(start: "10:00", end: "10:00", timeZoneIdentifier: "Europe/Moscow"))
        XCTAssertNil(WorkdayHours(start: "утро", end: "21:00", timeZoneIdentifier: "Europe/Moscow"))
    }

    func testWindowIsTheWorkingHoursOfTheDayInTheDeviceTimeZone() throws {
        let moscow = try calendar("Europe/Moscow")
        let day = try XCTUnwrap(moscow.date(from: DateComponents(year: 2026, month: 10, day: 15)))

        let local = WorkdayHours(startMinute: 600, endMinute: 1260, timeZone: try zone("Europe/Moscow"))
        XCTAssertEqual(local.window(on: day, calendar: moscow), 600..<1260)

        // A studio in Tomsk (UTC+7) seen from a phone in Moscow (UTC+3): 10:00–21:00 there is 06:00–17:00 here.
        let tomsk = WorkdayHours(startMinute: 600, endMinute: 1260, timeZone: try zone("Asia/Tomsk"))
        XCTAssertEqual(tomsk.window(on: day, calendar: moscow), 360..<1020)

        // A Moscow studio open 01:00–23:00 seen from Vladivostok (UTC+10) runs past the local midnight: clipped.
        let vladivostok = try calendar("Asia/Vladivostok")
        let farDay = try XCTUnwrap(vladivostok.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        let late = WorkdayHours(startMinute: 60, endMinute: 1380, timeZone: try zone("Europe/Moscow"))
        XCTAssertEqual(late.window(on: farDay, calendar: vladivostok), 480..<1440)
    }

    func testAppointmentInsideOrOutsideWorkingHours() throws {
        let moscow = try calendar("Europe/Moscow")
        let hours = WorkdayHours(startMinute: 600, endMinute: 1260, timeZone: try zone("Europe/Moscow"))
        func at(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(moscow.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: hour, minute: minute)))
        }
        XCTAssertTrue(hours.contains(start: try at(10), end: try at(21), calendar: moscow))
        XCTAssertFalse(hours.contains(start: try at(9, 30), end: try at(11), calendar: moscow), "starts before opening")
        XCTAssertFalse(hours.contains(start: try at(20), end: try at(21, 30), calendar: moscow), "ends after closing")
    }

    func testPickerOptionsKeepAnOffStepValue() {
        XCTAssertEqual(WorkdayHours.timeOptions(in: 600...720, including: "10:00"), ["10:00", "10:30", "11:00", "11:30", "12:00"])
        XCTAssertEqual(
            WorkdayHours.timeOptions(in: 600...720, including: "10:45"),
            ["10:00", "10:30", "10:45", "11:00", "11:30", "12:00"]
        )
        XCTAssertEqual(WorkdayHours.timeOptions(in: 1380...1440, including: "24:00"), ["23:00", "23:30", "24:00"])
        XCTAssertEqual(WorkdayHours.timeOptions(in: 600...660, including: "08:15").count, 3, "values outside the bounds are ignored")
    }
}

/// The time grid shows the working hours, widened to appointments outside them.
final class VisibleHoursTests: XCTestCase {
    private func segment(_ id: Int, _ start: Int, _ end: Int) -> TimeGridLayout.Segment {
        TimeGridLayout.Segment(id: id, startMinute: start, endMinute: end)
    }

    func testRangeIsTheWorkingHoursWhenEverythingFits() {
        let range = TimeGridLayout.visibleRange(windows: [600..<1260, 600..<1260], segments: [segment(1, 660, 720)])
        XCTAssertEqual(range, 600..<1260)
    }

    func testEarlyAndLateAppointmentsWidenTheRangeToWholeHours() {
        let range = TimeGridLayout.visibleRange(
            windows: [600..<1260],
            segments: [segment(1, 8 * 60 + 30, 9 * 60 + 30), segment(2, 21 * 60 + 15, 22 * 60 + 10)]
        )
        XCTAssertEqual(range, 480..<1380)
    }

    func testOddWorkingHoursAreRoundedOutward() {
        XCTAssertEqual(TimeGridLayout.visibleRange(windows: [570..<1290], segments: []), 540..<1320)
    }

    func testShortLateAppointmentStillGetsItsMinimumRoom() {
        // 21:00–21:05 is drawn 20 minutes tall; the range must not cut it at 21:00.
        let range = TimeGridLayout.visibleRange(windows: [600..<1260], segments: [segment(1, 1260, 1265)], minimumDuration: 20)
        XCTAssertEqual(range, 600..<1320)
    }

    func testAppointmentsPastMidnightAreClippedToTheDay() {
        XCTAssertEqual(TimeGridLayout.visibleRange(windows: [600..<1260], segments: [segment(1, 1380, 1440)]), 600..<1440)
        XCTAssertEqual(TimeGridLayout.visibleRange(windows: [600..<1260], segments: [segment(1, 0, 60)]), 0..<1260)
    }

    func testWithoutWorkingHoursOrAppointmentsTheWholeDayIsShown() {
        XCTAssertEqual(TimeGridLayout.visibleRange(windows: [], segments: []), TimeGridLayout.fullDay)
        XCTAssertEqual(TimeGridLayout.visibleRange(windows: [1440..<1440], segments: []), TimeGridLayout.fullDay)
    }

    func testMinutesMapToYFromTheTopOfTheRange() {
        XCTAssertEqual(TimeGridLayout.y(forMinute: 600, hourHeight: 60, rangeStart: 600), 0)
        XCTAssertEqual(TimeGridLayout.y(forMinute: 690, hourHeight: 60, rangeStart: 600), 90)
        XCTAssertEqual(TimeGridLayout.y(forMinute: 540, hourHeight: 48, rangeStart: 600), -48)
        XCTAssertEqual(TimeGridLayout.minute(forY: 90, hourHeight: 60, rangeStart: 600), 690)
        XCTAssertEqual(TimeGridLayout.minute(forY: 10, hourHeight: 0, rangeStart: 600), 600)
    }

    func testTappedSlotStaysInsideTheRange() {
        let range = 600..<1260
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 7, hourHeight: 60, range: range), 600)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 16, hourHeight: 60, range: range), 615)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: -30, hourHeight: 60, range: range), 600)
        XCTAssertEqual(TimeGridLayout.slotStart(forY: 60 * 11 + 50, hourHeight: 60, range: range), 1245, "clamped to the last slot")
    }
}
