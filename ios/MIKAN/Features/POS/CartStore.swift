import Foundation
import Observation

/// The open receipt being edited on this device, shared app-wide so other screens (appointment, client card) can
/// open one. `OpenReceiptsStore` loads it from the server and saves it back after every change.
@Observable
final class CartStore {
    /// UserDefaults key of the single payment method used for the last sale.
    static let lastPaymentMethodKey = "pos.lastPaymentMethod"
    static let defaultPaymentMethod = PaymentMethod.cash

    /// The open receipt (`/receipts/:id`) in the cart; `nil` before one is loaded and once it is paid.
    private(set) var receiptId: Int?
    var lines: [CartLine] = []
    var client: ClientRef?
    /// Appointment this receipt pays for (kept whole: checkout may need to complete it first).
    private(set) var appointment: Appointment?
    var appointmentId: Int? { appointment?.id }
    var discount = 0
    /// Prepayment held for the appointment (received earlier); `depositApplied` of it is counted in this receipt.
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

    /// Bonuses the cashier asked to spend; checkout applies at most `bonusLimit` of them (see `bonusApplied`).
    var bonusRequested = 0
    /// Gift certificates spent at this checkout, in the order they were added.
    private(set) var certificateCharges: [CertificateCharge] = []
    /// The studio's loyalty rules (`GET /settings/retention`); `nil` until checkout loads them.
    private(set) var loyaltyRules: CheckoutLoyaltyRules?
    /// The bonuses and birthday discount of the cart's client, loaded at checkout.
    private(set) var clientLoyalty: CartClientLoyalty?

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

    /// Nothing worth keeping: no lines, no client, no appointment and no note.
    var isBlank: Bool { lines.isEmpty && client == nil && appointment == nil && note.nonEmpty == nil }

    // MARK: Payment

    /// Part of the held prepayment counted in this receipt: `min(held, total)`.
    var depositApplied: Int { CheckoutRules.depositApplied(deposit, total: total) }
    /// What is left after the prepayment: bonuses, certificates and the payment methods cover it.
    var amountAfterDeposit: Int { CheckoutRules.amountDue(total: total, deposit: deposit) }
    /// What the client pays now by the payment methods: total minus the prepayment, bonuses and certificates.
    var amountDue: Int { max(0, amountAfterDeposit - creditsApplied) }
    /// Prepayment that stays held for the appointment after this receipt (more was paid than the receipt costs).
    var depositRemainder: Int { CheckoutRules.depositRemainder(deposit, total: total) }
    /// The prepayment alone covers the whole receipt.
    var isPaidByDeposit: Bool { depositApplied > 0 && amountAfterDeposit == 0 }
    /// Nothing is left for the payment methods: the prepayment, bonuses and certificates cover the whole receipt.
    var isPaidInFull: Bool { amountDue == 0 && depositApplied + creditsApplied > 0 }

    /// How `amountDue` is paid now (the prepayment, bonuses and certificates are not part of it). Empty when they
    /// cover everything (checkout then hides the methods, so amounts typed earlier in «Разделить» must not count).
    var split: PaymentSplit {
        guard !isPaidInFull else { return PaymentSplit() }
        return switch paymentMode {
        case .single(let method): PaymentSplit.single(method, due: amountDue)
        case .split: manualSplit
        }
    }

    /// Payments sent with the sale: the split, the applied prepayment (always sent, 0 when none), bonuses and the
    /// certificates spent.
    var payments: Payments {
        CheckoutCredits.payments(
            split: split, deposit: depositApplied, bonus: bonusApplied,
            charges: certificateCharges, amounts: certificateAmounts
        )
    }

    /// Positive: still to distribute; negative: overpaid. Always 0 in single mode.
    var remaining: Int { split.remaining(for: amountDue) }

    var isCashMode: Bool { paymentMode == .single(.cash) }

