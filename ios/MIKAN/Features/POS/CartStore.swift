import Foundation
import Observation

struct CartLine: Identifiable, Hashable {
    enum Kind: Hashable {
        case product(id: Int, stock: Int)
        case service(id: Int?)
    }

    let id: UUID
    let kind: Kind
    var name: String
    var quantity: Int
    var unitPrice: Int

    init(kind: Kind, name: String, quantity: Int = 1, unitPrice: Int) {
        self.id = UUID()
        self.kind = kind
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var total: Int { quantity * unitPrice }

    var productId: Int? {
        if case .product(let id, _) = kind { return id }
        return nil
    }

    var stock: Int? {
        if case .product(_, let stock) = kind { return stock }
        return nil
    }

    var isValid: Bool { quantity > 0 && unitPrice >= 0 && !name.trimmed.isEmpty }

    var exceedsStock: Bool { stock.map { quantity > $0 } ?? false }

    var body: SaleItemBody {
        switch kind {
        case .product(let id, _):
            SaleItemBody(type: .product, productId: id, serviceId: nil, name: nil, quantity: quantity, price: unitPrice)
        case .service(let id):
            SaleItemBody(type: .service, productId: nil, serviceId: id, name: name.trimmed, quantity: quantity, price: unitPrice)
        }
    }
}

/// POS cart shared app-wide, so other screens (appointment, client card) can start a checkout.
@Observable
final class CartStore {
    /// UserDefaults key of the single payment method used for the last sale.
    static let lastPaymentMethodKey = "pos.lastPaymentMethod"
    static let defaultPaymentMethod = PaymentMethod.cash

    var lines: [CartLine] = []
    var client: ClientRef?
    /// Appointment this receipt pays for (kept whole: checkout may need to complete it first).
    private(set) var appointment: Appointment?
    var appointmentId: Int? { appointment?.id }
    var discount = 0
    /// Deposit already received for the appointment; it stays in `transfer` whatever the payment mode.
    private(set) var deposit = 0
    var note = ""
    var isCheckoutPresented = false
    /// Bumped after every successful sale, so the POS hub can reload its lists and pop the receipt screen.
    private(set) var salesCompleted = 0

    /// One method (amount computed from the total) or a manual split. New receipts start with the last used method.
    private(set) var paymentMode: PaymentMode
    /// Amounts typed in the «Разделить» mode.
    var manualSplit = PaymentSplit()
    /// Cash handed over by the client (single cash mode only); used for the change, never sent to the server.
    var cashReceived: Int?

    /// `POST /appointments/:id/complete` before the sale (only while the appointment is not completed yet).
    var completesAppointment = true
    /// Aftercare via the Telegram bot; effective only when the appointment's client has linked the bot.
    var sendsAftercare = false

    /// Kept while the sale body is unchanged (retries after a lost response), renewed when the cart changes,
    /// reset when the cart is cleared.
    @ObservationIgnored private var saleKey = IdempotencyKey()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.paymentMode = .single(Self.storedPaymentMethod(in: defaults))
    }

    var isEmpty: Bool { lines.isEmpty }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    var subtotal: Int { lines.reduce(0) { $0 + $1.total } }
    var total: Int { CheckoutRules.total(subtotal: subtotal, discount: discount) }
    var isDiscountValid: Bool { CheckoutRules.isDiscountValid(discount, subtotal: subtotal) }

    // MARK: Payment

    /// Part of the deposit counted in this receipt (paid by transfer before the visit).
    var depositApplied: Int { CheckoutRules.depositApplied(deposit, total: total) }
    /// What the client still has to pay now: total minus the deposit.
    var amountDue: Int { total - depositApplied }

    /// Payments sent with the sale.
    var split: PaymentSplit {
        switch paymentMode {
        case .single(let method): PaymentSplit.single(method, total: total, deposit: deposit)
        case .split: manualSplit
        }
    }

    /// Positive: still to distribute; negative: overpaid. Always 0 in single mode.
    var remaining: Int { split.remaining(for: total) }

    var isCashMode: Bool { paymentMode == .single(.cash) }

    /// Change for `cashReceived`; `nil` outside cash mode, while the field is empty or the amount is short.
    var cashChange: Int? {
        guard isCashMode else { return nil }
        return CashTender.change(received: cashReceived, due: amountDue)
    }

    /// False when the cashier entered a received amount smaller than what is due.
    var isCashReceivedEnough: Bool {
        guard isCashMode else { return true }
        return CashTender.isEnough(received: cashReceived, due: amountDue)
    }

    var canSubmit: Bool {
        CheckoutRules.canSubmit(
            lineCount: lines.count,
            linesValid: lines.allSatisfy(\.isValid),
            subtotal: subtotal,
            discount: discount,
            split: split
        ) && isCashReceivedEnough
    }

    /// Switching to «Разделить» starts from the amounts of the current mode, so only the difference needs typing.
    func selectPaymentMode(_ mode: PaymentMode) {
        guard mode != paymentMode else { return }
        if mode == .split {
            manualSplit = split
        }
        paymentMode = mode
    }

    /// Puts what is left to distribute into `method` (or takes an overpayment back from it, never below 0).
    func fillRemaining(with method: PaymentMethod) {
        manualSplit[method] = max(0, manualSplit[method] + remaining)
    }

    /// The server takes no QR payments: a remembered «QR СБП» falls back to the default method.
    func dropQrIfUnavailable(qrEnabled: Bool) {
        guard !qrEnabled, paymentMode == .single(.qr) else { return }
        paymentMode = .single(Self.defaultPaymentMethod)
    }

