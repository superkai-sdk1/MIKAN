import Foundation

/// The client card being edited: name, last name, birthday, phone, Telegram nick and the rest.
/// Only the name and the phone are required. A card imported without a phone (YCLIENTS) can still be saved
/// without one, so its other fields stay editable; a phone, once set, can be changed but not removed.
nonisolated struct ClientDraft: Equatable, Sendable {
    static let defaultBirthday = Calendar.app.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? .now

    var name = ""
    var lastName = ""
    var phone = ""
    var telegramNick = ""
    var instagram = ""
    var hasBirthday = false
    var birthday = ClientDraft.defaultBirthday
    var source = ""
    var notes = ""
    var botEnabled = true
    /// `false` only for a saved card that has no phone yet.
    let requiresPhone: Bool

    /// A new card.
    init() {
        requiresPhone = true
    }

    /// A blank card prefilled from a name typed in one line and a phone (e.g. a booking request).
    init(suggestedName: String, phone: String) {
        let parts = PersonName.split(suggestedName)
        self.init()
        name = parts.first
        lastName = parts.last
        self.phone = phone
    }

    /// An existing card.
    init(client: Client) {
        requiresPhone = client.phone.nonEmpty != nil
        name = client.name
        lastName = client.lastName ?? ""
        phone = client.phone ?? ""
        telegramNick = client.telegramNick ?? ""
        instagram = client.instagram ?? ""
        let birthdayDate = client.birthday.flatMap { CalendarDay.date(from: $0) }
        hasBirthday = birthdayDate != nil
        birthday = birthdayDate ?? Self.defaultBirthday
        source = client.source ?? ""
        notes = client.notes ?? ""
        botEnabled = client.botEnabled
    }

    var fullName: String { PersonName.full(name, lastName) }
    var isMissingName: Bool { name.trimmed.isEmpty }
    var isMissingPhone: Bool { requiresPhone && phone.trimmed.isEmpty }
    var canSave: Bool { !isMissingName && !isMissingPhone }

    /// What still blocks saving, for the form's footer: "Укажите имя и телефон.".
    var missingFieldsHint: String? {
        switch (isMissingName, isMissingPhone) {
        case (true, true): "Укажите имя и телефон."
        case (true, false): "Укажите имя."
        case (false, true): "Укажите телефон."
        case (false, false): nil
        }
    }

    func body() -> ClientBody {
        ClientBody(
            name: name.trimmed,
            lastName: Nullable(lastName.nonEmpty),
            phone: Nullable(phone.nonEmpty),
            instagram: Nullable(Self.handle(instagram)),
            telegramNick: Nullable(Self.handle(telegramNick)),
            birthday: Nullable(hasBirthday ? CalendarDay.string(from: birthday) : nil),
            notes: Nullable(notes.nonEmpty),
            source: Nullable(source.nonEmpty),
            botEnabled: botEnabled
        )
    }

    /// "@nick", "t.me/nick" or "https://instagram.com/nick/" → "nick"; `nil` when empty.
    static func handle(_ text: String) -> String? {
        var value = text.trimmed
        for prefix in ["https://", "http://", "www.", "t.me/", "telegram.me/", "instagram.com/", "@"]
        where value.lowercased().hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value.nonEmpty
    }
}
