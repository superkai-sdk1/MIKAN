import SwiftUI

/// «Услуги»: revenue by category and the top services.
struct AnalyticsServicesCard: View {
    let services: AnalyticsServices

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Услуги", systemImage: "sparkle", caption: "Услуг: \(services.quantity) · \(Money.format(services.revenue))")
            ForEach(Array(services.byCategory.enumerated()), id: \.element.id) { index, category in
                AnalyticsShareRow(
                    title: ReportText.categoryTitle(category.category),
                    amount: category.revenue,
                    share: ReportText.share(category.revenue, of: services.revenue),
                    detail: "Услуг: \(category.quantity)",
                    color: AnalyticsPalette.color(index)
                )
            }
            if !services.top.isEmpty {
                Divider()
                Text("Топ услуг").font(.subheadline.weight(.semibold))
                AnalyticsTopList(items: services.top) { index, service in
                    RankedRow(index: index, title: service.name, detail: "\(ReportText.categoryTitle(service.category)) · \(service.quantity)", amount: service.revenue)
                }
            }
        }
        .cardStyle()
    }
}

/// «Украшения» / «Товары»: the top products with their sizes, margin and units without cost.
struct AnalyticsProductsCard: View {
    let products: AnalyticsProducts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: ReportText.productsTitle(products.byKind.map(\.kind)), systemImage: "shippingbox", caption: "\(ReportText.units(products.margin.quantity)) · \(Money.format(products.margin.revenue))")
            AnalyticsTopList(items: products.top) { index, product in
                RankedRow(index: index, title: product.name, detail: detail(product), sizes: ReportText.sizeBreakdown(of: product.variants), amount: product.margin.revenue)
            }
        }
        .cardStyle()
    }

    private func detail(_ product: AnalyticsProduct) -> String {
        var parts = [ReportText.units(product.margin.quantity)]
        if products.byKind.count > 1 { parts.insert(ReportText.kindTitle(product.kind), at: 0) }
        if let margin = product.margin.marginPercent {
            parts.append("прибыль \(Money.format(product.margin.grossProfit)), маржа \(ReportText.percent(margin))")
        }
        if product.margin.itemsWithoutCost > 0 {
            parts.append("без себестоимости: \(product.margin.itemsWithoutCost)")
        }
        return parts.joined(separator: " · ")
    }
}

/// A ranked line of a top: position, name, details, optional sizes and the amount.
struct RankedRow: View {
    let index: Int
    let title: String
    let detail: String
    var sizes: String?
    let amount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            AnalyticsRank(index: index)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let sizes {
                    Text(sizes).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            MoneyText(amount).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AnalyticsServicesCard(services: PreviewData.analytics.services)
            AnalyticsProductsCard(products: PreviewData.analytics.products)
        }
        .padding()
    }
    .background { AuraBackground() }
}
#endif
