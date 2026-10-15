import Foundation

/// Prefill for the inline "new client" form (e.g. from a booking request).
struct ClientSuggestion: Hashable {
    var name: String
    var phone: String
}

/// Editable state of the appointment editor.
struct AppointmentDraft: Identifiable, Hashable {
    static let defaultDurationMin = 60
    static let durationStep = 15
    static let defaultStartHour = 12

    let id = UUID()
    var appointmentId: Int?
    var client: ClientRef?
    var clientSuggestion: ClientSuggestion?
    var masterId: Int?
    var serviceId: Int?
    var serviceName: String?
    var servicePriceFrom = false
    var start: Date
    var durationMin: Int
    var price = 0
    var deposit = 0
    var title = ""
    var notes = ""

    var isEditing: Bool { appointmentId != nil }
    var end: Date { start.addingTimeInterval(TimeInterval(durationMin * 60)) }
    var isValid: Bool { client != nil && masterId != nil && durationMin > 0 && price >= 0 && deposit >= 0 }

    static func new(
        day: Date,
        client: ClientRef? = nil,
        notes: String = "",
        suggestion: ClientSuggestion? = nil
    ) -> AppointmentDraft {
        AppointmentDraft(
            client: client,
            clientSuggestion: suggestion,
            start: defaultStart(on: day),
            durationMin: defaultDurationMin,
            notes: notes
        )
    }

    /// New appointment at a tapped calendar slot.
    static func new(at start: Date, masterId: Int?) -> AppointmentDraft {
        AppointmentDraft(masterId: masterId, start: start, durationMin: defaultDurationMin)
    }

    static func edit(_ appointment: Appointment) -> AppointmentDraft {
        AppointmentDraft(
            appointmentId: appointment.id,
            client: appointment.client,
            masterId: appointment.master.id,
            serviceId: appointment.service?.id,
            serviceName: appointment.service?.name,
            start: appointment.startsAt,
            durationMin: max(defaultDurationMin / 4, appointment.durationMin),
            price: appointment.price,
            deposit: appointment.deposit,
            title: appointment.title ?? "",
            notes: appointment.notes ?? ""
        )
    }

    /// Next round hour today (if the studio is still open), otherwise noon on that day.
    static func defaultStart(on day: Date, now: Date = .now) -> Date {
        let calendar = Calendar.app
        if calendar.isDate(day, inSameDayAs: now) {
            let nextHour = calendar.component(.hour, from: now) + 1
            if nextHour < 21, let start = calendar.date(bySettingHour: nextHour, minute: 0, second: 0, of: day) {
                return start
            }
        }
        return calendar.date(bySettingHour: defaultStartHour, minute: 0, second: 0, of: day) ?? day
    }

    mutating func apply(service: Service?) {
        serviceId = service?.id
        serviceName = service?.name
        servicePriceFrom = service?.priceFrom ?? false
        guard let service else { return }
        price = service.price
        durationMin = service.durationMin
    }

    func body(force: Bool) -> AppointmentBody? {
        guard let client, let masterId, isValid else { return nil }
        return AppointmentBody(
            clientId: client.id,
            masterId: masterId,
            serviceId: Nullable(serviceId),
            title: Nullable(title.nonEmpty),
            startsAt: start,
            endsAt: end,
            price: price,
            deposit: deposit,
            notes: Nullable(notes.nonEmpty),
            force: force ? true : nil
        )
    }
}
