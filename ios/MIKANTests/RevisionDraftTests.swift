import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

/// The stock count (ревизия): what is counted, prefilled stock, checked lines, differences at cost, availability of
/// «есть / нет» consumables and the request body.
final class RevisionDraftTests: XCTestCase {
    /// Лабрет (cost 600): 6 мм — 4, 8 мм — 1, 10 мм — 0 (own cost 700).
    private let labret = F.labret
    /// Unknown cost: differences of it count as 0 ₽.
    private let clicker = F.product(id: 2, name: "Кликер", category: "Кольцо", cost: nil, variants: [F.size(12, "", quantity: 6)])
    /// Hidden and empty: not on the shelf, not counted.
    private let hiddenEmpty = F.product(id: 3, name: "Старый банан", category: "Лабрет", active: false, variants: [F.size(13, "", quantity: 0)])
    /// Hidden but still in stock: counted, without a category.
    private let hiddenInStock = F.product(id: 6, name: "Архивное кольцо", active: false, variants: [F.size(16, "", quantity: 2)])

    private let needles = F.product(
        id: 9, kind: .consumable, name: "Иглы 1.2", category: "Иглы", price: 0, cost: 40, variants: [F.size(19, "", quantity: 50)]
    )
    private let antiseptic = F.presence(id: 15, name: "Антисептик", status: .low, category: "Дезинфекция", quantity: 3)
    private let gloves = F.presence(id: 16, name: "Перчатки", status: .ok)
    private let hiddenSoap = F.presence(id: 17, name: "Мыло", status: .out, active: false)

    private let categories = [
        F.category(1, "Лабрет", position: 1),
        F.category(2, "Кольцо", position: 0),
        F.category(3, "Иглы", section: .consumable, position: 1),
        F.category(4, "Дезинфекция", section: .consumable, position: 0),
    ]

    private var all: [Product] { [labret, clicker, hiddenEmpty, hiddenInStock, needles, antiseptic, gloves, hiddenSoap] }

    private func jewelryDraft() -> RevisionDraft {
        RevisionDraft(section: .jewelry, products: all, categories: categories)
    }

    private func consumablesDraft() -> RevisionDraft {
        RevisionDraft(section: .consumable, products: all, categories: categories)
    }

    private func size(_ draft: RevisionDraft, _ id: Int) throws -> RevisionSize {
        try XCTUnwrap(draft.products.flatMap(\.sizes).first { $0.id == id })
    }

    // MARK: - What is counted

    func testCountsTheSectionByCategoryInRegistryOrder() {
        let draft = jewelryDraft()
        XCTAssertEqual(draft.groups.map(\.title), ["Кольцо", "Лабрет", "Без категории"])
        XCTAssertEqual(draft.products.map(\.id), [2, 1, 6], "other kinds and a hidden empty product are left out")
        XCTAssertEqual(draft.lineCount, 5, "three labret sizes, the clicker and the hidden ring in stock")

        let consumables = consumablesDraft()
        XCTAssertEqual(consumables.groups.map(\.title), ["Дезинфекция", "Иглы", "Без категории"])
        XCTAssertEqual(consumables.products.map(\.id), [15, 9, 16], "a hidden presence consumable is not counted")
        XCTAssertEqual(consumables.lineCount, 3)
    }

    func testPresenceProductsHaveNoSizesAndKeepTheirStatus() throws {
        let product = try XCTUnwrap(consumablesDraft().products.first { $0.id == 15 })
        XCTAssertTrue(product.isPresence)
        XCTAssertEqual(product.sizes, [], "the stock kept aside is not counted")
        XCTAssertEqual(product.expectedStatus, .low)
    }

    func testUnitCostFallsBackToTheProductAndUnknownIsZero() throws {
        let draft = jewelryDraft()
        XCTAssertEqual(try size(draft, 1).unitCost, 600)
        XCTAssertEqual(try size(draft, 5).unitCost, 700, "a size's own cost")
        XCTAssertEqual(try size(draft, 12).unitCost, 0, "no cost known")
    }

    // MARK: - Prefill

