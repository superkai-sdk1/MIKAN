import Foundation
import Testing
@testable import MIKAN

/// Catalog and appointment values shaped like docs/API.md examples.
@MainActor
private enum Sample {
    static let start = Date(timeIntervalSince1970: 1_792_062_000) // 2026-10-15 11:00 UTC

    static let lobe = Service(
        id: 3, name: "Прокол мочки", category: .piercing, group: "Ухо", price: 1600, priceFrom: false,
        durationMin: 30, aftercareTemplateId: 2, active: true, sort: 0
    )
    static let tattoo = Service(
        id: 4, name: "Мини тату", category: .tattoo, group: nil, price: 2000, priceMax: 5000, priceFrom: true,
        durationMin: 60, aftercareTemplateId: nil, active: true, sort: 1
    )
    static let nipple = Service(
        id: 5, name: "Соски", category: .piercing, group: "Тело", price: 2500, priceFrom: false, durationMin: 45,
        description: "Nipple — прокол через сосок",
        variants: [
            ServiceVariant(name: "Один", price: 2500, durationMin: nil),
            ServiceVariant(name: "Два", price: 4000, durationMin: 60),
        ],
        aftercareTemplateId: nil, active: true, sort: 2
    )
    static let quick = Service(
        id: 6, name: "Замена украшения", category: .other, price: 300, priceFrom: false, durationMin: 5,
        aftercareTemplateId: nil, active: true, sort: 3
    )

    static let client = ClientRef(id: 1, name: "Иван Петров", phone: "+79991234567", telegramLinked: true)

    static func appointment(
        service: ServiceRef? = nil,
        services: [AppointmentServiceLine] = [],
        price: Int,
        minutes: Int = 90
    ) -> Appointment {
        Appointment(
            id: 7, client: client, master: EmployeeRef(id: 2, name: "Анна", color: nil), service: service,
            services: services, title: "Эскиз согласован", startsAt: start,
            endsAt: start.addingTimeInterval(TimeInterval(minutes * 60)), status: .scheduled, price: price,
            deposit: 500, notes: nil, saleId: nil, completedAt: nil, createdAt: start, updatedAt: start
        )
    }

    static func template(id: Int, category: ServiceCategory) -> AftercareTemplate {
        AftercareTemplate(id: id, name: "Шаблон \(id)", category: category, steps: [], createdAt: start, updatedAt: start)
    }

    static func newDraft() -> AppointmentDraft {
        var draft = AppointmentDraft.new(at: start, masterId: 2)
        draft.client = client
        return draft
    }
}

@MainActor
struct AppointmentDraftTests {
    // MARK: - edit()

    @Test("edit() builds lines from appointment services and keeps the saved duration")
    func editFromServices() {
        let appointment = Sample.appointment(
            service: Sample.lobe.ref,
            services: [
                AppointmentServiceLine(id: 10, serviceId: 3, name: "Прокол мочки", category: .piercing, price: 1600, durationMin: 30),
                AppointmentServiceLine(id: 11, serviceId: nil, name: "Подбор украшения", category: nil, price: 0, durationMin: nil),
            ],
            price: 1600,
            minutes: 90
        )

        let draft = AppointmentDraft.edit(appointment)

        #expect(draft.appointmentId == 7)
        #expect(draft.lines.map(\.serviceId) == [3, nil])
        #expect(draft.lines.map(\.name) == ["Прокол мочки", "Подбор украшения"])
        #expect(draft.lines.map(\.durationMin) == [30, nil])
        #expect(draft.lines.first?.category == .piercing)
        #expect(draft.total == 1600)
        #expect(draft.durationMin == 90, "editing never recomputes the saved duration")
        #expect(draft.title == "Эскиз согласован")
        #expect(draft.deposit == 500)
    }

    @Test("edit() falls back to the legacy service with the whole price and duration")
    func editFromLegacyService() throws {
        let draft = AppointmentDraft.edit(Sample.appointment(service: Sample.tattoo.ref, price: 8000, minutes: 120))

        #expect(draft.lines.count == 1)
        let line = try #require(draft.lines.first)
        #expect(line.serviceId == 4)
        #expect(line.name == "Мини тату")
        #expect(line.price == 8000)
        #expect(line.durationMin == 120)
        #expect(line.category == .tattoo)
        #expect(draft.total == 8000)
    }

