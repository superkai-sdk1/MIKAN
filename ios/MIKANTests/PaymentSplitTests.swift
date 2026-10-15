import XCTest
@testable import MIKAN

final class PaymentSplitTests: XCTestCase {
    func testSumRemainingAndBalance() {
        let split = PaymentSplit(cash: 1_500, card: 2_000, transfer: 0)
        XCTAssertEqual(split.sum, 3_500)
        XCTAssertEqual(split.remaining(for: 4_000), 500)
        XCTAssertEqual(split.remaining(for: 3_000), -500, "negative remaining means overpaid")
        XCTAssertTrue(split.isBalanced(for: 3_500))
        XCTAssertFalse(split.isBalanced(for: 4_000))
        XCTAssertEqual(split.payments, Payments(cash: 1_500, card: 2_000, transfer: 0))
    }

    func testNegativeAmountsNeverBalance() {
        let split = PaymentSplit(cash: 4_000, card: -500, transfer: 0)
        XCTAssertEqual(split.sum, 3_500)
        XCTAssertTrue(split.hasNegative)
        XCTAssertFalse(split.isBalanced(for: 3_500))
    }

    func testSubscriptReadsAndWritesEachMethod() {
        var split = PaymentSplit()
        split[.cash] = 100
        split[.card] = 200
        split[.transfer] = 300
        split[.qr] = 400
        XCTAssertEqual(split, PaymentSplit(cash: 100, card: 200, transfer: 300, qr: 400))
        XCTAssertEqual(PaymentMethod.allCases.map { split[$0] }, [100, 200, 300, 400])
        XCTAssertEqual(split.sum, 1_000)
        XCTAssertEqual(split.payments, Payments(cash: 100, card: 200, transfer: 300, qr: 400))
        XCTAssertEqual(PaymentSplit(split.payments), split)
    }

    func testQrShareCountsTowardsTheTotal() {
        let split = PaymentSplit.oneTap(.qr, total: 8_000, deposit: 2_000)
        XCTAssertEqual(split, PaymentSplit(cash: 0, card: 0, transfer: 2_000, qr: 6_000))
        XCTAssertTrue(split.isBalanced(for: 8_000))
        XCTAssertTrue(PaymentSplit(cash: 0, card: 0, transfer: 0, qr: -1).hasNegative)
        XCTAssertEqual(PaymentMethod.qr.oneTapTitle, "По QR")
        XCTAssertEqual(PaymentMethod.cash.oneTapTitle, "Наличными")
    }

    func testAllInOneMethod() {
        XCTAssertEqual(PaymentSplit.all(.card, total: 3_500), PaymentSplit(cash: 0, card: 3_500, transfer: 0))
        XCTAssertEqual(PaymentSplit.all(.cash, total: -10), PaymentSplit(), "never negative")
        for method in PaymentMethod.allCases {
            XCTAssertTrue(PaymentSplit.all(method, total: 9_999).isBalanced(for: 9_999))
        }
    }

    func testOneTapKeepsDepositInTransfer() {
        let split = PaymentSplit.oneTap(.cash, total: 8_000, deposit: 2_000)
        XCTAssertEqual(split, PaymentSplit(cash: 6_000, card: 0, transfer: 2_000))
        XCTAssertTrue(split.isBalanced(for: 8_000))

        let byTransfer = PaymentSplit.oneTap(.transfer, total: 8_000, deposit: 2_000)
        XCTAssertEqual(byTransfer, PaymentSplit(cash: 0, card: 0, transfer: 8_000))
    }

    func testOneTapClampsDepositToTotal() {
        let split = PaymentSplit.oneTap(.card, total: 1_000, deposit: 5_000)
        XCTAssertEqual(split, PaymentSplit(cash: 0, card: 0, transfer: 1_000))
        XCTAssertTrue(split.isBalanced(for: 1_000))
        XCTAssertEqual(PaymentSplit.oneTap(.card, total: 1_000, deposit: 0), PaymentSplit.all(.card, total: 1_000))
    }

