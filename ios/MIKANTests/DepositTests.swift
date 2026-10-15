import Foundation
import Testing
@testable import MIKAN

/// Prepayment JSON shaped like docs/API.md («Appointment», «DepositOperation», «QrPayment»).
private enum DepositJSON {
    static let employee = ##"{ "id": 2, "name": "Анна", "color": "#FF7A1A" }"##

    static func operation(
        id: Int,
        type: String,
        amount: Int,
        method: String? = nil,
        saleId: Int? = nil,
        note: String? = nil,
        withEmployee: Bool = true
    ) -> String {
        """
        { "id": \(id), "appointmentId": 4, "type": "\(type)", "amount": \(amount),
          "method": \(method.map { "\"\($0)\"" } ?? "null"), "saleId": \(saleId.map(String.init) ?? "null"),
          "shiftId": 3, "qrPaymentId": null, "note": \(note.map { "\"\($0)\"" } ?? "null"),
          "employee": \(withEmployee ? employee : "null"), "createdAt": "2026-10-15T11:05:00.000Z" }
        """
    }

    static let link = """
    { "id": 5, "kind": "deposit", "appointmentId": 4, "status": "pending", "amount": 500,
      "payload": "https://qr.nspk.ru/AD10001B38T99KA99CD8S37FMTH8CFQ7?type=02&bank=100000000065&sum=50000&cur=RUB&crc=43B6",
      "expiresAt": "2026-10-18T11:00:00.000Z", "sentAt": "2026-10-15T11:00:00.000Z", "error": null, "sale": null,
      "createdAt": "2026-10-15T11:00:00.000Z" }
    """

    /// Received 2 000 by transfer, applied in sale 17, the sale refunded, 500 returned in cash: 1 500 held.
    static let appointment = """
    { "id": 4, "client": { "id": 1, "name": "Иван Петров", "phone": "+79991234567", "telegramLinked": true },
      "master": \(employee), "service": { "id": 3, "name": "Соски", "category": "piercing" },
      "services": [ { "id": 10, "serviceId": 3, "name": "Соски — Два", "category": "piercing", "price": 4000, "durationMin": 60 } ],
      "title": null, "startsAt": "2026-10-18T11:00:00.000Z", "endsAt": "2026-10-18T12:00:00.000Z",
      "status": "confirmed", "price": 4000, "notes": null,
      "deposit": 1500, "depositRequired": 2000, "depositStatus": "paid",
      "depositOperations": [
        \(operation(id: 7, type: "receive", amount: 2000, method: "transfer")),
        \(operation(id: 8, type: "apply", amount: 2000, saleId: 17)),
        \(operation(id: 9, type: "unapply", amount: 2000, saleId: 17)),
        \(operation(id: 10, type: "refund", amount: 500, method: "cash", note: "Перенос", withEmployee: false))
      ],
      "depositLink": \(link),
      "saleId": null, "completedAt": null, "createdAt": "2026-10-15T10:00:00.000Z", "updatedAt": "2026-10-15T11:05:00.000Z" }
    """

    /// A server that predates prepayments; an unknown status from a newer one.
    static let legacyAppointment = """
    { "id": 5, "client": { "id": 1, "name": "Иван Петров", "phone": null, "telegramLinked": false },
      "master": \(employee), "service": null, "title": "Тату", "startsAt": "2026-10-18T11:00:00.000Z",
      "endsAt": "2026-10-18T12:00:00.000Z", "status": "scheduled", "price": 5000, "deposit": 1000,
      "depositStatus": "frozen", "notes": null, "saleId": null, "completedAt": null,
      "createdAt": "2026-10-15T10:00:00.000Z", "updatedAt": "2026-10-15T10:00:00.000Z" }
    """

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.makeDecoder().decode(T.self, from: Data(json.utf8))
    }
}

@MainActor
private enum DepositSample {
    static let start = Date(timeIntervalSince1970: 1_792_062_000) // 2026-10-15 11:00 UTC
    static let anna = EmployeeRef(id: 2, name: "Анна", color: nil)

