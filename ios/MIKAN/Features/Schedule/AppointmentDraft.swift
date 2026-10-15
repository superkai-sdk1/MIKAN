import Foundation
import SwiftUI // `remove(atOffsets:)` for swipe-to-delete

/// Prefill for the inline "new client" form (e.g. from a booking request).
struct ClientSuggestion: Hashable {
    var name: String
    var phone: String
}

/// One service line being edited: a catalog service (or one of its variants) or a custom line.
struct DraftServiceLine: Identifiable, Hashable {
    let id: UUID
    /// `nil` for a custom line.
    var serviceId: Int?
    var name: String
    var price: Int
    var durationMin: Int?
    /// The catalog price is «от» / a range — the final price is set per appointment.
    var isVariablePrice: Bool
    var category: ServiceCategory?

    init(
        id: UUID = UUID(),
        serviceId: Int?,
        name: String,
        price: Int,
        durationMin: Int?,
        isVariablePrice: Bool = false,
        category: ServiceCategory? = nil
    ) {
        self.id = id
        self.serviceId = serviceId
        self.name = name
        self.price = price
        self.durationMin = durationMin
        self.isVariablePrice = isVariablePrice
        self.category = category
    }

    /// A booked catalog service; a variant brings its own name, price and (optionally) duration.
    init(service: Service, variant: ServiceVariant? = nil) {
        self.init(
            serviceId: service.id,
            name: service.lineName(variant: variant),
            price: variant?.price ?? service.price,
            durationMin: variant?.durationMin ?? service.durationMin,
            isVariablePrice: variant == nil && service.hasVariablePrice,
            category: service.category
        )
    }

    /// A line of a saved appointment.
    init(line: AppointmentServiceLine) {
        self.init(
            serviceId: line.serviceId,
            name: line.name,
            price: line.price,
            durationMin: line.durationMin,
            category: line.category
        )
    }

    var body: AppointmentServiceBody {
        AppointmentServiceBody(serviceId: serviceId, name: name.trimmed, price: price, durationMin: durationMin)
    }
}

/// Editable state of the appointment editor.
struct AppointmentDraft: Identifiable, Hashable {
    static let defaultDurationMin = 60
    static let durationStep = 15
    static let defaultStartHour = 12
    /// Server limit of service lines per appointment.
    static let maxLines = 20

    let id = UUID()
    var appointmentId: Int?
    var client: ClientRef?
    var clientSuggestion: ClientSuggestion?
    var masterId: Int?
    /// Any change drops the kept total and lets an automatic duration follow the services.
    var lines: [DraftServiceLine] = [] {
        didSet {
            guard lines != oldValue else { return }
            priceOverride = nil
            recomputeDuration()
        }
    }
    var start: Date
    var durationMin: Int
    /// The last duration the draft set from its services; while `durationMin` equals it, the duration
    /// follows the services. `nil` (or any other value) means a duration set by hand or loaded as is.
    private(set) var autoDurationMin: Int?
    /// Manual price, used only while there are no service lines.
    var price = 0
    /// Total of a saved appointment whose price differs from its line sum (set by an older build, the
    /// server or an import); kept until the lines change or «Пересчитать по услугам».
    private(set) var priceOverride: Int?
    var deposit = 0
    var title = ""
    var notes = ""

    var isEditing: Bool { appointmentId != nil }
    var end: Date { start.addingTimeInterval(TimeInterval(durationMin * 60)) }

    /// Appointment total: the kept total or the sum of line prices, or the manual price when there are no lines.
    var total: Int { lines.isEmpty ? price : priceOverride ?? linesTotal }
    var linesTotal: Int { lines.reduce(0) { $0 + $1.price } }
    /// Sum of line durations (lines without one count as 0).
    var linesDuration: Int { lines.reduce(0) { $0 + ($1.durationMin ?? 0) } }
    var canAddLine: Bool { lines.count < Self.maxLines }

    var isValid: Bool {
        client != nil && masterId != nil && durationMin > 0 && total >= 0 && deposit >= 0
            && lines.allSatisfy { $0.name.nonEmpty != nil && $0.price >= 0 }
    }

    static func new(
        day: Date,
        client: ClientRef? = nil,
        notes: String = "",
        suggestion: ClientSuggestion? = nil
    ) -> AppointmentDraft {
        // The default duration is a placeholder, so the first booked service replaces it.
        AppointmentDraft(
            client: client,
            clientSuggestion: suggestion,
            start: defaultStart(on: day),
            durationMin: defaultDurationMin,
            autoDurationMin: defaultDurationMin,
            notes: notes
        )
    }

