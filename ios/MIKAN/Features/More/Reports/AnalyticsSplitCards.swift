import Charts
import SwiftUI

/// «Способы оплаты»: a donut of how the period's sales were paid, then each method with its share.
struct AnalyticsPaymentsCard: View {
    let payments: Payments

    private var slices: [AnalyticsChartData.Slice] { AnalyticsChartData.paymentSlices(payments) }

    var body: some View {
        let slices = slices
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsCardTitle(title: "Способы оплаты", systemImage: "creditcard", caption: "Как оплачены чеки периода")
            if slices.isEmpty {
                Text("Оплат не было").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    SectorMark(angle: .value("Сумма", slice.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(AnalyticsPalette.color(index))
                }
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("Итого").font(.caption).foregroundStyle(.secondary)
                        Text(Money.format(payments.total)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                }
                .frame(height: 170)
                .accessibilityHidden(true)
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    AnalyticsShareRow(title: slice.title, amount: slice.amount, share: slice.share, color: AnalyticsPalette.color(index))
                }
                if payments.deposit > 0 {
                    AnalyticsHint(text: "«Из предоплат» — деньги, полученные раньше как предоплата и зачтённые в чеках.")
                }
            }
        }
        .cardStyle()
    }
}

/// «Услуги и товары»: what the revenue is made of — services and each product kind.
struct AnalyticsStructureCard: View {
    let services: Int
    let kinds: [AnalyticsProductKind]

    private var slices: [AnalyticsChartData.Slice] { AnalyticsChartData.structureSlices(services: services, kinds: kinds) }

    var body: some View {
        let slices = slices
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsCardTitle(title: "Услуги и товары", systemImage: "square.split.2x1", caption: "Чеки без возвратов, скидки распределены по позициям")
            if slices.isEmpty {
                Text("Продаж не было").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    BarMark(x: .value("Сумма", slice.amount), y: .value("Выручка", "Выручка"))
                        .foregroundStyle(AnalyticsPalette.color(index))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 22)
                .clipShape(.capsule)
                .accessibilityHidden(true)
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    AnalyticsShareRow(title: slice.title, amount: slice.amount, share: slice.share, color: AnalyticsPalette.color(index))
                }
            }
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AnalyticsPaymentsCard(payments: PreviewData.analytics.revenue.payments)
            AnalyticsStructureCard(services: PreviewData.analytics.services.revenue, kinds: PreviewData.analytics.products.byKind)
        }
        .padding()
    }
    .background { AuraBackground() }
}
#endif