    static func appointment(
        status: AppointmentStatus = .scheduled,
        held: Int = 0,
        required: Int = 0,
        depositStatus: DepositStatus = .none,
        operations: [DepositOperation] = [],
        link: QrPayment? = nil
    ) -> Appointment {
        Appointment(
            id: 4, client: ClientRef(id: 1, name: "Иван Петров", phone: nil, telegramLinked: true), master: anna,
            service: nil, title: nil, startsAt: start, endsAt: start.addingTimeInterval(3600), status: status,
            price: 4000, deposit: held, depositRequired: required, depositStatus: depositStatus,
            depositOperations: operations, depositLink: link, notes: nil, saleId: nil, completedAt: nil,
            createdAt: start, updatedAt: start
        )
    }

    static func operation(
        _ type: DepositOperationType,
        amount: Int,
        method: PaymentMethod? = nil,
        note: String? = nil,
        employee: EmployeeRef? = anna
    ) -> DepositOperation {
        DepositOperation(
            id: 1, appointmentId: 4, type: type, amount: amount, method: method, saleId: type == .apply ? 17 : nil,
            shiftId: nil, qrPaymentId: nil, note: note, employee: employee, createdAt: start
        )
    }

    static func link(status: QrPaymentStatus, sentAt: Date? = nil, error: String? = nil) -> QrPayment {
        QrPayment(
            id: 5, kind: .deposit, appointmentId: 4, status: status, amount: 1000, payload: "https://qr.nspk.ru/ABC",
            expiresAt: start.addingTimeInterval(3 * 3600), sentAt: sentAt, error: error, sale: nil,
            createdAt: start.addingTimeInterval(-600)
        )
    }
}

@MainActor
struct DepositDecodingTests {
    @Test("An appointment decodes its prepayment ledger and link")
    func decodesLedgerAndLink() throws {
        let appointment = try DepositJSON.decode(Appointment.self, DepositJSON.appointment)

        #expect(appointment.deposit == 1500)
        #expect(appointment.depositRequired == 2000)
        #expect(appointment.depositStatus == .paid)
        #expect(appointment.depositOperations.map(\.type) == [.receive, .apply, .unapply, .refund])
        #expect(appointment.depositOperations.map(\.method) == [.transfer, nil, nil, .cash])
        #expect(appointment.depositOperations[1].saleId == 17)
        #expect(appointment.depositOperations[3].note == "Перенос")
        #expect(appointment.depositOperations[3].employee == nil)
        #expect(appointment.depositOperations[0].employee?.name == "Анна")

        let link = try #require(appointment.depositLink)
        #expect(link.isDeposit)
        #expect(link.appointmentId == 4)
        #expect(link.status == .pending)
        #expect(link.amount == 500)
        #expect(link.sentAt == Date(timeIntervalSince1970: 1_792_062_000))
    }

    @Test("The ledger adds up to the held amount")
    func ledgerAddsUpToHeld() throws {
        let appointment = try DepositJSON.decode(Appointment.self, DepositJSON.appointment)
        let held = appointment.depositOperations.reduce(0) { $0 + DepositLedger.heldDelta(for: $1) }
        #expect(held == appointment.deposit)
        #expect(DepositSummary.missing(appointment) == 500)
        #expect(DepositSummary.latestReceiveMethod(appointment.depositOperations) == .transfer)
    }

    @Test("A server without prepayments decodes with defaults; an unknown status reads as none")
    func legacyDefaults() throws {
        let appointment = try DepositJSON.decode(Appointment.self, DepositJSON.legacyAppointment)
        #expect(appointment.deposit == 1000)
        #expect(appointment.depositRequired == 0)
        #expect(appointment.depositStatus == .none)
        #expect(appointment.depositOperations.isEmpty)
        #expect(appointment.depositLink == nil)
        #expect(DepositMark.of(appointment) == .held(1000))
    }
}

