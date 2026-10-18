import Foundation
import Testing
@testable import MIKAN

private typealias F = InventoryFixtures

/// Deleting a product from the warehouse (`DELETE /products/:id?writeOff=true`) and the unit cost of a receipt
/// (`unitCost` of `POST /products/:id/movements/batch`): confirmation texts, cost pre-fill and the receipt row.
struct ProductDeleteAndReceiptCostTests {
    private static let nbsp = "\u{00A0}"
    private static let base = "Позиция пропадёт со склада, из кассы и у бота. Продажи и история движений сохранятся."

    /// A product without sizes: 3 уп at 600 ₽.
    private let needles = F.product(id: 9, kind: .consumable, name: "Иглы", price: 0, unit: "уп", quantity: 3, minQuantity: 1)

    private func receipt(delta: Int, amount: Int?) -> StockMovement {
        StockMovement(
            id: 1, productId: 1, productName: "Лабрет", variantId: 4, variantName: "8 мм", delta: delta, quantityAfter: 6,
            type: .receipt, note: nil, saleId: nil, appointmentId: nil, amount: amount, employee: nil,
            createdAt: Fixtures.referenceDate
        )
    }

    // MARK: - Delete

    @Test("Stock left is written off first, and the dialog says so")
    func deleteWithStock() {
        let confirmation = ProductDeleteConfirmation(product: F.labret)
        #expect(confirmation.title == "Удалить «Лабрет»?")
        #expect(confirmation.message == Self.base + " На складе 5 шт — остаток будет списан.")
        #expect(confirmation.buttonTitle == "Списать остаток и удалить")
        #expect(confirmation.writesOff)
    }

    @Test("Without stock the product is simply deleted")
    func deleteWithoutStock() {
        let empty = F.product(name: "Кольцо", quantity: 0)
        let confirmation = ProductDeleteConfirmation(product: empty)
        #expect(confirmation.title == "Удалить «Кольцо»?")
        #expect(confirmation.message == Self.base)
        #expect(confirmation.buttonTitle == "Удалить")
        #expect(!confirmation.writesOff)
    }

    @Test("A presence consumable never mentions units, but its counted stock kept aside is written off")
    func deletePresenceConsumable() {
        let confirmation = ProductDeleteConfirmation(product: F.presence(id: 15, name: "Перчатки", status: .ok, quantity: 4))
        #expect(confirmation.message == Self.base)
        #expect(confirmation.buttonTitle == "Удалить")
        #expect(confirmation.writesOff)
        #expect(!ProductDeleteConfirmation(product: F.presence(id: 16, name: "Салфетки", status: .out)).writesOff)
    }

    @Test("The delete answer: deleted for good, or archived with the units written off")
    func deletionResult() throws {
        let deleted = try Fixtures.decode(ProductDeletionResult.self, #"{ "deleted": true }"#)
        #expect(deleted == ProductDeletionResult(deleted: true))
        let archived = try Fixtures.decode(ProductDeletionResult.self, #"{ "archived": true, "writtenOff": 3 }"#)
        #expect(archived == ProductDeletionResult(archived: true, writtenOff: 3))
    }

    // MARK: - Unit cost of a receipt

    @Test("The unit cost starts at the current cost: the size's own, else the product's; none when sizes differ")
    func unitCostPrefill() {
        #expect(StockBatchDraft(product: needles, type: .receipt).unitCost == 600)
        #expect(StockBatchDraft(product: F.labret, type: .receipt).unitCost == nil, "10 мм has its own cost")
        #expect(StockBatchDraft(product: F.labret, type: .receipt, preselected: 5).unitCost == 700)
        #expect(StockBatchDraft(product: F.labret, type: .receipt, preselected: 4).unitCost == 600)
        let sameCost = F.product(variants: [F.size(1, "6 мм", quantity: 1), F.size(2, "8 мм", quantity: 1, cost: 600)])
        #expect(StockBatchDraft(product: sameCost, type: .receipt).unitCost == 600)
        let noCost = F.product(cost: nil, quantity: 2)
        #expect(StockBatchDraft(product: noCost, type: .receipt).unitCost == nil)
    }

    @Test("Only a receipt sends the unit cost")
    func unitCostBody() throws {
        var draft = StockBatchDraft(product: needles, type: .receipt).settingAmount(5, for: 9)
        draft.unitCost = 1200
        #expect(draft.body.unitCost == 1200)

        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(draft.body), as: UTF8.self)
            == #"{"lines":[{"quantity":5,"variantId":9}],"type":"receipt","unitCost":1200}"#)

        #expect(draft.switching(to: .writeoff).settingAmount(1, for: 9).body.unitCost == nil)
        draft.unitCost = nil
        #expect(draft.body.unitCost == nil, "a cleared field leaves the cost as it is")
    }

    @Test("The unit cost is limited; its title follows the unit")
    func unitCostValidationAndTitle() {
        var draft = StockBatchDraft(product: needles, type: .receipt).settingAmount(1, for: 9)
        draft.unitCost = StockBatchDraft.maxUnitCost + 1
        #expect(!draft.canSubmit)
        draft.unitCost = 0
        #expect(draft.canSubmit, "a free delivery is still a receipt")
        #expect(draft.unitCostTitle == "Цена закупки за уп")
        #expect(StockBatchDraft(product: F.labret, type: .receipt).unitCostTitle == "Цена закупки за шт.")
    }

    @Test("Jewelry and goods have no «Расход»: it is for consumables used in procedures")
    func operationsByKind() {
        #expect(MovementType.manual(for: .jewelry) == [.receipt, .writeoff, .adjustment])
        #expect(MovementType.manual(for: .goods) == [.receipt, .writeoff, .adjustment])
        #expect(MovementType.manual(for: .consumable) == [.receipt, .writeoff, .usage, .adjustment])
        #expect(StockBatchDraft(product: F.labret, type: .receipt).availableTypes.first == .receipt)
        #expect(!StockBatchDraft(product: F.labret, type: .receipt).availableTypes.contains(.usage))
    }

    @Test("A receipt with its cost reads «Приход · +5 шт · 6 000 ₽»; without it just «Приход»")
    func receiptRowText() {
        #expect(MovementText.title(receipt(delta: 5, amount: 6000)) == "Приход · +5 шт · 6\(Self.nbsp)000\(Self.nbsp)₽")
        #expect(MovementText.title(receipt(delta: 2, amount: 900), unit: "уп") == "Приход · +2 уп · 900\(Self.nbsp)₽")
        #expect(MovementText.title(receipt(delta: 5, amount: nil)) == "Приход")
        #expect(MovementText.subtitle(receipt(delta: 5, amount: 6000), showsProduct: true).hasPrefix("Приход · +5 шт · "))
    }
}
