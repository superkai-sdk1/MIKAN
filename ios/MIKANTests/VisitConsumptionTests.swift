import Foundation
import Testing
@testable import MIKAN

/// Completing a visit: consumables prefilled from the norms of its services; untouched norms are left to the server.
struct VisitConsumptionTests {
    private let start = Date(timeIntervalSince1970: 1_792_062_000)

    private let needles = InventoryFixtures.product(id: 12, kind: .consumable, name: "Иглы", price: 0, quantity: 40)
    private let gloves = InventoryFixtures.product(id: 15, kind: .consumable, name: "Перчатки", price: 0, quantity: 1)
    private var soap: Product {
        var product = InventoryFixtures.product(id: 20, kind: .consumable, name: "Мыло", price: 0)
        product.stockMode = .presence
        product.presenceStatus = .ok
        return product
    }

    private var products: [Product] { [needles, gloves, soap] }

    private var helix: Service {
        service(id: 3, name: "Хеликс", norm: [(12, 1), (15, 2), (20, 1)])
    }

    private var lobe: Service {
        service(id: 4, name: "Мочка", norm: [(15, 1), (12, 2), (99, 1)])
    }

    private func service(id: Int, name: String, norm: [(Int, Int)]) -> Service {
        Service(
            id: id, name: name, category: .piercing, group: nil, price: 1_000, priceFrom: false, durationMin: 30,
            consumables: norm.map { ServiceConsumable(productId: $0.0, quantity: $0.1) }, active: true, sort: 0
        )
    }

    private func appointment(lines: [Int?], legacy: ServiceRef? = nil) -> Appointment {
        Appointment(
            id: 4, client: ClientRef(id: 1, name: "Иван", phone: nil, telegramLinked: true),
            master: EmployeeRef(id: 1, name: "Анна", color: "#FF7A1A"), service: legacy,
            services: lines.enumerated().map { index, serviceId in
                AppointmentServiceLine(
                    id: index + 1, serviceId: serviceId, name: "Услуга \(index + 1)", category: .piercing,
                    price: 1_000, durationMin: 30
                )
            },
            title: nil, startsAt: start, endsAt: start.addingTimeInterval(3600), status: .confirmed,
            price: 1_000, deposit: 0, notes: nil, saleId: nil, completedAt: nil, createdAt: start, updatedAt: start
        )
    }

    // MARK: - Norms

    @Test("Norms add up over the service lines (a service booked twice counts twice); custom lines add nothing")
    func normsOverLines() {
        let visit = appointment(lines: [3, nil, 4, 3])
        let norms = VisitConsumption.norms(for: visit, services: [helix, lobe], products: products)
        #expect(norms == [ServiceConsumable(productId: 12, quantity: 4), ServiceConsumable(productId: 15, quantity: 5)])
    }

    @Test("Without lines the legacy single service gives the norm")
    func legacyService() {
        let visit = appointment(lines: [], legacy: ServiceRef(id: 4, name: "Мочка", category: .piercing))
        #expect(VisitConsumption.serviceIds(of: visit) == [4])
        let norms = VisitConsumption.norms(for: visit, services: [helix, lobe], products: products)
        #expect(norms == [ServiceConsumable(productId: 15, quantity: 1), ServiceConsumable(productId: 12, quantity: 2)])
        #expect(VisitConsumption.norms(for: appointment(lines: []), services: [helix], products: products).isEmpty)
    }

    @Test("Presence consumables are listed as used, never counted; unknown products are skipped")
    func presenceAndUnknown() {
        let visit = appointment(lines: [3, 4, 3])
        let norms = VisitConsumption.norms(for: visit, services: [helix, lobe], products: products)
        #expect(!norms.map(\.productId).contains(20), "presence: never deducted")
        #expect(!norms.map(\.productId).contains(99), "gone from the warehouse")
        let presence = VisitConsumption.presenceProducts(for: visit, services: [helix, lobe], products: products)
        #expect(presence.map(\.id) == [20], "listed once")
    }

    // MARK: - Complete body

    @Test("Untouched norms send no list, so the server deducts them without blocking")
    func untouchedSendsNil() throws {
        let norms = [ServiceConsumable(productId: 12, quantity: 2), ServiceConsumable(productId: 15, quantity: 1)]
        var usage = VisitConsumption.usage(from: norms)
        #expect(VisitConsumption.consumables(usage: usage, norms: norms) == nil)
        usage[30] = 0
        #expect(VisitConsumption.consumables(usage: usage, norms: norms) == nil, "a row left at 0 changes nothing")
        #expect(VisitConsumption.consumables(usage: [:], norms: []) == nil)

        let body = CompleteBody(sendAftercare: false, aftercareTemplateId: nil, consumables: VisitConsumption.consumables(usage: usage, norms: norms))
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(body), as: UTF8.self) == #"{"sendAftercare":false}"#)
    }

    @Test("Edited counts send exactly the list, by product, without zeros")
    func editedSendsList() throws {
        let norms = [ServiceConsumable(productId: 15, quantity: 1), ServiceConsumable(productId: 12, quantity: 2)]
        var usage = VisitConsumption.usage(from: norms)
        usage[12] = 3
        usage[15] = 0
        usage[30] = 1
        let list = try #require(VisitConsumption.consumables(usage: usage, norms: norms))
        #expect(list == [ConsumableUse(productId: 12, quantity: 3), ConsumableUse(productId: 30, quantity: 1)])

        let removedAll = VisitConsumption.consumables(usage: [12: 0, 15: 0], norms: norms)
        #expect(removedAll == [], "nothing used is an explicit empty list, not the norms")
        let body = CompleteBody(sendAftercare: false, aftercareTemplateId: nil, consumables: removedAll)
        let json = String(decoding: try JSONCoding.makeEncoder().encode(body), as: UTF8.self)
        #expect(json.contains(#""consumables":[]"#))
    }

    @Test("Picking consumables adds rows with one unit and zeroes unpicked ones; norm rows stay")
    func applyingPickerSelection() {
        let norms = [ServiceConsumable(productId: 12, quantity: 2)]
        let start = (usage: [12: 2, 15: 1], shown: [12, 15])
        let next = VisitConsumption.applying(selection: [30], usage: start.usage, shown: start.shown, norms: norms)
        #expect(next.usage == [12: 0, 15: 0, 30: 1])
        #expect(next.shown == [12, 30], "the norm row stays at 0, the added one leaves")
        let again = VisitConsumption.applying(selection: [12, 30], usage: next.usage, shown: next.shown, norms: norms)
        #expect(again.usage[12] == 1)
        #expect(again.usage[30] == 1, "a used row keeps its count")
    }

    @Test("A shortage names what was needed and what the stock gave")
    func shortageText() {
        let shortage = Consumption.Shortage(productId: 15, productName: "Перчатки", needed: 2, deducted: 1)
        #expect(VisitConsumption.shortageText(shortage, unit: "пар") == "Перчатки: нужно 2 пар, списано 1")
    }
}
