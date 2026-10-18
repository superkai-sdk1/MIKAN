import XCTest
@testable import MIKAN

private enum POSFixtures {
    static let ivan = ClientRef(id: 1, name: "Иван Петров", phone: nil, telegramLinked: true)
    static let maria = ClientRef(id: 2, name: "Мария Ким", phone: nil, telegramLinked: false)

    static func appointment(
        id: Int = 4,
        client: ClientRef = ivan,
        startsAt: Date = Fixtures.referenceDate,
        status: AppointmentStatus = .completed,
        price: Int = 3_000,
        deposit: Int = 0,
        saleId: Int? = nil
    ) -> Appointment {
        Appointment(
            id: id, client: client,
            master: EmployeeRef(id: 2, name: "Анна", color: "#FF7A1A"),
            service: ServiceRef(id: 3, name: "Хеликс", category: .piercing),
            title: nil, startsAt: startsAt, endsAt: startsAt.addingTimeInterval(3_600),
            status: status, price: price, deposit: deposit, notes: nil, saleId: saleId, completedAt: nil,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    static func receive(id: Int, amount: Int, method: PaymentMethod?, at date: Date) -> DepositOperation {
        operation(id: id, type: .receive, amount: amount, method: method, at: date)
    }

    static func operation(id: Int, type: DepositOperationType, amount: Int, method: PaymentMethod?, at date: Date) -> DepositOperation {
        DepositOperation(
            id: id, appointmentId: 4, type: type, amount: amount, method: method, saleId: nil, shiftId: nil,
            qrPaymentId: nil, note: nil, employee: nil, createdAt: date
        )
    }

    static func product(id: Int, name: String, category: String?, sku: String? = nil, quantity: Int = 5) -> Product {
        Product(
            id: id, kind: .jewelry, name: name, sku: sku, category: category, material: "Титан G23", size: nil,
            description: nil, price: 1_500, cost: nil, quantity: quantity, minQuantity: 1, unit: "шт", photoUrl: nil,
            active: true, lowStock: false, createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }
}

final class PaymentQueueTests: XCTestCase {
    func testStatusQueryListsPayableStatuses() {
        XCTAssertEqual(PaymentQueue.statusQuery, "scheduled,confirmed,completed")
    }

    func testDayIsLocalMidnightToNextMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tomsk"))
        // 2026-10-15 11:00 UTC = 18:00 in Tomsk (UTC+7)
        let day = PaymentQueue.day(containing: Fixtures.referenceDate, calendar: calendar)
        XCTAssertEqual(day.start, Date(timeIntervalSince1970: 1_791_997_200), "2026-10-15 00:00 in Tomsk")
        XCTAssertEqual(day.duration, 24 * 60 * 60)
        XCTAssertTrue(day.contains(Fixtures.referenceDate))
    }

    func testUnpaidDropsPaidAndClosedAppointmentsAndSortsByStart() {
        let early = Fixtures.referenceDate
        let late = early.addingTimeInterval(7_200)
        let appointments = [
            POSFixtures.appointment(id: 1, startsAt: late, status: .scheduled),
            POSFixtures.appointment(id: 2, startsAt: early, status: .completed, saleId: 9),
            POSFixtures.appointment(id: 3, startsAt: early, status: .cancelled),
            POSFixtures.appointment(id: 4, startsAt: early, status: .noShow),
            POSFixtures.appointment(id: 5, startsAt: early, status: .confirmed),
            POSFixtures.appointment(id: 6, startsAt: late, status: .completed),
        ]
        XCTAssertEqual(PaymentQueue.unpaid(appointments).map(\.id), [5, 1, 6])
    }

    func testAVisitWithASaleIsPaid() {
        XCTAssertTrue(POSFixtures.appointment(id: 7, status: .completed, saleId: 3).isPaid)
        XCTAssertFalse(POSFixtures.appointment(id: 8).isPaid)
    }

    func testDepositBadgeShowsAHeldOrAWaitedPrepayment() {
        var appointment = POSFixtures.appointment(status: .confirmed, deposit: 0)
        XCTAssertNil(PaymentQueue.depositBadge(for: appointment), "nothing required")

        appointment.depositRequired = 2_000
        appointment.depositStatus = .waiting
        XCTAssertEqual(PaymentQueue.depositBadge(for: appointment), .waiting(2_000))
        XCTAssertEqual(QueueDepositBadge.waiting(2_000).text, "Ждём предоплату \(Money.format(2_000))")

        appointment.deposit = 1_500
        appointment.depositStatus = .paid
        XCTAssertEqual(PaymentQueue.depositBadge(for: appointment), .held(1_500), "a partial prepayment is still held")
        XCTAssertEqual(QueueDepositBadge.held(1_500).text, "Предоплата \(Money.format(1_500))")

        appointment.deposit = 0
        appointment.depositStatus = .applied
        XCTAssertNil(PaymentQueue.depositBadge(for: appointment), "already counted in a sale")
    }
}

final class ProductCatalogFilterTests: XCTestCase {
    private let products = [
        POSFixtures.product(id: 1, name: "Лабрет", category: "Лабрет", sku: "LB-12"),
        POSFixtures.product(id: 2, name: "Кольцо-кликер", category: "Кольцо"),
        POSFixtures.product(id: 3, name: "Микробанан", category: " "),
        POSFixtures.product(id: 4, name: "Кольцо сегментное", category: "Кольцо"),
        POSFixtures.product(id: 5, name: "Штанга", category: nil),
    ]

    func testCategoriesAreUniqueSortedAndSkipBlank() {
        XCTAssertEqual(ProductCatalogFilter.categories(of: products), ["Кольцо", "Лабрет"])
    }

    func testFilterByCategoryAndQuery() {
        XCTAssertEqual(ProductCatalogFilter.apply(products, query: "", category: nil).count, 5)
        XCTAssertEqual(ProductCatalogFilter.apply(products, query: "", category: "Кольцо").map(\.id), [2, 4])
        XCTAssertEqual(ProductCatalogFilter.apply(products, query: "  кликер ", category: nil).map(\.id), [2])
        XCTAssertEqual(ProductCatalogFilter.apply(products, query: "lb-12", category: nil).map(\.id), [1], "matches SKU")
        XCTAssertEqual(ProductCatalogFilter.apply(products, query: "титан", category: "Кольцо").map(\.id), [2, 4], "matches material")
        XCTAssertTrue(ProductCatalogFilter.apply(products, query: "лабрет", category: "Кольцо").isEmpty)
    }

    func testRowsSplitTilesIntoFixedColumns() {
        XCTAssertEqual(ProductCatalogFilter.rows(products, columns: 2).map { $0.map(\.id) }, [[1, 2], [3, 4], [5]])
        XCTAssertEqual(ProductCatalogFilter.rows(Array(products.prefix(4)), columns: 2).count, 2)
        XCTAssertTrue(ProductCatalogFilter.rows([], columns: 2).isEmpty)
        XCTAssertTrue(ProductCatalogFilter.rows(products, columns: 0).isEmpty)
    }
}

@MainActor
final class ReceiptDraftTests: XCTestCase {
    func testUntouchedAppointmentPrefillIsNotUnsavedWork() {
        let appointment = POSFixtures.appointment(price: 3_000)
        let cart = CartStore()
        XCTAssertFalse(ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment), "empty cart")

        cart.prefill(from: appointment)
        XCTAssertFalse(ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment))

        cart.lines[0].unitPrice = 3_500
        XCTAssertTrue(ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment), "edited price")

