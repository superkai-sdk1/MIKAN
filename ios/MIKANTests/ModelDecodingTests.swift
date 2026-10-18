import XCTest
@testable import MIKAN

/// Every model decodes from the exact example shapes in docs/API.md,
/// with and without fractional seconds in instants.
final class ModelDecodingTests: XCTestCase {
    private let variants = [true, false]

    func testInstantsDecodeWithAndWithoutFractionalSeconds() throws {
        for fractional in variants {
            let employee = try Fixtures.decode(Employee.self, Fixtures.employee, fractional: fractional)
            XCTAssertEqual(employee.createdAt, Fixtures.referenceDate, "fractional: \(fractional)")
        }
    }

    func testInstantWithMillisecondsKeepsPrecision() throws {
        let data = Data(#"{ "id": 1, "name": "А", "login": "a", "phone": null, "color": null, "isMaster": false, "active": true, "createdAt": "2026-10-15T11:00:00.250Z" }"#.utf8)
        let employee = try JSONCoding.makeDecoder().decode(Employee.self, from: data)
        XCTAssertEqual(employee.createdAt.timeIntervalSince1970, Fixtures.referenceDate.timeIntervalSince1970 + 0.25, accuracy: 0.001)
        XCTAssertNil(employee.phone)
        XCTAssertNil(employee.color)
    }

    func testInvalidInstantFailsDecoding() {
        let data = Data(#"{ "id": 1, "name": "А", "login": "a", "phone": null, "color": null, "isMaster": false, "active": true, "createdAt": "15.10.2026" }"#.utf8)
        XCTAssertThrowsError(try JSONCoding.makeDecoder().decode(Employee.self, from: data))
    }

    func testEmbeddedRefs() throws {
        let employee = try Fixtures.decode(EmployeeRef.self, Fixtures.employeeRef)
        XCTAssertEqual(employee, EmployeeRef(id: 2, name: "Анна", color: "#FF7A1A"))
        let client = try Fixtures.decode(ClientRef.self, Fixtures.clientRef)
        XCTAssertEqual(client, ClientRef(id: 1, name: "Иван", lastName: "Петров", phone: "+79991234567", telegramLinked: true))
        XCTAssertEqual(client.fullName, "Иван Петров")
        let legacy = try Fixtures.decode(ClientRef.self, Fixtures.legacyClientRef)
        XCTAssertNil(legacy.lastName)
        XCTAssertEqual(legacy.fullName, "Иван Петров")
        let service = try Fixtures.decode(ServiceRef.self, Fixtures.serviceRef)
        XCTAssertEqual(service, ServiceRef(id: 3, name: "Прокол мочки", category: .piercing))
    }

    func testEmployee() throws {
        for fractional in variants {
            let employee = try Fixtures.decode(Employee.self, Fixtures.employee, fractional: fractional)
            XCTAssertEqual(employee.login, "anna")
            XCTAssertTrue(employee.isMaster)
            XCTAssertTrue(employee.active)
            XCTAssertEqual(employee.ref, EmployeeRef(id: 1, name: "Анна", color: "#FF7A1A"))
        }
    }

    func testClientInListHasNullStats() throws {
        for fractional in variants {
            let client = try Fixtures.decode(Client.self, Fixtures.clientInList, fractional: fractional)
            XCTAssertEqual(client.birthday, "1995-04-12")
            XCTAssertEqual(client.instagram, "ivan.p")
            XCTAssertEqual(client.lastName, "Петров")
            XCTAssertEqual(client.telegramNick, "ivan_petrov")
            XCTAssertEqual(client.fullName, "Иван Петров")
            XCTAssertEqual(client.ref.lastName, "Петров")
            XCTAssertTrue(client.telegramLinked)
            XCTAssertNil(client.stats)
        }
    }

    func testClientDetailWithStats() throws {
        for fractional in variants {
            let client = try Fixtures.decode(Client.self, Fixtures.clientWithStats, fractional: fractional)
            XCTAssertNil(client.phone)
            XCTAssertNil(client.lastName, "older servers send no last name")
            XCTAssertNil(client.telegramNick)
            XCTAssertEqual(client.stats?.visits, 3)
            XCTAssertEqual(client.stats?.totalSpent, 25_000)
            XCTAssertEqual(client.stats?.lastVisitAt, Fixtures.referenceDate)
            XCTAssertEqual(client.stats?.upcomingAppointments, 1)
        }
    }

    func testServiceAndAftercareTemplate() throws {
        let service = try Fixtures.decode(Service.self, Fixtures.service)
        XCTAssertEqual(service.category, .piercing)
        XCTAssertEqual(service.durationMin, 30)
        XCTAssertEqual(service.aftercareTemplateId, 2)
        XCTAssertFalse(service.priceFrom)

        for fractional in variants {
            let template = try Fixtures.decode(AftercareTemplate.self, Fixtures.aftercareTemplate, fractional: fractional)
            XCTAssertEqual(template.category, .tattoo)
            XCTAssertEqual(template.steps.map(\.dayOffset), [0, 1, 7])
        }
    }

    func testProductAndMovements() throws {
        for fractional in variants {
            let product = try Fixtures.decode(Product.self, Fixtures.product, fractional: fractional)
            XCTAssertEqual(product.kind, .jewelry)
            XCTAssertEqual(product.photoUrl, "/uploads/3f1c.jpg")
            XCTAssertEqual(product.detailLine, "Титан G23 · 1.2×8 мм")
            XCTAssertFalse(product.lowStock)

            let movement = try Fixtures.decode(StockMovement.self, Fixtures.stockMovement, fractional: fractional)
            XCTAssertEqual(movement.type, .sale)
            XCTAssertEqual(movement.delta, -1)
            XCTAssertEqual(movement.saleId, 5)
            XCTAssertNil(movement.appointmentId)

            let result = try Fixtures.decode(
                MovementResult.self,
                #"{ "product": \#(Fixtures.product), "movement": \#(Fixtures.stockMovement) }"#,
                fractional: fractional
            )
            XCTAssertEqual(result.movement.quantityAfter, 11)
        }
    }

    func testAllMovementTypesDecode() throws {
        for raw in ["receipt", "sale", "return", "writeoff", "usage", "adjustment"] {
            let type = try JSONDecoder().decode(MovementType.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(type.rawValue, raw)
        }
    }

    func testAppointment() throws {
        for fractional in variants {
            let appointment = try Fixtures.decode(Appointment.self, Fixtures.appointment, fractional: fractional)
            XCTAssertEqual(appointment.status, .noShow)
            XCTAssertEqual(appointment.service?.category, .piercing)
            XCTAssertEqual(appointment.displayTitle, "Прокол мочки")
            XCTAssertFalse(appointment.isActive)
            XCTAssertEqual(appointment.deposit, 2000)
            XCTAssertEqual(appointment.depositRequired, 0, "a server without prepayments sends no depositRequired")
            XCTAssertEqual(appointment.depositStatus, DepositStatus.none)
            XCTAssertTrue(appointment.depositOperations.isEmpty)
            XCTAssertNil(appointment.depositLink)

            let bare = try Fixtures.decode(Appointment.self, Fixtures.appointmentWithoutService, fractional: fractional)
            XCTAssertNil(bare.service)
            XCTAssertEqual(bare.displayTitle, "Запись")
            XCTAssertEqual(bare.saleId, 7)
            XCTAssertEqual(bare.completedAt, Fixtures.referenceDate)

            let completed = try Fixtures.decode(
                CompleteAppointmentResult.self,
                #"{ "appointment": \#(Fixtures.appointment), "scheduledMessages": 3 }"#,
                fractional: fractional
            )
            XCTAssertEqual(completed.scheduledMessages, 3)
        }
    }

    func testAppointmentPrepaymentFields() throws {
        for fractional in variants {
            let appointment = try Fixtures.decode(Appointment.self, Fixtures.appointmentWithDeposit, fractional: fractional)
            XCTAssertEqual(appointment.deposit, 2000, "held")
            XCTAssertEqual(appointment.depositRequired, 2000)
            XCTAssertEqual(appointment.depositStatus, .paid)
            let receive = try XCTUnwrap(appointment.depositOperations.first)
            XCTAssertEqual(appointment.depositOperations.count, 1)
            XCTAssertEqual(receive.type, .receive)
            XCTAssertEqual(receive.method, .transfer)
            XCTAssertEqual(receive.shiftId, 3)
            XCTAssertEqual(receive.employee?.name, "Анна")
            XCTAssertEqual(receive.createdAt, Fixtures.referenceDate)
            let link = try XCTUnwrap(appointment.depositLink)
            XCTAssertTrue(link.isDeposit)
            XCTAssertEqual(link.appointmentId, 4)
            XCTAssertEqual(link.status, .paid)
        }

        let apply = try Fixtures.decode(DepositOperation.self, Fixtures.depositApply)
        XCTAssertEqual(apply.type, .apply)
        XCTAssertNil(apply.method)
        XCTAssertEqual(apply.saleId, 1)
        XCTAssertNil(apply.employee, "migrated entries have no employee")

        let newer = Fixtures.appointmentWithDeposit.replacingOccurrences(of: #""depositStatus": "paid""#, with: #""depositStatus": "partly_paid""#)
        XCTAssertEqual(try Fixtures.decode(Appointment.self, newer).depositStatus, DepositStatus.none, "unknown statuses are tolerated")
    }

    func testSaleAndHistory() throws {
        for fractional in variants {
            let sale = try Fixtures.decode(Sale.self, Fixtures.sale, fractional: fractional)
            XCTAssertEqual(sale.number, 17)
            XCTAssertEqual(sale.items.first?.type, .product)
            XCTAssertEqual(sale.payments, Payments(cash: 1500, card: 0, transfer: 0))
            XCTAssertEqual(sale.payments.qr, 0, "a server without QR payments sends no qr key")
            XCTAssertEqual(sale.payments.deposit, 0, "a server without prepayments sends no deposit key")
            XCTAssertEqual(sale.status, .completed)
            XCTAssertTrue(sale.hasProducts)

            let history = try Fixtures.decode(
                ClientHistory.self,
                #"{ "appointments": [\#(Fixtures.appointment)], "sales": [\#(Fixtures.sale)] }"#,
                fractional: fractional
            )
            XCTAssertEqual(history.appointments.count, 1)
            XCTAssertEqual(history.sales.count, 1)
        }
    }

    func testSalePaymentsWithPrepayment() throws {
        for fractional in variants {
            let sale = try Fixtures.decode(Sale.self, Fixtures.saleWithDeposit, fractional: fractional)
            XCTAssertEqual(sale.appointmentId, 4)
            XCTAssertEqual(sale.payments, Payments(cash: 6000, card: 0, transfer: 0, qr: 0, deposit: 2000))
            XCTAssertEqual(sale.payments.total, sale.total)
            XCTAssertEqual(sale.payments.paidNow, 6000)
        }
    }

    func testCashShiftAndOperations() throws {
        for fractional in variants {
            let shift = try Fixtures.decode(CashShift.self, Fixtures.cashShift, fractional: fractional)
            XCTAssertTrue(shift.isOpen)
            XCTAssertEqual(shift.expectedCash, 7500)
            XCTAssertEqual(shift.summary.card, 5000)
            XCTAssertEqual(shift.summary.deposit, 0, "a server without prepayments sends no deposit")
            XCTAssertEqual(shift.summary.deposits, .zero)
            XCTAssertEqual(shift.operations.first?.type, .withdrawal)

            let current = try Fixtures.decode(CurrentShiftResponse.self, #"{ "shift": \#(Fixtures.cashShift) }"#, fractional: fractional)
            XCTAssertEqual(current.shift?.id, 3)
        }
        let none = try Fixtures.decode(CurrentShiftResponse.self, #"{ "shift": null }"#)
        XCTAssertNil(none.shift)
    }

    func testCashShiftWithPrepayments() throws {
        for fractional in variants {
            let shift = try Fixtures.decode(CashShift.self, Fixtures.cashShiftWithDeposits, fractional: fractional)
            let summary = shift.summary
            XCTAssertEqual(summary.deposit, 2500)
            XCTAssertEqual(summary.revenue, summary.cash + summary.card + summary.transfer + summary.qr + summary.deposit)
            XCTAssertEqual(summary.deposits.received, 3000)
            XCTAssertEqual(summary.deposits.cash, 1000)
            XCTAssertEqual(summary.deposits.transfer, 2000)
            XCTAssertEqual(summary.deposits.retained, 0)
            let drawer = ShiftBreakdown.drawer(summary).reduce(0) { $0 + $1.amount }
            XCTAssertEqual(shift.openingCash + drawer, shift.expectedCash, "the drawer breakdown matches the server")
        }
    }

    func testBotEntities() throws {
        for fractional in variants {
            let chat = try Fixtures.decode(BotChat.self, Fixtures.botChat, fractional: fractional)
            XCTAssertEqual(chat.chatId, 123_456_789)
            XCTAssertEqual(chat.lastMessage?.role, .user)
            XCTAssertEqual(chat.displayName, "Иван Петров")
            XCTAssertNil(chat.employee, "older servers send no employee")
            XCTAssertFalse(chat.isStaff)

            let staff = try Fixtures.decode(BotChat.self, Fixtures.staffBotChat, fractional: fractional)
            XCTAssertEqual(staff.employee, EmployeeRef(id: 2, name: "Анна", color: "#FF7A1A"))
            XCTAssertTrue(staff.isStaff)
            XCTAssertNil(staff.client)
            XCTAssertNil(staff.lastMessage)
            XCTAssertEqual(staff.displayName, "Анна", "a staff chat is named after the employee")

            let scheduled = try Fixtures.decode(ScheduledMessage.self, Fixtures.scheduledMessage, fractional: fractional)
            XCTAssertEqual(scheduled.kind, .aftercare)
            XCTAssertEqual(scheduled.status, .pending)

            let request = try Fixtures.decode(BookingRequest.self, Fixtures.bookingRequest, fractional: fractional)
            XCTAssertEqual(request.status, .new)
            XCTAssertEqual(request.displayName, "Иван")

            let entry = try Fixtures.decode(KnowledgeEntry.self, Fixtures.knowledgeEntry, fractional: fractional)
            XCTAssertEqual(entry.title, "Противопоказания")

            let code = try Fixtures.decode(
                StaffCode.self,
                #"{ "code": "482913", "expiresAt": "<T>", "instruction": "Добавьте бота в рабочий чат и отправьте: /staff 482913" }"#,
                fractional: fractional
            )
            XCTAssertEqual(code.code, "482913")
        }
        let reply = try Fixtures.decode(BotTestReply.self, #"{ "reply": "Здравствуйте!" }"#)
        XCTAssertEqual(reply.reply, "Здравствуйте!")
    }

    func testGroupChatIdsFitInt64() throws {
        let message = try Fixtures.decode(
            BotMessage.self,
            #"{ "id": 9, "chatId": -1001234567890, "role": "staff", "text": "Ок", "employee": \#(Fixtures.employeeRef), "createdAt": "<T>" }"#
        )
        XCTAssertEqual(message.chatId, -1_001_234_567_890)
        XCTAssertEqual(message.employee?.name, "Анна")
    }

    func testSettings() throws {
        let studio = try Fixtures.decode(StudioSettings.self, Fixtures.studioSettings)
        XCTAssertEqual(studio.timezone, "Europe/Moscow")
        XCTAssertEqual(studio.workingHours, "Ежедневно 11:00–21:00")
        XCTAssertEqual(studio.workdayStart, "10:00")
        XCTAssertEqual(studio.workdayEnd, "21:00")

        let tolerant = try Fixtures.decode(StudioSettings.self, #"{ "name": "MIKAN", "address": null, "timezone": "Europe/Moscow" }"#)
        XCTAssertEqual(tolerant.address, "")
        XCTAssertEqual(tolerant.workdayStart, "11:00", "servers without working hours get the server default")
        XCTAssertEqual(tolerant.workdayEnd, "21:00")

        let legacy = try Fixtures.decode(BotSettings.self, Fixtures.botSettings)
        XCTAssertEqual(legacy.botUsername, "mikan_studio_bot")
        XCTAssertEqual(legacy.reminderOffsets, [1440], "a server without offsets: [reminderHoursBefore * 60]")
        XCTAssertFalse(legacy.supportsReminderOffsets)
        XCTAssertTrue(legacy.aiConfigured)
        XCTAssertFalse(legacy.staffChatBound)

        let bot = try Fixtures.decode(BotSettings.self, Fixtures.botSettingsWithOffsets)
        XCTAssertEqual(bot.reminderOffsets, [1440, 120], "earliest reminder first")
        XCTAssertTrue(bot.supportsReminderOffsets)
        XCTAssertTrue(bot.staffChatBound)
        XCTAssertEqual(bot.reminderSchedule.summary, "за 1 день и за 2 часа")
    }

    func testBotChatEmployeeMayBeNull() throws {
        let chat = try Fixtures.decode(
            BotChat.self,
            #"{ "chatId": 1, "client": null, "telegramName": "Иван", "username": null, "aiPaused": false, "needsAttention": false, "unreadCount": 0, "lastMessage": null, "updatedAt": "<T>", "employee": null }"#
        )
        XCTAssertNil(chat.employee)
        XCTAssertEqual(chat.displayName, "Иван")
    }

    func testDashboardBadgesAndAuth() throws {
        for fractional in variants {
            let dashboard = try Fixtures.decode(Dashboard.self, Fixtures.dashboard, fractional: fractional)
            XCTAssertEqual(dashboard.date, "2026-10-15")
            XCTAssertEqual(dashboard.revenueToday, 12_000)
            XCTAssertEqual(dashboard.openShift?.id, 3)
            XCTAssertEqual(dashboard.badges.lowStock, 3)

            let login = try Fixtures.decode(LoginResponse.self, #"{ "token": "abc", "employee": \#(Fixtures.employee) }"#, fractional: fractional)
            XCTAssertEqual(login.token, "abc")
        }
        let link = try Fixtures.decode(LinkResponse.self, #"{ "url": "https://t.me/mikan_studio_bot?start=cAbC" }"#)
        XCTAssertEqual(link.url, "https://t.me/mikan_studio_bot?start=cAbC")
        let health = try Fixtures.decode(HealthResponse.self, #"{ "ok": true, "version": "1.0.0" }"#)
        XCTAssertTrue(health.ok)
    }

    func testReportSummary() throws {
        for fractional in variants {
            let report = try Fixtures.decode(ReportSummary.self, Fixtures.report, fractional: fractional)
            XCTAssertEqual(report.revenue, 120_000)
            XCTAssertEqual(report.byDay.first?.date, "2026-10-01")
            XCTAssertEqual(report.topProducts.first?.quantity, 7)
            XCTAssertEqual(report.topServices.first?.serviceId, 3)
            XCTAssertEqual(report.byMaster.first?.employee.id, 2)
            XCTAssertEqual(report.payments.total, 120_000)
            XCTAssertEqual(report.payments.deposit, 0)
            XCTAssertNil(report.deposits, "a server without prepayments sends no deposits")
        }
    }

    func testReportSummaryWithPrepayments() throws {
        for fractional in variants {
            let report = try Fixtures.decode(ReportSummary.self, Fixtures.reportWithDeposits, fractional: fractional)
            XCTAssertEqual(report.payments.deposit, 10_000)
            XCTAssertEqual(report.payments.total, report.revenue)
            let deposits = try XCTUnwrap(report.deposits)
            XCTAssertEqual(deposits.received, deposits.cash + deposits.card + deposits.transfer + deposits.qr)
            XCTAssertEqual(deposits.applied, 10_000)
            XCTAssertEqual(deposits.refunded, 1000)
            XCTAssertEqual(deposits.retained, 2000)
            XCTAssertEqual(deposits.held, 7000)
        }
    }

    func testQrPayment() throws {
        for fractional in variants {
            let pending = try Fixtures.decode(QrPayment.self, Fixtures.qrPaymentPending, fractional: fractional)
            XCTAssertEqual(pending.status, .pending)
            XCTAssertEqual(pending.amount, 3000)
            XCTAssertTrue(pending.payload.hasPrefix("https://qr.nspk.ru/"))
            XCTAssertNil(pending.sale)
            XCTAssertEqual(pending.kind, .sale, "a server without prepayment codes sends no kind")
            XCTAssertFalse(pending.isDeposit)
            XCTAssertNil(pending.appointmentId)
            XCTAssertNil(pending.sentAt)

            let deposit = try Fixtures.decode(QrPayment.self, Fixtures.qrPaymentDeposit, fractional: fractional)
            XCTAssertEqual(deposit.kind, .deposit)
            XCTAssertTrue(deposit.isDeposit)
            XCTAssertEqual(deposit.appointmentId, 4)
            XCTAssertEqual(deposit.sentAt, Fixtures.referenceDate)
            XCTAssertNil(deposit.sale, "a paid prepayment creates no sale")

            let paid = try Fixtures.decode(QrPayment.self, Fixtures.qrPaymentPaid, fractional: fractional)
            XCTAssertEqual(paid.status, .paid)
            XCTAssertEqual(paid.sale?.payments, Payments(cash: 0, card: 0, transfer: 0, qr: 1500))
            XCTAssertEqual(paid.sale?.payments.total, 1500)
        }
        XCTAssertTrue(try Fixtures.decode(QrPaymentsConfig.self, #"{ "enabled": true }"#).enabled)
    }

    func testPaginatedListWrapper() throws {
        let page = try Fixtures.decode(ItemsResponse<Client>.self, #"{ "items": [\#(Fixtures.clientInList)], "total": 120 }"#)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.total, 120)

        let plain = try Fixtures.decode(ItemsResponse<Service>.self, #"{ "items": [\#(Fixtures.service)] }"#)
        XCTAssertNil(plain.total)
    }
}
