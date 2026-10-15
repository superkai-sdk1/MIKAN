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
    var lines: [CartLine] = []
    var client: ClientRef?
    private(set) var appointmentId: Int?
    var discount = 0
    var split = PaymentSplit()
    /// Deposit already received for the appointment; pre-filled into `transfer`.
    private(set) var deposit = 0
    var note = ""
    var isCheckoutPresented = false
    /// Kept while the sale body is unchanged (retries after a lost response), renewed when the cart changes,
    /// reset when the cart is cleared.
    @ObservationIgnored private var saleKey = IdempotencyKey()

    var isEmpty: Bool { lines.isEmpty }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    var subtotal: Int { lines.reduce(0) { $0 + $1.total } }
    var total: Int { CheckoutRules.total(subtotal: subtotal, discount: discount) }
    var remaining: Int { split.remaining(for: total) }
    var isDiscountValid: Bool { CheckoutRules.isDiscountValid(discount, subtotal: subtotal) }

    var canSubmit: Bool {
        CheckoutRules.canSubmit(
            lineCount: lines.count,
            linesValid: lines.allSatisfy(\.isValid),
            subtotal: subtotal,
            discount: discount,
            split: split
        )
    }

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

    func applyOneTap(_ method: PaymentMethod) {
        split = deposit > 0
            ? PaymentSplit.oneTap(method, total: total, deposit: deposit)
            : PaymentSplit.all(method, total: total)
    }

    /// Fills the cart from a completed appointment: its service lines (see `serviceLines(for:)`),
    /// the client, the appointment link and the deposit pre-filled into the transfer payment.
    func prefill(from appointment: Appointment) {
        clear()
        lines = Self.serviceLines(for: appointment)
        client = appointment.client
        appointmentId = appointment.id
        deposit = min(max(0, appointment.deposit), appointment.price)
        split = PaymentSplit(cash: 0, card: 0, transfer: deposit)
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

    func clear() {
        saleKey.reset()
        lines = []
        client = nil
        appointmentId = nil
        discount = 0
        split = PaymentSplit()
        deposit = 0
        note = ""
    }
}