    func testEverySizeStartsAtItsExpectedStockButNothingIsChecked() throws {
        let draft = jewelryDraft()
        XCTAssertEqual(draft.count(for: try size(draft, 1)), 4)
        XCTAssertEqual(draft.count(for: try size(draft, 4)), 1)
        XCTAssertFalse(draft.isChecked(try size(draft, 1)))
        XCTAssertNil(draft.delta(for: try size(draft, 1)))
        XCTAssertEqual(draft.checkedCount, 0)
        XCTAssertEqual(draft.uncheckedCount, 5)
        XCTAssertFalse(draft.canSubmit)
        XCTAssertEqual(draft.body.counts, [])
        XCTAssertEqual(draft.body.presence, [])

        let consumables = consumablesDraft()
        let antiseptic = try XCTUnwrap(consumables.products.first { $0.id == 15 })
        XCTAssertEqual(consumables.status(for: antiseptic), .low, "the expected status shows until marked")
        XCTAssertFalse(consumables.isChecked(antiseptic))
    }

    // MARK: - Counting

    func testTypedCountChecksTheSizeAndShowsTheDifference() throws {
        let draft = jewelryDraft().settingCount(2, for: 1)
        let six = try size(draft, 1)
        XCTAssertTrue(draft.isChecked(six))
        XCTAssertEqual(draft.count(for: six), 2)
        XCTAssertEqual(draft.delta(for: six), -2)
        XCTAssertTrue(draft.isChanged(six))
        XCTAssertEqual(draft.checkedCount, 1)
        XCTAssertEqual(draft.changedCount, 1)
        XCTAssertEqual(draft.shortage, 2)
        XCTAssertEqual(draft.shortageCost, 1_200)
        XCTAssertTrue(draft.canSubmit)
    }

    func testStepsConfirmationAndClearing() throws {
        var draft = jewelryDraft().adjustingCount(for: 4, by: 1)
        XCTAssertEqual(draft.count(for: try size(draft, 4)), 2, "one more than the expected 1")
        XCTAssertEqual(draft.delta(for: try size(draft, 4)), 1)

        draft = draft.adjustingCount(for: 5, by: -1)
        XCTAssertEqual(draft.count(for: try size(draft, 5)), 0, "never below zero")
        XCTAssertEqual(draft.delta(for: try size(draft, 5)), 0)
        XCTAssertTrue(draft.isChecked(try size(draft, 5)), "a step checks the size")

        draft = draft.settingCount(-4, for: 1)
        XCTAssertEqual(draft.count(for: try size(draft, 1)), 0, "a negative count is clamped")

        draft = draft.confirming(sizeId: 1)
        XCTAssertEqual(draft.delta(for: try size(draft, 1)), 0, "«сходится» puts back the expected stock")

        draft = draft.settingCount(nil, for: 4)
        XCTAssertFalse(draft.isChecked(try size(draft, 4)), "an emptied field is not checked")
        XCTAssertEqual(draft.count(for: try size(draft, 4)), 1)

        draft = draft.clearing(productId: 1)
        XCTAssertEqual(draft.checkedCount, 0)
        XCTAssertEqual(draft.settingCount(3, for: 999), draft, "an unknown size changes nothing")
    }

    func testTotalsAtCost() {
        let draft = jewelryDraft()
            .settingCount(3, for: 5) // 10 мм: +3 at 700
            .settingCount(1, for: 1) // 6 мм: −3 at 600
            .settingCount(4, for: 12) // clicker: −2 at unknown cost
            .confirming(sizeId: 4)
        XCTAssertEqual(draft.checkedCount, 4)
        XCTAssertEqual(draft.changedCount, 3)
        XCTAssertEqual(draft.surplus, 3)
        XCTAssertEqual(draft.surplusCost, 2_100)
        XCTAssertEqual(draft.shortage, 5)
        XCTAssertEqual(draft.shortageCost, 1_800, "the clicker's units count, its value does not")
        XCTAssertEqual(draft.progress, 0.8, accuracy: 0.001)
    }

    // MARK: - Availability

