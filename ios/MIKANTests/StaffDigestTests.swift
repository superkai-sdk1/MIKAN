import Foundation
import Testing
@testable import MIKAN

/// Staff digests in the bot settings: the toggle, "HH:MM" ⇄ picker date and the `morningDigestAt` / `eveningDigestAt` wire format.
struct StaffDigestTests {
    private let withDigests = #"""
    { "enabled": true, "aiEnabled": true, "greeting": "Привет", "extraInstructions": "",
      "aftercareHour": 12, "remindersEnabled": true, "reminderOffsets": [1440], "reminderHoursBefore": 24,
      "morningDigestAt": "09:30", "eveningDigestAt": null,
      "botUsername": "mikan_studio_bot", "staffChatBound": true, "aiConfigured": true }
    """#

    private func body(_ settings: BotSettings) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(settings)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Toggle

    @Test("Turning a digest on gives the default time, or keeps the current one")
    func toggleOn() {
        #expect(StaffDigest.morning.toggled(nil, isOn: true) == "09:30")
        #expect(StaffDigest.evening.toggled(nil, isOn: true) == "21:30")
        #expect(StaffDigest.morning.toggled("08:15", isOn: true) == "08:15")
    }

    @Test("Turning a digest off clears its time")
    func toggleOff() {
        #expect(StaffDigest.morning.toggled("09:30", isOn: false) == nil)
        #expect(StaffDigest.evening.toggled(nil, isOn: false) == nil)
    }

    @Test("Each digest edits its own setting")
    func keyPaths() throws {
        var settings = try Fixtures.decode(BotSettings.self, withDigests)
        settings[keyPath: StaffDigest.evening.keyPath] = "22:00"
        settings[keyPath: StaffDigest.morning.keyPath] = nil
        #expect(settings.eveningDigestAt == "22:00")
        #expect(settings.morningDigestAt == nil)
        #expect(StaffDigest.allCases.map(\.title) == ["Утренняя сводка", "Вечерняя сводка"])
    }

    // MARK: - Time

    static let minutesByText: [(String, Int)] = [
        ("09:30", 570), ("9:30", 570), ("00:00", 0), ("21:30", 1290), ("23:59", 1439),
    ]

    @Test("\"HH:MM\" becomes that time on a fixed day in UTC", arguments: minutesByText)
    func dateFromText(text: String, minute: Int) {
        #expect(DigestTime.date(from: text) == Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60)))
    }

    @Test("Malformed times have no date", arguments: ["", "24:00", "25:00", "9:5", "09:60", "абв", "09-30"])
    func malformedText(text: String) {
        #expect(DigestTime.date(from: text) == nil)
    }

    @Test("Round trip keeps the time", arguments: ["00:00", "07:05", "09:30", "12:00", "21:30", "23:59"])
    func roundTrip(text: String) throws {
        let date = try #require(DigestTime.date(from: text))
        #expect(DigestTime.text(from: date) == text)
    }

    @Test("Only the UTC hour and minute count: other days and seconds are ignored")
    func textIgnoresDayAndSeconds() {
        let laterDay: TimeInterval = 400 * 86_400
        let evening: TimeInterval = 21 * 3600 + 5 * 60 + 59
        let morning: TimeInterval = 9 * 3600 + 30 * 60 + 30
        #expect(DigestTime.text(from: Date(timeIntervalSinceReferenceDate: laterDay + evening)) == "21:05")
        #expect(DigestTime.text(from: Date(timeIntervalSinceReferenceDate: morning)) == "09:30")
    }

    // MARK: - Wire format

    @Test("A new server's digests decode, null meaning off")
    func decodeNewServer() throws {
        let settings = try Fixtures.decode(BotSettings.self, withDigests)
        #expect(settings.morningDigestAt == "09:30")
        #expect(settings.eveningDigestAt == nil)
        #expect(settings.supportsStaffDigests)
    }

    @Test("An older server without digests leaves them off and unsupported")
    func decodeOlderServer() throws {
        let settings = try Fixtures.decode(BotSettings.self, Fixtures.botSettingsWithOffsets)
        #expect(settings.morningDigestAt == nil)
        #expect(settings.eveningDigestAt == nil)
        #expect(!settings.supportsStaffDigests)
    }

    @Test("PUT sends both digest times, an explicit null for one that is off")
    func encodeNewServer() throws {
        var settings = try Fixtures.decode(BotSettings.self, withDigests)
        settings.eveningDigestAt = "22:15"
        var json = try body(settings)
        #expect(json["morningDigestAt"] as? String == "09:30")
        #expect(json["eveningDigestAt"] as? String == "22:15")

        settings.morningDigestAt = nil
        json = try body(settings)
        #expect(json["morningDigestAt"] is NSNull)
        #expect(json.keys.contains("morningDigestAt"))
        #expect(json["supportsStaffDigests"] == nil)
    }

    @Test("PUT to an older server leaves the digest keys out")
    func encodeOlderServer() throws {
        let settings = try Fixtures.decode(BotSettings.self, Fixtures.botSettingsWithOffsets)
        let json = try body(settings)
        #expect(!json.keys.contains("morningDigestAt"))
        #expect(!json.keys.contains("eveningDigestAt"))
    }
}