@MainActor
struct DepositSummaryTests {
    @Test("Missing amount never goes below zero")
    func missing() {
        #expect(DepositSummary.missing(DepositSample.appointment(held: 0, required: 2000)) == 2000)
        #expect(DepositSummary.missing(DepositSample.appointment(held: 500, required: 2000)) == 1500)
        #expect(DepositSummary.missing(DepositSample.appointment(held: 3000, required: 2000)) == 0)
    }

    @Test("The prepayment screen follows a create only while something is missing on an open appointment")
    func asksAfterCreating() {
        #expect(DepositSummary.asksForDeposit(afterCreating: DepositSample.appointment(required: 1000)))
        #expect(!DepositSummary.asksForDeposit(afterCreating: DepositSample.appointment()))
        #expect(!DepositSummary.asksForDeposit(afterCreating: DepositSample.appointment(held: 1000, required: 1000)))
        #expect(!DepositSummary.asksForDeposit(afterCreating: DepositSample.appointment(status: .completed, required: 1000)))
    }

    @Test("The card shows the block when something is required or happened")
    func showsSection() {
        #expect(!DepositSummary.showsSection(DepositSample.appointment()))
        #expect(DepositSummary.showsSection(DepositSample.appointment(required: 1000)))
        #expect(DepositSummary.showsSection(DepositSample.appointment(operations: [DepositSample.operation(.receive, amount: 500)])))
    }

    @Test("Headline: held of required, or what became of it")
    func headline() {
        #expect(DepositSummary.headline(DepositSample.appointment(required: 2000, depositStatus: .waiting)) == "Внесено 0 из 2\u{00A0}000\u{00A0}₽")
        #expect(DepositSummary.headline(DepositSample.appointment(held: 2000, required: 2000, depositStatus: .paid)) == "Внесено 2\u{00A0}000 из 2\u{00A0}000\u{00A0}₽")
        #expect(DepositSummary.headline(DepositSample.appointment(held: 500, depositStatus: .paid)) == "Внесено 500\u{00A0}₽")

        let applied = DepositSample.appointment(
            status: .completed, required: 2000, depositStatus: .applied,
            operations: [DepositSample.operation(.receive, amount: 2000, method: .cash), DepositSample.operation(.apply, amount: 2000)]
        )
        #expect(DepositSummary.headline(applied) == "Зачтено в чеке 2\u{00A0}000\u{00A0}₽")

        let refunded = DepositSample.appointment(
            status: .cancelled, required: 2000, depositStatus: .refunded,
            operations: [DepositSample.operation(.receive, amount: 2000, method: .cash), DepositSample.operation(.refund, amount: 2000, method: .cash)]
        )
        #expect(DepositSummary.headline(refunded) == "Возвращено 2\u{00A0}000\u{00A0}₽")

        let retained = DepositSample.appointment(
            status: .noShow, required: 2000, depositStatus: .retained,
            operations: [DepositSample.operation(.receive, amount: 2000, method: .qr), DepositSample.operation(.retain, amount: 2000, note: "Неявка")]
        )
        #expect(DepositSummary.headline(retained) == "Удержано 2\u{00A0}000\u{00A0}₽")
    }

    @Test("The latest receive decides the default refund method")
    func latestReceiveMethod() {
        let operations = [
            DepositSample.operation(.receive, amount: 500, method: .cash),
            DepositSample.operation(.receive, amount: 500, method: .qr),
            DepositSample.operation(.refund, amount: 200, method: .transfer),
        ]
        #expect(DepositSummary.latestReceiveMethod(operations) == .qr)
        #expect(DepositSummary.latestReceiveMethod([]) == nil)
    }

    @Test("Status titles")
    func statusTitles() {
        #expect(DepositStatus.waiting.title == "Ждём")
        #expect(DepositStatus.paid.title == "Внесена")
        #expect(DepositStatus.applied.title == "Зачтена в чеке")
        #expect(DepositStatus.refunded.title == "Возвращена")
        #expect(DepositStatus.retained.title == "Удержана")
    }
}

