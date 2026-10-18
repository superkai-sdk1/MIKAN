import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

private let labret = F.labret
private let earring = F.product(
    id: 2, name: "Серёжка-кольцо", sku: "SR-01", category: "Кольцо", material: "Хирургическая сталь 316L",
    color: "Золотистый", supplier: "Мастерская", variants: [F.size(10, "8 мм", quantity: 5, min: 1), F.size(11, "10 ММ", quantity: 3, min: 1)]
)
private let ring = F.product(
    id: 3, name: "Кликер", category: "кольцо", material: "Титан ASTM F136", stone: "Опал",
    variants: [F.size(12, "", quantity: 6, min: 2)]
)
private let gloves = F.product(
    id: 4, kind: .consumable, name: "Перчатки нитриловые", category: "Расходники", material: "Нитрил", price: 0,
    variants: [F.size(13, "M", quantity: 1, min: 5)]
)
private let all = [labret, earring, ring, gloves]

final class InventoryFilterTests: XCTestCase {
    private func ids(_ filter: InventoryFilter) -> [Int] {
        filter.apply(all).map(\.id)
    }

    // MARK: - Search

    func testEmptyFilterKeepsEverything() {
        XCTAssertEqual(ids(InventoryFilter()), [1, 2, 3, 4])
        XCTAssertFalse(InventoryFilter(kind: .jewelry).isActive)
    }

    func testSearchIgnoresCaseAndReadsYoAsYe() {
        XCTAssertEqual(ids(InventoryFilter(search: "СЕРЕЖКА")), [2])
        XCTAssertEqual(ids(InventoryFilter(search: "серёж")), [2])
        XCTAssertEqual(ids(InventoryFilter(search: "  кликер  ")), [3])
    }

    func testSearchFindsProductAndSizeSkus() {
        XCTAssertEqual(ids(InventoryFilter(search: "lb-12")), [1], "the product article")
        XCTAssertEqual(ids(InventoryFilter(search: "LB-12-10")), [1], "an article of one size")
        XCTAssertEqual(ids(InventoryFilter(search: "sr-01")), [2])
    }

    func testSearchCoversCategoryMaterialColourStoneSupplierAndSizes() {
        XCTAssertEqual(ids(InventoryFilter(search: "лабрет")), [1], "name and category")
        XCTAssertEqual(ids(InventoryFilter(search: "316L")), [2], "material")
        XCTAssertEqual(ids(InventoryFilter(search: "золотист")), [2], "colour")
        XCTAssertEqual(ids(InventoryFilter(search: "опал")), [3], "stone")
        XCTAssertEqual(ids(InventoryFilter(search: "industrial")), [1], "supplier")
        XCTAssertEqual(ids(InventoryFilter(search: "10 мм")), [1, 2], "size names, case-insensitive")
        XCTAssertEqual(ids(InventoryFilter(search: "16G")), [1], "thickness with the gauge")
    }

    func testEveryWordMustMatchSomeField() {
        XCTAssertEqual(ids(InventoryFilter(search: "титан 8 мм")), [1])
        XCTAssertEqual(ids(InventoryFilter(search: "титан опал")), [3])
        XCTAssertEqual(ids(InventoryFilter(search: "титан нитрил")), [])
    }

    // MARK: - Filters

    func testKindKeepsOneKind() {
        XCTAssertEqual(ids(InventoryFilter(kind: .jewelry)), [1, 2, 3])
        XCTAssertEqual(ids(InventoryFilter(kind: .consumable)), [4])
    }

    func testLowOnlyKeepsProductsWithALowSize() {
        XCTAssertEqual(ids(InventoryFilter(lowOnly: true)), [1, 4], "the labret has low 8 and 10 мм; gloves are below minimum")
        XCTAssertTrue(InventoryFilter(lowOnly: true).isActive)
    }

    func testCategoryAndMaterialMatchIgnoringCase() {
        XCTAssertEqual(ids(InventoryFilter(category: "Кольцо")), [2, 3], "«кольцо» and «Кольцо» are one category")
        XCTAssertEqual(ids(InventoryFilter(material: "титан astm f136")), [1, 3])
        XCTAssertEqual(ids(InventoryFilter(kind: .jewelry, category: "Кольцо", material: "Титан ASTM F136")), [3])
    }

    func testSizeKeepsProductsThatHaveIt() {
        XCTAssertEqual(ids(InventoryFilter(size: "10 мм")), [1, 2])
        XCTAssertEqual(ids(InventoryFilter(size: "6 мм")), [1])
        XCTAssertEqual(ids(InventoryFilter(size: "12 мм")), [])
    }

