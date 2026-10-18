import Foundation
import Testing
@testable import MIKAN

/// «Свежий прокол» / «Свежее тату»: the service switch that decides whether completing a visit sends aftercare memos.
@MainActor
struct FreshProcedureTests {
    private let start = Date(timeIntervalSince1970: 1_792_062_000)
    private let templates = [
        AftercareTemplate(id: 1, name: "Тату", category: .tattoo, steps: [], createdAt: .distantPast, updatedAt: .distantPast),
        AftercareTemplate(id: 2, name: "Пирсинг", category: .piercing, steps: [], createdAt: .distantPast, updatedAt: .distantPast),
    ]

    private func service(id: Int, name: String, category: ServiceCategory = .piercing, template: Int?, fresh: Bool) -> Service {
        Service(
            id: id, name: name, category: category, group: nil, price: 1_000, priceFrom: false, durationMin: 30,
            aftercareTemplateId: template, freshProcedure: fresh, active: true, sort: 0
        )
    }

    private func appointment(lines: [(Int?, String, ServiceCategory?)], legacy: ServiceRef? = nil) -> Appointment {
        Appointment(
            id: 4, client: ClientRef(id: 1, name: "Иван", phone: nil, telegramLinked: true),
            master: EmployeeRef(id: 1, name: "Анна", color: "#FF7A1A"), service: legacy,
            services: lines.enumerated().map { index, line in
                AppointmentServiceLine(id: index + 1, serviceId: line.0, name: line.1, category: line.2, price: 1_000, durationMin: 30)
            },
            title: nil, startsAt: start, endsAt: start.addingTimeInterval(3600), status: .confirmed,
            price: 1_000, deposit: 0, notes: nil, saleId: nil, completedAt: nil, createdAt: start, updatedAt: start
        )
    }

    @Test("A visit with only extras sends no memo, even when the extra has a template")
    func extrasOnly() {
        let swap = service(id: 7, name: "Замена украшения", template: 2, fresh: false)
        let visit = appointment(lines: [(7, "Замена украшения", .piercing)])
        #expect(!AftercareDefaults.sendsMemo(for: visit, services: [swap]))
        #expect(AftercareDefaults.templateId(for: visit, services: [swap], templates: templates) == nil)
    }

    @Test("The memo follows the fresh procedure, not an extra booked before it")
    func freshAfterExtra() {
        let swap = service(id: 7, name: "Замена украшения", category: .tattoo, template: 1, fresh: false)
        let helix = service(id: 8, name: "Хеликс", template: nil, fresh: true)
        let visit = appointment(lines: [(7, "Замена украшения", .tattoo), (8, "Хеликс", .piercing)])
        #expect(AftercareDefaults.sendsMemo(for: visit, services: [swap, helix]))
        #expect(AftercareDefaults.templateId(for: visit, services: [swap, helix], templates: templates) == 2, "piercing by category")
    }

    @Test("Custom lines never send a memo; services the app has not loaded are left to the server")
    func customAndUnknown() {
        #expect(!AftercareDefaults.sendsMemo(for: appointment(lines: [(nil, "Коррекция", nil)]), services: []))
        let unknown = appointment(lines: [(42, "Пупок", .piercing)])
        #expect(AftercareDefaults.sendsMemo(for: unknown, services: []))
        #expect(AftercareDefaults.templateId(for: unknown, services: [], templates: templates) == 2)
    }

    @Test("The switch is named after the category")
    func titles() {
        #expect(ServiceCategory.piercing.freshProcedureTitle == "Свежий прокол")
        #expect(ServiceCategory.tattoo.freshProcedureTitle == "Свежее тату")
        #expect(ServiceCategory.other.freshProcedureTitle == "Нужна памятка по уходу")
    }

    @Test("The editor keeps the switch, sends it and explains it")
    func editorDraft() {
        #expect(ServiceEditorDraft(service: nil, nextSort: 0).freshProcedure, "new services send memos")
        var draft = ServiceEditorDraft(service: service(id: 7, name: "Замена украшения", template: nil, fresh: false), nextSort: 0)
        #expect(!draft.body.freshProcedure)
        #expect(draft.aftercareHint.contains("не отправляется"))
        draft.freshProcedure = true
        #expect(draft.body.freshProcedure)
        #expect(ServiceBody(service(id: 8, name: "Хеликс", template: 2, fresh: true)).freshProcedure)
    }

    @Test("A server without the switch is read as sending memos for every service")
    func decoding() throws {
        let legacy = try Fixtures.decode(Service.self, Fixtures.service)
        #expect(legacy.freshProcedure)
        let off = Fixtures.service.replacingOccurrences(of: #""active": true"#, with: #""freshProcedure": false, "active": true"#)
        #expect(try !Fixtures.decode(Service.self, off).freshProcedure)
    }
}
