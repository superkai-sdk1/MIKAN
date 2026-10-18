import XCTest
@testable import MIKAN

/// The bot's reminder schedule: labels, editing, the server limits and the `reminderOffsets` wire format.
final class ReminderScheduleTests: XCTestCase {
    private func schedule(_ offsets: [Int]) -> ReminderSchedule { ReminderSchedule(offsets: offsets) }

    // MARK: - Labels

    func testLabelsUseTheAccusativeAfterZa() {
        XCTAssertEqual(ReminderSchedule.label(1440), "за 1 день")
        XCTAssertEqual(ReminderSchedule.label(4320), "за 3 дня")
        XCTAssertEqual(ReminderSchedule.label(120), "за 2 часа")
        XCTAssertEqual(ReminderSchedule.label(60), "за 1 час")
        XCTAssertEqual(ReminderSchedule.label(360), "за 6 часов")
        XCTAssertEqual(ReminderSchedule.label(30), "за 30 минут")
        XCTAssertEqual(ReminderSchedule.label(15), "за 15 минут")
        XCTAssertEqual(ReminderSchedule.label(21), "за 21 минуту")
        XCTAssertEqual(ReminderSchedule.label(22), "за 22 минуты")
        XCTAssertEqual(ReminderSchedule.label(0), "за 0 минут")
    }

    func testMixedValuesListEveryUnit() {
        XCTAssertEqual(ReminderSchedule.label(90), "за 1 час 30 минут")
        XCTAssertEqual(ReminderSchedule.label(1500), "за 1 день 1 час")
        XCTAssertEqual(ReminderSchedule.label(1530), "за 1 день 1 час 30 минут")
        XCTAssertEqual(ReminderSchedule.label(2 * 1440 + 5), "за 2 дня 5 минут")
    }

    func testWholeWeeksReadAsWeeks() {
        XCTAssertEqual(ReminderSchedule.label(10_080), "за 1 неделю")
        XCTAssertEqual(ReminderSchedule.label(20_160), "за 2 недели")
        XCTAssertEqual(ReminderSchedule.label(10_080 + 1440), "за 8 дней")
    }

    func testTitleCapitalisesTheLabel() {
        XCTAssertEqual(ReminderSchedule.title(1440), "За 1 день")
        XCTAssertEqual(ReminderSchedule.title(30), "За 30 минут")
    }

    func testSummaryAndPreviewJoinTheLabelsEarliestFirst() {
        let two = schedule([120, 1440])
        XCTAssertEqual(two.summary, "за 1 день и за 2 часа")
        XCTAssertEqual(two.preview, "Клиент получит: за 1 день и за 2 часа до записи — с кнопками «Приду» и «Перенести»")
        XCTAssertEqual(schedule([30, 4320, 1440]).summary, "за 3 дня, за 1 день и за 30 минут")
        XCTAssertEqual(schedule([1440]).summary, "за 1 день")
        XCTAssertNil(schedule([]).summary)
        XCTAssertNil(schedule([]).preview)
    }

    func testLimitsHintNamesTheServerBounds() {
        XCTAssertEqual(ReminderSchedule.limitsHint, "Не позже чем за 15 минут и не раньше чем за 2 недели до записи.")
    }

    // MARK: - Editing

    func testOffsetsAreDistinctAndSortedEarliestFirst() {
        XCTAssertEqual(schedule([120, 1440, 120, 30]).offsets, [1440, 120, 30])
    }

    func testAddingKeepsTheOrder() {
        XCTAssertEqual(schedule([1440]).adding(120), .success(schedule([1440, 120])))
        XCTAssertEqual(schedule([120]).adding(4320).map(\.offsets), .success([4320, 120]))
    }

    func testAddingMirrorsTheServerLimits() {
        let base = schedule([1440])
        XCTAssertEqual(base.adding(14), .failure(.tooSoon))
        XCTAssertEqual(base.adding(15).map(\.offsets), .success([1440, 15]))
        XCTAssertEqual(base.adding(20_160).map(\.offsets), .success([20_160, 1440]))
        XCTAssertEqual(base.adding(20_161), .failure(.tooFar))
        XCTAssertEqual(base.adding(1440), .failure(.duplicate))

        let full = schedule([15, 30, 60, 120, 1440, 2880])
        XCTAssertFalse(full.canAdd)
        XCTAssertEqual(full.adding(4320), .failure(.tooMany))
        XCTAssertEqual(full.addIssue(for: 5), .tooSoon, "the range is checked first")
    }

    func testRemovingKeepsTheLastReminder() {
        let two = schedule([1440, 120])
        XCTAssertTrue(two.canRemove)
        let one = two.removing(1440)
        XCTAssertEqual(one.offsets, [120])
        XCTAssertFalse(one.canRemove)
        XCTAssertEqual(one.removing(120), one)
        XCTAssertEqual(two.removing(999), two, "removing an absent value changes nothing")
    }

    func testAvailablePresetsSkipThoseInTheSchedule() {
        let presets = schedule([1440, 120]).availablePresets
        XCTAssertFalse(presets.contains(1440))
        XCTAssertFalse(presets.contains(120))
        XCTAssertEqual(presets, presets.sorted(by: >))
        XCTAssertEqual(presets.count, ReminderSchedule.presets.count - 2)
        XCTAssertTrue(ReminderSchedule.presets.allSatisfy { ReminderSchedule.issue(forOffset: $0) == nil })
    }

