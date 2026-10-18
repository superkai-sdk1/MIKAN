import Foundation

// MARK: - Services

nonisolated struct AnalyticsServices: Decodable, Hashable, Sendable {
    var quantity = 0
    var revenue = 0
    /// By the catalog category (`tattoo` / `piercing` / `other`, or one a newer server adds), by revenue.
    var byCategory: [AnalyticsServiceCategory] = []
    /// Up to 20 services by revenue.
    var top: [AnalyticsService] = []
}

nonisolated struct AnalyticsServiceCategory: Decodable, Hashable, Identifiable, Sendable {
    let category: String
    var quantity = 0
    var revenue = 0

    var id: String { category }
}

nonisolated struct AnalyticsService: Decodable, Hashable, Identifiable, Sendable {
    /// `nil` for a custom line.
    let serviceId: Int?
    let name: String
    let category: String
    var quantity = 0
    var revenue = 0

    var id: String { "\(serviceId ?? -1)-\(name)" }
}

// MARK: - Products and margin

/// Sold units with their cost: COGS and gross profit over the units whose cost is known.
nonisolated struct AnalyticsMargin: Decodable, Hashable, Sendable {
    var quantity = 0
    var revenue = 0
    /// Revenue of the units whose cost is known.
    var revenueWithCost = 0
    var cogs = 0
    var grossProfit = 0
    /// `grossProfit / revenueWithCost` in percent; `nil` when no unit with a cost sold.
    var marginPercent: Double?
    /// Sold units without a cost (left out of `cogs`).
    var itemsWithoutCost = 0
}

nonisolated struct AnalyticsProducts: Hashable, Sendable {
    var margin = AnalyticsMargin()
    /// One entry per product kind that sold (`jewelry`, or kinds a newer server adds), by revenue.
    var byKind: [AnalyticsProductKind] = []
    /// Up to 20 products by revenue.
    var top: [AnalyticsProduct] = []
}

nonisolated struct AnalyticsProductKind: Hashable, Identifiable, Sendable {
    let kind: String
    var margin = AnalyticsMargin()

    var id: String { kind }
}

nonisolated struct AnalyticsProduct: Hashable, Identifiable, Sendable {
    let productId: Int?
    let name: String
    let kind: String
    var margin = AnalyticsMargin()
    /// The same split by size ("" — a product without sizes).
    var variants: [AnalyticsProductVariant] = []

    var id: String { "\(productId ?? -1)-\(name)" }
}

nonisolated struct AnalyticsProductVariant: Hashable, Identifiable, Sendable {
    let variantId: Int
    let name: String
    var margin = AnalyticsMargin()

    var id: Int { variantId }
}

// The server sends the margin keys flat next to the entry's own keys, so each entry decodes them from its own object.
nonisolated extension AnalyticsProducts: Decodable {
    private enum CodingKeys: String, CodingKey { case byKind, top }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        margin = try AnalyticsMargin(from: decoder)
        byKind = try c.decode(.byKind, or: [])
        top = try c.decode(.top, or: [])
    }
}

nonisolated extension AnalyticsProductKind: Decodable {
    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: any Decoder) throws {
        kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        margin = try AnalyticsMargin(from: decoder)
    }
}

nonisolated extension AnalyticsProduct: Decodable {
    private enum CodingKeys: String, CodingKey { case productId, name, kind, variants }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productId = try c.decodeIfPresent(Int.self, forKey: .productId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(.kind, or: ProductKind.jewelry.rawValue)
        margin = try AnalyticsMargin(from: decoder)
        variants = try c.decode(.variants, or: [])
    }
}

nonisolated extension AnalyticsProductVariant: Decodable {
    private enum CodingKeys: String, CodingKey { case variantId, name }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        variantId = try c.decode(Int.self, forKey: .variantId)
        name = try c.decode(.name, or: "")
        margin = try AnalyticsMargin(from: decoder)
    }
}

// MARK: - Stock

nonisolated struct AnalyticsStock: Hashable, Sendable {
    var writeoffs = AnalyticsStockFlow()
    /// Consumables used in procedures.
    var usage = AnalyticsStockFlow()
    /// Restocks of presence consumables at what they cost.
    var purchases = AnalyticsStockPurchases()
    /// `writeoffs.value + usage.value + purchases.value`.
    var expenses = 0
    /// Up to 20 products by value.
    var top: [AnalyticsStockExpense] = []
    /// Snapshot now, not at the end of the period.
    var onHand = AnalyticsStockOnHand()
}

