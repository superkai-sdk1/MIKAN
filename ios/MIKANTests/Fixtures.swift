import Foundation
@testable import MIKAN

/// JSON shapes taken from docs/API.md (with "..." filled in). `<T>` is replaced by an instant,
/// either with milliseconds (`2026-10-15T11:00:00.000Z`) or without (`2026-10-15T11:00:00Z`).
enum Fixtures {
    static let fractionalInstant = "2026-10-15T11:00:00.000Z"
    static let wholeInstant = "2026-10-15T11:00:00Z"
    /// 2026-10-15 11:00:00 UTC
    static let referenceDate = Date(timeIntervalSince1970: 1_792_062_000)

    static func json(_ template: String, fractional: Bool) -> Data {
        Data(template.replacingOccurrences(of: "<T>", with: fractional ? fractionalInstant : wholeInstant).utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ template: String, fractional: Bool = true) throws -> T {
        try JSONCoding.makeDecoder().decode(T.self, from: json(template, fractional: fractional))
    }

    static let employeeRef = ##"{ "id": 2, "name": "Анна", "color": "#FF7A1A" }"##
    static let clientRef = #"{ "id": 1, "name": "Иван", "lastName": "Петров", "phone": "+79991234567", "telegramLinked": true }"#
    /// A ClientRef from a server without last names.
    static let legacyClientRef = #"{ "id": 1, "name": "Иван Петров", "phone": "+79991234567", "telegramLinked": true }"#
    static let serviceRef = #"{ "id": 3, "name": "Прокол мочки", "category": "piercing" }"#

    static let employee = #"""
    { "id": 1, "name": "Анна", "login": "anna", "phone": "+79991234567", "color": "#FF7A1A",
      "isMaster": true, "active": true, "createdAt": "<T>" }
    """#

    static let clientInList = #"""
    { "id": 1, "name": "Иван", "lastName": "Петров", "phone": "+79991234567", "instagram": "ivan.p",
      "telegramNick": "ivan_petrov", "birthday": "1995-04-12", "notes": "Аллергия на никель", "source": "instagram",
      "telegramLinked": true, "telegramUsername": "ivanp", "botEnabled": true,
      "archived": false, "createdAt": "<T>", "updatedAt": "<T>",
      "stats": null }
    """#

    static let clientWithStats = #"""
    { "id": 1, "name": "Иван Петров", "phone": null, "instagram": null,
      "birthday": null, "notes": null, "source": null,
      "telegramLinked": false, "telegramUsername": null, "botEnabled": true,
      "archived": false, "createdAt": "<T>", "updatedAt": "<T>",
      "stats": { "visits": 3, "totalSpent": 25000, "lastVisitAt": "<T>", "upcomingAppointments": 1 } }
    """#

    static let service = #"""
    { "id": 1, "name": "Прокол мочки", "category": "piercing", "price": 2500, "priceFrom": false,
      "durationMin": 30, "description": "Текст для бота и сотрудников", "aftercareTemplateId": 2,
      "active": true, "sort": 0 }
    """#

    static let aftercareTemplate = #"""
    { "id": 1, "name": "Уход за татуировкой", "category": "tattoo",
      "steps": [ { "dayOffset": 0, "text": "Снимите плёнку" }, { "dayOffset": 1, "text": "Крем" }, { "dayOffset": 7, "text": "Как дела?" } ],
      "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    /// A product from a server that predates sizes (the app reads it as one size).
    static let product = #"""
    { "id": 1, "kind": "jewelry", "name": "Лабрет", "sku": "LB-12-08", "category": "Лабрет",
      "material": "Титан G23", "size": "1.2×8 мм", "description": "Описание",
      "price": 1500, "cost": 600, "quantity": 12, "minQuantity": 3, "unit": "шт",
      "photoUrl": "/uploads/3f1c.jpg", "active": true, "lowStock": false,
      "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let stockMovement = #"""
    { "id": 1, "productId": 1, "productName": "Лабрет", "delta": -1, "quantityAfter": 11,
      "type": "sale", "note": null, "saleId": 5, "appointmentId": null,
      "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "<T>" }
    """#

    static let appointment = #"""
    { "id": 1, "client": \#(clientRef), "master": \#(employeeRef), "service": \#(serviceRef),
      "title": "Тату на предплечье, эскиз согласован", "startsAt": "<T>", "endsAt": "<T>",
      "status": "no_show", "price": 8000, "deposit": 2000, "notes": "Заметка",
      "saleId": null, "completedAt": null, "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let appointmentWithoutService = #"""
    { "id": 2, "client": \#(clientRef), "master": \#(employeeRef), "service": null,
      "title": null, "startsAt": "<T>", "endsAt": "<T>",
      "status": "scheduled", "price": 0, "deposit": 0, "notes": null,
      "saleId": 7, "completedAt": "<T>", "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let depositReceive = #"""
    { "id": 7, "appointmentId": 4, "type": "receive", "amount": 2000, "method": "transfer",
      "saleId": null, "shiftId": 3, "qrPaymentId": null, "note": null,
      "employee": \#(employeeRef), "createdAt": "<T>" }
    """#

    static let depositApply = #"""
    { "id": 8, "appointmentId": 4, "type": "apply", "amount": 2000, "method": null,
      "saleId": 1, "shiftId": null, "qrPaymentId": null, "note": null, "employee": null, "createdAt": "<T>" }
    """#

    static let qrPaymentDeposit = #"""
    { "id": 6, "kind": "deposit", "appointmentId": 4, "status": "paid", "amount": 2000,
      "payload": "https://qr.nspk.ru/AD10001B38T99KA99CD8S37FMTH8CFQ7",
      "expiresAt": "<T>", "sentAt": "<T>", "error": null, "sale": null, "createdAt": "<T>" }
    """#

    /// Prepayment of 2 000 ₽ received by transfer and held; the latest QR link for it is paid.
    static let appointmentWithDeposit = #"""
    { "id": 4, "client": \#(clientRef), "master": \#(employeeRef), "service": \#(serviceRef), "services": [],
      "title": null, "startsAt": "<T>", "endsAt": "<T>",
      "status": "confirmed", "price": 8000, "notes": null,
      "deposit": 2000, "depositRequired": 2000, "depositStatus": "paid",
      "depositOperations": [ \#(depositReceive) ], "depositLink": \#(qrPaymentDeposit),
      "saleId": null, "completedAt": null, "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let sale = #"""
    { "id": 1, "number": 17, "client": \#(clientRef), "employee": \#(employeeRef),
      "appointmentId": null, "shiftId": 3,
      "items": [ { "id": 1, "type": "product", "productId": 1, "serviceId": null,
                   "name": "Лабрет", "quantity": 1, "price": 1500, "total": 1500 } ],
      "subtotal": 1500, "discount": 0, "total": 1500,
      "payments": { "cash": 1500, "card": 0, "transfer": 0 },
      "status": "completed", "note": null, "refundedAt": null, "refundReason": null, "createdAt": "<T>" }
    """#

    /// Pays for appointment 4: 2 000 ₽ of the total comes from its prepayment.
    static let saleWithDeposit = #"""
    { "id": 3, "number": 19, "client": \#(clientRef), "employee": \#(employeeRef),
      "appointmentId": 4, "shiftId": 3,
      "items": [ { "id": 4, "type": "service", "productId": null, "serviceId": 3,
                   "name": "Прокол мочки", "quantity": 1, "price": 8000, "total": 8000 } ],
      "subtotal": 8000, "discount": 0, "total": 8000,
      "payments": { "cash": 6000, "card": 0, "transfer": 0, "qr": 0, "deposit": 2000 },
      "status": "completed", "note": null, "refundedAt": null, "refundReason": null, "createdAt": "<T>" }
    """#

    static let qrPaymentPending = #"""
    { "id": 5, "status": "pending", "amount": 3000,
      "payload": "https://qr.nspk.ru/AD10001B38T99KA99CD8S37FMTH8CFQ7?type=02&bank=100000000065&sum=300000&cur=RUB&crc=43B6",
      "expiresAt": "<T>", "error": null, "sale": null, "createdAt": "<T>" }
    """#

    static let qrPaymentPaid = #"""
    { "id": 5, "status": "paid", "amount": 1500, "payload": "https://qr.nspk.ru/AD10001B38T99KA99CD8S37FMTH8CFQ7",
      "expiresAt": "<T>", "error": null, "createdAt": "<T>",
      "sale": { "id": 2, "number": 18, "client": null, "employee": \#(employeeRef),
                "appointmentId": null, "shiftId": null, "items": [], "subtotal": 1500, "discount": 0, "total": 1500,
                "payments": { "cash": 0, "card": 0, "transfer": 0, "qr": 1500 },
                "status": "completed", "note": null, "refundedAt": null, "refundReason": null, "createdAt": "<T>" } }
    """#

    static let cashOperation = #"""
    { "id": 1, "shiftId": 3, "type": "out", "amount": 1000, "reason": "Инкассация",
      "employee": \#(employeeRef), "createdAt": "<T>" }
    """#

    static let cashShift = #"""
    { "id": 3, "openedAt": "<T>", "openedBy": \#(employeeRef), "openingCash": 5000,
      "closedAt": null, "closedBy": null, "closingCash": null, "note": null,
      "expectedCash": 7500, "difference": null,
      "summary": { "salesCount": 3, "revenue": 10000, "cash": 2500, "card": 5000, "transfer": 2500,
                   "refunds": 0, "cashRefunds": 0, "cashIn": 0, "cashOut": 0 },
      "operations": [ \#(cashOperation) ] }
    """#

    /// docs/API.md example; `expectedCash` follows the documented formula (5000 + 2500 + 1000).
    static let cashShiftWithDeposits = #"""
    { "id": 3, "openedAt": "<T>", "openedBy": \#(employeeRef), "openingCash": 5000,
      "closedAt": null, "closedBy": null, "closingCash": null, "note": null,
      "expectedCash": 8500, "difference": null,
      "summary": { "salesCount": 3, "revenue": 10000, "cash": 2500, "card": 5000, "transfer": 0, "qr": 0, "deposit": 2500,
                   "refunds": 0, "cashRefunds": 0, "cashIn": 0, "cashOut": 0,
                   "deposits": { "received": 3000, "cash": 1000, "card": 0, "transfer": 2000, "qr": 0,
                                 "refunded": 0, "cashRefunded": 0, "retained": 0 } },
      "operations": [] }
    """#

    static let botMessage = #"""
    { "id": 1, "chatId": 123456789, "role": "user", "text": "Сколько стоит прокол хеликса?",
      "employee": null, "createdAt": "<T>" }
    """#

    static let botChat = #"""
    { "chatId": 123456789, "client": \#(clientRef), "telegramName": "Иван", "username": "ivanp",
      "aiPaused": false, "needsAttention": false, "unreadCount": 2,
      "lastMessage": \#(botMessage), "updatedAt": "<T>" }
    """#

    /// A chat whose shared contact matched an employee's phone.
    static let staffBotChat = #"""
    { "chatId": 987654321, "client": null, "telegramName": "Аня", "username": "anna_mikan",
      "aiPaused": false, "needsAttention": false, "unreadCount": 0,
      "lastMessage": null, "updatedAt": "<T>", "employee": \#(employeeRef) }
    """#

    static let scheduledMessage = #"""
    { "id": 1, "chatId": 123456789, "client": \#(clientRef), "appointmentId": 4,
      "kind": "aftercare", "sendAt": "<T>", "text": "Памятка",
      "status": "pending", "sentAt": null, "error": null }
    """#

    static let bookingRequest = #"""
    { "id": 1, "chatId": 123456789, "client": null, "contactName": "Иван",
      "phone": "+79991234567", "serviceName": "Прокол хеликса", "preferredTime": "в субботу после 15:00",
      "comment": "Комментарий", "status": "new", "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let knowledgeEntry = #"""
    { "id": 1, "title": "Противопоказания", "content": "Текст", "active": true, "sort": 0, "updatedAt": "<T>" }
    """#

    static let studioSettings = #"""
    { "name": "MIKAN STUDIO", "address": "", "phone": "", "workingHours": "Ежедневно 11:00–21:00",
      "instagram": "", "website": "", "about": "", "timezone": "Europe/Moscow",
      "workdayStart": "10:00", "workdayEnd": "21:00" }
    """#

    static let botSettings = #"""
    { "enabled": true, "aiEnabled": true, "greeting": "Привет", "extraInstructions": "",
      "aftercareHour": 12, "remindersEnabled": true, "reminderHoursBefore": 24,
      "botUsername": "mikan_studio_bot", "staffChatBound": false, "aiConfigured": true }
    """#

    /// Several reminders: a day and two hours before (`reminderHoursBefore` = the first one, for older builds).
    static let botSettingsWithOffsets = #"""
    { "enabled": true, "aiEnabled": true, "greeting": "Привет", "extraInstructions": "",
      "aftercareHour": 12, "remindersEnabled": true, "reminderOffsets": [120, 1440], "reminderHoursBefore": 24,
      "botUsername": "mikan_studio_bot", "staffChatBound": true, "aiConfigured": true }
    """#

    static let badges = #"{ "unreadChats": 2, "needsAttention": 1, "newBookingRequests": 1, "lowStock": 3 }"#

    static let dashboard = #"""
    { "date": "2026-10-15", "appointments": [ \#(appointment) ], "revenueToday": 12000,
      "salesCountToday": 4, "openShift": \#(cashShift), "badges": \#(badges) }
    """#

    static let report = #"""
    { "from": "<T>", "to": "<T>",
      "revenue": 120000, "salesCount": 40, "averageCheck": 3000, "refunds": 2500,
      "payments": { "cash": 30000, "card": 70000, "transfer": 20000 },
      "servicesRevenue": 90000, "productsRevenue": 30000,
      "byDay": [ { "date": "2026-10-01", "revenue": 8000, "salesCount": 3 } ],
      "topProducts": [ { "productId": 1, "name": "Лабрет", "quantity": 7, "revenue": 10500 } ],
      "topServices": [ { "serviceId": 3, "name": "Прокол мочки", "quantity": 12, "revenue": 30000 } ],
      "byMaster": [ { "employee": \#(employeeRef), "appointmentsCompleted": 10, "revenue": 50000 } ],
      "newClients": 14, "appointmentsCompleted": 35, "noShows": 2 }
    """#

    static let reportWithDeposits = #"""
    { "from": "<T>", "to": "<T>",
      "revenue": 120000, "salesCount": 40, "averageCheck": 3000, "refunds": 2500,
      "payments": { "cash": 30000, "card": 0, "transfer": 20000, "qr": 60000, "deposit": 10000 },
      "deposits": { "received": 15000, "cash": 2000, "card": 0, "transfer": 3000, "qr": 10000,
                    "applied": 10000, "refunded": 1000, "retained": 2000, "held": 7000 },
      "servicesRevenue": 90000, "productsRevenue": 30000,
      "byDay": [], "topProducts": [], "topServices": [], "byMaster": [],
      "newClients": 14, "appointmentsCompleted": 35, "noShows": 2 }
    """#
}
