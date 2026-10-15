#if DEBUG
import Foundation
import SwiftUI

/// Sample data for SwiftUI previews only.
enum PreviewData {
    static let now = Date.now
    static let today = Calendar.app.startOfDay(for: now)

    static func at(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = Calendar.app.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return Calendar.app.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static let anna = Employee(
        id: 1, name: "Анна Смирнова", login: "anna", phone: "+79991234567",
        color: "#FF7A1A", isMaster: true, active: true, createdAt: now
    )
    static let oleg = Employee(
        id: 2, name: "Олег", login: "oleg", phone: nil,
        color: "#0090FF", isMaster: true, active: true, createdAt: now
    )
    static let employees = [anna, oleg]

    static let ivanRef = ClientRef(id: 1, name: "Иван Петров", phone: "+79991234567", telegramLinked: true)
    static let mariaRef = ClientRef(id: 2, name: "Мария Ким", phone: "+79161112233", telegramLinked: false)

    static let ivan = Client(
        id: 1, name: "Иван Петров", phone: "+79991234567", instagram: "ivan.p", birthday: "1995-04-12",
        notes: "Аллергия на никель", source: "instagram", telegramLinked: true, telegramUsername: "ivanp",
        botEnabled: true, archived: false, createdAt: now, updatedAt: now,
        stats: ClientStats(visits: 3, totalSpent: 25_000, lastVisitAt: at(hour: 12, dayOffset: -20), upcomingAppointments: 1)
    )
    static let maria = Client(
        id: 2, name: "Мария Ким", phone: "+79161112233", instagram: nil, birthday: nil, notes: nil,
        source: "рекомендация", telegramLinked: false, telegramUsername: nil, botEnabled: true,
        archived: false, createdAt: now, updatedAt: now, stats: nil
    )
    static let clients = [ivan, maria]

    static let lobe = Service(
        id: 3, name: "Прокол мочки", category: .piercing, price: 2500, priceFrom: false, durationMin: 30,
        description: "Прокол титаном G23", aftercareTemplateId: 2, active: true, sort: 0
    )
    static let tattoo = Service(
        id: 4, name: "Тату до 10 см", category: .tattoo, price: 8000, priceFrom: true, durationMin: 120,
        description: nil, aftercareTemplateId: 1, active: true, sort: 1
    )
    static let services = [lobe, tattoo]

    static let template = AftercareTemplate(
        id: 1, name: "Уход за татуировкой", category: .tattoo,
        steps: [
            AftercareStep(dayOffset: 0, text: "Снимите плёнку через 3 часа и промойте тату тёплой водой."),
            AftercareStep(dayOffset: 1, text: "Наносите заживляющий крем тонким слоем 3 раза в день."),
            AftercareStep(dayOffset: 7, text: "Как заживает? Пришлите фото, если что-то беспокоит."),
        ],
        createdAt: now, updatedAt: now
    )

    static let appointments = [
        Appointment(
            id: 1, client: ivanRef, master: anna.ref, service: tattoo.ref, title: "Предплечье, эскиз согласован",
            startsAt: at(hour: 11), endsAt: at(hour: 13), status: .confirmed, price: 8000, deposit: 2000,
            notes: "Принести эскиз в цвете", saleId: nil, completedAt: nil, createdAt: now, updatedAt: now
        ),
        Appointment(
            id: 2, client: mariaRef, master: oleg.ref, service: lobe.ref, title: nil,
            startsAt: at(hour: 14, minute: 30), endsAt: at(hour: 15), status: .scheduled, price: 2500, deposit: 0,
            notes: nil, saleId: nil, completedAt: nil, createdAt: now, updatedAt: now
        ),
        Appointment(
            id: 3, client: ivanRef, master: anna.ref, service: lobe.ref, title: nil,
            startsAt: at(hour: 17), endsAt: at(hour: 17, minute: 30), status: .completed, price: 2500, deposit: 0,
            notes: nil, saleId: 9, completedAt: now, createdAt: now, updatedAt: now
        ),
    ]

    static let labret = Product(
        id: 1, kind: .jewelry, name: "Лабрет", sku: "LB-12-08", category: "Лабрет", material: "Титан G23",
        size: "1.2×8 мм", description: nil, price: 1500, cost: 600, quantity: 12, minQuantity: 3, unit: "шт",
        photoUrl: nil, active: true, lowStock: false, createdAt: now, updatedAt: now
    )
    static let ring = Product(
        id: 2, kind: .jewelry, name: "Кольцо-кликер", sku: "CL-10", category: "Кольцо", material: "Титан G23",
        size: "1.2×10 мм", description: nil, price: 2800, cost: 1100, quantity: 2, minQuantity: 3, unit: "шт",
        photoUrl: nil, active: true, lowStock: true, createdAt: now, updatedAt: now
    )
    static let needles = Product(
        id: 3, kind: .consumable, name: "Иглы 1.2 мм", sku: nil, category: "Иглы", material: nil,
        size: nil, description: nil, price: 0, cost: 40, quantity: 48, minQuantity: 20, unit: "шт",
        photoUrl: nil, active: true, lowStock: false, createdAt: now, updatedAt: now
    )
    static let products = [labret, ring, needles]

    static let movement = StockMovement(
        id: 1, productId: 1, productName: "Лабрет", delta: -1, quantityAfter: 11, type: .sale,
        note: nil, saleId: 5, appointmentId: nil, employee: anna.ref, createdAt: now
    )

    static let sale = Sale(
        id: 9, number: 17, client: ivanRef, employee: anna.ref, appointmentId: 3, shiftId: 3,
        items: [
            SaleItem(id: 1, type: .product, productId: 1, serviceId: nil, name: "Лабрет", quantity: 1, price: 1500, total: 1500),
            SaleItem(id: 2, type: .service, productId: nil, serviceId: 3, name: "Прокол мочки", quantity: 1, price: 2500, total: 2500),
        ],
        subtotal: 4000, discount: 500, total: 3500,
        payments: Payments(cash: 1500, card: 2000, transfer: 0),
        status: .completed, note: nil, refundedAt: nil, refundReason: nil, createdAt: now
    )

    static let shift = CashShift(
        id: 3, openedAt: at(hour: 10, minute: 2), openedBy: anna.ref, openingCash: 5000,
        closedAt: nil, closedBy: nil, closingCash: nil, note: nil, expectedCash: 7500, difference: nil,
        summary: ShiftSummary(salesCount: 3, revenue: 10_000, cash: 2500, card: 5000, transfer: 2500,
                              refunds: 0, cashRefunds: 0, cashIn: 0, cashOut: 0),
        operations: []
    )

    static let messages = [
        BotMessage(id: 1, chatId: 123_456_789, role: .user, text: "Здравствуйте! Сколько стоит прокол хеликса?", employee: nil, createdAt: at(hour: 9, minute: 40)),
        BotMessage(id: 2, chatId: 123_456_789, role: .assistant, text: "Здравствуйте! Прокол хеликса — 3 000 ₽, украшение из титана подбирается отдельно.", employee: nil, createdAt: at(hour: 9, minute: 41)),
        BotMessage(id: 3, chatId: 123_456_789, role: .staff, text: "Можем записать на субботу в 15:00 😊", employee: anna.ref, createdAt: at(hour: 9, minute: 50)),
        BotMessage(id: 4, chatId: 123_456_789, role: .system, text: "Напоминаем о записи завтра в 15:00.", employee: nil, createdAt: at(hour: 10)),
    ]

    static let chat = BotChat(
        chatId: 123_456_789, client: ivanRef, telegramName: "Иван", username: "ivanp", aiPaused: false,
        needsAttention: true, unreadCount: 2, lastMessage: messages.last, updatedAt: now
    )

    static let bookingRequest = BookingRequest(
        id: 1, chatId: 123_456_789, client: nil, contactName: "Иван", phone: "+79991234567",
        serviceName: "Прокол хеликса", preferredTime: "в субботу после 15:00", comment: "Хочу кольцо",
        status: .new, createdAt: now, updatedAt: now
    )

    static let studioSettings = StudioSettings(
        name: "MIKAN STUDIO", address: "ул. Ленина, 1", phone: "+79990000000",
        workingHours: "Ежедневно 11:00–21:00", instagram: "mikan.studio", website: "",
        about: "Тату и пирсинг", timezone: "Europe/Moscow"
    )

    static func appState(signedIn: Bool = true) -> AppState {
        let api = APIClient(serverURL: URL(string: "http://localhost:3000")!)
        return AppState(api: api, employee: signedIn ? anna : nil, phase: signedIn ? .signedIn : .signedOut)
    }
}

extension View {
    /// Injects a preview `AppState` and its stores.
    func previewEnvironment(signedIn: Bool = true) -> some View {
        appEnvironment(PreviewData.appState(signedIn: signedIn))
    }
}
#endif
