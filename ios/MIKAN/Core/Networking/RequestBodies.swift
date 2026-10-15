import Foundation

/// Optional value that encodes `nil` as an explicit JSON `null` (instead of omitting the key),
/// so PATCH requests can clear fields.
nonisolated struct Nullable<Value: Encodable & Sendable>: Encodable, Sendable, ExpressibleByNilLiteral {
    let value: Value?

    init(_ value: Value?) {
        self.value = value
    }

    init(nilLiteral: ()) {
        self.value = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

nonisolated struct LoginBody: Encodable, Sendable {
    let login: String
    let password: String
}

nonisolated struct EmployeeBody: Encodable, Sendable {
    var name: String
    var login: String
    /// Omitted when not changing the password.
    var password: String?
    var phone: Nullable<String>
    var color: Nullable<String>
    var isMaster: Bool
    var active: Bool?
}

nonisolated struct ClientBody: Encodable, Sendable {
    var name: String
    var phone: Nullable<String>
    var instagram: Nullable<String>
    var birthday: Nullable<String>
    var notes: Nullable<String>
    var source: Nullable<String>
    var botEnabled: Bool
}

nonisolated struct ArchiveBody: Encodable, Sendable {
    let archived: Bool
}

nonisolated struct ServiceBody: Encodable, Sendable {
    var name: String
    var category: ServiceCategory
    var price: Int
    var priceFrom: Bool
    var durationMin: Int
    var description: Nullable<String>
    var aftercareTemplateId: Nullable<Int>
    var active: Bool
    var sort: Int
}

nonisolated struct AftercareTemplateBody: Encodable, Sendable {
    var name: String
    var category: ServiceCategory
    var steps: [AftercareStep]
}

nonisolated struct ProductBody: Encodable, Sendable {
    var kind: ProductKind
    var name: String
    var sku: Nullable<String>
    var category: Nullable<String>
    var material: Nullable<String>
    var size: Nullable<String>
    var description: Nullable<String>
    var price: Int
    var cost: Nullable<Int>
    var minQuantity: Int
    var unit: String
    var photoUrl: Nullable<String>
    var active: Bool
    /// Create only; omitted on PATCH.
    var initialQuantity: Int?
}

nonisolated struct MovementBody: Encodable, Sendable {
    let type: MovementType
    let quantity: Int
    var note: Nullable<String>
}

nonisolated struct AppointmentBody: Encodable, Sendable {
    var clientId: Int
    var masterId: Int
    var serviceId: Nullable<Int>
    var title: Nullable<String>
    var startsAt: Date
    var endsAt: Date
    var price: Int
    var deposit: Int
    var notes: Nullable<String>
    /// Omitted unless the user confirmed saving despite a schedule conflict.
    var force: Bool?
}

nonisolated struct StatusBody<Status: Encodable & Sendable>: Encodable, Sendable {
    let status: Status
}

nonisolated struct ConsumableUse: Encodable, Hashable, Sendable {
    let productId: Int
    let quantity: Int
}

nonisolated struct CompleteBody: Encodable, Sendable {
    let sendAftercare: Bool
    let aftercareTemplateId: Int?
    let consumables: [ConsumableUse]
}

nonisolated struct SaleItemBody: Encodable, Hashable, Sendable {
    let type: SaleItemType
    let productId: Int?
    let serviceId: Int?
    let name: String?
    let quantity: Int
    let price: Int
}

nonisolated struct SaleBody: Encodable, Sendable {
    let clientId: Int?
    let appointmentId: Int?
    let items: [SaleItemBody]
    let discount: Int
    let payments: Payments
    let note: String?
}

nonisolated struct RefundBody: Encodable, Sendable {
    let reason: String
    let restock: Bool
}

nonisolated struct OpenShiftBody: Encodable, Sendable {
    let openingCash: Int
}

nonisolated struct CloseShiftBody: Encodable, Sendable {
    let closingCash: Int
    let note: String?
}

nonisolated struct CashOperationBody: Encodable, Sendable {
    let type: CashOperationType
    let amount: Int
    let reason: String
}

nonisolated struct TextBody: Encodable, Sendable {
    let text: String
}

nonisolated struct AIPausedBody: Encodable, Sendable {
    let aiPaused: Bool
}

nonisolated struct KnowledgeBody: Encodable, Sendable {
    var title: String
    var content: String
    var active: Bool
    var sort: Int?
}
