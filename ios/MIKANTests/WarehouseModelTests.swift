import Foundation
import Testing
@testable import MIKAN

/// The unified warehouse shapes of docs/API.md: categories, goods, presence consumables, service links and norms,
/// stock counts and the consumption of a completed visit.
struct WarehouseModelTests {
    private let encoder: JSONEncoder = {
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    @Test("A presence consumable is low unless marked «есть»; a server without stock modes reads as counted")
    func presenceConsumable() throws {
        let json = Fixtures.product
            .replacingOccurrences(of: #""kind": "jewelry""#, with: #""kind": "consumable""#)
            .replacingOccurrences(of: #""active": true"#, with: #""stockMode": "presence", "presenceStatus": "low", "active": true"#)
        let soap = try Fixtures.decode(Product.self, json)
        #expect(soap.isPresenceTracked)
        #expect(soap.presenceStatus == .low)
        #expect(soap.lowStock)
        let legacy = try Fixtures.decode(Product.self, Fixtures.product)
        #expect(legacy.stockMode == .quantity)
        #expect(legacy.presenceStatus == nil)
    }

    @Test("Goods are sold, consumables are not")
    func goods() throws {
        let json = Fixtures.product.replacingOccurrences(of: #""kind": "jewelry""#, with: #""kind": "goods""#)
        #expect(try Fixtures.decode(Product.self, json).kind == .goods)
        #expect(ProductKind.goods.isSold)
        #expect(!ProductKind.consumable.isSold)
        #expect(CatalogSection(kind: .goods) == .goods)
        #expect(CatalogSection.service.productKind == nil)
    }

    @Test("Services carry compatible jewelry and consumption norms; older servers send none")
    func serviceLinks() throws {
        let json = Fixtures.service.replacingOccurrences(
            of: #""active": true"#,
            with: #""jewelryIds": [1, 7], "consumables": [ { "productId": 12, "quantity": 2 } ], "active": true"#
        )
        let service = try Fixtures.decode(Service.self, json)
        #expect(service.jewelryIds == [1, 7])
        #expect(service.consumables == [ServiceConsumable(productId: 12, quantity: 2)])
        let legacy = try Fixtures.decode(Service.self, Fixtures.service)
        #expect(legacy.jewelryIds.isEmpty && legacy.consumables.isEmpty)
        #expect(ServiceBody(service).jewelryIds == [1, 7], "a PATCH keeps the links")
    }

    @Test("Categories keep staff order; names items carry but the registry lacks come after")
    func categoryOrder() throws {
        let json = #"""
        [ { "id": 2, "section": "jewelry", "serviceCategory": null, "name": "Лабрет", "position": 1, "itemCount": 3 },
          { "id": 1, "section": "jewelry", "serviceCategory": null, "name": "Кольца", "position": 0, "itemCount": 2 },
          { "id": 5, "section": "service", "serviceCategory": "piercing", "name": "Ухо", "position": 0, "itemCount": 4 } ]
        """#
        let categories = try Fixtures.decode([CatalogCategory].self, json)
        #expect(categories.scope(.jewelry).map(\.name) == ["Кольца", "Лабрет"])
        #expect(categories.scope(.service, serviceCategory: .piercing).map(\.id) == [5])
        #expect(categories.orderedNames(.jewelry, including: ["Септум", "Лабрет", " "]) == ["Кольца", "Лабрет", "Септум"])
    }

    @Test("A stock count decodes with its movements and presence changes")
    func revision() throws {
        let json = #"""
        { "id": 3, "number": 3, "section": "consumable", "note": "Конец месяца",
          "employee": \#(Fixtures.employeeRef), "counted": 24, "changed": 3,
          "surplus": 2, "shortage": 5, "surplusCost": 80, "shortageCost": 1200,
          "presenceChanges": [ { "productId": 15, "productName": "Антисептик", "from": "ok", "to": "low" } ],
          "movements": [ \#(Fixtures.movementWithSize) ], "createdAt": "<T>" }
        """#
        let revision = try Fixtures.decode(StockRevision.self, json)
        #expect(revision.section == .consumable)
        #expect(revision.presenceChanges.first?.to == .low)
        #expect(revision.movements.count == 1)
    }

    @Test("Checkout completes without a consumables list (the server applies the norms); the result reports consumption")
    func completion() throws {
        let body = CompleteBody(sendAftercare: true, aftercareTemplateId: nil, consumables: nil)
        #expect(String(decoding: try encoder.encode(body), as: UTF8.self) == #"{"sendAftercare":true}"#)
        let json = #"""
        { "appointment": \#(Fixtures.appointment), "scheduledMessages": 0,
          "consumption": { "used": [ { "productId": 12, "productName": "Иглы", "quantity": 3 } ],
                           "shortages": [ { "productId": 15, "productName": "Перчатки", "needed": 2, "deducted": 1 } ] } }
        """#
        let result = try Fixtures.decode(CompleteAppointmentResult.self, json)
        #expect(result.consumption.used.first?.quantity == 3)
        #expect(result.consumption.shortages.first?.deducted == 1)
        let legacy = try Fixtures.decode(CompleteAppointmentResult.self, #"{ "appointment": \#(Fixtures.appointment), "scheduledMessages": 0 }"#)
        #expect(legacy.consumption == Consumption())
    }
}
