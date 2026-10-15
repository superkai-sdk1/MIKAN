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

    func testOpeningTheSameAppointmentKeepsEditsAndTakesTheFreshCopy() {
        let cart = CartStore()
        cart.open(POSFixtures.appointment(status: .confirmed, price: 3_000, deposit: 1_000))
        cart.addCustomService(name: "Украшение", price: 1_500)
        cart.discount = 200
        cart.note = "Скидка постоянному клиенту"
        cart.selectPaymentMode(.split)
        cart.manualSplit = PaymentSplit(cash: 1_000, card: 2_300, transfer: 1_000)
        cart.completesAppointment = false

        let completed = POSFixtures.appointment(status: .completed, price: 3_000, deposit: 1_000)
        cart.open(completed)

        XCTAssertEqual(cart.appointment, completed)
        XCTAssertEqual(cart.lines.map(\.name), ["Хеликс", "Украшение"])
        XCTAssertEqual(cart.discount, 200)
        XCTAssertEqual(cart.note, "Скидка постоянному клиенту")
        XCTAssertEqual(cart.deposit, 1_000)
        XCTAssertEqual(cart.paymentMode, .split)
        XCTAssertEqual(cart.manualSplit, PaymentSplit(cash: 1_000, card: 2_300, transfer: 1_000))
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