@MainActor
struct DepositMarkTests {
    @Test("Held, partial, waiting or nothing")
    func marks() {
        #expect(DepositMark.of(DepositSample.appointment(held: 2000, required: 2000, depositStatus: .paid)) == .held(2000))
        #expect(DepositMark.of(DepositSample.appointment(held: 2500, required: 2000, depositStatus: .paid)) == .held(2500))
        #expect(DepositMark.of(DepositSample.appointment(held: 500, required: 2000, depositStatus: .paid)) == .partial(held: 500, required: 2000))
        #expect(DepositMark.of(DepositSample.appointment(required: 2000, depositStatus: .waiting)) == .waiting(2000))
        #expect(DepositMark.of(DepositSample.appointment(status: .completed, required: 2000, depositStatus: .applied)) == nil)
        #expect(DepositMark.of(DepositSample.appointment(status: .cancelled, required: 2000, depositStatus: .none)) == nil)
        #expect(DepositMark.of(DepositSample.appointment()) == nil)
    }

    @Test("Mark texts read unambiguously")
    func texts() {
        #expect(DepositMark.held(2000).text == "Предоплата внесена 2\u{00A0}000\u{00A0}₽")
        #expect(DepositMark.partial(held: 500, required: 2000).text == "Предоплата внесена 500 из 2\u{00A0}000\u{00A0}₽")
        #expect(DepositMark.waiting(1000).text == "Ждём предоплату 1\u{00A0}000\u{00A0}₽")
        #expect(DepositMark.held(1).accessibilityText == "предоплата внесена")
        #expect(DepositMark.waiting(1).accessibilityText == "ждём предоплату")
        #expect(DepositMark.held(1).symbol == "rublesign.circle.fill")
        #expect(DepositMark.waiting(1).symbol == "hourglass")
    }
}

@MainActor
struct DepositLedgerTests {
    @Test("Row titles")
    func titles() {
        #expect(DepositLedger.title(for: DepositSample.operation(.receive, amount: 1, method: .transfer)) == "Получена переводом")
        #expect(DepositLedger.title(for: DepositSample.operation(.receive, amount: 1, method: .qr)) == "Получена по QR СБП")
        #expect(DepositLedger.title(for: DepositSample.operation(.apply, amount: 1)) == "Зачтена в чеке")
        #expect(DepositLedger.title(for: DepositSample.operation(.unapply, amount: 1)) == "Чек возвращён — предоплата снова за записью")
        #expect(DepositLedger.title(for: DepositSample.operation(.refund, amount: 1, method: .cash)) == "Возвращена наличными")
        #expect(DepositLedger.title(for: DepositSample.operation(.retain, amount: 1, note: "Неявка")) == "Удержана: Неявка")
        #expect(DepositLedger.title(for: DepositSample.operation(.retain, amount: 1)) == "Удержана")
    }

    @Test("Details name the employee and the note; a retain reason stays in the title only")
    func details() {
        let refund = DepositLedger.detail(for: DepositSample.operation(.refund, amount: 1, method: .cash, note: "Перенос"))
        #expect(refund.hasPrefix(DateText.dateTime(DepositSample.start)))
        #expect(refund.hasSuffix(" · Анна · Перенос"))

        let retain = DepositLedger.detail(for: DepositSample.operation(.retain, amount: 1, note: "Неявка"))
        #expect(!retain.contains("Неявка"))

        let migrated = DepositLedger.detail(for: DepositSample.operation(.receive, amount: 1, employee: nil))
        #expect(migrated == DateText.dateTime(DepositSample.start))
    }

