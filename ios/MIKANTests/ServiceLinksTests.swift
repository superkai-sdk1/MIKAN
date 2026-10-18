import Foundation
import Testing
@testable import MIKAN

/// The service editor's warehouse links: compatible jewelry (the bot offers it) and the consumption norm,
/// and the services list grouped in the warehouse categories' order.
struct ServiceLinksTests {
    private func service(
        id: Int = 1,
        name: String = "Хеликс",
        group: String? = nil,
        jewelryIds: [Int] = [],
        consumables: [ServiceConsumable] = [],
        sort: Int = 0
    ) -> Service {
        Service(
            id: id, name: name, category: .piercing, group: group, price: 2_500, priceFrom: false, durationMin: 30,
            jewelryIds: jewelryIds, consumables: consumables, active: true, sort: sort
        )
    }

    private func presence(_ id: Int, name: String, status: PresenceStatus) -> Product {
        var product = InventoryFixtures.product(id: id, kind: .consumable, name: name, price: 0, variants: [InventoryFixtures.size(id, "")])
        product.stockMode = .presence
        product.presenceStatus = status
        return product
    }

    // MARK: - Draft and body

    @Test("The draft loads the links and the norm and sends them in the body")
    func draftBody() throws {
        let norm = [ServiceConsumable(productId: 12, quantity: 1), ServiceConsumable(productId: 15, quantity: 2)]
        var draft = ServiceEditorDraft(service: service(jewelryIds: [1, 7], consumables: norm), nextSort: 0)
        #expect(draft.jewelryIds == [1, 7])
        #expect(draft.consumables == norm)
        #expect(draft.body.jewelryIds == [1, 7])
        #expect(draft.body.consumables == norm)

        draft.jewelryIds = ServiceJewelryLinks.removing(1, from: draft.jewelryIds)
        draft.consumables = ServiceConsumptionNorms.settingQuantity(3, of: 12, in: draft.consumables)
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(draft.body), as: UTF8.self)
        #expect(json.contains(#""jewelryIds":[7]"#))
        #expect(json.contains(#""consumables":[{"productId":12,"quantity":3},{"productId":15,"quantity":2}]"#))
    }

    @Test("A new service starts without links, and an empty list is still sent (PATCH replaces)")
    func newServiceSendsEmptyLists() throws {
        let draft = ServiceEditorDraft(service: nil, nextSort: 0)
        #expect(draft.jewelryIds.isEmpty && draft.consumables.isEmpty)
        let json = String(decoding: try JSONCoding.makeEncoder().encode(draft.body), as: UTF8.self)
        #expect(json.contains(#""jewelryIds":[]"#))
        #expect(json.contains(#""consumables":[]"#))
    }

    @Test("Too many links or a quantity out of range block saving")
    func validation() {
        var draft = ServiceEditorDraft(service: service(), nextSort: 0)
        #expect(draft.canSave)
        draft.jewelryIds = Array(1...101)
        #expect(draft.validationMessage == "Не больше 100 совместимых украшений.")
        draft.jewelryIds = Array(1...100)
        #expect(draft.canSave)
        draft.consumables = (1...51).map { ServiceConsumable(productId: $0, quantity: 1) }
        #expect(draft.validationMessage == "Не больше 50 расходников в норме.")
        draft.consumables = [ServiceConsumable(productId: 1, quantity: 0)]
        #expect(draft.validationMessage == "Количество расходника — от 1 до 1000.")
    }

    // MARK: - Operations

    @Test("The picker keeps linked pieces in place and appends new ones in catalog order")
    func applyingJewelrySelection() {
        let linked = [7, 1]
        let result = ServiceJewelryLinks.applying(selection: [1, 3, 9], to: linked, catalogOrder: [9, 1, 3, 7])
        #expect(result == [1, 9, 3])
        #expect(ServiceJewelryLinks.applying(selection: [], to: linked, catalogOrder: [1, 7]).isEmpty)
        #expect(linked == [7, 1], "the input is not mutated")
    }

    @Test("Norm quantities are clamped to 1…1000; the picker keeps quantities and adds one unit")
    func normOperations() {
        let norm = [ServiceConsumable(productId: 12, quantity: 2), ServiceConsumable(productId: 15, quantity: 1)]
        #expect(ServiceConsumptionNorms.settingQuantity(0, of: 12, in: norm).first?.quantity == 1)
        #expect(ServiceConsumptionNorms.settingQuantity(5_000, of: 12, in: norm).first?.quantity == 1_000)
        #expect(ServiceConsumptionNorms.settingQuantity(4, of: 99, in: norm) == norm, "an unknown product changes nothing")
        #expect(ServiceConsumptionNorms.removing(12, from: norm) == [ServiceConsumable(productId: 15, quantity: 1)])

        let picked = ServiceConsumptionNorms.applying(selection: [12, 20], to: norm, catalogOrder: [20, 12])
        #expect(picked == [ServiceConsumable(productId: 12, quantity: 2), ServiceConsumable(productId: 20, quantity: 1)])
    }

    // MARK: - Texts and lookup

    @Test("Sizes in stock, the norm text and availability of presence consumables")
    func texts() {
        #expect(ServiceLinkText.sizesInStock(InventoryFixtures.labret) == "6 мм · 8 мм", "the 10 мм size is out")
        let plain = InventoryFixtures.product(id: 2, variants: [InventoryFixtures.size(2, "", quantity: 4)])
        #expect(ServiceLinkText.sizesInStock(plain) == "4 шт")
        let gone = InventoryFixtures.product(id: 3, variants: [InventoryFixtures.size(3, "6 мм")])
        #expect(ServiceLinkText.sizesInStock(gone) == "Нет в наличии")
        #expect(StockAvailability(gone) == .out)
        #expect(StockAvailability(InventoryFixtures.labret) == .low, "a size runs low")

        let soap = presence(15, name: "Мыло", status: .ok)
        #expect(ServiceLinkText.norm(quantity: 1, product: soap) == "используется")
        #expect(StockAvailability(soap) == .inStock, "presence «есть» even with no counted stock")
        #expect(StockAvailability(presence(16, name: "Салфетки", status: .low)) == .low)
        let needles = InventoryFixtures.product(id: 12, kind: .consumable, name: "Иглы", unit: "шт")
        #expect(ServiceLinkText.norm(quantity: 2, product: needles) == "2 шт")
    }

    @Test("Links resolve in link order; pickers offer active products and hidden ones already linked")
    func lookup() {
        let active = InventoryFixtures.product(id: 1)
        let hidden = InventoryFixtures.product(id: 2, active: false)
        let otherHidden = InventoryFixtures.product(id: 3, active: false)
        let needles = InventoryFixtures.product(id: 4, kind: .consumable)
        let all = [active, hidden, otherHidden, needles]
        #expect(ServiceLinkedProducts.resolve([2, 9, 1], in: all).map(\.id) == [2, 1])
        #expect(ServiceLinkedProducts.missing([2, 9, 1], in: all) == [9])
        #expect(ServiceLinkedProducts.options(all, kind: .jewelry, linked: [2]).map(\.id) == [1, 2])
        #expect(ServiceLinkedProducts.options(all, kind: .consumable, linked: []).map(\.id) == [4])
    }

    // MARK: - Services list

    @Test("Groups follow the warehouse categories' order; unregistered ones follow, «Без группы» last")
    func groupsInRegistryOrder() {
        let registry = [
            CatalogCategory(id: 1, section: .service, serviceCategory: .piercing, name: "Ухо", position: 1, itemCount: 2),
            CatalogCategory(id: 2, section: .service, serviceCategory: .piercing, name: "Лицо", position: 0, itemCount: 1),
            CatalogCategory(id: 3, section: .service, serviceCategory: .piercing, name: "Пусто", position: 2, itemCount: 0),
            CatalogCategory(id: 4, section: .service, serviceCategory: .tattoo, name: "Тело", position: 0, itemCount: 0),
        ]
        let services = [
            service(id: 1, name: "Хеликс", group: "Ухо"),
            service(id: 2, name: "Без группы", group: nil),
            service(id: 3, name: "Пупок", group: "Тело"),
            service(id: 4, name: "Крыло носа", group: "Лицо"),
            service(id: 5, name: "Снятие", group: "Без группы"),
        ]
        let sections = ServiceCatalog.sections(services, categories: registry)
        #expect(sections.map(\.group) == ["Лицо", "Ухо", "Тело", "Без группы"])
        #expect(sections.last?.services.map(\.id) == [2, 5], "a group named «Без группы» merges with ungrouped")
        #expect(sections.map(\.isFirstInCategory) == [true, false, false, false])
    }
}
