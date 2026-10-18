import SwiftUI

/// «Маржа по товарам»: revenue, cost of goods sold, gross profit and margin of the products sold, by kind when the
/// studio sells more than one kind; warns about units sold without a cost.
struct AnalyticsMarginCard: View {
    let products: AnalyticsProducts

    private var margin: AnalyticsMargin { products.margin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Маржа по товарам", systemImage: "chart.line.uptrend.xyaxis", caption: "По текущей себестоимости размеров и товаров")
            AnalyticsMoneyRow(title: "Выручка с товаров", amount: margin.revenue, detail: ReportText.units(margin.quantity))
            AnalyticsMoneyRow(title: "Себестоимость проданного", amount: margin.cogs)
            Divider()
            AnalyticsMoneyRow(title: "Валовая прибыль", amount: margin.grossProfit, isEmphasized: true,
                              tint: margin.grossProfit < 0 ? .red : nil)
            AnalyticsValueRow(title: "Маржа", value: ReportText.percent(margin.marginPercent), isEmphasized: true)
            if products.byKind.count > 1 {
                Divider()
                ForEach(products.byKind) { kind in
                    AnalyticsValueRow(
                        title: ReportText.kindTitle(kind.kind),
                        value: Money.format(kind.margin.grossProfit),
                        detail: "Выручка \(Money.format(kind.margin.revenue)) · маржа \(ReportText.percent(kind.margin.marginPercent))"
                    )
                }
            }
            if let hint = ReportText.missingCostHint(margin.itemsWithoutCost) {
                AnalyticsHint(text: hint + ". Их выручка (\(Money.format(margin.revenue - margin.revenueWithCost))) не входит в маржу.",
                              systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AnalyticsMarginCard(products: PreviewData.analytics.products)
            .padding()
    }
    .background { AuraBackground() }
}
#endif