    @Test("Held amount moves up on receive / unapply, down otherwise")
    func heldDelta() {
        #expect(DepositLedger.heldDelta(for: DepositSample.operation(.receive, amount: 500)) == 500)
        #expect(DepositLedger.heldDelta(for: DepositSample.operation(.unapply, amount: 500)) == 500)
        #expect(DepositLedger.heldDelta(for: DepositSample.operation(.apply, amount: 500)) == -500)
        #expect(DepositLedger.heldDelta(for: DepositSample.operation(.refund, amount: 500)) == -500)
        #expect(DepositLedger.heldDelta(for: DepositSample.operation(.retain, amount: 500)) == -500)
    }
}

@MainActor
struct DepositLinkNoteTests {
    @Test("A pending link says whether the bot sent it and until when it works")
    func pending() {
        let sentAt = DepositSample.start.addingTimeInterval(-300)
        let sent = DepositLinkNote.of(DepositSample.appointment(required: 1000, depositStatus: .waiting, link: DepositSample.link(status: .pending, sentAt: sentAt)))
        #expect(sent == .pending(amount: 1000, sentAt: sentAt, expiresAt: DepositSample.start.addingTimeInterval(3 * 3600)))
        #expect(sent?.text.hasPrefix("Ссылка отправлена \(DateText.dateTime(sentAt)) · действует до ") == true)

        let unsent = DepositLinkNote.of(DepositSample.appointment(required: 1000, depositStatus: .waiting, link: DepositSample.link(status: .pending)))
        #expect(unsent?.text.hasPrefix("Ссылка не отправлена · действует до ") == true)
        #expect(unsent?.offersNewLink == false)
    }

    @Test("Expired and cancelled links matter only while waiting for the money")
    func expiredAndCancelled() {
        let waiting = DepositSample.appointment(required: 1000, depositStatus: .waiting, link: DepositSample.link(status: .expired))
        #expect(DepositLinkNote.of(waiting)?.offersNewLink == true)

        let paidOtherwise = DepositSample.appointment(held: 1000, required: 1000, depositStatus: .paid, link: DepositSample.link(status: .cancelled))
        #expect(DepositLinkNote.of(paidOtherwise) == nil)

        let cancelledVisit = DepositSample.appointment(status: .cancelled, required: 1000, link: DepositSample.link(status: .cancelled))
        #expect(DepositLinkNote.of(cancelledVisit) == nil)

        let cancelledLink = DepositSample.appointment(required: 1000, depositStatus: .waiting, link: DepositSample.link(status: .cancelled))
        #expect(DepositLinkNote.of(cancelledLink) == .cancelled)
    }

    @Test("A paid link shows only a server note")
    func paid() {
        let clean = DepositSample.appointment(held: 1000, required: 1000, depositStatus: .paid, link: DepositSample.link(status: .paid))
        #expect(DepositLinkNote.of(clean) == nil)

        let flagged = DepositSample.appointment(held: 2000, required: 1000, depositStatus: .paid, link: DepositSample.link(status: .paid, error: "Оплачено сверх суммы"))
        #expect(DepositLinkNote.of(flagged) == .paidWithIssue("Оплачено сверх суммы"))
    }
}

@MainActor
struct DepositFlowTests {
    @Test("Open appointments take and remind; held money can be refunded")
    func openAppointment() {
        let waiting = DepositSample.appointment(required: 1000, depositStatus: .waiting)
        #expect(DepositFlow.available(for: waiting, qrEnabled: true) == [.collect, .remind])
        #expect(DepositFlow.available(for: waiting, qrEnabled: false) == [.collect], "reminders send SBP links")

        let paid = DepositSample.appointment(status: .confirmed, held: 1000, required: 1000, depositStatus: .paid)
        #expect(DepositFlow.available(for: paid, qrEnabled: true) == [.collect, .refund], "nothing to remind about")
    }

    @Test("Cancelled / no-show with money held: refund or retain")
    func closedWithoutVisit() {
        for status in [AppointmentStatus.cancelled, .noShow] {
            let appointment = DepositSample.appointment(status: status, held: 1000, required: 1000, depositStatus: .paid)
            #expect(DepositFlow.available(for: appointment, qrEnabled: true) == [.refund, .retain])
            #expect(DepositFlow.needsDecision(appointment))
        }
        let nothingHeld = DepositSample.appointment(status: .cancelled, required: 1000)
        #expect(DepositFlow.available(for: nothingHeld, qrEnabled: true).isEmpty)
        #expect(!DepositFlow.needsDecision(nothingHeld))
    }

