import Foundation
import Testing
@testable import MIKAN

/// Open receipts shared by the devices: decoding, the cart round trip, the sale link, the hub list and its texts.
@MainActor
struct OpenReceiptTests {
    private static let anna = EmployeeRef(id: 2, name: "Анна", color: "#FF7A1A")
    private static let ivan = ClientRef(id: 1, name: "Иван", lastName: "Петров", phone: nil, telegramLinked: true)

    private static func appointment(
        id: Int = 4,
        startsAt: Date = Fixtures.referenceDate,
        status: AppointmentStatus = .confirmed,
        deposit: Int = 0,
        saleId: Int? = nil,
        receiptId: Int? = nil
    ) -> Appointment {
        Appointment(
            id: id, client: ivan, master: anna, service: ServiceRef(id: 3, name: "Хеликс", category: .piercing),
            title: nil, startsAt: startsAt, endsAt: startsAt.addingTimeInterval(3_600), status: status, price: 3_000,
            deposit: deposit, notes: nil, saleId: saleId, receiptId: receiptId, completedAt: nil,
            createdAt: Fixtures.referenceDate, updatedAt: Fixtures.referenceDate
        )
    }

    private static func receipt(
        id: Int = 7,
        appointment: Appointment? = nil,
        client: ClientRef? = nil,
        items: [OpenReceiptItem] = [],
        discount: Int = 0,
        note: String? = nil,
        openedBy: EmployeeRef? = anna,
        createdAt: Date = Fixtures.referenceDate,
        updatedAt: Date = Fixtures.referenceDate
    ) -> OpenReceipt {
        let subtotal = items.reduce(0) { $0 + $1.total }
        return OpenReceipt(
            id: id, appointment: appointment, client: client, items: items, subtotal: subtotal, discount: discount,
            total: subtotal - discount, itemCount: items.reduce(0) { $0 + $1.quantity }, note: note, openedBy: openedBy,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private static let helix = OpenReceiptItem(type: .service, serviceId: 3, name: "Хеликс", quantity: 1, price: 3_000, total: 3_000)
    private static let spray = OpenReceiptItem(
        type: .product, productId: 21, variantId: 32, variantName: "100 мл", productKind: .goods,
        name: "Спрей для ухода — 100 мл", quantity: 2, price: 700, total: 1_400, stock: 5
    )

    private func makeCart() throws -> CartStore {
        CartStore(defaults: try #require(UserDefaults(suiteName: "OpenReceiptTests")))
    }

    // MARK: Decoding

    @Test("OpenReceipt decodes as documented, with the started appointment", arguments: [true, false])
    func decoding(fractional: Bool) throws {
        let receipt = try Fixtures.decode(OpenReceipt.self, Fixtures.openReceipt, fractional: fractional)

        #expect(receipt.id == 7)
        #expect(receipt.appointment?.id == 4)
        #expect(receipt.appointment?.receiptId == 7)
        #expect(receipt.appointment?.deposit == 2_000)
        #expect(receipt.client?.fullName == "Иван Петров")
        #expect(receipt.items.map(\.name) == ["Лабрет — 8 мм", "Прокол мочки"])
        #expect(receipt.items[0].productKind == .jewelry)
        #expect(receipt.items[0].variantId == 5)
        #expect(receipt.items[0].stock == 3)
        #expect(receipt.items[1].type == .service)
        #expect(receipt.items[1].stock == nil)
        let totals: [Int] = [receipt.subtotal, receipt.discount, receipt.total, receipt.itemCount]
        #expect(totals == [4_000, 0, 4_000, 2])
        #expect(receipt.openedBy?.name == "Анна")
        #expect(receipt.createdAt == Fixtures.referenceDate)
    }

    @Test("Missing totals are derived from the lines; an unknown product kind is tolerated")
    func tolerantDecoding() throws {
        let json = #"""
        { "id": 9, "appointment": null, "client": null, "note": null, "createdAt": "<T>",
          "items": [ { "type": "product", "productId": 1, "variantId": 5, "productKind": "sticker",
                       "name": "Лабрет", "quantity": 2, "price": 1500 } ] }
        """#
        let receipt = try Fixtures.decode(OpenReceipt.self, json)

        #expect(receipt.items[0].productKind == nil)
        #expect(receipt.items[0].total == 3_000)
        let totals: [Int] = [receipt.subtotal, receipt.discount, receipt.total, receipt.itemCount]
        #expect(totals == [3_000, 0, 3_000, 2])
        #expect(receipt.openedBy == nil)
        #expect(receipt.updatedAt == receipt.createdAt)
    }

    @Test("Appointment.receiptId: set while the visit is in the POS, nil from older servers")
    func appointmentReceiptId() throws {
        let older = try Fixtures.decode(Appointment.self, Fixtures.appointment)
        #expect(older.receiptId == nil)
        #expect(!older.isInPOS)

        let started = try Fixtures.decode(Appointment.self, Fixtures.appointmentInPOS)
        #expect(started.receiptId == 7)
        #expect(started.isInPOS)

        var paid = started
        paid.saleId = 3
        #expect(!paid.isInPOS, "a paid visit is no longer in the POS")
    }

    // MARK: Cart

    @Test("A loaded receipt fills the cart and saves back the same receipt")
    func loadRoundTrip() throws {
        let cart = try makeCart()
        let receipt = try Fixtures.decode(OpenReceipt.self, Fixtures.openReceipt)

        cart.load(receipt)

        #expect(cart.receiptId == 7)
        #expect(cart.lines.map(\.kind) == [.product(id: 1, variantId: 5, stock: 3), .service(id: 3)])
        #expect(cart.lines.map(\.sizeName) == ["8 мм", nil])
        #expect(cart.lines.map(\.productKind) == [.jewelry, nil])
        #expect(cart.client?.id == 1)
        #expect(cart.appointmentId == 4)
        #expect(cart.deposit == 2_000)
        #expect(cart.depositApplied == 2_000)
        #expect(cart.sendsAftercare, "the client has the bot")
        #expect(cart.makeReceiptBody() == ReceiptBody(
            appointmentId: 4, clientId: 1,
            items: [
                SaleItemBody(type: .product, productId: 1, serviceId: nil, name: nil, quantity: 1, price: 1_500, variantId: 5),
                SaleItemBody(type: .service, productId: nil, serviceId: 3, name: "Прокол мочки", quantity: 1, price: 2_500),
            ],
            discount: 0, note: nil
        ))
    }

    @Test("Discount, note and a client without an appointment survive the round trip")
    func loadRoundTripWithoutAppointment() throws {
        let cart = try makeCart()
        cart.load(Self.receipt(client: Self.ivan, items: [Self.helix, Self.spray], discount: 400, note: "Постоянный клиент"))

        #expect(cart.appointment == nil)
        #expect(cart.deposit == 0)
        #expect(cart.total == 4_000)
        #expect(cart.lines[1].symbol == "bag")
        #expect(cart.makeReceiptBody() == ReceiptBody(
            appointmentId: nil, clientId: 1,
            items: [
                SaleItemBody(type: .service, productId: nil, serviceId: 3, name: "Хеликс", quantity: 1, price: 3_000),
                SaleItemBody(type: .product, productId: 21, serviceId: nil, name: nil, quantity: 2, price: 700, variantId: 32),
            ],
            discount: 400, note: "Постоянный клиент"
        ))
    }

    @Test("A product line without its product or size is not loaded; a size that is gone has no stock")
    func productLinesNeedTheirIds() {
        #expect(CartLine(item: OpenReceiptItem(type: .product, variantId: 5, name: "Лабрет", quantity: 1, price: 1_500, total: 1_500)) == nil)
        let gone = OpenReceiptItem(type: .product, productId: 1, variantId: 5, name: "Лабрет — 8 мм", quantity: 1, price: 1_500, total: 1_500)
        #expect(CartLine(item: gone)?.stock == 0)
    }

    @Test("Reloading the same receipt keeps the checkout choices; another receipt starts afresh")
    func reloading() throws {
        let cart = try makeCart()
        cart.load(Self.receipt(appointment: Self.appointment(deposit: 1_000), items: [Self.helix]))
        cart.selectPaymentMode(.split)
        cart.manualSplit = PaymentSplit(cash: 1_000, transfer: 1_000)
        cart.completesAppointment = false

        cart.load(Self.receipt(appointment: Self.appointment(status: .completed, deposit: 1_000), items: [Self.helix, Self.spray]))
        #expect(cart.paymentMode == .split)
        #expect(cart.manualSplit == PaymentSplit(cash: 1_000, transfer: 1_000))
        #expect(!cart.completesAppointment)
        #expect(cart.appointment?.status == .completed, "the fresh copy")
        #expect(cart.lines.count == 2)

        cart.load(Self.receipt(id: 8, client: Self.ivan))
        #expect(cart.receiptId == 8)
        #expect(cart.paymentMode != .split)
        #expect(cart.completesAppointment)
        #expect(cart.isEmpty)
    }

    @Test("The sale names the receipt; a completed sale or clearing lets it go")
    func saleLink() throws {
        let cart = try makeCart()
        cart.load(Self.receipt(items: [Self.helix]))
        #expect(cart.makeSaleBody().receiptId == 7)

        cart.recordCompletedSale()
        #expect(cart.receiptId == nil, "the server deleted the paid receipt")
        #expect(cart.makeSaleBody().receiptId == nil)

        cart.load(Self.receipt(id: 9, items: [Self.helix]))
        cart.clear()
        #expect(cart.receiptId == nil)
    }

    @Test("A discount above the lines is saved capped; checkout still flags it")
    func cappedDiscount() throws {
        let cart = try makeCart()
        cart.load(Self.receipt(items: [Self.helix], discount: 500))
        cart.lines.removeAll()

        #expect(cart.makeReceiptBody().discount == 0)
        #expect(!cart.isDiscountValid)
    }

    @Test("A blank cart has no lines, client, appointment or note")
    func blank() throws {
        let cart = try makeCart()
        cart.load(Self.receipt())
        #expect(cart.isBlank)
        cart.note = "Позвонить"
        #expect(!cart.isBlank)
        cart.note = ""
        cart.client = Self.ivan
        #expect(!cart.isBlank)
    }

    @Test("Starting a visit leaves the lines to the server; a new receipt sends none")
    func receiptBodies() throws {
        let encoder = JSONCoding.makeEncoder()
        let visit = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(ReceiptBody.visit(appointmentId: 4))) as? [String: Any]
        )
        #expect(visit["appointmentId"] as? Int == 4)
        #expect(!visit.keys.contains("items"), "omitted: the appointment's service lines")
        #expect(!visit.keys.contains("clientId"), "the appointment's client")

        let blank = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(ReceiptBody.blank(clientId: 1))) as? [String: Any]
        )
        #expect((blank["items"] as? [Any])?.isEmpty == true)
        #expect(blank["clientId"] as? Int == 1)
        #expect(!blank.keys.contains("appointmentId"))
    }

    // MARK: Hub

    @Test("«К оплате по записям» leaves out visits that already have a receipt")
    func queueExcludesStartedVisits() {
        let appointments = [
            Self.appointment(id: 1),
            Self.appointment(id: 2, receiptId: 5),
            Self.appointment(id: 3),
        ]
        let receipts = [Self.receipt(id: 6, appointment: Self.appointment(id: 3))]

        #expect(PaymentQueue.notStarted(appointments, openReceipts: receipts).map(\.id) == [1])
        #expect(PaymentQueue.notStarted(appointments, openReceipts: []).map(\.id) == [1, 3])
    }

    @Test("The list replaces a receipt in place or appends a new one; opening prefers the newer copy")
    func listUpdates() {
        let first = Self.receipt(id: 1)
        let second = Self.receipt(id: 2)
        let edited = Self.receipt(id: 1, items: [Self.helix], updatedAt: Fixtures.referenceDate.addingTimeInterval(60))

        #expect(OpenReceiptList.upserting(edited, into: [first, second]).map(\.itemCount) == [1, 0])
        #expect(OpenReceiptList.upserting(Self.receipt(id: 3), into: [first, second]).map(\.id) == [1, 2, 3])

        #expect(OpenReceiptList.newer(first, edited) == edited)
        #expect(OpenReceiptList.newer(edited, first) == edited)
        #expect(OpenReceiptList.newer(first, second) == first, "another receipt")
        #expect(OpenReceiptList.newer(first, nil) == first)
    }

    @Test("Row texts: who, the visit, lines and who opened it")
    func rowTexts() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let visit = Self.appointment(deposit: 2_000)
        let created = Fixtures.referenceDate

        #expect(OpenReceiptText.who(Self.receipt(appointment: visit, client: Self.ivan)) == "По записи · Иван Петров")
        #expect(OpenReceiptText.who(Self.receipt(client: Self.ivan)) == "Иван Петров")
        #expect(OpenReceiptText.who(Self.receipt()) == "Без клиента")

        let time = DateText.timeRange(visit.startsAt, visit.endsAt)
        #expect(OpenReceiptText.appointmentLine(visit) == "\(time) · Хеликс · Анна")

        #expect(OpenReceiptText.contents(itemCount: 0) == "Пусто")
        #expect(OpenReceiptText.contents(itemCount: 3) == "3 позиции")

        let today = created.addingTimeInterval(3_600)
        let receipt = Self.receipt(items: [Self.helix, Self.spray], createdAt: created)
        #expect(OpenReceiptText.details(receipt, now: today, calendar: utc) == "3 позиции · Открыл(а) Анна · \(DateText.time(created))")
        #expect(
            OpenReceiptText.opened(receipt, now: created.addingTimeInterval(2 * 86_400), calendar: utc)
                == "Открыл(а) Анна · \(DateText.dateTime(created))",
            "left from another day"
        )
        #expect(OpenReceiptText.opened(Self.receipt(openedBy: nil), now: today, calendar: utc) == "Открыт · \(DateText.time(created))")
    }

    @Test("«Удалить чек?» says what is lost and what stays")
    func deleteMessages() {
        let amount = Money.format(4_000)
        #expect(
            OpenReceiptText.deleteMessage(subtotal: 4_000, itemCount: 2, hasAppointment: true)
                == "Позиции на \(amount) будут удалены. Склад и предоплата не изменятся, запись вернётся в «К оплате»."
        )
        #expect(
            OpenReceiptText.deleteMessage(subtotal: 4_000, itemCount: 2, hasAppointment: false)
                == "Позиции на \(amount) будут удалены. Склад не изменится."
        )
        #expect(
            OpenReceiptText.deleteMessage(subtotal: 0, itemCount: 0, hasAppointment: true)
                == "Чек пустой. Предоплата не изменится, запись вернётся в «К оплате»."
        )
        #expect(OpenReceiptText.deleteMessage(subtotal: 0, itemCount: 0, hasAppointment: false) == "Чек пустой.")

        let deletion = ReceiptDeletion(Self.receipt(appointment: Self.appointment(), items: [Self.helix]))
        #expect(deletion.id == 7)
        #expect(deletion.message == OpenReceiptText.deleteMessage(subtotal: 3_000, itemCount: 1, hasAppointment: true))
    }

    @Test("Another receipt is not opened over unsaved edits; the message says why")
    func unsavedReceiptMessage() {
        #expect(
            UnsavedReceiptError(reason: "Нет подключения к интернету.").userMessage
                == "Открытый сейчас чек не сохранён, поэтому другой не открыт. Нет подключения к интернету."
        )
        #expect(UnsavedReceiptError(reason: nil).userMessage == "Открытый сейчас чек не сохранён, поэтому другой не открыт.")
    }

    // MARK: Appointment card

    @Test("The appointment card opens the receipt, starts the visit or takes payment")
    func visitCheckout() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Fixtures.referenceDate
        func action(_ appointment: Appointment) -> VisitCheckout? { VisitCheckout.of(appointment, now: now, calendar: utc) }

        #expect(action(Self.appointment(receiptId: 7)) == .openReceipt)
        #expect(action(Self.appointment(status: .completed, receiptId: 7)) == .openReceipt)
        #expect(action(Self.appointment(status: .scheduled)) == .startVisit)
        #expect(action(Self.appointment(startsAt: now.addingTimeInterval(-3 * 86_400))) == .startVisit, "an earlier day")
        #expect(action(Self.appointment(startsAt: now.addingTimeInterval(10 * 3_600))) == .startVisit, "later today")
        #expect(action(Self.appointment(startsAt: now.addingTimeInterval(86_400))) == nil, "tomorrow")
        #expect(action(Self.appointment(status: .completed)) == .takePayment(3_000))
        #expect(action(Self.appointment(status: .completed, saleId: 3)) == nil, "paid")
        #expect(action(Self.appointment(status: .cancelled)) == nil)
        #expect(action(Self.appointment(status: .noShow)) == nil)

        #expect(VisitCheckout.startVisit.title == "Начать визит")
        #expect(VisitCheckout.openReceipt.footer == "Визит идёт — чек открыт в кассе.")
        #expect(VisitCheckout.takePayment(3_000).title == "Принять оплату · \(Money.format(3_000))")
    }
}
