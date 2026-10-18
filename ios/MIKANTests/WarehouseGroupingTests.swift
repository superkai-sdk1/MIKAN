import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

/// The warehouse list by category: the registry's staff order, unregistered names after it, «Без категории» last.
final class WarehouseGroupingTests: XCTestCase {
    private let categories = [
        F.category(1, "Лабрет", position: 1),
        F.category(2, "Кольца", position: 0),
        F.category(3, "Септум", position: 2),
        F.category(4, "Иглы", section: .consumable, position: 0),
        F.category(5, "Ухо", section: .service, serviceCategory: .piercing, position: 0),
    ]

    private func product(_ id: Int, _ name: String, category: String?, kind: ProductKind = .jewelry) -> Product {
        F.product(id: id, kind: kind, name: name, category: category)
    }

    func testGroupsFollowTheRegistryOrder() {
        let products = [
            product(1, "Лабрет 6 мм", category: "Лабрет"),
            product(2, "Кликер", category: "Кольца"),
            product(3, "Банан", category: nil),
            product(4, "Сегментное кольцо", category: "Кольца"),
            product(5, "Микродермал", category: "Дермалы"),
            product(6, "Твистер", category: "Анкер"),
        ]
        let groups = WarehouseGrouping.groups(products, section: .jewelry, categories: categories)
        XCTAssertEqual(groups.map(\.title), ["Кольца", "Лабрет", "Анкер", "Дермалы", "Без категории"],
                       "registered first in staff order, then unregistered names alphabetically, then no category; empty «Септум» is left out")
        XCTAssertEqual(groups.map { $0.items.map(\.id) }, [[2, 4], [1], [6], [5], [3]])
        XCTAssertNil(groups.last?.category)
    }

    func testItemsInsideAGroupAreSortedNaturallyByName() {
        let products = [
            product(1, "Лабрет 10 мм", category: "Лабрет"),
            product(2, "лабрет 6 мм", category: "Лабрет"),
            product(3, "Лабрет 8 мм", category: "Лабрет"),
        ]
        let groups = WarehouseGrouping.groups(products, section: .jewelry, categories: categories)
        XCTAssertEqual(groups.first?.items.map(\.id), [2, 3, 1], "6, 8, 10 — numbers compare as numbers, case ignored")
    }

    func testCategoryNamesMatchIgnoringCaseUnderTheRegistrySpelling() {
        let products = [
            product(1, "Кликер", category: "кольца"),
            product(2, "Сегмент", category: "  Кольца "),
            product(3, "Ёлочка", category: "ЛАБРЕТ"),
        ]
        let groups = WarehouseGrouping.groups(products, section: .jewelry, categories: categories)
        XCTAssertEqual(groups.map(\.title), ["Кольца", "Лабрет"])
        XCTAssertEqual(groups.map(\.items.count), [2, 1])
        XCTAssertEqual(Set(groups.map(\.id)).count, 2, "group ids are stable and distinct")
    }

    func testOtherSectionsCategoriesDoNotOrderThisOne() {
        let products = [product(1, "Иглы 1.2", category: "Иглы", kind: .consumable), product(2, "Ватные диски", category: "Вата", kind: .consumable)]
        let consumables = WarehouseGrouping.groups(products, section: .consumable, categories: categories)
        XCTAssertEqual(consumables.map(\.title), ["Иглы", "Вата"], "«Иглы» is registered for consumables, «Вата» is not")

        let goods = WarehouseGrouping.groups(products, section: .goods, categories: categories)
        XCTAssertEqual(goods.map(\.title), ["Вата", "Иглы"], "nothing registered for goods: alphabetical")
    }

    func testWithoutTheRegistryGroupsAreAlphabetical() {
        let products = [product(1, "Кликер", category: "Кольца"), product(2, "Банан", category: nil), product(3, "Лабрет", category: "Лабрет")]
        let groups = WarehouseGrouping.groups(products, section: .jewelry, categories: [])
        XCTAssertEqual(groups.map(\.title), ["Кольца", "Лабрет", "Без категории"])
        XCTAssertEqual(WarehouseGrouping.groups([Product](), section: .jewelry, categories: categories), [])
    }

    func testCategoryOptionsForPickersAndFilters() {
        let products = [product(1, "Твистер", category: "Анкер"), product(2, "Кликер", category: "кольца")]
        XCTAssertEqual(
            WarehouseGrouping.categoryOptions(section: .jewelry, categories: categories, products: products, extra: ["Новая", " "]),
            ["Кольца", "Лабрет", "Септум", "Анкер", "Новая"],
            "every registered category (even empty), then product and typed names; repeats in another case dropped"
        )
    }
}
