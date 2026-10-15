import Foundation

nonisolated enum ServiceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tattoo
    case piercing
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tattoo: "Тату"
        case .piercing: "Пирсинг"
        case .other: "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .tattoo: "paintbrush.pointed"
        case .piercing: "sparkle"
        case .other: "square.grid.2x2"
        }
    }
}

nonisolated struct Service: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var category: ServiceCategory
    var price: Int
    /// `true` means "от N ₽" — the final price is set per appointment.
    var priceFrom: Bool
    var durationMin: Int
    var description: String?
    var aftercareTemplateId: Int?
    var active: Bool
    var sort: Int

    var ref: ServiceRef { ServiceRef(id: id, name: name, category: category) }
}

/// Embedded service summary used inside other entities.
nonisolated struct ServiceRef: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let category: ServiceCategory
}

nonisolated struct AftercareStep: Codable, Hashable, Sendable {
    var dayOffset: Int
    var text: String
}

nonisolated struct AftercareTemplate: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var category: ServiceCategory
    var steps: [AftercareStep]
    let createdAt: Date
    var updatedAt: Date
}
