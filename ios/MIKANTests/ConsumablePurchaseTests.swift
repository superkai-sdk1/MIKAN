import Foundation
import Testing
@testable import MIKAN

/// Purchases of consumables tracked as «есть / нет» (docs/API.md «StockMovement», `POST /products/:id/purchases`,
/// analytics `stock.purchases`): decoding, the purchase form, the movement row and the analytics texts.
struct ConsumablePurchaseTests {
    private static let purchaseJSON = #"""
    { "id": 7, "productId": 15, "productName": "Перчатки", "variantId": 15, "variantName": "", "delta": 0,
      "quantityAfter": 0, "type": "purchase", "note": "Медтехника, 2 упаковки", "saleId": null, "appointmentId": null,
      "revisionId": null, "amount": 3500, "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "<T>" }
    """#

    private static let nbsp = "\u{00A0}"

    private func movement(type: MovementType, amount: Int?, daysAgo: Int, now: Date) -> StockMovement {
        StockMovement(
            id: daysAgo, productId: 15, productName: "Перчатки", variantId: 15, variantName: "", delta: 0, quantityAfter: 0,
            type: type, note: nil, saleId: nil, appointmentId: nil, amount: amount, employee: nil,
            createdAt: now.addingTimeInterval(-Double(daysAgo) * 86_400)
        )
    }

    private func analytics(stock: String) throws -> ReportAnalytics {
        let json = #"{ "from": "2026-10-12T21:00:00Z", "to": "2026-10-15T21:00:00Z", "totals": { "net": 0 }, "stock": "#
            + stock + " }"
        return try JSONCoding.makeDecoder().decode(ReportAnalytics.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    @Test("A purchase movement carries what it cost; other movements have no amount")
    func purchaseMovement() throws {
        let purchase = try Fixtures.decode(StockMovement.self, Self.purchaseJSON)
        #expect(purchase.type == .purchase)
        #expect(purchase.amount == 3500)
        #expect(purchase.delta == 0)
        #expect(!purchase.movesStock)

        let sale = try Fixtures.decode(StockMovement.self, Fixtures.stockMovement)
        #expect(sale.amount == nil, "a server that predates purchases sends no amount")
        #expect(sale.movesStock)
    }

    @Test("A movement type this build does not know still decodes, and is not offered as a filter")
    func unknownType() throws {
        let json = Fixtures.stockMovement.replacingOccurrences(of: #""type": "sale""#, with: #""type": "transfer""#)
        #expect(try Fixtures.decode(StockMovement.self, json).type == .other)
        #expect(try JSONDecoder().decode(MovementType.self, from: Data(#""purchase""#.utf8)) == .purchase)
        #expect(MovementType.listed.contains(.purchase))
        #expect(!MovementType.listed.contains(.other))
        #expect(!MovementType.manual.contains(.purchase), "a purchase has its own sheet")
    }

    @Test("Analytics: purchases decode, and a server without them reads as zero")
    func analyticsPurchases() throws {
        let stock = try analytics(stock: #"""
        { "writeoffs": { "quantity": 2, "value": 800, "unitsWithoutCost": 0 },
          "usage": { "quantity": 8, "value": 50, "unitsWithoutCost": 3 },
          "purchases": { "count": 1, "value": 3500 }, "expenses": 4350,
          "top": [ { "productId": 15, "name": "Перчатки", "kind": "consumable", "type": "purchase", "quantity": 1, "value": 3500 } ],
          "onHand": { "units": 0, "value": 0, "unitsWithoutCost": 0, "byKind": [] } }
        """#).stock
        #expect(stock.purchases == AnalyticsStockPurchases(count: 1, value: 3500))
        #expect(stock.expenses == 4350)
        #expect(stock.top.first?.isPurchase == true)
        #expect(stock.top.first?.isUsage == false)

        let legacy = try analytics(stock: #"""
        { "writeoffs": { "quantity": 2, "value": 800, "unitsWithoutCost": 0 },
          "usage": { "quantity": 0, "value": 0, "unitsWithoutCost": 0 }, "expenses": 800, "top": [],
          "onHand": { "units": 0, "value": 0, "unitsWithoutCost": 0, "byKind": [] } }
        """#)
        #expect(legacy.stock.purchases == AnalyticsStockPurchases())
        #expect(legacy.stock.writeoffs.value == 800)
    }

    @Test("A period with only a purchase is not empty")
    func purchaseOnlyPeriod() throws {
        let a = try analytics(stock: #"{ "purchases": { "count": 1, "value": 0 } }"#)
        #expect(!a.isEmpty)
    }

    // MARK: - Purchase form

    @Test("The amount is required, positive and within the server's limit")
    func validation() {
        var draft = ConsumablePurchaseDraft()
        #expect(draft.isBlank)
        #expect(!draft.canSubmit)
        #expect(draft.validationMessage == "Укажите, сколько заплатили")
        #expect(draft.body == nil)

        draft.amount = 0
        #expect(!draft.isBlank)
        #expect(draft.validationMessage == "Сумма должна быть больше нуля")

        draft.amount = ConsumablePurchaseDraft.maxAmount + 1
        #expect(!draft.canSubmit)

        draft.amount = ConsumablePurchaseDraft.maxAmount
        #expect(draft.canSubmit)
    }

    @Test("The body sends the amount, a trimmed note and the status after the purchase («Есть» by default)")
    func body() {
        var draft = ConsumablePurchaseDraft()
        draft.amount = 3500
        #expect(draft.body == PurchaseBody(amount: 3500, note: nil, presenceStatus: .ok))

        draft.note = "  Медтехника, 2 упаковки \n"
        draft.status = .low
        #expect(draft.body == PurchaseBody(amount: 3500, note: "Медтехника, 2 упаковки", presenceStatus: .low))
    }

    // MARK: - Texts

    @Test("A purchase row reads «Покупка · 3 500 ₽»; the list of all products starts its subtitle with it")
    func rowText() throws {
        let purchase = try Fixtures.decode(StockMovement.self, Self.purchaseJSON)
        let title = "Покупка · 3\(Self.nbsp)500\(Self.nbsp)₽"
        #expect(MovementText.title(purchase) == title)
        #expect(MovementText.subtitle(purchase, showsProduct: true).hasPrefix(title + " · "))
        #expect(MovementText.subtitle(purchase, showsProduct: true).hasSuffix(" · Анна"))
        #expect(!MovementText.subtitle(purchase, showsProduct: false).contains("Покупка"))

        let sale = try Fixtures.decode(StockMovement.self, Fixtures.stockMovement)
        #expect(MovementText.title(sale) == "Продажа")
    }

    @Test("Spent in 30 days counts purchases inside the window, only when the loaded history reaches that far")
    func spentRecently() {
        let now = Fixtures.referenceDate
        let recent = [
            movement(type: .purchase, amount: 3500, daysAgo: 2, now: now),
            movement(type: .purchase, amount: 1200, daysAgo: 20, now: now),
            movement(type: .adjustment, amount: nil, daysAgo: 25, now: now),
        ]
        let old = movement(type: .purchase, amount: 9000, daysAgo: 45, now: now)

        #expect(PurchaseSummary.spent(in: recent, isComplete: true, now: now) == 4700)
        #expect(PurchaseSummary.spent(in: recent, isComplete: false, now: now) == nil, "older purchases may not be loaded")
        #expect(PurchaseSummary.spent(in: recent + [old], isComplete: false, now: now) == 4700)
        #expect(PurchaseSummary.spent(in: [], isComplete: true, now: now) == 0)
        #expect(PurchaseSummary.spentText(4700) == "Потрачено за 30 дней: 4\(Self.nbsp)700\(Self.nbsp)₽")
    }

    @Test("Analytics top: a purchase counts purchases, not units; the export names the operation")
    func analyticsTexts() {
        let purchase = AnalyticsStockExpense(productId: 15, name: "Перчатки", kind: "consumable", type: "purchase", quantity: 3, value: 9000)
        let usage = AnalyticsStockExpense(productId: 3, name: "Иглы", kind: "consumable", type: "usage", quantity: 5, value: 50)
        let writeoff = AnalyticsStockExpense(productId: 1, name: "Лабрет", kind: "jewelry", type: "writeoff", quantity: 2, value: 800)
        #expect(ReportText.stockExpenseLine(purchase) == "Покупка · 3 раза")
        #expect(ReportText.stockExpenseLine(usage) == "Расход · 5\(Self.nbsp)шт.")
        #expect(ReportText.stockExpenseLine(writeoff) == "Списание · 2\(Self.nbsp)шт.")
        #expect(ReportText.stockExpenseTitle(purchase) == "Покупка")
        #expect(ReportText.stockExpenseTitle(usage) == "Расход на процедуры")
        #expect(ReportText.purchases(1) == "1 покупка")
        #expect(ReportText.purchases(3) == "3 покупки")
        #expect(ReportText.purchases(5) == "5 покупок")
    }

    @Test("The CSV export lists purchases next to write-offs and usage")
    func csv() throws {
        let a = try analytics(stock: #"""
        { "purchases": { "count": 2, "value": 7000 }, "expenses": 7000,
          "top": [ { "productId": 15, "name": "Перчатки", "kind": "consumable", "type": "purchase", "quantity": 2, "value": 7000 } ] }
        """#)
        let lines = AnalyticsCSV.make(a, period: "13 – 15 октября", previousPeriod: "10 – 12 октября").components(separatedBy: "\r\n")
        #expect(lines.contains("Покупки расходников;2;7000;"))
        #expect(lines.contains("Перчатки;Покупка;2;7000"))
        #expect(lines.contains("Итого;;7000;"))
    }
}