        cart.prefill(from: appointment)
        cart.addCustomService(name: "Замена украшения", price: 500)
        XCTAssertTrue(ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment), "added line")

        cart.prefill(from: appointment)
        cart.detachAppointment()
        XCTAssertTrue(ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment), "lines without appointment")
    }

    func testIsOpenWithLinesClientOrAppointment() {
        XCTAssertFalse(ReceiptDraft.isOpen(lines: [], client: nil, appointment: nil))
        XCTAssertTrue(ReceiptDraft.isOpen(lines: [], client: POSFixtures.ivan, appointment: nil))
        XCTAssertTrue(ReceiptDraft.isOpen(lines: [], client: nil, appointment: POSFixtures.appointment()))
        let line = CartLine(kind: .service(id: nil), name: "Прокол", unitPrice: 2_000)
        XCTAssertTrue(ReceiptDraft.isOpen(lines: [line], client: nil, appointment: nil))
    }

    func testTexts() {
        XCTAssertEqual(ReceiptDraft.continueTitle(lineCount: 0, total: 0), "Продолжить чек")
        XCTAssertEqual(ReceiptDraft.continueTitle(lineCount: 2, total: 3_500), "Продолжить чек · 3\u{00A0}500\u{00A0}₽")

        let appointment = POSFixtures.appointment()
        XCTAssertEqual(ReceiptDraft.summary(itemCount: 1, client: POSFixtures.ivan, appointment: appointment), "По записи · Иван Петров · 1 позиция")
        XCTAssertEqual(ReceiptDraft.summary(itemCount: 3, client: POSFixtures.maria, appointment: nil), "Мария Ким · 3 позиции")
        XCTAssertEqual(ReceiptDraft.summary(itemCount: 0, client: nil, appointment: nil), "Без клиента · пусто")

        let time = DateText.timeRange(appointment.startsAt, appointment.endsAt)
        XCTAssertEqual(ReceiptDraft.appointmentBanner(appointment), "По записи · \(time) · Иван Петров · Хеликс")
    }

    func testAppointmentDetailsSayHowMuchOfThePrepaymentIsApplied() {
        XCTAssertEqual(ReceiptDraft.appointmentDetails(master: "Анна", deposit: 0, applied: 0), "Мастер Анна")
        XCTAssertEqual(
            ReceiptDraft.appointmentDetails(master: "Анна", deposit: 2_000, applied: 2_000),
            "Мастер Анна · предоплата \(Money.format(2_000)) зачтётся"
        )
        XCTAssertEqual(
            ReceiptDraft.appointmentDetails(master: "Анна", deposit: 5_000, applied: 3_000),
            "Мастер Анна · из предоплаты \(Money.format(5_000)) зачтётся \(Money.format(3_000))"
        )
        XCTAssertEqual(
            ReceiptDraft.appointmentDetails(master: "Анна", deposit: 2_000, applied: 0),
            "Мастер Анна · предоплата \(Money.format(2_000)) зачтётся",
            "an empty receipt still shows the whole prepayment"
        )
    }

    func testDepositReceivedNoteUsesTheLatestReceive() {
        let first = Fixtures.referenceDate.addingTimeInterval(-3 * 86_400)
        let operations = [
            POSFixtures.receive(id: 1, amount: 1_000, method: .cash, at: first),
            POSFixtures.receive(id: 2, amount: 1_000, method: .transfer, at: Fixtures.referenceDate),
            POSFixtures.operation(id: 3, type: .apply, amount: 500, method: nil, at: Fixtures.referenceDate.addingTimeInterval(60)),
        ]
        XCTAssertEqual(
            ReceiptDraft.depositReceivedNote(operations),
            "внесена переводом \(DateText.dayMonth(Fixtures.referenceDate))"
        )
        XCTAssertEqual(
            ReceiptDraft.depositReceivedNote([POSFixtures.receive(id: 4, amount: 2_000, method: .qr, at: first)]),
            "внесена по QR СБП \(DateText.dayMonth(first))"
        )
        XCTAssertEqual(
            ReceiptDraft.depositReceivedNote([POSFixtures.receive(id: 5, amount: 2_000, method: nil, at: first)]),
            "внесена \(DateText.dayMonth(first))"
        )
        XCTAssertNil(ReceiptDraft.depositReceivedNote([]), "migrated prepayments have no ledger")
        XCTAssertNil(ReceiptDraft.depositReceivedNote([POSFixtures.operation(id: 6, type: .unapply, amount: 500, method: nil, at: first)]))
    }

    func testOpeningTheSameAppointmentKeepsEditsAndTakesTheFreshCopy() {
        let cart = CartStore()
        cart.open(POSFixtures.appointment(status: .confirmed, price: 3_000, deposit: 1_000))
        cart.addCustomService(name: "Украшение", price: 1_500)
        cart.discount = 200
        cart.note = "Скидка постоянному клиенту"
        cart.selectPaymentMode(.split)
        cart.manualSplit = PaymentSplit(cash: 1_000, qr: 2_300)
        cart.completesAppointment = false

        let completed = POSFixtures.appointment(status: .completed, price: 3_000, deposit: 1_000)
        cart.open(completed)

        XCTAssertEqual(cart.appointment, completed)
        XCTAssertEqual(cart.lines.map(\.name), ["Хеликс", "Украшение"])
        XCTAssertEqual(cart.discount, 200)
        XCTAssertEqual(cart.note, "Скидка постоянному клиенту")
        XCTAssertEqual(cart.deposit, 1_000)
        XCTAssertEqual(cart.amountDue, 3_300)
        XCTAssertEqual(cart.paymentMode, .split)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 1_000, qr: 2_300))
        XCTAssertTrue(cart.canSubmit, "the typed split still covers the amount due")
        XCTAssertFalse(cart.completesAppointment)
    }

    func testOpeningAnotherAppointmentReplacesTheReceipt() {
        let cart = CartStore()
        cart.open(POSFixtures.appointment(id: 4))
        cart.addCustomService(name: "Украшение", price: 1_500)
        cart.discount = 200

        cart.open(POSFixtures.appointment(id: 5, client: POSFixtures.maria, price: 2_000))

        XCTAssertEqual(cart.appointmentId, 5)
        XCTAssertEqual(cart.client, POSFixtures.maria)
        XCTAssertEqual(cart.lines.map(\.unitPrice), [2_000])
        XCTAssertEqual(cart.discount, 0)
    }
}

