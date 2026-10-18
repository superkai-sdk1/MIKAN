import SwiftUI

/// Services whose procedure uses a consumable (their consumption norms, `Service.consumables`).
/// The norms are edited in the service card; the product card and editor only show them.
nonisolated enum ConsumableUsage {
    /// One service that uses the consumable and how many units one procedure takes.
    struct Entry: Identifiable, Hashable, Sendable {
        let service: Service
        let quantity: Int

        var id: Int { service.id }
    }

    /// Services in catalog order (category, then position and name); hidden ones too, since their norms still exist.
    static func entries(for productId: Int, in services: [Service]) -> [Entry] {
        let categoryOrder = ServiceCategory.allCases
        return services
            .compactMap { service in
                service.consumables.first { $0.productId == productId }.map { Entry(service: service, quantity: $0.quantity) }
            }
            .sorted { lhs, rhs in
                let left = categoryOrder.firstIndex(of: lhs.service.category) ?? 0
                let right = categoryOrder.firstIndex(of: rhs.service.category) ?? 0
                if left != right { return left < right }
                if lhs.service.sort != rhs.service.sort { return lhs.service.sort < rhs.service.sort }
                return lhs.service.name.localizedStandardCompare(rhs.service.name) == .orderedAscending
            }
    }

    /// «2 шт на процедуру»; a presence consumable is not counted, it is just «используется».
    static func normText(_ quantity: Int, unit: String, isPresence: Bool) -> String {
        isPresence ? "используется" : "\(quantity) \(unit) на процедуру"
    }

    /// «Используется в 3 услугах».
    static func summary(_ count: Int) -> String {
        count == 0
            ? "Не используется в услугах"
            : "Используется в " + Plural.count(count, one: "услуге", few: "услугах", many: "услугах")
    }
}

/// «Используется в услугах»: the services with their norms, read-only.
struct ConsumableUsageList: View {
    let entries: [ConsumableUsage.Entry]
    let unit: String
    let isPresence: Bool

    var body: some View {
        ForEach(entries) { entry in
            HStack(spacing: 12) {
                ServiceThumbnail(service: entry.service, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.service.name).lineLimit(2)
                        if !entry.service.active {
                            StatusBadge(text: "Скрыта", color: .gray)
                        }
                    }
                    Text(entry.service.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ConsumableUsage.normText(entry.quantity, unit: unit, isPresence: isPresence))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The product card's «Используется в услугах» card for a consumable.
struct ConsumableUsageCard: View {
    let product: Product
    let services: [Service]

    var body: some View {
        let entries = ConsumableUsage.entries(for: product.id, in: services)
        VStack(alignment: .leading, spacing: 10) {
            Text("Используется в услугах").font(.headline)
            if entries.isEmpty {
                Text("Ни в одной услуге нет нормы расхода с этим расходником.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ConsumableUsageList(entries: entries, unit: product.unitLabel, isPresence: product.isPresenceTracked)
            }
            Text(ConsumableUsage.hint(isPresence: product.isPresenceTracked))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

extension ConsumableUsage {
    /// Where the norms live and what completing a visit does with them.
    nonisolated static func hint(isPresence: Bool) -> String {
        isPresence
            ? "Нормы задаются в карточке услуги. «Есть / нет» не списывается при завершении записи — отмечайте наличие вручную или в ревизии."
            : "Нормы задаются в карточке услуги; при завершении записи расход списывается со склада."
    }
}
