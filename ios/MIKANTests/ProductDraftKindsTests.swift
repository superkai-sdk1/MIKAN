import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

/// The product editor for goods and consumables: what each kind sends, stock modes and the availability status.
final class ProductDraftKindsTests: XCTestCase {
    // MARK: - Goods

    func testGoodsHaveSizesPricesAndNoJewelryAttributes() throws {
        var draft = ProductDraft(product: nil, defaultKind: .goods)
        draft.name = "Спрей"
        draft.material = "Пластик"
        draft.color = "Синий"
        draft.threadType = .internalThread
        draft.thicknessText = "1.2"
        draft.serviceIds = [3]
        draft.price = 1_200
        draft.cost = 650
        draft.supplier = "H2Ocean"
        draft = draft.addingSizes(named: ["50 мл", "100 мл"])
        draft.sizes[1].initialQuantity = 4

        XCTAssertTrue(draft.showsSizesEditor)
        XCTAssertTrue(draft.isSold)
        XCTAssertFalse(draft.hasMaterial)
        XCTAssertNil(draft.validationMessage, "goods may have several sizes")

        let body = draft.body
        XCTAssertEqual(body.kind, .goods)
        XCTAssertEqual(body.material, Nullable(nil))
        XCTAssertEqual(body.threadType, Nullable(nil))
        XCTAssertEqual(body.thicknessMm, Nullable(nil))
        XCTAssertEqual(body.color, Nullable(nil))
        XCTAssertEqual(body.serviceIds, [])
        XCTAssertEqual(body.price, 1_200)
        XCTAssertEqual(body.cost, Nullable(650))
        XCTAssertEqual(body.supplier, Nullable("H2Ocean"))
        XCTAssertEqual(body.variants.map(\.name), ["50 мл", "100 мл"])
        XCTAssertEqual(body.variants.map(\.initialQuantity), [nil, 4])
        XCTAssertNil(body.stockMode, "only consumables have a stock mode")
        XCTAssertNil(body.presenceStatus)

        let json = try encoded(body)
        XCTAssertNil(json["stockMode"], "omitted, not null")
        XCTAssertNil(json["presenceStatus"])
    }

    // MARK: - Consumables

    func testCountedConsumableSendsItsStockMode() throws {
        var draft = ProductDraft(product: nil, defaultKind: .consumable)
        draft.name = "Иглы 1.2"
        draft.sizes[0].initialQuantity = 100
        XCTAssertEqual(draft.stockMode, .quantity)
        XCTAssertFalse(draft.isPresenceTracked)
        XCTAssertFalse(draft.showsSizesEditor)

        let body = draft.body
        XCTAssertEqual(body.stockMode, .quantity)
        XCTAssertNil(body.presenceStatus, "no status in quantity mode")
        XCTAssertEqual(body.variants.first?.initialQuantity, 100)
        let json = try encoded(body)
        XCTAssertEqual(json["stockMode"] as? String, "quantity")
        XCTAssertNil(json["presenceStatus"])
    }

    func testNewPresenceConsumableStartsMarkedOkAndCarriesNoStock() throws {
        var draft = ProductDraft(product: nil, defaultKind: .consumable)
        draft.name = "Антисептик"
        draft.sizes[0].initialQuantity = 5
        draft.stockMode = .presence
        XCTAssertTrue(draft.isPresenceTracked)
        XCTAssertEqual(draft.presenceStatus, .ok)
        XCTAssertNil(draft.validationMessage)

        draft.presenceStatus = .low
        let body = draft.body
        XCTAssertEqual(body.stockMode, .presence)
        XCTAssertEqual(body.presenceStatus, .low)
        XCTAssertEqual(body.variants, [
            ProductVariantBody(id: nil, name: "", sku: nil, price: nil, cost: nil, minQuantity: 0, initialQuantity: nil),
        ], "a typed initial stock is not sent in presence mode")
        let json = try encoded(body)
        XCTAssertEqual(json["stockMode"] as? String, "presence")
        XCTAssertEqual(json["presenceStatus"] as? String, "low")
    }

    func testExistingPresenceConsumableKeepsItsStatus() {
        let soap = F.presence(id: 15, name: "Мыло", status: .out, quantity: 3)
        let draft = ProductDraft(product: soap)
        XCTAssertEqual(draft.stockMode, .presence)
        XCTAssertEqual(draft.presenceStatus, .out)
        XCTAssertEqual(draft.body.variants.map(\.id), [1_500], "the only size stays")
    }

