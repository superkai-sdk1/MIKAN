import Foundation

/// Consumables of a visit being completed: prefilled from the norms of its services, then changed by staff.
/// Untouched norms go to the server as «no list» (it deducts them itself without blocking and reports shortages);
/// a changed list is sent as is and must fit the stock.
nonisolated enum VisitConsumption {
    /// Catalog services of the visit in line order (a service booked twice counts twice);
    /// the legacy single service when the visit has no lines.
    static func serviceIds(of appointment: Appointment) -> [Int] {
        guard !appointment.services.isEmpty else { return appointment.service.map { [$0.id] } ?? [] }
        return appointment.services.compactMap(\.serviceId)
    }

    /// Σ over the visit's services of each service's norm, in order of first appearance — counted consumables only.
    /// Presence consumables (never deducted, see `presenceProducts`) and consumables missing from `products`
    /// (gone from the warehouse) are left out.
    static func norms(for appointment: Appointment, services: [Service], products: [Product]) -> [ServiceConsumable] {
        let counted = Set(products.filter { $0.kind == .consumable && !$0.isPresenceTracked }.map(\.id))
        var order: [Int] = []
        var totals: [Int: Int] = [:]
        for norm in allNorms(of: appointment, services: services) where counted.contains(norm.productId) {
            if totals[norm.productId] == nil { order.append(norm.productId) }
            totals[norm.productId, default: 0] += norm.quantity
        }
        return order.map { ServiceConsumable(productId: $0, quantity: totals[$0] ?? 0) }
    }

    /// Presence consumables the visit's services use, listed as «используется».
    static func presenceProducts(for appointment: Appointment, services: [Service], products: [Product]) -> [Product] {
        let byId = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        return allNorms(of: appointment, services: services).compactMap { norm in
            guard seen.insert(norm.productId).inserted, let product = byId[norm.productId], product.isPresenceTracked else {
                return nil
            }
            return product
        }
    }

    private static func allNorms(of appointment: Appointment, services: [Service]) -> [ServiceConsumable] {
        serviceIds(of: appointment).flatMap { id in services.first { $0.id == id }?.consumables ?? [] }
    }

    /// Starting values of the steppers.
    static func usage(from norms: [ServiceConsumable]) -> [Int: Int] {
        Dictionary(norms.map { ($0.productId, $0.quantity) }, uniquingKeysWith: +)
    }

    /// Staff changed the prefilled norms (a count of 0 means «not used»).
    static func isEdited(usage: [Int: Int], norms: [ServiceConsumable]) -> Bool {
        usage.filter { $0.value > 0 } != self.usage(from: norms).filter { $0.value > 0 }
    }

    /// `consumables` of `POST /appointments/:id/complete`: `nil` while the norms are as prefilled (the server deducts
    /// them itself, giving what it has); the exact list, by product, once staff changed something.
    static func consumables(usage: [Int: Int], norms: [ServiceConsumable]) -> [ConsumableUse]? {
        guard isEdited(usage: usage, norms: norms) else { return nil }
        return usage
            .filter { $0.value > 0 }
            .map { ConsumableUse(productId: $0.key, quantity: $0.value) }
            .sorted { $0.productId < $1.productId }
    }

    /// The picker's choice applied to the rows: newly chosen consumables get one unit and a row,
    /// unchosen ones drop to 0 (their row stays only when the norm lists them).
    static func applying(
        selection ids: [Int],
        usage: [Int: Int],
        shown: [Int],
        norms: [ServiceConsumable]
    ) -> (usage: [Int: Int], shown: [Int]) {
        let chosen = Set(ids)
        let normIds = Set(norms.map(\.productId))
        var nextUsage = usage
        for id in ids where (usage[id] ?? 0) == 0 { nextUsage[id] = 1 }
        for (id, count) in usage where count > 0 && !chosen.contains(id) { nextUsage[id] = 0 }
        let kept = shown.filter { chosen.contains($0) || normIds.contains($0) }
        let added = ids.filter { !kept.contains($0) }
        return (nextUsage, kept + added)
    }

    /// «Перчатки: нужно 2 шт, списано 1» — a norm the stock could not cover.
    static func shortageText(_ shortage: Consumption.Shortage, unit: String) -> String {
        "\(shortage.productName): нужно \(shortage.needed) \(unit), списано \(shortage.deducted)"
    }
}