@MainActor
final class POSRoutingTests: XCTestCase {
    private func makeState() throws -> AppState {
        let api = APIClient(serverURL: try XCTUnwrap(URL(string: "http://localhost:3000")))
        return AppState(api: api, employee: nil, phase: .signedIn)
    }

    func testStartCheckoutLandsOnPrefilledReceiptNotInCheckout() throws {
        let state = try makeState()
        state.posPath = [.salesHistory]
        let appointment = POSFixtures.appointment(deposit: 500)

        state.startCheckout(for: appointment)

        XCTAssertEqual(state.selectedTab, .pos)
        XCTAssertEqual(state.posPath, [.receipt])
        XCTAssertFalse(state.cart.isCheckoutPresented)
        XCTAssertEqual(state.cart.appointmentId, appointment.id)
        XCTAssertEqual(state.cart.client, POSFixtures.ivan)
        XCTAssertEqual(state.cart.lines.count, 1)
    }

    func testStartSaleKeepsLinesAndAttachesTheClient() throws {
        let state = try makeState()
        state.cart.addCustomService(name: "Прокол", price: 2_000)

        state.startSale(for: POSFixtures.maria)

        XCTAssertEqual(state.selectedTab, .pos)
        XCTAssertEqual(state.posPath, [.receipt])
        XCTAssertEqual(state.cart.client, POSFixtures.maria)
        XCTAssertEqual(state.cart.lines.count, 1)
    }