    @Test("edit() without services keeps the manual price")
    func editWithoutServices() {
        let draft = AppointmentDraft.edit(Sample.appointment(price: 3000, minutes: 10))

        #expect(draft.lines.isEmpty)
        #expect(draft.total == 3000)
        #expect(draft.durationMin == AppointmentDraft.durationStep, "duration is clamped to one step")
    }

    // MARK: - Kept total

    @Test("edit() keeps a price that differs from the line sum, and saves it unchanged")
    func editKeepsExplicitPrice() throws {
        var draft = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 5000))

        #expect(draft.priceOverride == 5000)
        #expect(draft.linesTotal == 3600)
        #expect(draft.total == 5000)

        draft.notes = "Принести эскиз"
        let json = try object(#require(draft.body(force: false)))
        #expect(json["price"] as? Int == 5000, "fixing a note never reprices the appointment")
    }

    @Test("Changing a line price switches the kept total to the line sum")
    func linePriceChangeDropsKeptTotal() {
        var draft = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 5000))

        draft.lines[1].price = 2500

        #expect(draft.priceOverride == nil)
        #expect(draft.total == 4100)
    }

    @Test("Adding or removing a line switches the kept total to the line sum")
    func lineChangeDropsKeptTotal() {
        var added = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 5000))
        added.addCustom(name: "Подбор украшения", price: 300)
        #expect(added.total == 3900)

        var removed = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 5000))
        removed.remove(at: IndexSet(integer: 0))
        #expect(removed.total == 2000)
    }

    @Test("«Пересчитать по услугам» drops the kept total")
    func recalculateTotal() {
        var draft = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 5000))
        draft.recalculateTotal()
        #expect(draft.priceOverride == nil)
        #expect(draft.total == 3600)
    }

    @Test("A price equal to the line sum, or a legacy service, keeps no override")
    func noOverrideWhenPricesMatch() {
        #expect(AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 3600)).priceOverride == nil)
        #expect(AppointmentDraft.edit(Sample.appointment(service: Sample.lobe.ref, price: 9000)).priceOverride == nil)
        #expect(AppointmentDraft.edit(Sample.appointment(price: 9000)).priceOverride == nil)
    }

    private static let twoLines = [
        AppointmentServiceLine(id: 10, serviceId: 3, name: "Прокол мочки", category: .piercing, price: 1600, durationMin: 30),
        AppointmentServiceLine(id: 11, serviceId: 4, name: "Мини тату", category: .tattoo, price: 2000, durationMin: 60),
    ]

    // MARK: - Adding and removing lines

    @Test("Adding and removing lines recomputes total and duration")
    func addRemoveRecomputes() {
        var draft = Sample.newDraft()
        draft.price = 999

        draft.add(service: Sample.lobe)
        #expect(draft.total == 1600, "lines replace the manual price")
        #expect(draft.durationMin == 30)

        draft.add(service: Sample.tattoo)
        #expect(draft.total == 3600)
        #expect(draft.durationMin == 90)
        #expect(draft.lines[1].isVariablePrice)
        #expect(!draft.lines[0].isVariablePrice)

        draft.remove(at: IndexSet(integer: 0))
        #expect(draft.lines.map(\.name) == ["Мини тату"])
        #expect(draft.total == 2000)
        #expect(draft.durationMin == 60)

        draft.remove(at: IndexSet(integer: 0))
        #expect(draft.lines.isEmpty)
        #expect(draft.total == 999, "no lines: back to the manual price")
        #expect(draft.durationMin == 60, "nothing to sum: the last duration stays")
    }

    @Test("A hand-set duration survives adding and removing lines")
    func handSetDurationIsKept() {
        var draft = Sample.newDraft()
        draft.add(service: Sample.lobe)
        draft.durationMin = 120

        draft.add(service: Sample.tattoo)
        #expect(draft.durationMin == 120)
        draft.removeLines(serviceId: 3)
        #expect(draft.durationMin == 120)

        draft.durationMin = 30
        draft.add(service: Sample.lobe)
        #expect(draft.durationMin == 90, "set back to the last automatic value, it follows the services again")
    }

    @Test("A saved duration follows the services only if it equals their sum")
    func savedDurationFollowsOnlyWhenAutomatic() {
        var automatic = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 3600, minutes: 90))
        automatic.add(service: Sample.lobe)
        #expect(automatic.durationMin == 120)

        var manual = AppointmentDraft.edit(Sample.appointment(services: Self.twoLines, price: 3600, minutes: 180))
        manual.add(service: Sample.lobe)
        #expect(manual.durationMin == 180)

        var withoutDurations = AppointmentDraft.edit(Sample.appointment(price: 3000, minutes: 150))
        withoutDurations.add(service: Sample.lobe)
        #expect(withoutDurations.durationMin == 150, "a loaded duration without service durations is kept")
    }

    @Test("Duration never drops below one step")
    func durationClampedToStep() {
        var draft = Sample.newDraft()
        draft.add(service: Sample.quick)
        #expect(draft.durationMin == AppointmentDraft.durationStep)
    }

    @Test("Editing a line price changes the total")
    func linePriceEditUpdatesTotal() {
        var draft = Sample.newDraft()
        draft.add(service: Sample.lobe)
        draft.add(service: Sample.tattoo)
        draft.lines[1].price = 4500
        #expect(draft.total == 6100)
    }

    @Test("Toggling a service adds it once and removes it again")
    func toggle() {
        var draft = Sample.newDraft()
        draft.toggle(service: Sample.lobe)
        #expect(draft.lineCount(serviceId: 3) == 1)
        draft.toggle(service: Sample.lobe)
        #expect(draft.lineCount(serviceId: 3) == 0)
        #expect(draft.lines.isEmpty)
    }

    @Test("Lines are capped at the server limit")
    func lineLimit() {
        var draft = Sample.newDraft()
        for index in 0..<(AppointmentDraft.maxLines + 3) {
            draft.addCustom(name: "Услуга \(index)", price: 100)
        }
        #expect(draft.lines.count == AppointmentDraft.maxLines)
        #expect(!draft.canAddLine)
        #expect(draft.total == 100 * AppointmentDraft.maxLines)
    }

    // MARK: - Variants and custom lines

    @Test("A variant books «<service> — <variant>» with the variant price and duration")
    func variantLine() {
        var draft = Sample.newDraft()

        draft.add(service: Sample.nipple, variant: Sample.nipple.variants[1])

        let line = draft.lines[0]
        #expect(line.serviceId == 5)
        #expect(line.name == "Соски — Два")
        #expect(line.price == 4000)
        #expect(line.durationMin == 60)
        #expect(!line.isVariablePrice)
        #expect(draft.durationMin == 60)
    }

    @Test("A variant without its own duration uses the service duration")
    func variantFallsBackToServiceDuration() {
        let line = DraftServiceLine(service: Sample.nipple, variant: Sample.nipple.variants[0])
        #expect(line.name == "Соски — Один")
        #expect(line.price == 2500)
        #expect(line.durationMin == 45)
    }

    @Test("Selecting another variant replaces the booked line in place")
    func selectReplacesVariant() {
        var draft = Sample.newDraft()
        draft.add(service: Sample.lobe)
        draft.select(service: Sample.nipple, variant: Sample.nipple.variants[0])
        draft.add(service: Sample.tattoo)

        draft.select(service: Sample.nipple, variant: Sample.nipple.variants[1])

        #expect(draft.lines.map(\.name) == ["Прокол мочки", "Соски — Два", "Мини тату"])
        #expect(draft.lineCount(serviceId: 5) == 1)
        #expect(draft.total == 1600 + 4000 + 2000)
        #expect(draft.durationMin == 30 + 60 + 60)

        draft.removeLines(serviceId: 5)
        #expect(draft.lines.map(\.name) == ["Прокол мочки", "Мини тату"])
        #expect(draft.durationMin == 90)
    }

    @Test("A custom line is trimmed, has no service and keeps a hand-set duration")
    func customLine() {
        var draft = Sample.newDraft()
        draft.add(service: Sample.lobe)
        draft.durationMin = 120

        draft.addCustom(name: "  Подбор украшения ", price: 500)
        draft.addCustom(name: "   ", price: 100)

        #expect(draft.lines.count == 2, "blank names are ignored")
        let line = draft.lines[1]
        #expect(line.serviceId == nil)
        #expect(line.name == "Подбор украшения")
        #expect(line.price == 500)
        #expect(line.durationMin == nil)
        #expect(line.category == nil)
        #expect(draft.total == 2100)
        #expect(draft.durationMin == 120, "a line without duration doesn't reset the duration")
    }

    // MARK: - Request body

    @Test("body() sends every line in order, the total price and a null legacy serviceId")
    func bodyEncodesServices() throws {
        var draft = Sample.newDraft()
        draft.add(service: Sample.nipple, variant: Sample.nipple.variants[1])
        draft.addCustom(name: "Подбор украшения", price: 0)
        draft.add(service: Sample.tattoo)
        draft.lines[2].price = 3500
        draft.deposit = 1000

        let json = try object(#require(draft.body(force: false)))

        let services = try #require(json["services"] as? [[String: Any]])
        #expect(services.count == 3)
        #expect(services[0]["serviceId"] as? Int == 5)
        #expect(services[0]["name"] as? String == "Соски — Два")
        #expect(services[0]["price"] as? Int == 4000)
        #expect(services[0]["durationMin"] as? Int == 60)
        #expect(services[1]["serviceId"] is NSNull, "custom lines send an explicit null serviceId")
        #expect(services[1]["name"] as? String == "Подбор украшения")
        #expect(services[1]["price"] as? Int == 0)
        #expect(services[1]["durationMin"] is NSNull)
        #expect(services[2]["serviceId"] as? Int == 4)
        #expect(services[2]["price"] as? Int == 3500)
        #expect(json["serviceId"] is NSNull)
        #expect(json["price"] as? Int == 7500)
        #expect(json["deposit"] as? Int == 1000)
        #expect(json["clientId"] as? Int == 1)
        #expect(json["masterId"] as? Int == 2)
        #expect(json["startsAt"] as? String == "2026-10-15T11:00:00.000Z")
        #expect(json["endsAt"] as? String == "2026-10-15T13:00:00.000Z")
        #expect(json["force"] == nil)
    }

    @Test("body() without lines sends services: [] and the manual price")
    func bodyEncodesEmptyServices() throws {
        var draft = Sample.newDraft()
        draft.price = 3000
        draft.title = "  "

        let json = try object(#require(draft.body(force: true)))

        let services = try #require(json["services"] as? [Any])
        #expect(services.isEmpty, "[] clears the lines on the server")
        #expect(json["price"] as? Int == 3000)
        #expect(json["title"] is NSNull)
        #expect(json["force"] as? Bool == true)
    }

    @Test("body() is nil until client and master are set")
    func bodyRequiresClientAndMaster() {
        var draft = AppointmentDraft.new(at: Sample.start, masterId: nil)
        #expect(draft.body(force: false) == nil)
        draft.client = Sample.client
        #expect(draft.body(force: false) == nil)
        draft.masterId = 2
        #expect(draft.body(force: false) != nil)
    }

    private func object(_ body: AppointmentBody) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
struct ServicePickerCatalogTests {
    @Test("Sections follow category, then group; ungrouped services go last")
    func sections() {
        let helix = Service(
            id: 7, name: "Хеликс", category: .piercing, group: "Ухо", price: 2000, priceFrom: false,
            durationMin: 30, aftercareTemplateId: nil, active: true, sort: 4
        )
        let tongue = Service(
            id: 8, name: "Язык", category: .piercing, group: nil, price: 3000, priceFrom: false,
            durationMin: 30, aftercareTemplateId: nil, active: true, sort: 5
        )

        let sections = ServicePickerCatalog.sections([Sample.lobe, Sample.tattoo, Sample.nipple, helix, tongue], query: "")

        #expect(sections.map(\.title) == ["Тату", "Пирсинг · Ухо", "Пирсинг · Тело", "Пирсинг · Другое"])
        #expect(sections[1].services.map(\.id) == [3, 7])
        #expect(sections[3].services.map(\.id) == [8])
        #expect(Set(sections.map(\.id)).count == sections.count, "section ids are unique")
    }

    @Test("A group literally named «Другое» merges with ungrouped services")
    func otherGroupMergesWithUngrouped() {
        let named = Service(
            id: 9, name: "Снятие украшения", category: .piercing, group: "Другое", price: 500, priceFrom: false,
            durationMin: 10, aftercareTemplateId: nil, active: true, sort: 6
        )
        let ungrouped = Service(
            id: 10, name: "Язык", category: .piercing, group: nil, price: 3000, priceFrom: false,
            durationMin: 30, aftercareTemplateId: nil, active: true, sort: 7
        )

        let sections = ServicePickerCatalog.sections([Sample.lobe, named, ungrouped], query: "")

        #expect(sections.map(\.title) == ["Пирсинг · Ухо", "Пирсинг · Другое"])
        #expect(sections[1].services.map(\.id) == [9, 10])
        #expect(Set(sections.map(\.id)).count == sections.count)

        let onlyOther = ServicePickerCatalog.sections([named, ungrouped], query: "")
        #expect(onlyOther.map(\.title) == ["Пирсинг"], "no named groups: one section per category")
    }

    @Test("Search matches name, description, group and variant names, ignoring case")
    func search() {
        let catalog = [Sample.lobe, Sample.tattoo, Sample.nipple]
        #expect(ServicePickerCatalog.sections(catalog, query: "мочк").flatMap(\.services).map(\.id) == [3])
        #expect(ServicePickerCatalog.sections(catalog, query: "NIPPLE").flatMap(\.services).map(\.id) == [5])
        #expect(ServicePickerCatalog.sections(catalog, query: "ухо").flatMap(\.services).map(\.id) == [3])
        #expect(ServicePickerCatalog.sections(catalog, query: "два").flatMap(\.services).map(\.id) == [5])
        #expect(ServicePickerCatalog.sections(catalog, query: "  ").flatMap(\.services).count == 3)
        #expect(ServicePickerCatalog.sections(catalog, query: "брови").isEmpty)
    }
}

@MainActor
struct AftercareDefaultsTests {
    private let templates = [Sample.template(id: 1, category: .tattoo), Sample.template(id: 2, category: .piercing)]

    @Test("Uses the template of the first line whose service has one")
    func firstLineWithTemplate() {
        let appointment = Sample.appointment(
            service: Sample.tattoo.ref,
            services: [
                AppointmentServiceLine(id: 1, serviceId: 4, name: "Мини тату", category: .tattoo, price: 2000, durationMin: 60),
                AppointmentServiceLine(id: 2, serviceId: 3, name: "Прокол мочки", category: .piercing, price: 1600, durationMin: 30),
            ],
            price: 3600
        )
        let id = AftercareDefaults.templateId(for: appointment, services: [Sample.lobe, Sample.tattoo], templates: templates)
        #expect(id == 2, "the tattoo has no template, the lobe line does")
    }

    @Test("Falls back to the category of the first line with one")
    func categoryFallback() {
        let appointment = Sample.appointment(
            services: [
                AppointmentServiceLine(id: 1, serviceId: nil, name: "Консультация", category: nil, price: 0, durationMin: nil),
                AppointmentServiceLine(id: 2, serviceId: 4, name: "Мини тату", category: .tattoo, price: 2000, durationMin: 60),
            ],
            price: 2000
        )
        let id = AftercareDefaults.templateId(for: appointment, services: [Sample.tattoo], templates: templates)
        #expect(id == 1)
    }

    @Test("Falls back to the legacy service, and to nothing without services")
    func legacyFallback() {
        let legacy = Sample.appointment(service: Sample.lobe.ref, price: 1600)
        #expect(AftercareDefaults.templateId(for: legacy, services: [Sample.lobe], templates: templates) == 2)
        #expect(AftercareDefaults.templateId(for: legacy, services: [], templates: templates) == 2, "by category")
        #expect(AftercareDefaults.templateId(for: Sample.appointment(price: 0), services: [], templates: templates) == nil)
    }

    @Test("Ignores a template id that no longer exists")
    func missingTemplate() {
        let legacy = Sample.appointment(service: Sample.lobe.ref, price: 1600)
        let id = AftercareDefaults.templateId(for: legacy, services: [Sample.lobe], templates: [Sample.template(id: 9, category: .piercing)])
        #expect(id == 9, "template 2 is gone: first piercing template")
    }
}