    func testFiltersCombineWithSearch() {
        XCTAssertEqual(ids(InventoryFilter(kind: .jewelry, search: "титан", lowOnly: true)), [1])
        XCTAssertEqual(ids(InventoryFilter(search: "кольцо", size: "8 мм")), [2])
    }

    // MARK: - State

    func testFacetCountAndResets() {
        let filter = InventoryFilter(kind: .jewelry, search: "лаб", lowOnly: true, category: "Лабрет", material: " ", size: "8 мм")
        XCTAssertEqual(filter.facetCount, 2, "a blank material is not a facet")
        XCTAssertTrue(filter.isActive)

        let withoutFacets = filter.withoutFacets
        XCTAssertEqual(withoutFacets, InventoryFilter(kind: .jewelry, search: "лаб", lowOnly: true))

        let switched = filter.switching(to: .consumable)
        XCTAssertEqual(switched, InventoryFilter(kind: .consumable, search: "лаб", lowOnly: true), "facets belong to a kind")

        XCTAssertEqual(filter.cleared, InventoryFilter(kind: .jewelry))
    }

    // MARK: - Options

    func testOptionsAreDistinctAndNaturallySorted() {
        XCTAssertEqual(InventoryFilter.sizes(in: all), ["6 мм", "8 мм", "10 мм", "M"], "numbers compare as numbers; «10 ММ» repeats «10 мм»")
        XCTAssertEqual(InventoryFilter.categories(in: all), ["Кольцо", "Лабрет", "Расходники"])
        XCTAssertEqual(InventoryFilter.materials(in: [labret, ring]), ["Титан ASTM F136"])
        XCTAssertEqual(InventoryFilter.categories(in: [F.product(category: "  ")]), [], "blank values are skipped")
    }

    func testNormalization() {
        XCTAssertEqual(InventoryFilter.normalized("  Ёлка  "), "елка")
    }

    // MARK: - Goods and «есть / нет» consumables

    private var warehouse: [Product] {
        let spray = F.product(
            id: 20, kind: .goods, name: "Спрей H2Ocean", category: "Уход", supplier: "H2Ocean",
            variants: [F.size(30, "50 мл", quantity: 5, min: 1), F.size(31, "100 мл", quantity: 0, min: 1)]
        )
        let card = F.product(id: 21, kind: .goods, name: "Подарочный сертификат", category: "Сертификаты", variants: [F.size(32, "", quantity: 9, min: 0)])
        let antiseptic = F.presence(id: 22, name: "Антисептик", status: .low, category: "Дезинфекция")
        let soap = F.presence(id: 23, name: "Мыло", status: .out)
        let wipes = F.presence(id: 24, name: "Салфетки", status: .ok, quantity: 40)
        return all + [spray, card, antiseptic, soap, wipes]
    }

    private func warehouseIds(_ filter: InventoryFilter) -> [Int] {
        filter.apply(warehouse).map(\.id)
    }

    func testGoodsAreTheirOwnKind() {
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .goods)), [20, 21])
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .goods, search: "h2ocean")), [20], "supplier")
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .goods, size: "100 МЛ")), [20], "volumes are sizes")
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .goods, lowOnly: true)), [20], "100 мл is out")
    }

    func testLowOnlyKeepsPresenceConsumablesNotMarkedOk() {
        XCTAssertEqual(
            warehouseIds(InventoryFilter(kind: .consumable, lowOnly: true)), [4, 22, 23],
            "gloves below the minimum, «заканчивается» and «нет»; «есть» with stock aside is fine"
        )
    }

    func testAvailabilityFacet() {
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .consumable, presence: .low)), [22])
        XCTAssertEqual(warehouseIds(InventoryFilter(kind: .consumable, presence: .ok)), [24], "counted consumables never match")
        XCTAssertEqual(warehouseIds(InventoryFilter(presence: .out)), [23])

        let filter = InventoryFilter(kind: .consumable, search: "а", lowOnly: true, category: "Дезинфекция", presence: .low)
        XCTAssertEqual(filter.facetCount, 2)
        XCTAssertEqual(filter.withoutFacets, InventoryFilter(kind: .consumable, search: "а", lowOnly: true))
        XCTAssertEqual(filter.switching(to: .goods), InventoryFilter(kind: .goods, search: "а", lowOnly: true))
        XCTAssertEqual(filter.cleared, InventoryFilter(kind: .consumable))
    }

    func testFacetOptionsForPresenceConsumables() {
        let consumables = warehouse.filter { $0.kind == .consumable }
        XCTAssertEqual(InventoryFilter.sizes(in: consumables), ["M"], "«есть / нет» items have no sizes to offer")
        XCTAssertTrue(InventoryFilter.hasPresence(in: consumables))
        XCTAssertFalse(InventoryFilter.hasPresence(in: all))
    }
}