    /// Change for `cashReceived`; `nil` outside cash mode, when nothing is due, while the field is empty
    /// or the amount is short.
    var cashChange: Int? {
        guard isCashMode, amountDue > 0 else { return nil }
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
            deposit: deposit,
            credits: creditsApplied,
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

    // MARK: Bonuses and gift certificates (see `CartStore+Loyalty.swift`)

    func setLoyaltyRules(_ rules: CheckoutLoyaltyRules) {
        loyaltyRules = rules
    }

    /// The client's bonuses as `GET /clients/:id` reported them. Bonuses asked for another client are dropped.
    func setClientLoyalty(_ loyalty: ClientLoyalty?, for clientId: Int) {
        if clientLoyalty?.clientId != clientId { bonusRequested = 0 }
        clientLoyalty = loyalty.map { CartClientLoyalty(clientId: clientId, loyalty: $0) }
    }

    /// Adds a looked-up certificate taking `amount` (a second lookup of the same code updates it instead).
    func addCertificateCharge(_ certificate: GiftCertificate, amount: Int) {
        let charge = CertificateCharge(certificate: certificate, amount: amount)
        if let index = certificateCharges.firstIndex(where: { $0.code == charge.code }) {
            certificateCharges[index] = charge
        } else {
            certificateCharges.append(charge)
        }
    }

    /// What was typed is kept; `certificateAmounts` takes at most the balance and what is unpaid.
    func setCertificateAmount(_ amount: Int, code: String) {
        guard let index = certificateCharges.firstIndex(where: { $0.code == code }) else { return }
        certificateCharges[index].amount = max(0, amount)
    }

    func removeCertificateCharge(code: String) {
        certificateCharges.removeAll { $0.code == code }
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
        // No consumables list: the server deducts the norms of the appointment's services.
        return CompleteBody(sendAftercare: sendsAftercare && canSendAftercare, aftercareTemplateId: nil, consumables: nil)
    }

    /// Stores the completed appointment, so a retried checkout skips the completion and sends only the sale.
    func appointmentCompleted(_ completed: Appointment) {
        guard completed.id == appointment?.id else { return }
        appointment = completed
    }

    // MARK: Lines

    /// Units of the product in all its sizes (the catalog tile badge).
    func quantity(ofProduct productId: Int) -> Int {
        lines.filter { $0.productId == productId }.reduce(0) { $0 + $1.quantity }
    }

    /// Units of one size, summed over its lines (an edited price makes a separate line of the same size).
    func quantity(ofVariant variantId: Int) -> Int {
        lines.filter { $0.variantId == variantId }.reduce(0) { $0 + $1.quantity }
    }

    func quantity(ofService serviceId: Int) -> Int {
        lines.filter { $0.kind == .service(id: serviceId) }.reduce(0) { $0 + $1.quantity }
    }

    /// Adds one of a size at its catalog price. A product with one size may come without `variant` (its only size
    /// is sold); a product with several sizes needs one, otherwise nothing is added and the result is `false`.
    /// The same size at the same price bumps the quantity; another size, or a line repriced in the receipt,
    /// is a separate line.
    @discardableResult
    func add(product: Product, variant: ProductVariant? = nil) -> Bool {
        guard let size = Self.size(of: product, variant) else { return false }
        let line = CartLine(
            kind: .product(id: product.id, variantId: size.id, stock: size.quantity),
            name: product.lineName(variant: size),
            sizeName: size.name,
            unitPrice: product.price(of: size),
            productKind: product.kind
        )
        if let index = lines.firstIndex(where: { $0.isSameSize(as: line) && $0.unitPrice == line.unitPrice }) {
            lines[index].quantity += 1
        } else {
            lines.append(line)
        }
        return true
    }

    /// The size to sell: the product's own copy of `variant` (fresh stock), or its only size.
    private static func size(of product: Product, _ variant: ProductVariant?) -> ProductVariant? {
        guard let variant else { return product.hasSeveralSizes ? nil : product.variants.first }
        return product.variant(id: variant.id)
    }

    // MARK: Stock

    /// Units of the line's size in the whole receipt.
    func sizeQuantity(of line: CartLine) -> Int {
        lines.filter { $0.isSameSize(as: line) }.reduce(0) { $0 + $1.quantity }
    }

    /// How many the line may hold so that all lines of its size stay within the stock; `nil` for services.
    func stockLimit(for line: CartLine) -> Int? {
        guard let stock = line.stock else { return nil }
        return stock - (sizeQuantity(of: line) - line.quantity)
    }

    /// All lines of the line's size together ask for more than its stock (the server answers `insufficient_stock`).
    func exceedsStock(_ line: CartLine) -> Bool {
        guard let stock = line.stock else { return false }
        return sizeQuantity(of: line) > stock
    }

    /// «На складе только 1 шт размера 8 мм» under every line of a size that is short; `nil` otherwise.
    func stockWarning(for line: CartLine) -> String? {
        guard let stock = line.stock else { return nil }
        return ReceiptStock.warning(
            stock: stock, inReceipt: sizeQuantity(of: line), lineQuantity: line.quantity, sizeName: line.sizeName
        )
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

    /// «Подарочный сертификат» for `amount` rubles; the sale issues it. Such a receipt is paid with money only.
    func addCertificate(amount: Int, recipientName: String) {
        lines.append(.certificate(amount: amount, recipientName: recipientName))
    }

    func addCustomService(name: String, price: Int) {
        lines.append(CartLine(kind: .service(id: nil), name: name.trimmed, unitPrice: max(0, price)))
    }

    func remove(at offsets: IndexSet) {
        lines.remove(atOffsets: offsets)
    }

    /// Fills the cart from an appointment: its service lines (see `serviceLines(for:)`), the client,
    /// the appointment link and its held prepayment (applied up to the receipt total).
    func prefill(from appointment: Appointment) {
        clear()
        lines = Self.serviceLines(for: appointment)
        client = appointment.client
        self.appointment = appointment
        deposit = max(0, appointment.deposit)
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

    // MARK: Open receipt

    /// Puts a saved open receipt into the cart: its lines, client, appointment with the held prepayment, discount
    /// and note. Reloading the receipt already in the cart keeps the checkout choices (payment, completion, memo).
    func load(_ receipt: OpenReceipt) {
        let isSameReceipt = receipt.id == receiptId
        let kept = (
            paymentMode: paymentMode, manualSplit: manualSplit, cashReceived: cashReceived,
            completesAppointment: completesAppointment, sendsAftercare: sendsAftercare,
            certificateLines: lines.filter(\.isCertificate), bonusRequested: bonusRequested,
            certificateCharges: certificateCharges, clientLoyalty: clientLoyalty
        )
        clear()
        receiptId = receipt.id
        lines = receipt.items.compactMap(CartLine.init(item:))
        client = receipt.client
        appointment = receipt.appointment
        deposit = max(0, receipt.appointment?.deposit ?? 0)
        discount = receipt.discount
        note = receipt.note ?? ""
        sendsAftercare = receipt.appointment?.client.telegramLinked ?? false
        guard isSameReceipt else { return }
        selectPaymentMode(kept.paymentMode)
        manualSplit = kept.manualSplit
        cashReceived = kept.cashReceived
        completesAppointment = kept.completesAppointment
        sendsAftercare = kept.sendsAftercare
        // Certificates to sell live only here (the open receipt does not hold them); spent ones stay chosen.
        lines += kept.certificateLines
        bonusRequested = kept.bonusRequested
        certificateCharges = kept.certificateCharges
        clientLoyalty = kept.clientLoyalty
    }

    /// The whole receipt for `PUT /receipts/:id`. A discount above the lines (being typed, or lines removed) is
    /// saved capped, so the save still goes through; checkout keeps flagging it. A gift certificate to sell is not
    /// part of it: the contract has no certificate lines in open receipts, so it stays in this cart until paid.
    func makeReceiptBody() -> ReceiptBody {
        let saved = lines.filter { !$0.isCertificate }
        return ReceiptBody(
            appointmentId: appointmentId,
            clientId: client?.id,
            items: saved.map(\.body),
            discount: min(max(0, discount), saved.reduce(0) { $0 + $1.total }),
            note: note.nonEmpty
        )
    }

    // MARK: Sale

    func makeSaleBody() -> SaleBody {
        SaleBody(
            clientId: client?.id,
            appointmentId: appointmentId,
            items: lines.map(\.body),
            discount: discount,
            payments: payments,
            note: note.nonEmpty,
            receiptId: receiptId
        )
    }

    func saleIdempotencyKey(for body: SaleBody) -> UUID {
        saleKey.key(for: body)
    }

    /// Call once the sale succeeded: the server deleted the paid receipt, so the cart no longer points at it.
    /// Remembers the single payment method for the next receipts and notifies the hub.
    func recordCompletedSale() {
        receiptId = nil
        if let method = paymentMode.method {
            defaults.set(method.rawValue, forKey: Self.lastPaymentMethodKey)
        }
        salesCompleted += 1
    }

    /// Keeps the lines and the client but stops paying for the appointment: its prepayment stays held for it.
    func detachAppointment() {
        appointment = nil
        deposit = 0
        completesAppointment = true
        sendsAftercare = false
    }

    func clear() {
        saleKey.reset()
        receiptId = nil
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
        bonusRequested = 0
        certificateCharges = []
        clientLoyalty = nil
    }

    /// The last used method, unless the studio no longer takes it (card).
    private static func storedPaymentMethod(in defaults: UserDefaults) -> PaymentMethod {
        let stored = defaults.string(forKey: lastPaymentMethodKey).flatMap(PaymentMethod.init(rawValue:))
        guard let stored, PaymentMethod.accepted(qrEnabled: true).contains(stored) else { return defaultPaymentMethod }
        return stored
    }
}