    func testCustomPartsRoundTrip() {
        XCTAssertEqual(ReminderParts(days: 1, hours: 2, minutes: 30).totalMinutes, 1590)
        XCTAssertEqual(ReminderParts(totalMinutes: 1590), ReminderParts(days: 1, hours: 2, minutes: 30))
        XCTAssertEqual(ReminderParts(totalMinutes: 20_160), ReminderParts(days: 14, hours: 0, minutes: 0))
        XCTAssertEqual(ReminderParts(totalMinutes: -5).totalMinutes, 0)
    }

    // MARK: - Validation

    func testScheduleIssues() {
        XCTAssertNil(schedule([1440, 120]).issue)
        XCTAssertEqual(schedule([]).issue, .empty)
        XCTAssertEqual(schedule([1440, 10]).issue, .tooSoon)
        XCTAssertEqual(schedule([30_000]).issue, .tooFar)
        XCTAssertEqual(schedule([15, 30, 60, 120, 180, 1440, 2880]).issue, .tooMany)
    }

    func testIssueMessages() {
        XCTAssertEqual(ReminderSchedule.Issue.empty.message, "Добавьте хотя бы одно напоминание.")
        XCTAssertEqual(ReminderSchedule.Issue.tooMany.message, "Не больше 6 напоминаний.")
        XCTAssertEqual(ReminderSchedule.Issue.tooSoon.message, "Самое позднее напоминание — за 15 минут до записи.")
        XCTAssertEqual(ReminderSchedule.Issue.tooFar.message, "Самое раннее напоминание — за 2 недели до записи.")
        XCTAssertEqual(ReminderSchedule.Issue.duplicate.message, "Такое напоминание уже есть.")
    }

    func testSettingsBlockSavingOnlyWhileRemindersAreOn() throws {
        var settings = try Fixtures.decode(BotSettings.self, Fixtures.botSettingsWithOffsets)
        settings.reminderOffsets = []
        XCTAssertEqual(settings.reminderIssue, .empty)
        settings.remindersEnabled = false
        XCTAssertNil(settings.reminderIssue)
    }

    // MARK: - Wire format

    func testServerValuesWithFallbacks() {
        XCTAssertEqual(ReminderSchedule.offsets(decoded: [120, 1440], legacyHours: 24), [1440, 120])
        XCTAssertEqual(ReminderSchedule.offsets(decoded: nil, legacyHours: 3), [180])
        XCTAssertEqual(ReminderSchedule.offsets(decoded: [], legacyHours: 48), [2880])
        XCTAssertEqual(ReminderSchedule.offsets(decoded: nil, legacyHours: nil), [1440])
        XCTAssertEqual(ReminderSchedule.offsets(decoded: nil, legacyHours: 0), [1440])
    }

    func testLegacyHoursAreTheEarliestReminderInWholeHours() {
        XCTAssertEqual(schedule([1440, 120]).legacyHoursBefore, 24)
        XCTAssertEqual(schedule([30]).legacyHoursBefore, 1, "at least an hour")
        XCTAssertEqual(schedule([90]).legacyHoursBefore, 2)
        XCTAssertEqual(schedule([20_160]).legacyHoursBefore, 168, "older servers accept up to a week")
    }

    func testDecodingAServerWithoutOffsets() throws {
        let settings = try Fixtures.decode(
            BotSettings.self,
            #"{ "enabled": true, "aiEnabled": false, "aftercareHour": 12, "remindersEnabled": true, "reminderHoursBefore": 3 }"#
        )
        XCTAssertEqual(settings.reminderOffsets, [180])
        XCTAssertFalse(settings.supportsReminderOffsets)
        XCTAssertEqual(settings.greeting, "")
    }

    func testDecodingANullOffsetsFallsBackToHours() throws {
        let settings = try Fixtures.decode(
            BotSettings.self,
            #"{ "enabled": true, "aiEnabled": true, "aftercareHour": 12, "remindersEnabled": true, "reminderOffsets": null, "reminderHoursBefore": 2 }"#
        )
        XCTAssertEqual(settings.reminderOffsets, [120])
        XCTAssertFalse(settings.supportsReminderOffsets)
    }

    func testEncodingSendsOffsetsAndOnlyEditableFields() throws {
        var settings = try Fixtures.decode(BotSettings.self, Fixtures.botSettingsWithOffsets)
        settings.reminderSchedule = settings.reminderSchedule.removing(120)
        let json = try body(settings)
        XCTAssertEqual(json["reminderOffsets"] as? [Int], [1440])
        XCTAssertNil(json["reminderHoursBefore"], "a new server takes reminderOffsets")
        XCTAssertEqual(json["remindersEnabled"] as? Bool, true)
        XCTAssertEqual(json["aftercareHour"] as? Int, 12)
        XCTAssertEqual(json["greeting"] as? String, "Привет")
        for readOnly in ["botUsername", "staffChatBound", "aiConfigured", "supportsReminderOffsets"] {
            XCTAssertNil(json[readOnly], readOnly)
        }
    }

    func testEncodingForAnOlderServerAlsoSendsTheEarliestHours() throws {
        var settings = try Fixtures.decode(BotSettings.self, Fixtures.botSettings)
        settings.reminderSchedule = ReminderSchedule(offsets: [2880, 120])
        let json = try body(settings)
        XCTAssertEqual(json["reminderHoursBefore"] as? Int, 48)
        XCTAssertEqual(json["reminderOffsets"] as? [Int], [2880, 120])
    }

    private func body(_ settings: BotSettings) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(settings)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
