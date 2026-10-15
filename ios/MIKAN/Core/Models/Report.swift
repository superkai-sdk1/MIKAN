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

    var id: Int { productId }
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
