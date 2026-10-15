import SwiftUI

// Pure prepayment logic shared by the appointment card, the calendar and the prepayment screen.

/// Symbols of the prepayment UI.
enum DepositStyle {
    /// Prepayment in general (service card, sections).
    static let symbol = "rublesign.circle"
    /// Prepayment held for an appointment (calendar mark).
    static let heldSymbol = "rublesign.circle.fill"
    /// Waiting for the client to pay (calendar mark).
    static let waitingSymbol = "hourglass"
}

extension DepositStatus {
    var title: String {
        switch self {
        case .none: "Не внесена"
        case .waiting: "Ждём"
        case .paid: "Внесена"
        case .applied: "Зачтена в чеке"
        case .refunded: "Возвращена"
        case .retained: "Удержана"
        }
    }

    var color: Color {
        switch self {
        case .none: .gray
        case .waiting: .orange
        case .paid: .green
        case .applied: .blue
        case .refunded: .gray
        case .retained: .purple
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .waiting: DepositStyle.waitingSymbol
        case .paid: "checkmark.circle.fill"
        case .applied: "receipt"
        case .refunded: "arrow.uturn.backward.circle"
        case .retained: "lock.fill"
        }
    }
}

// MARK: - Amounts

enum DepositSummary {
    /// What is still to be paid: required − held, never negative.
    static func missing(_ appointment: Appointment) -> Int {
        max(0, appointment.depositRequired - appointment.deposit)
    }

    /// The appointment card shows the prepayment block.
    static func showsSection(_ appointment: Appointment) -> Bool {
        appointment.depositRequired > 0 || !appointment.depositOperations.isEmpty
    }

    /// Right after creating: the prepayment screen opens instead of closing the editor.
    static func asksForDeposit(afterCreating appointment: Appointment) -> Bool {
        appointment.isOpen && missing(appointment) > 0
    }

    /// «Внесено 1 000 из 2 000 ₽», or what became of the prepayment once nothing is held.
    static func headline(_ appointment: Appointment) -> String {
        let held = appointment.deposit
        let required = appointment.depositRequired
        if held > 0 || appointment.depositStatus == .waiting || appointment.depositOperations.isEmpty {
            return progressText(held: held, required: required)
        }
        let operations = appointment.depositOperations
        switch appointment.depositStatus {
        case .applied:
            return "Зачтено в чеке \(Money.format(total(of: .apply, in: operations) - total(of: .unapply, in: operations)))"
        case .refunded:
            return "Возвращено \(Money.format(total(of: .refund, in: operations)))"
        case .retained:
            return "Удержано \(Money.format(total(of: .retain, in: operations)))"
        case .none, .waiting, .paid:
            return progressText(held: held, required: required)
        }
    }

    /// «Внесено 1 000 из 2 000 ₽»; «Внесено 1 000 ₽» when nothing is required.
    static func progressText(held: Int, required: Int) -> String {
        guard required > 0 else { return "Внесено \(Money.format(held))" }
        return "Внесено \(Money.group(UInt(max(0, held)))) из \(Money.format(required))"
    }

    /// How the client paid last time: the default way to return the money.
    static func latestReceiveMethod(_ operations: [DepositOperation]) -> PaymentMethod? {
        operations.last { $0.type == .receive && $0.method != nil }?.method
    }