    func testCheckoutRules() {
        let balanced = PaymentSplit(cash: 3_500, card: 0, transfer: 0)
        XCTAssertTrue(CheckoutRules.canSubmit(lineCount: 2, linesValid: true, subtotal: 4_000, discount: 500, split: balanced))
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 0, linesValid: true, subtotal: 0, discount: 0, split: PaymentSplit()), "empty cart")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 2, linesValid: false, subtotal: 4_000, discount: 500, split: balanced), "invalid line")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 4_000, discount: 0, split: balanced), "split ≠ total")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 400, discount: 500, split: PaymentSplit()), "discount > subtotal")
        XCTAssertTrue(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 500, discount: 500, split: PaymentSplit()), "free sale with full discount")
        XCTAssertEqual(CheckoutRules.total(subtotal: 4_000, discount: 500), 3_500)
        XCTAssertEqual(CheckoutRules.total(subtotal: 400, discount: 500), 0)
    }
}

@MainActor
final class CartStoreTests: XCTestCase {
    private func appointment(price: Int, deposit: Int) -> Appointment {
        Appointment(
            id: 4,
            client: ClientRef(id: 1, name: "Иван Петров", phone: nil, telegramLinked: true),
            master: EmployeeRef(id: 2, name: "Анна", color: nil),
            service: ServiceRef(id: 3, name: "Прокол мочки", category: .piercing),
            title: nil, startsAt: Fixtures.referenceDate, endsAt: Fixtures.referenceDate.addingTimeInterval(1800),
            status: .completed, price: price, deposit: deposit, notes: nil, saleId: nil, completedAt: nil,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    func testPrefillFromAppointmentPutsDepositIntoTransfer() throws {
        let cart = CartStore()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))

        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.total, 8_000)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 0, transfer: 2_000))
        XCTAssertEqual(cart.remaining, 6_000)
        XCTAssertFalse(cart.canSubmit, "cannot submit until the split equals the total")

        cart.applyOneTap(.card)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 6_000, transfer: 2_000))
        XCTAssertTrue(cart.canSubmit)

        let body = cart.makeSaleBody()
        XCTAssertEqual(body.appointmentId, 4)
        XCTAssertEqual(body.clientId, 1)
        let item = try XCTUnwrap(body.items.first)
        XCTAssertEqual(item.type, .service)
        XCTAssertEqual(item.serviceId, 3)
        XCTAssertEqual(item.name, "Прокол мочки")
        XCTAssertEqual(item.price, 8_000)
        XCTAssertEqual(body.payments, Payments(cash: 0, card: 6_000, transfer: 2_000))
    }

    func testQrOneTapSendsTheRestAsQrShare() {
        let cart = CartStore()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))

        cart.applyOneTap(.qr)

        XCTAssertTrue(cart.canSubmit)
        XCTAssertEqual(cart.makeSaleBody().payments, Payments(cash: 0, card: 0, transfer: 2_000, qr: 6_000))

        cart.moveQrShareToTransfer()
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 0, transfer: 8_000, qr: 0), "paid by QR but not sold: finish as a transfer")
        XCTAssertTrue(cart.canSubmit)
    }

    func testAddingProductsMergesLinesAndDiscountChangesTotal() {
        let cart = CartStore()
        let product = Product(
            id: 1, kind: .jewelry, name: "Лабрет", sku: nil, category: nil, material: nil, size: nil,
            description: nil, price: 1_500, cost: nil, quantity: 2, minQuantity: 1, unit: "шт", photoUrl: nil,
            active: true, lowStock: false, createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
        cart.add(product: product)
        cart.add(product: product)
        cart.addCustomService(name: "  Прокол  ", price: 2_000)

        XCTAssertEqual(cart.lines.count, 2)
        XCTAssertEqual(cart.quantity(ofProduct: 1), 2)
        XCTAssertEqual(cart.itemCount, 3)
        XCTAssertEqual(cart.subtotal, 5_000)

        cart.discount = 1_000
        XCTAssertEqual(cart.total, 4_000)
        cart.applyOneTap(.cash)
        XCTAssertEqual(cart.split, PaymentSplit.all(.cash, total: 4_000))
        XCTAssertTrue(cart.canSubmit)

        cart.discount = 6_000
        XCTAssertFalse(cart.isDiscountValid)
        XCTAssertFalse(cart.canSubmit)

        let body = cart.makeSaleBody()
        XCTAssertEqual(body.items.first?.productId, 1)
        XCTAssertNil(body.items.first?.name, "product lines are identified by productId")
        XCTAssertEqual(body.items.last?.name, "Прокол")

        cart.clear()
        XCTAssertTrue(cart.isEmpty)
        XCTAssertEqual(cart.split, PaymentSplit())
    }
}
