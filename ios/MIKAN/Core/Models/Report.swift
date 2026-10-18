import Foundation

nonisolated struct ReportSummary: Codable, Sendable {
    let from: Date
    let to: Date
    let revenue: Int
    let salesCount: Int
    let averageCheck: Int
    let refunds: Int
    let payments: Payments
    /// Prepayments in the period; `nil` from servers that predate them.
    let deposits: ReportDeposits?
    let servicesRevenue: Int
    let productsRevenue: Int
    let byDay: [ReportDay]
    let topProducts: [TopProduct]
    let topServices: [TopService]
    let byMaster: [MasterStat]
    let newClients: Int
    let appointmentsCompleted: Int
    let noShows: Int
}

nonisolated struct ReportDay: Codable, Hashable, Identifiable, Sendable {
    /// `YYYY-MM-DD` in the studio time zone.
    let date: String
    let revenue: Int
    let salesCount: Int

    var id: String { date }
}

nonisolated struct TopProduct: Codable, Hashable, Identifiable, Sendable {
    let productId: Int
    let name: String
    let quantity: Int
    let revenue: Int
    /// Sales of the product split by size (`[]` from a server that predates sizes).
    var variants: [TopProductVariant] = []

    var id: Int { productId }
}

nonisolated extension TopProduct {
    private enum CodingKeys: String, CodingKey { case productId, name, quantity, revenue, variants }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productId = try c.decode(Int.self, forKey: .productId)
        name = try c.decode(String.self, forKey: .name)
        quantity = try c.decode(Int.self, forKey: .quantity)
        revenue = try c.decode(Int.self, forKey: .revenue)
        variants = try c.decodeIfPresent([TopProductVariant].self, forKey: .variants) ?? []
    }
}

/// One size of a top product: «8 мм» — 4 шт.
nonisolated struct TopProductVariant: Codable, Hashable, Identifiable, Sendable {
    let variantId: Int
    /// "" for a product without sizes.
    let name: String
    let quantity: Int
    let revenue: Int

    var id: Int { variantId }
}

nonisolated struct TopService: Codable, Hashable, Identifiable, Sendable {
    let serviceId: Int?
    let name: String
    let quantity: Int
    let revenue: Int

    var id: String { "\(serviceId ?? -1)-\(name)" }
}

nonisolated struct MasterStat: Codable, Hashable, Identifiable, Sendable {
    let employee: EmployeeRef
    let appointmentsCompleted: Int
    let revenue: Int

    var id: Int { employee.id }
}