nonisolated extension AnalyticsStock: Decodable {
    private enum CodingKeys: String, CodingKey { case writeoffs, usage, purchases, expenses, top, onHand }

    /// A server that predates purchases sends none (zero).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writeoffs = try c.decode(.writeoffs, or: AnalyticsStockFlow())
        usage = try c.decode(.usage, or: AnalyticsStockFlow())
        purchases = try c.decode(.purchases, or: AnalyticsStockPurchases())
        expenses = try c.decode(.expenses, or: 0)
        top = try c.decode(.top, or: [])
        onHand = try c.decode(.onHand, or: AnalyticsStockOnHand())
    }
}

/// Restocks of presence consumables: how many and what was paid.
nonisolated struct AnalyticsStockPurchases: Decodable, Hashable, Sendable {
    var count = 0
    var value = 0
}

/// Units that left the stock, valued at the current cost.
nonisolated struct AnalyticsStockFlow: Decodable, Hashable, Sendable {
    var quantity = 0
    var value = 0
    var unitsWithoutCost = 0
}

nonisolated struct AnalyticsStockExpense: Decodable, Hashable, Identifiable, Sendable {
    let productId: Int
    let name: String
    let kind: String
    /// `writeoff` | `usage` | `purchase`.
    let type: String
    /// Units; for a purchase — the number of purchases.
    var quantity = 0
    var value = 0

    var id: String { "\(productId)-\(type)" }
    var isUsage: Bool { type == MovementType.usage.rawValue }
    var isPurchase: Bool { type == MovementType.purchase.rawValue }
}

nonisolated struct AnalyticsStockOnHand: Decodable, Hashable, Sendable {
    var units = 0
    var value = 0
    var unitsWithoutCost = 0
    var byKind: [AnalyticsStockKind] = []
}

nonisolated struct AnalyticsStockKind: Decodable, Hashable, Identifiable, Sendable {
    let kind: String
    var units = 0
    var value = 0
    var unitsWithoutCost = 0

    var id: String { kind }
}

// MARK: - Cash register

nonisolated struct AnalyticsCash: Decodable, Hashable, Sendable {
    var cashIn = 0
    var cashOut = 0
    var operationsCount = 0
    /// Shifts closed in the period.
    var shiftsClosed = 0
    /// Σ (closing cash − expected cash).
    var closingDifference = 0
    /// Negative part of `closingDifference` (≤ 0).
    var shortage = 0
    /// Positive part of `closingDifference` (≥ 0).
    var surplus = 0
    /// Σ (opening cash − what the previous shift left).
    var openingDifference = 0
    /// Shifts with a discrepancy, newest first.
    var shifts: [AnalyticsShift] = []
}

nonisolated struct AnalyticsShift: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let openedAt: Date
    let closedAt: Date?
    let closedBy: EmployeeRef?
    var openingCash = 0
    var closingCash: Int?
    var expectedCash: Int?
    /// `nil` for the very first shift.
    var openingDifference: Int?
    var difference = 0
}

// MARK: - People

nonisolated struct AnalyticsMaster: Decodable, Hashable, Identifiable, Sendable {
    let employee: EmployeeRef
    var revenue = 0
    var salesCount = 0
    var averageCheck = 0
    var appointmentsCompleted = 0
    var noShows = 0
    var servicesCount = 0

    var id: Int { employee.id }
}

nonisolated struct AnalyticsClients: Decodable, Hashable, Sendable {
    /// Cards created in the period.
    var newClients = 0
    /// Clients with sales in the period.
    var buyers = 0
    var firstTime = AnalyticsClientGroup()
    /// Bought or visited before the period.
    var returning = AnalyticsClientGroup()
    /// Sales without a client.
    var anonymous = AnalyticsAnonymousSales()
    /// Up to 10 clients by spend.
    var top: [AnalyticsTopClient] = []
}

nonisolated struct AnalyticsClientGroup: Decodable, Hashable, Sendable {
    var count = 0
    var revenue = 0
}

nonisolated struct AnalyticsAnonymousSales: Decodable, Hashable, Sendable {
    var salesCount = 0
    var revenue = 0
}

nonisolated struct AnalyticsTopClient: Decodable, Hashable, Identifiable, Sendable {
    let client: ClientRef
    var revenue = 0
    var salesCount = 0
    /// Completed appointments in the period.
    var visits = 0

    var id: Int { client.id }
}

/// Appointments starting in the period.
nonisolated struct AnalyticsAppointments: Decodable, Hashable, Sendable {
    var total = 0
    /// Still `scheduled` / `confirmed`.
    var open = 0
    var completed = 0
    var cancelled = 0
    var noShow = 0
    /// Σ price of no-shows.
    var noShowLoss = 0
    /// Σ price of cancelled appointments.
    var cancelledValue = 0
}