    func testStartSaleReplacesAnotherClientsAppointmentReceipt() throws {
        let state = try makeState()
        state.cart.open(POSFixtures.appointment(client: POSFixtures.ivan))

        state.startSale(for: POSFixtures.maria)

        XCTAssertNil(state.cart.appointment)
        XCTAssertTrue(state.cart.isEmpty)
        XCTAssertEqual(state.cart.client, POSFixtures.maria)
    }

    func testStartSaleKeepsTheSameClientsAppointmentReceipt() throws {
        let state = try makeState()
        let appointment = POSFixtures.appointment(client: POSFixtures.ivan)
        state.cart.open(appointment)

        state.startSale(for: POSFixtures.ivan)

        XCTAssertEqual(state.cart.appointment, appointment)
        XCTAssertEqual(state.cart.lines.count, 1)
    }

    func testCloseReceiptReturnsToTheHub() throws {
        let state = try makeState()
        state.startSale(for: POSFixtures.ivan)
        state.posPath.append(.clientPicker)

        state.closeReceipt()

        XCTAssertTrue(state.posPath.isEmpty)
        XCTAssertEqual(state.cart.client, POSFixtures.ivan, "closing the screen keeps the receipt")
    }
}

final class ShiftBreakdownTests: XCTestCase {
    private func shift(summary: ShiftSummary, openingCash: Int = 5_000, expectedCash: Int) -> CashShift {
        CashShift(
            id: 3, openedAt: Fixtures.referenceDate, openedBy: EmployeeRef(id: 2, name: "Анна", color: nil),
            openingCash: openingCash, closedAt: nil, closedBy: nil, closingCash: nil, note: nil,
            expectedCash: expectedCash, difference: nil, summary: summary, operations: []
        )
    }