    func testSwitchingACountedConsumableStartsLikeTheServer() {
        let withStock = F.product(id: 9, kind: .consumable, name: "Иглы", price: 0, variants: [F.size(19, "", quantity: 4)])
        var draft = ProductDraft(product: withStock)
        draft.stockMode = .presence
        XCTAssertEqual(draft.presenceStatus, .ok, "stock on hand — «есть»")

        let empty = F.product(id: 10, kind: .consumable, name: "Вата", price: 0, variants: [F.size(20, "", quantity: 0)])
        var emptyDraft = ProductDraft(product: empty)
        emptyDraft.stockMode = .presence
        XCTAssertEqual(emptyDraft.presenceStatus, .out, "nothing left — «нет»")
    }

    func testOtherKindsDropTheStockModeOfAFormerConsumable() {
        var draft = ProductDraft(product: F.presence(id: 15, name: "Спрей", status: .low))
        draft.kind = .goods
        XCTAssertFalse(draft.isPresenceTracked)
        XCTAssertNil(draft.body.stockMode)
        XCTAssertNil(draft.body.presenceStatus)
    }

    func testConsumableStillHasOneSize() {
        var draft = ProductDraft(product: nil, defaultKind: .goods).addingSizes(named: ["S", "M"])
        draft.name = "Перчатки"
        draft.kind = .consumable
        XCTAssertEqual(draft.validationMessage, "У расходника только один размер — удалите лишние или выберите тип «Украшение».")
    }

    // MARK: - Quick status change

    func testStatusPatchResendsTheCardWithTheNewStatus() {
        let antiseptic = F.presence(id: 15, name: "Антисептик", status: .ok, category: "Дезинфекция", cost: 450)
        let body = ProductBody.presence(.out, of: antiseptic)
        XCTAssertEqual(body.presenceStatus, .out)
        XCTAssertEqual(body.stockMode, .presence)
        XCTAssertEqual(body.name, "Антисептик")
        XCTAssertEqual(body.category, Nullable("Дезинфекция"))
        XCTAssertEqual(body.cost, Nullable(450))
        XCTAssertEqual(body.variants.map(\.id), [1_500])
    }

    // MARK: - Used in services

    func testUsageListsTheServicesWithNormsInCatalogOrder() {
        var lobe = Service(id: 3, name: "Мочка", category: .piercing, price: 1_600, priceFrom: false, durationMin: 30, aftercareTemplateId: nil, active: true, sort: 1)
        lobe.consumables = [ServiceConsumable(productId: 9, quantity: 2)]
        var tattoo = Service(id: 4, name: "Мини тату", category: .tattoo, price: 2_000, priceFrom: false, durationMin: 60, aftercareTemplateId: nil, active: true, sort: 5)
        tattoo.consumables = [ServiceConsumable(productId: 12, quantity: 1), ServiceConsumable(productId: 9, quantity: 3)]
        var helix = Service(id: 5, name: "Хеликс", category: .piercing, price: 2_000, priceFrom: false, durationMin: 30, aftercareTemplateId: nil, active: false, sort: 0)
        helix.consumables = [ServiceConsumable(productId: 9, quantity: 1)]
        let other = Service(id: 6, name: "Консультация", category: .other, price: 0, priceFrom: false, durationMin: 15, aftercareTemplateId: nil, active: true, sort: 0)

        let entries = ConsumableUsage.entries(for: 9, in: [lobe, tattoo, helix, other])
        XCTAssertEqual(entries.map(\.service.id), [4, 5, 3], "Тату, then Пирсинг by position; hidden services keep their norms")
        XCTAssertEqual(entries.map(\.quantity), [3, 1, 2])
        XCTAssertEqual(ConsumableUsage.entries(for: 99, in: [lobe, tattoo]), [])

        XCTAssertEqual(ConsumableUsage.normText(2, unit: "шт", isPresence: false), "2 шт на процедуру")
        XCTAssertEqual(ConsumableUsage.normText(1, unit: "фл", isPresence: true), "используется")
        XCTAssertEqual(ConsumableUsage.summary(0), "Не используется в услугах")
        XCTAssertEqual(ConsumableUsage.summary(1), "Используется в 1 услуге")
        XCTAssertEqual(ConsumableUsage.summary(3), "Используется в 3 услугах")
    }

    // MARK: - Helpers

    private func encoded(_ body: ProductBody) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