    @Test("A completed appointment can only return what is still held")
    func completed() {
        let held = DepositSample.appointment(status: .completed, held: 1000, required: 1000, depositStatus: .paid)
        #expect(DepositFlow.available(for: held, qrEnabled: true) == [.refund])
        #expect(!DepositFlow.needsDecision(held))

        let applied = DepositSample.appointment(status: .completed, required: 1000, depositStatus: .applied)
        #expect(DepositFlow.available(for: applied, qrEnabled: true).isEmpty)
    }
}

@MainActor
struct DepositTextTests {
    @Test("The shared message names the amount, the visit and the link")
    func shareMessage() {
        let text = DepositText.shareMessage(amount: 2000, startsAt: DepositSample.start, payload: "https://qr.nspk.ru/ABC")
        #expect(text.contains("2\u{00A0}000\u{00A0}₽"))
        #expect(text.contains(DateText.dayMonth(DepositSample.start)))
        #expect(text.contains(DateText.time(DepositSample.start)))
        #expect(text.hasSuffix("https://qr.nspk.ru/ABC"))
    }

    @Test("Retain reason follows the status")
    func retainReason() {
        #expect(DepositText.retainReason(for: .noShow) == "Неявка")
        #expect(DepositText.retainReason(for: .cancelled) == "Отмена записи")
    }

    @Test("Reminder notice: sent, or why not")
    func remindNotice() {
        let appointment = DepositSample.appointment(required: 1000, depositStatus: .waiting)
        let sent = DepositText.remindNotice(DepositLinkResult(appointment: appointment, payment: DepositSample.link(status: .pending), sendError: nil))
        #expect(sent.title == "Напоминание отправлено")
        #expect(sent.message.contains("1\u{00A0}000\u{00A0}₽"))

        let failed = DepositText.remindNotice(DepositLinkResult(appointment: appointment, payment: DepositSample.link(status: .pending), sendError: "Клиент заблокировал бота"))
        #expect(failed.title == "Напоминание не отправлено")
        #expect(failed.message.hasPrefix("Клиент заблокировал бота"))
    }

    @Test("Refund amount must be positive and within what is held")
    func refundRules() {
        #expect(DepositRefundRules.amountMessage(0, held: 1000) == "Укажите сумму возврата.")
        #expect(DepositRefundRules.amountMessage(1500, held: 1000) == "Не больше внесённой суммы (1\u{00A0}000\u{00A0}₽).")
        #expect(DepositRefundRules.amountMessage(1000, held: 1000) == nil)
        #expect(DepositRefundRules.methodNote(.cash).contains("открытая смена"))
        #expect(DepositRefundRules.methodNote(.qr).contains("Точки"))
    }
}

@MainActor
struct QRPaymentPollingTests {
    @Test("The device-clock deadline keeps the code's lifetime")
    func deadline() {
        let payment = DepositSample.link(status: .pending)
        let shown = Date(timeIntervalSince1970: 1_000)
        let lifetime = payment.expiresAt.timeIntervalSince(payment.createdAt)
        #expect(QRPaymentPolling.deadline(for: payment, shownAt: shown) == shown.addingTimeInterval(lifetime))
    }

    @Test("Connection problems read as offline; server errors show their message")
    func problemText() {
        #expect(QRPaymentPolling.problemText(for: APIError.transport(message: "x")) == QRPaymentPolling.offlineText)
        #expect(QRPaymentPolling.problemText(for: CancellationError()) == QRPaymentPolling.offlineText)
        #expect(QRPaymentPolling.problemText(for: APIError.server(status: 502, code: "payment_provider_error", message: "Банк недоступен")) == "Банк недоступен")
    }
}