    private let busy = ShiftSummary(
        salesCount: 3, revenue: 10_000, cash: 2_500, card: 0, transfer: 5_000, deposit: 2_500,
        refunds: 1_000, cashRefunds: 500, cashIn: 300, cashOut: 1_000,
        deposits: ShiftDepositSummary(received: 3_000, cash: 1_000, transfer: 2_000, refunded: 700, cashRefunded: 200, retained: 400)
    )

    private let quiet = ShiftSummary(
        salesCount: 0, revenue: 0, cash: 0, card: 0, transfer: 0, refunds: 0, cashRefunds: 0, cashIn: 0, cashOut: 0
    )

    func testDrawerRowsAddUpToTheServersExpectedCash() {
        // expectedCash = opening + cash − cashRefunds + deposits.cash − deposits.cashRefunded + cashIn − cashOut
        let current = shift(summary: busy, expectedCash: 5_000 + 2_500 - 500 + 1_000 - 200 + 300 - 1_000)
        let rows = ShiftBreakdown.drawer(current.summary)

        XCTAssertEqual(rows.map(\.title), [
            "Продажи наличными", "Возвраты наличными", "Предоплаты наличными", "Возвраты предоплат наличными",
            "Внесения", "Изъятия",
        ])
        XCTAssertEqual(rows.map(\.amount), [2_500, -500, 1_000, -200, 300, -1_000])
        XCTAssertEqual(current.openingCash + rows.reduce(0) { $0 + $1.amount }, current.expectedCash)
    }

    func testQuietShiftShowsOnlyCashSales() {
        XCTAssertEqual(ShiftBreakdown.drawer(quiet).map(\.title), ["Продажи наличными"])
        XCTAssertTrue(ShiftBreakdown.deposits(quiet).isEmpty)
        XCTAssertNil(ShiftBreakdown.cardLine(quiet))
    }

    func testDepositRowsListReceivedByMethodAppliedRefundedAndRetained() {
        let rows = ShiftBreakdown.deposits(busy)

        XCTAssertEqual(rows.map(\.title), ["Получено", "Зачтено в чеках", "Возвращено клиентам", "Удержано (неявки и отмены)"])
        XCTAssertEqual(rows.map(\.amount), [3_000, 2_500, 700, 400])
        XCTAssertEqual(rows[0].detail, "наличными \(Money.format(1_000)) · переводом \(Money.format(2_000))")
        XCTAssertNil(rows[1].detail)
        XCTAssertEqual(rows[2].detail, "из них наличными \(Money.format(200))")

        var appliedOnly = quiet
        appliedOnly.deposit = 2_000
        XCTAssertEqual(ShiftBreakdown.deposits(appliedOnly).map(\.title), ["Зачтено в чеках"])
    }

    func testCardLineSummarisesThePrepayments() {
        XCTAssertEqual(
            ShiftBreakdown.cardLine(busy),
            "Предоплаты: получено \(Money.format(3_000)) · зачтено \(Money.format(2_500)) · "
                + "возвращено \(Money.format(700)) · удержано \(Money.format(400))"
        )
    }
}