    private static func total(of type: DepositOperationType, in operations: [DepositOperation]) -> Int {
        operations.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Calendar mark

/// Prepayment mark of an appointment in the calendar and lists.
enum DepositMark: Equatable {
    /// The whole required prepayment (or more) is held.
    case held(Int)
    /// Part of the required prepayment is held.
    case partial(held: Int, required: Int)
    /// Required, nothing received yet, appointment still open.
    case waiting(Int)

    static func of(_ appointment: Appointment) -> DepositMark? {
        let held = appointment.deposit
        let required = appointment.depositRequired
        if held > 0 {
            return held < required ? .partial(held: held, required: required) : .held(held)
        }
        if appointment.depositStatus == .waiting, required > 0 {
            return .waiting(required)
        }
        return nil
    }

    /// «Предоплата внесена 2 000 ₽», «Ждём предоплату 2 000 ₽».
    var text: String {
        switch self {
        case .held(let amount): "Предоплата внесена \(Money.format(amount))"
        case .partial(let held, let required): "Предоплата внесена \(Money.group(UInt(held))) из \(Money.format(required))"
        case .waiting(let amount): "Ждём предоплату \(Money.format(amount))"
        }
    }

    var accessibilityText: String {
        switch self {
        case .held: "предоплата внесена"
        case .partial: "предоплата внесена частично"
        case .waiting: "ждём предоплату"
        }
    }

    var symbol: String {
        switch self {
        case .held, .partial: DepositStyle.heldSymbol
        case .waiting: DepositStyle.waitingSymbol
        }
    }

    var color: Color {
        switch self {
        case .held, .partial: .green
        case .waiting: .orange
        }
    }
}

// MARK: - Ledger

enum DepositLedger {
    /// «Получена переводом», «Зачтена в чеке», «Возвращена наличными», «Удержана: Неявка».
    static func title(for operation: DepositOperation) -> String {
        switch operation.type {
        case .receive: operation.method.map { "Получена \($0.instrumental)" } ?? "Получена"
        case .apply: "Зачтена в чеке"
        case .unapply: "Чек возвращён — предоплата снова за записью"
        case .refund: operation.method.map { "Возвращена \($0.instrumental)" } ?? "Возвращена"
        case .retain: operation.note.nonEmpty.map { "Удержана: \($0)" } ?? "Удержана"
        }
    }

    /// «15 окт., 14:05 · Анна · комментарий» (a retain reason is already in the title).
    static func detail(for operation: DepositOperation) -> String {
        var parts = [DateText.dateTime(operation.createdAt)]
        if let name = operation.employee?.name.nonEmpty {
            parts.append(name)
        }
        if operation.type != .retain, let note = operation.note.nonEmpty {
            parts.append(note)
        }
        return parts.joined(separator: " · ")
    }

    /// How the operation changed the held amount: + received or returned by a sale refund, − otherwise.
    static func heldDelta(for operation: DepositOperation) -> Int {
        switch operation.type {
        case .receive, .unapply: operation.amount
        case .apply, .refund, .retain: -operation.amount
        }
    }

    static func symbol(for operation: DepositOperation) -> String {
        switch operation.type {
        case .receive: operation.method?.symbol ?? "arrow.down.circle"
        case .apply: "receipt"
        case .unapply: "arrow.uturn.backward"
        case .refund: "arrow.uturn.backward.circle"
        case .retain: "lock.fill"
        }
    }
}

// MARK: - Actions

/// Prepayment actions of the appointment card.
enum DepositFlow: Hashable {
    /// «Принять предоплату» / «Новая ссылка / QR»: the prepayment screen.
    case collect
    /// «Напомнить клиенту»: the bot sends the pending link again (or a fresh one).
    case remind
    /// «Вернуть клиенту».
    case refund
    /// «Удержать» (cancelled / no-show only).
    case retain
    /// Asked right after a cancellation / no-show of an appointment that holds a prepayment; not a button.
    case decide

    /// Buttons of the card, in display order.
    static func available(for appointment: Appointment, qrEnabled: Bool) -> [DepositFlow] {
        var result: [DepositFlow] = []
        if appointment.isOpen {
            result.append(.collect)
            if qrEnabled, DepositSummary.missing(appointment) > 0 {
                result.append(.remind)
            }
        }
        if appointment.deposit > 0 {
            result.append(.refund)
            if isClosedWithoutVisit(appointment.status) {
                result.append(.retain)
            }
        }
        return result
    }

    /// Cancelled or no-show while holding a prepayment: staff decide to refund or retain it.
    static func needsDecision(_ appointment: Appointment) -> Bool {
        appointment.deposit > 0 && isClosedWithoutVisit(appointment.status)
    }

    private static func isClosedWithoutVisit(_ status: AppointmentStatus) -> Bool {
        status == .cancelled || status == .noShow
    }
}

// MARK: - Link

/// What the appointment card says about the latest prepayment QR code.
enum DepositLinkNote: Equatable {
    case pending(amount: Int, sentAt: Date?, expiresAt: Date)
    /// Only while there is something left to pay.
    case expired(Date)
    case cancelled
    /// Paid, but the server flagged it (paid after cancel, above the required amount…).
    case paidWithIssue(String)

    static func of(_ appointment: Appointment) -> DepositLinkNote? {
        guard let link = appointment.depositLink else { return nil }
        let stillWaiting = appointment.isOpen && DepositSummary.missing(appointment) > 0
        switch link.status {
        case .pending: return .pending(amount: link.amount, sentAt: link.sentAt, expiresAt: link.expiresAt)
        case .expired: return stillWaiting ? .expired(link.expiresAt) : nil
        case .cancelled: return stillWaiting ? .cancelled : nil
        case .paid: return link.error.nonEmpty.map(DepositLinkNote.paidWithIssue)
        }
    }

    /// «Ссылка отправлена 15 окт., 14:00 · действует до 18 окт., 14:00».
    var text: String {
        switch self {
        case .pending(_, let sentAt?, let expiresAt):
            "Ссылка отправлена \(DateText.dateTime(sentAt)) · действует до \(DateText.dateTime(expiresAt))"
        case .pending(_, nil, let expiresAt):
            "Ссылка не отправлена · действует до \(DateText.dateTime(expiresAt))"
        case .expired(let expiresAt):
            "Срок ссылки истёк \(DateText.dateTime(expiresAt))"
        case .cancelled:
            "Ссылка на оплату отменена"
        case .paidWithIssue(let message):
            message
        }
    }

    /// The card offers a fresh link / QR code.
    var offersNewLink: Bool {
        switch self {
        case .expired, .cancelled: true
        case .pending, .paidWithIssue: false
        }
    }
}

// MARK: - Texts

enum DepositText {
    /// What staff send the client with «Поделиться ссылкой».
    static func shareMessage(amount: Int, startsAt: Date, payload: String) -> String {
        "Предоплата за запись \(DateText.dayMonth(startsAt)) в \(DateText.time(startsAt)) — \(Money.format(amount)). "
            + "Оплатить через СБП: \(payload)"
    }

    /// Stored as the retain operation note.
    static func retainReason(for status: AppointmentStatus) -> String {
        status == .noShow ? "Неявка" : "Отмена записи"
    }

    /// Alert after «Напомнить клиенту».
    static func remindNotice(_ result: DepositLinkResult) -> (title: String, message: String) {
        let link = "Ссылка на \(Money.format(result.payment.amount)) действует до \(DateText.dateTime(result.payment.expiresAt))."
        if let sendError = result.sendError.nonEmpty {
            return ("Напоминание не отправлено", "\(sendError)\n\n\(link) Её можно отправить клиенту другим способом.")
        }
        return ("Напоминание отправлено", "Клиент получил ссылку на оплату в Telegram. \(link)")
    }
}