    func testMarkedStatusesAndTheirChanges() throws {
        let draft = consumablesDraft()
            .markingStatus(.out, for: 15)
            .markingStatus(.ok, for: 16)
        let antiseptic = try XCTUnwrap(draft.products.first { $0.id == 15 })
        let gloves = try XCTUnwrap(draft.products.first { $0.id == 16 })
        XCTAssertEqual(draft.status(for: antiseptic), .out)
        XCTAssertTrue(draft.isChanged(antiseptic), "«Заканчивается» → «Нет»")
        XCTAssertTrue(draft.isChecked(gloves))
        XCTAssertFalse(draft.isChanged(gloves), "marked as expected")
        XCTAssertEqual(draft.checkedCount, 2)
        XCTAssertEqual(draft.changedCount, 1)
        XCTAssertEqual(draft.shortage, 0, "statuses are not units")
        XCTAssertEqual(draft.markingStatus(.ok, for: 9), draft, "a counted consumable takes no status")

        let cleared = draft.markingStatus(nil, for: 16)
        XCTAssertFalse(cleared.isChecked(gloves))
    }

    // MARK: - Body

    func testBodyCarriesOnlyCheckedLinesInListOrder() {
        var draft = consumablesDraft()
            .markingStatus(.ok, for: 15)
            .settingCount(47, for: 19)
        draft.note = "  Конец месяца  "
        XCTAssertEqual(draft.body, StockRevisionBody(
            section: .consumable,
            note: "Конец месяца",
            counts: [StockLineBody(variantId: 19, quantity: 47)],
            presence: [PresenceLineBody(productId: 15, status: .ok)]
        ), "the unmarked gloves are left out")

        let jewelry = jewelryDraft()
            .settingCount(9, for: 16)
            .confirming(sizeId: 4)
            .settingCount(5, for: 12)
        XCTAssertEqual(jewelry.body.counts.map(\.variantId), [12, 4, 16], "Кольцо, Лабрет, Без категории — not the typing order")
        XCTAssertEqual(jewelry.body.counts.map(\.quantity), [5, 1, 9], "a confirmed size sends its expected stock")
        XCTAssertNil(jewelry.body.note, "a blank note is omitted")
    }

    func testConfirmingTheRestOfAGroupOrOfEverything() throws {
        let draft = jewelryDraft().settingCount(2, for: 1)
        let labretGroup = try XCTUnwrap(draft.groups.first { $0.title == "Лабрет" }).id
        XCTAssertEqual(draft.uncheckedCount(inGroup: labretGroup), 2)

        let group = draft.confirmingUnchecked(inGroup: labretGroup)
        XCTAssertEqual(group.uncheckedCount(inGroup: labretGroup), 0)
        XCTAssertEqual(group.count(for: try size(group, 1)), 2, "a typed count stays")
        XCTAssertEqual(group.count(for: try size(group, 4)), 1)
        XCTAssertEqual(group.checkedCount, 3)

        let everything = consumablesDraft().settingCount(40, for: 19).confirmingUnchecked()
        XCTAssertEqual(everything.uncheckedCount, 0)
        XCTAssertEqual(everything.body.counts, [StockLineBody(variantId: 19, quantity: 40)])
        XCTAssertEqual(everything.body.presence, [
            PresenceLineBody(productId: 15, status: .low),
            PresenceLineBody(productId: 16, status: .ok),
        ], "unmarked statuses are confirmed as they were")
    }

    // MARK: - Filtering

    func testVisibleGroupsFollowTheLineFilterAndSearch() {
        let draft = jewelryDraft().settingCount(0, for: 4).confirming(sizeId: 12)
        XCTAssertEqual(draft.visibleGroups(search: "", filter: .all).flatMap(\.items).map(\.id), [2, 1, 6])
        XCTAssertEqual(
            draft.visibleGroups(search: "", filter: .unchecked).flatMap(\.items).map(\.id), [1, 6],
            "the labret still has unchecked sizes"
        )
        XCTAssertEqual(draft.visibleGroups(search: "", filter: .changed).flatMap(\.items).map(\.id), [1])
        XCTAssertEqual(draft.visibleGroups(search: "10 ММ", filter: .all).flatMap(\.items).map(\.id), [1], "size names match")
        XCTAssertEqual(draft.visibleGroups(search: "кольц", filter: .all).map(\.title), ["Кольцо", "Без категории"])
        XCTAssertEqual(draft.visibleGroups(search: "септум", filter: .all), [])
    }

    func testEmptySection() {
        let draft = RevisionDraft(section: .goods, products: all, categories: categories)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(draft.lineCount, 0)
        XCTAssertEqual(draft.progress, 0)
        XCTAssertFalse(draft.canSubmit)
    }
}