    /// The bank took the QR share but the server could not sell the cart: the money is already on the account,
    /// so staff finish the sale with it recorded as a transfer.
    func moveQrShareToTransfer() {
        if paymentMode == .single(.qr) {
            paymentMode = .single(.transfer)
        } else {
            manualSplit.transfer += manualSplit.qr
            manualSplit.qr = 0
        }
    }

    // MARK: Appointment

    /// The appointment still has to be completed: checkout shows the «Запись» section.
    var hasPendingAppointment: Bool {
        guard let appointment else { return false }
        return appointment.status != .completed
    }

    var canSendAftercare: Bool { appointment?.client.telegramLinked ?? false }

    /// Body for `POST /appointments/:id/complete`, or `nil` when checkout should go straight to the sale.
    func makeCompleteBody() -> CompleteBody? {
        guard hasPendingAppointment, completesAppointment else { return nil }
        return CompleteBody(sendAftercare: sendsAftercare && canSendAftercare, aftercareTemplateId: nil, consumables: [])
    }

    /// Stores the completed appointment, so a retried checkout skips the completion and sends only the sale.
    func appointmentCompleted(_ completed: Appointment) {
        guard completed.id == appointment?.id else { return }
        appointment = completed
    }

    // MARK: Lines

    func quantity(ofProduct productId: Int) -> Int {
        lines.filter { $0.productId == productId }.reduce(0) { $0 + $1.quantity }
    }

    func quantity(ofService serviceId: Int) -> Int {
        lines.filter { $0.kind == .service(id: serviceId) }.reduce(0) { $0 + $1.quantity }
    }

    func add(product: Product) {
        if let index = lines.firstIndex(where: { $0.productId == product.id }) {
            lines[index].quantity += 1
        } else {
            lines.append(CartLine(kind: .product(id: product.id, stock: product.quantity), name: product.name, unitPrice: product.price))
        }
    }

    /// Adds a catalog service (or one of its variants) at its catalog price. Repeating the same service
    /// at the same price bumps the quantity; a line whose price was edited in the receipt stays separate.
    func add(service: Service, variant: ServiceVariant? = nil) {
        let line = CartLine(
            kind: .service(id: service.id),
            name: service.lineName(variant: variant),
            unitPrice: variant?.price ?? service.price
        )
        if let index = lines.firstIndex(where: { $0.kind == line.kind && $0.name == line.name && $0.unitPrice == line.unitPrice }) {
            lines[index].quantity += 1
        } else {
            lines.append(line)
        }
    }

    func addCustomService(name: String, price: Int) {
        lines.append(CartLine(kind: .service(id: nil), name: name.trimmed, unitPrice: max(0, price)))
    }

    func remove(at offsets: IndexSet) {
        lines.remove(atOffsets: offsets)
    }

    /// Fills the cart from an appointment: its service lines (see `serviceLines(for:)`), the client,
    /// the appointment link and its deposit (kept in `transfer`).
    func prefill(from appointment: Appointment) {
        clear()
        lines = Self.serviceLines(for: appointment)
        client = appointment.client
        self.appointment = appointment
        deposit = min(max(0, appointment.deposit), appointment.price)
        sendsAftercare = appointment.client.telegramLinked
    }

    /// One line per booked service when their prices add up to the appointment price; otherwise
    /// (no lines, or the price was changed for the whole appointment) a single line at the appointment price.
    static func serviceLines(for appointment: Appointment) -> [CartLine] {
        let booked = appointment.services
        let bookedSum = booked.reduce(0) { $0 + $1.price }
        guard !booked.isEmpty, bookedSum == appointment.price else {
            return [CartLine(
                kind: .service(id: appointment.service?.id),
                name: appointment.displayTitle,
                unitPrice: appointment.price
            )]
        }
        return booked.map { CartLine(kind: .service(id: $0.serviceId), name: $0.name, unitPrice: $0.price) }
    }

    // MARK: Sale

    func makeSaleBody() -> SaleBody {
        SaleBody(
            clientId: client?.id,
            appointmentId: appointmentId,
            items: lines.map(\.body),
            discount: discount,
            payments: split.payments,
            note: note.nonEmpty
        )
    }

    func saleIdempotencyKey(for body: SaleBody) -> UUID {
        saleKey.key(for: body)
    }

    /// Call once the sale succeeded: remembers the single payment method for the next receipts and notifies the hub.
    func recordCompletedSale() {
        if let method = paymentMode.method {
            defaults.set(method.rawValue, forKey: Self.lastPaymentMethodKey)
        }
        salesCompleted += 1
    }

    /// Keeps the lines and the client but stops paying for the appointment (and drops its deposit).
    func detachAppointment() {
        if paymentMode == .split {
            manualSplit.transfer = max(0, manualSplit.transfer - depositApplied)
        }
        appointment = nil
        deposit = 0
        completesAppointment = true
        sendsAftercare = false
    }

    func clear() {
        saleKey.reset()
        lines = []
        client = nil
        appointment = nil
        discount = 0
        deposit = 0
        note = ""
        paymentMode = .single(Self.storedPaymentMethod(in: defaults))
        manualSplit = PaymentSplit()
        cashReceived = nil
        completesAppointment = true
        sendsAftercare = false
    }

    /// The last used method, unless the studio no longer takes it (card).
    private static func storedPaymentMethod(in defaults: UserDefaults) -> PaymentMethod {
        let stored = defaults.string(forKey: lastPaymentMethodKey).flatMap(PaymentMethod.init(rawValue:))
        guard let stored, PaymentMethod.accepted(qrEnabled: true).contains(stored) else { return defaultPaymentMethod }
        return stored
    }
}
