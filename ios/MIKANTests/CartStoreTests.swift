import XCTest
@testable import MIKAN

@MainActor
final class CartStoreTests: XCTestCase {
    /// Isolated UserDefaults domain per test, so the remembered payment method never leaks between tests.
    private lazy var suiteName: String = {
        let name = "CartStoreTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return name
    }()

    // MARK: Fixtures

    /// Carts of one test share the defaults domain (a «relaunch» sees what the previous cart stored).
    private func makeCart() throws -> CartStore {
        CartStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    private func appointment(
        price: Int,
        deposit: Int,
        status: AppointmentStatus = .confirmed,
        telegramLinked: Bool = true
    ) -> Appointment {
        Appointment(
            id: 4,
            client: ClientRef(id: 1, name: "Иван Петров", phone: nil, telegramLinked: telegramLinked),
            master: EmployeeRef(id: 2, name: "Анна", color: nil),
            service: ServiceRef(id: 3, name: "Прокол мочки", category: .piercing),
            title: nil, startsAt: Fixtures.referenceDate, endsAt: Fixtures.referenceDate.addingTimeInterval(1800),
            status: status, price: price, deposit: deposit, notes: nil, saleId: nil, completedAt: nil,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    private func product(price: Int, quantity: Int = 5) -> Product {
        Product(
            id: 1, kind: .jewelry, name: "Лабрет", sku: nil, category: nil, material: nil, size: nil,
            description: nil, price: price, cost: nil, quantity: quantity, minQuantity: 1, unit: "шт", photoUrl: nil,
            active: true, lowStock: false, createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    // MARK: Single method

    func testNewReceiptDefaultsToCardAndPaysTheWholeTotal() throws {
        let cart = try makeCart()
        cart.addCustomService(name: "Прокол", price: 4_500)

        XCTAssertEqual(cart.paymentMode, .single(.card))
        XCTAssertEqual(cart.amountDue, 4_500)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 4_500, transfer: 0))
        XCTAssertEqual(cart.remaining, 0)
        XCTAssertTrue(cart.canSubmit, "no typing needed")
        XCTAssertEqual(cart.makeSaleBody().payments, Payments(cash: 0, card: 4_500, transfer: 0))
    }

    func testSingleMethodWithDepositKeepsItInTransfer() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))

        XCTAssertEqual(cart.depositApplied, 2_000)
        XCTAssertEqual(cart.amountDue, 6_000)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 6_000, transfer: 2_000))
        XCTAssertTrue(cart.canSubmit)

        cart.selectPaymentMode(.single(.transfer))
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 0, transfer: 8_000), "transfer takes the whole total")
        XCTAssertEqual(cart.amountDue, 6_000, "the deposit is still not due again")

        cart.selectPaymentMode(.single(.cash))
        let body = cart.makeSaleBody()
        XCTAssertEqual(body.appointmentId, 4)
        XCTAssertEqual(body.clientId, 1)
        XCTAssertEqual(body.payments, Payments(cash: 6_000, card: 0, transfer: 2_000))
        let item = try XCTUnwrap(body.items.first)
        XCTAssertEqual(item.type, .service)
        XCTAssertEqual(item.serviceId, 3)
        XCTAssertEqual(item.name, "Прокол мочки")
        XCTAssertEqual(item.price, 8_000)
    }

    func testDiscountAndLineChangesRecomputeTheAmount() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))
        cart.add(product: product(price: 1_500))
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 7_500, transfer: 2_000))

        cart.discount = 1_500
        XCTAssertEqual(cart.total, 8_000)
        XCTAssertEqual(cart.amountDue, 6_000)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 6_000, transfer: 2_000))
        XCTAssertTrue(cart.canSubmit)

        cart.discount = 20_000
        XCTAssertFalse(cart.isDiscountValid)
        XCTAssertFalse(cart.canSubmit)
    }

    func testDepositCoveringTheTotalGoesEntirelyToTransfer() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 3_000, deposit: 3_000))
        XCTAssertEqual(cart.amountDue, 0)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 0, transfer: 3_000))
        XCTAssertTrue(cart.canSubmit)

        cart.discount = 1_000
        XCTAssertEqual(cart.depositApplied, 2_000, "never more than the total")
        XCTAssertEqual(cart.amountDue, 0)
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 0, transfer: 2_000))
        XCTAssertTrue(cart.canSubmit)
    }

    // MARK: Cash

    func testCashChangeAndShortAmountBlock() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 6_500, deposit: 2_000))
        cart.selectPaymentMode(.single(.cash))
        XCTAssertEqual(cart.amountDue, 4_500)
        XCTAssertNil(cart.cashChange)
        XCTAssertTrue(cart.canSubmit, "the received field is optional")

        cart.cashReceived = 5_000
        XCTAssertEqual(cart.cashChange, 500)
        XCTAssertTrue(cart.canSubmit)
        XCTAssertEqual(cart.makeSaleBody().payments, Payments(cash: 4_500, card: 0, transfer: 2_000), "change is never sent")

        cart.cashReceived = 4_000
        XCTAssertNil(cart.cashChange)
        XCTAssertFalse(cart.isCashReceivedEnough)
        XCTAssertFalse(cart.canSubmit, "received < due")

        cart.selectPaymentMode(.single(.card))
        XCTAssertTrue(cart.isCashReceivedEnough, "the received amount only matters in cash mode")
        XCTAssertNil(cart.cashChange)
        XCTAssertTrue(cart.canSubmit)
    }

    // MARK: Split

    func testSwitchingToSplitPrefillsTheCurrentAmounts() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))
        cart.selectPaymentMode(.single(.cash))

        cart.selectPaymentMode(.split)
        XCTAssertEqual(cart.paymentMode, .split)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 6_000, card: 0, transfer: 2_000))
        XCTAssertEqual(cart.split, cart.manualSplit)
        XCTAssertTrue(cart.canSubmit)

        cart.selectPaymentMode(.split)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 6_000, card: 0, transfer: 2_000), "re-selecting keeps typed amounts")

        cart.selectPaymentMode(.single(.card))
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 6_000, transfer: 2_000), "back to automatic amounts")
    }

    func testSplitSubmitsOnlyWhenBalanced() throws {
        let cart = try makeCart()
        cart.addCustomService(name: "Прокол", price: 5_000)
        cart.selectPaymentMode(.split)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 0, card: 5_000, transfer: 0))

        cart.manualSplit.card = 3_000
        XCTAssertEqual(cart.remaining, 2_000)
        XCTAssertFalse(cart.canSubmit)

        cart.fillRemaining(with: .cash)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 2_000, card: 3_000, transfer: 0))
        XCTAssertEqual(cart.remaining, 0)
        XCTAssertTrue(cart.canSubmit)
        XCTAssertEqual(cart.makeSaleBody().payments, Payments(cash: 2_000, card: 3_000, transfer: 0))

        cart.discount = 1_000
        XCTAssertEqual(cart.remaining, -1_000, "a manual split is not rebalanced automatically")
        XCTAssertFalse(cart.canSubmit)

        cart.fillRemaining(with: .card)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 2_000, card: 2_000, transfer: 0), "takes the overpayment back")
        XCTAssertTrue(cart.canSubmit)

        cart.manualSplit = PaymentSplit(cash: 500, card: 4_500, transfer: 0)
        cart.fillRemaining(with: .cash)
        XCTAssertEqual(cart.manualSplit.cash, 0, "never below zero")
    }

    func testDetachingTheAppointmentDropsTheDepositFromTheSplit() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000))
        cart.selectPaymentMode(.split)
        cart.detachAppointment()

        XCTAssertNil(cart.appointment)
        XCTAssertEqual(cart.deposit, 0)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 0, card: 6_000, transfer: 0))
        XCTAssertEqual(cart.remaining, 2_000)
        XCTAssertNil(cart.makeCompleteBody())
    }

    // MARK: Remembered method

    func testLastSingleMethodIsRememberedForNewReceipts() throws {
        let cart = try makeCart()
        cart.addCustomService(name: "Прокол", price: 2_500)
        cart.selectPaymentMode(.single(.cash))
        cart.recordCompletedSale()
        XCTAssertEqual(cart.salesCompleted, 1)

        cart.clear()
        XCTAssertEqual(cart.paymentMode, .single(.cash), "cleared cart starts with the last used method")
        XCTAssertEqual(try makeCart().paymentMode, .single(.cash), "survives relaunch")

        cart.addCustomService(name: "Прокол", price: 2_500)
        cart.selectPaymentMode(.split)
        cart.recordCompletedSale()
        cart.clear()
        XCTAssertEqual(cart.paymentMode, .single(.cash), "a split sale does not change the default")
        XCTAssertEqual(cart.manualSplit, PaymentSplit())
        XCTAssertNil(cart.cashReceived)
    }

    func testSelectingAMethodWithoutSellingDoesNotChangeTheDefault() throws {
        let cart = try makeCart()
        cart.selectPaymentMode(.single(.transfer))
        cart.clear()
        XCTAssertEqual(cart.paymentMode, .single(.card))
    }

    // MARK: Appointment completion

    func testOpenAppointmentIsCompletedWithAftercareForLinkedClient() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 0, status: .confirmed, telegramLinked: true))

        XCTAssertTrue(cart.hasPendingAppointment)
        XCTAssertTrue(cart.completesAppointment)
        XCTAssertTrue(cart.canSendAftercare)
        let body = try XCTUnwrap(cart.makeCompleteBody())
        XCTAssertTrue(body.sendAftercare)
        XCTAssertNil(body.aftercareTemplateId, "the server falls back to the service's template")
        XCTAssertEqual(body.consumables, [])

        cart.sendsAftercare = false
        XCTAssertEqual(cart.makeCompleteBody()?.sendAftercare, false)

        cart.completesAppointment = false
        XCTAssertNil(cart.makeCompleteBody(), "straight to the sale")
    }

    func testAftercareIsNeverRequestedWithoutTelegram() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 0, status: .scheduled, telegramLinked: false))

        XCTAssertFalse(cart.canSendAftercare)
        XCTAssertFalse(cart.sendsAftercare, "off by default")
        cart.sendsAftercare = true
        XCTAssertEqual(cart.makeCompleteBody()?.sendAftercare, false)
    }

    func testCompletedAppointmentSkipsCompletionAndKeepsTheSaleKey() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 2_000, status: .confirmed))
        let body = cart.makeSaleBody()
        let key = cart.saleIdempotencyKey(for: body)

        var completed = appointment(price: 8_000, deposit: 2_000, status: .completed)
        completed.completedAt = Fixtures.referenceDate
        cart.appointmentCompleted(completed)

        XCTAssertEqual(cart.appointment?.status, .completed)
        XCTAssertFalse(cart.hasPendingAppointment)
        XCTAssertNil(cart.makeCompleteBody(), "a retry after a failed sale sends only the sale")
        XCTAssertEqual(cart.saleIdempotencyKey(for: cart.makeSaleBody()), key, "the retried sale body is unchanged")
        XCTAssertEqual(cart.split, PaymentSplit(cash: 0, card: 6_000, transfer: 2_000))
    }

    func testAlreadyCompletedAppointmentHasNoCompletionStep() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 0, status: .completed))
        XCTAssertFalse(cart.hasPendingAppointment)
        XCTAssertNil(cart.makeCompleteBody())
        XCTAssertEqual(cart.makeSaleBody().appointmentId, 4)
    }

    func testCompletionResultOfAnotherAppointmentIsIgnored() throws {
        let cart = try makeCart()
        cart.prefill(from: appointment(price: 8_000, deposit: 0))
        let other = Appointment(
            id: 99, client: ClientRef(id: 5, name: "Мария", phone: nil, telegramLinked: false),
            master: EmployeeRef(id: 2, name: "Анна", color: nil), service: nil, title: "Консультация",
            startsAt: Fixtures.referenceDate, endsAt: Fixtures.referenceDate.addingTimeInterval(900),
            status: .completed, price: 0, deposit: 0, notes: nil, saleId: nil, completedAt: nil,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
        cart.appointmentCompleted(other)
        XCTAssertEqual(cart.appointmentId, 4)
        XCTAssertTrue(cart.hasPendingAppointment)
    }

    // MARK: Lines

    func testAddingProductsMergesLinesAndClearResetsEverything() throws {
        let cart = try makeCart()
        let labret = product(price: 1_500, quantity: 2)
        cart.add(product: labret)
        cart.add(product: labret)
        cart.addCustomService(name: "  Прокол  ", price: 2_000)

        XCTAssertEqual(cart.lines.count, 2)
        XCTAssertEqual(cart.quantity(ofProduct: 1), 2)
        XCTAssertEqual(cart.itemCount, 3)
        XCTAssertEqual(cart.subtotal, 5_000)

        let body = cart.makeSaleBody()
        XCTAssertEqual(body.items.first?.productId, 1)
        XCTAssertNil(body.items.first?.name, "product lines are identified by productId")
        XCTAssertEqual(body.items.last?.name, "Прокол")

        cart.cashReceived = 10_000
        cart.completesAppointment = false
        cart.clear()
        XCTAssertTrue(cart.isEmpty)
        XCTAssertEqual(cart.split, PaymentSplit())
        XCTAssertNil(cart.cashReceived)
        XCTAssertTrue(cart.completesAppointment)
    }
}