    /// New appointment at a tapped calendar slot.
    static func new(at start: Date, masterId: Int?) -> AppointmentDraft {
        AppointmentDraft(
            masterId: masterId,
            start: start,
            durationMin: defaultDurationMin,
            autoDurationMin: defaultDurationMin
        )
    }

    /// Loads a saved appointment as is: its duration follows the services only if it equals their sum,
    /// and a price that differs from the line sum is kept.
    static func edit(_ appointment: Appointment) -> AppointmentDraft {
        let lines = lines(of: appointment)
        let linesDuration = lines.reduce(0) { $0 + ($1.durationMin ?? 0) }
        let linesTotal = lines.reduce(0) { $0 + $1.price }
        return AppointmentDraft(
            appointmentId: appointment.id,
            client: appointment.client,
            masterId: appointment.master.id,
            lines: lines,
            start: appointment.startsAt,
            durationMin: max(durationStep, appointment.durationMin),
            autoDurationMin: linesDuration > 0 ? max(durationStep, linesDuration) : nil,
            price: appointment.price,
            priceOverride: lines.isEmpty || linesTotal == appointment.price ? nil : appointment.price,
            deposit: appointment.depositRequired,
            title: appointment.title ?? "",
            notes: appointment.notes ?? ""
        )
    }

    /// Service lines of a saved appointment; servers without `services` fall back to the legacy single
    /// `service`, which then carries the whole appointment price and duration.
    static func lines(of appointment: Appointment) -> [DraftServiceLine] {
        if !appointment.services.isEmpty {
            return appointment.services.map(DraftServiceLine.init(line:))
        }
        guard let service = appointment.service else { return [] }
        return [
            DraftServiceLine(
                serviceId: service.id,
                name: service.name,
                price: appointment.price,
                durationMin: appointment.durationMin,
                category: service.category
            ),
        ]
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

    // MARK: - Service lines

    /// Number of lines booked from the catalog service.
    func lineCount(serviceId: Int) -> Int {
        lines.count(where: { $0.serviceId == serviceId })
    }

    /// The first line booked from the catalog service.
    func line(serviceId: Int) -> DraftServiceLine? {
        lines.first { $0.serviceId == serviceId }
    }

    mutating func add(service: Service, variant: ServiceVariant? = nil) {
        append(DraftServiceLine(service: service, variant: variant))
    }

    /// Adds a free-form line; blank names are ignored.
    mutating func addCustom(name: String, price: Int) {
        guard let name = name.nonEmpty else { return }
        append(DraftServiceLine(serviceId: nil, name: name, price: max(0, price), durationMin: nil))
    }

    /// Catalog toggle for a service without variants: removes its lines, or adds it.
    mutating func toggle(service: Service) {
        if lineCount(serviceId: service.id) > 0 {
            removeLines(serviceId: service.id)
        } else {
            add(service: service)
        }
    }

    /// Books the variant (or the plain service), replacing an already booked line of that service in place.
    mutating func select(service: Service, variant: ServiceVariant?) {
        guard let index = lines.firstIndex(where: { $0.serviceId == service.id }) else {
            add(service: service, variant: variant)
            return
        }
        lines[index] = DraftServiceLine(service: service, variant: variant)
    }

    mutating func removeLines(serviceId: Int) {
        lines.removeAll { $0.serviceId == serviceId }
    }

    mutating func remove(at offsets: IndexSet) {
        lines.remove(atOffsets: IndexSet(offsets.filter(lines.indices.contains)))
    }

    /// Drops the kept total of a saved appointment: the total becomes the sum of line prices.
    mutating func recalculateTotal() {
        priceOverride = nil
    }

    private mutating func append(_ line: DraftServiceLine) {
        guard canAddLine else { return }
        lines.append(line)
    }

    /// Duration follows the booked services unless it was set by hand (differs from the last automatic value).
    private mutating func recomputeDuration() {
        let sum = linesDuration
        guard sum > 0, let autoDurationMin, durationMin == autoDurationMin else { return }
        durationMin = max(Self.durationStep, sum)
        self.autoDurationMin = durationMin
    }

    // MARK: - Request

    /// `services` is always sent (`[]` clears the lines), so the legacy `serviceId` is ignored by the server.
    func body(force: Bool) -> AppointmentBody? {
        guard let client, let masterId, isValid else { return nil }
        return AppointmentBody(
            clientId: client.id,
            masterId: masterId,
            services: lines.map(\.body),
            serviceId: nil,
            title: Nullable(title.nonEmpty),
            startsAt: start,
            endsAt: end,
            price: total,
            depositRequired: deposit,
            notes: Nullable(notes.nonEmpty),
            force: force ? true : nil
        )
    }
}
