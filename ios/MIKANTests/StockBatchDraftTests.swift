import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

/// The movement sheet: one operation over several sizes — amounts, resulting stock, lines and validation.
final class StockBatchDraftTests: XCTestCase {
    /// 6 мм: 4 (min 1) · 8 мм: 1 (min 2) · 10 мм: 0.
    private let labret = F.labret
    /// A product without sizes: 3 шт.
    private let needles = F.product(id: 9, kind: .consumable, name: "Иглы", price: 0, unit: "уп", quantity: 3, minQuantity: 1)

    private func size(_ draft: StockBatchDraft, _ id: Int) throws -> StockSize {
        try XCTUnwrap(draft.sizes.first { $0.id == id })
    }

    // MARK: - Receipt

    func testReceiptSendsOnlyTouchedSizesInSizeOrder() throws {
        let draft = StockBatchDraft(product: labret, type: .receipt)
            .settingAmount(2, for: 5)
            .settingAmount(5, for: 4)

        XCTAssertEqual(draft.lines, [
            StockLineBody(variantId: 4, quantity: 5),
            StockLineBody(variantId: 5, quantity: 2),
        ], "the 6 мм size was not touched")
        XCTAssertNil(draft.resulting(for: try size(draft, 1)))
        XCTAssertEqual(draft.resulting(for: try size(draft, 4)), 6)
        XCTAssertEqual(draft.resulting(for: try size(draft, 5)), 2)
        XCTAssertEqual(draft.totalDelta, 7)
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.body, StockBatchBody(type: .receipt, note: nil, lines: draft.lines))
    }

    func testZeroOrClearedAmountIsNotALine() {
        let draft = StockBatchDraft(product: labret, type: .receipt)
            .settingAmount(0, for: 1)
            .settingAmount(3, for: 4)
            .settingAmount(nil, for: 4)
        XCTAssertEqual(draft.lines, [])
        XCTAssertTrue(draft.isBlank)
        XCTAssertEqual(draft.validationMessage, "Укажите количество хотя бы для одного размера.")
        XCTAssertFalse(draft.canSubmit)
    }

    func testNegativeAmountIsInvalid() {
        let draft = StockBatchDraft(product: labret, type: .receipt).settingAmount(-2, for: 1)
        XCTAssertFalse(draft.isBlank)
        XCTAssertEqual(draft.validationMessage, "Количество должно быть больше нуля.")
    }

    // MARK: - Write-off and usage

    func testWriteoffCannotGoBelowZero() throws {
        let draft = StockBatchDraft(product: labret, type: .writeoff)
            .settingAmount(1, for: 1)
            .settingAmount(2, for: 4)
        XCTAssertEqual(draft.resulting(for: try size(draft, 4)), -1)
        XCTAssertEqual(draft.validationMessage, "Нельзя списать больше, чем есть: 8 мм — 1 шт.")
        XCTAssertFalse(draft.canSubmit)

        let fixed = draft.settingAmount(1, for: 4)
        XCTAssertNil(fixed.validationMessage)
        XCTAssertEqual(fixed.lines, [StockLineBody(variantId: 1, quantity: 1), StockLineBody(variantId: 4, quantity: 1)])
        XCTAssertEqual(fixed.totalDelta, -2)
    }

    func testUsageRemovesAndChecksStockToo() throws {
        let draft = StockBatchDraft(product: labret, type: .usage).settingAmount(4, for: 1)
        XCTAssertEqual(draft.resulting(for: try size(draft, 1)), 0)
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.body.type, .usage)

        XCTAssertEqual(
            draft.settingAmount(1, for: 5).validationMessage,
            "Нельзя списать больше, чем есть: 10 мм — 0 шт."
        )
    }

    func testProductWithoutSizesReadsAsBefore() throws {
        let empty = StockBatchDraft(product: needles, type: .writeoff)
        XCTAssertFalse(empty.hasSeveralSizes)
        XCTAssertEqual(empty.validationMessage, "Укажите количество.")

        let tooMuch = empty.settingAmount(5, for: 9)
        XCTAssertEqual(tooMuch.validationMessage, "Нельзя списать больше, чем есть на складе (3 уп).")

        let ok = empty.settingAmount(2, for: 9)
        XCTAssertEqual(ok.lines, [StockLineBody(variantId: 9, quantity: 2)], "the only size is the product's own variant")
        XCTAssertEqual(ok.resulting(for: try size(ok, 9)), 1)
    }

    // MARK: - Stock count

    func testCountStartsFromTheCurrentStock() {
        let draft = StockBatchDraft(product: labret, type: .adjustment)
        XCTAssertEqual(draft.amount(for: 1), 4)
        XCTAssertEqual(draft.amount(for: 4), 1)
        XCTAssertEqual(draft.amount(for: 5), 0)
        XCTAssertEqual(draft.lines, [])
        XCTAssertTrue(draft.isBlank)
        XCTAssertEqual(draft.validationMessage, "Остатки не изменились.")
    }

    func testCountSendsOnlyChangedSizesWithTheNewStock() throws {
        let draft = StockBatchDraft(product: labret, type: .adjustment)
            .settingAmount(3, for: 1)
            .settingAmount(1, for: 4)
            .settingAmount(2, for: 5)
        XCTAssertEqual(draft.lines, [
            StockLineBody(variantId: 1, quantity: 3),
            StockLineBody(variantId: 5, quantity: 2),
        ], "8 мм was counted unchanged")
        XCTAssertEqual(draft.resulting(for: try size(draft, 1)), 3)
        XCTAssertNil(draft.resulting(for: try size(draft, 4)))
        XCTAssertEqual(draft.totalDelta, 1)
        XCTAssertNil(draft.validationMessage)
    }

    func testCountMayBeZeroButNotNegative() {
        let zero = StockBatchDraft(product: labret, type: .adjustment).settingAmount(0, for: 1)
        XCTAssertEqual(zero.lines, [StockLineBody(variantId: 1, quantity: 0)])
        XCTAssertNil(zero.validationMessage)

        let negative = StockBatchDraft(product: labret, type: .adjustment).settingAmount(-1, for: 1)
        XCTAssertEqual(negative.validationMessage, "Количество не может быть меньше нуля.")
    }

    // MARK: - Editing

    func testSwitchingTheOperationStartsOver() {
        let receipt = StockBatchDraft(product: labret, type: .receipt).settingAmount(3, for: 1)
        let count = receipt.switching(to: .adjustment)
        XCTAssertEqual(count.type, .adjustment)
        XCTAssertEqual(count.amount(for: 1), 4, "a count is pre-filled with the stock")

        let back = count.switching(to: .writeoff)
        XCTAssertNil(back.amount(for: 1))
        XCTAssertEqual(back.switching(to: .writeoff), back)
    }

    func testUnknownSizeIsIgnored() {
        let draft = StockBatchDraft(product: labret, type: .receipt)
        XCTAssertEqual(draft.settingAmount(5, for: 999), draft)
    }

    func testPreselectedSizeIsShownAlone() {
        let draft = StockBatchDraft(product: labret, type: .receipt, preselected: 4)
        XCTAssertEqual(draft.preselectedId, 4)
        XCTAssertEqual(draft.visibleSizes(showingAll: false).map(\.id), [4])
        XCTAssertEqual(draft.visibleSizes(showingAll: true).map(\.id), [1, 4, 5])
        XCTAssertEqual(draft.visibleSizes(showingAll: false).first?.title, "8 мм")

        let unknown = StockBatchDraft(product: labret, type: .receipt, preselected: 999)
        XCTAssertNil(unknown.preselectedId)
        XCTAssertEqual(unknown.visibleSizes(showingAll: false).count, 3)
    }

    func testNoteIsTrimmedAndOptional() {
        var draft = StockBatchDraft(product: labret, type: .receipt).settingAmount(1, for: 1)
        draft.note = "  Поставка от Industrial  "
        XCTAssertEqual(draft.body.note, "Поставка от Industrial")
        draft.note = "   "
        XCTAssertNil(draft.body.note)
    }

    func testUnnamedSizeTitle() throws {
        let draft = StockBatchDraft(product: needles, type: .receipt)
        XCTAssertEqual(try size(draft, 9).title, "Без размера")
        XCTAssertEqual(draft.unit, "уп")
        XCTAssertEqual(draft.productName, "Иглы")
    }
}
