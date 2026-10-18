import Charts
import SwiftUI

/// Revenue (sales − refunds) by day, or by month for a long period.
struct AnalyticsRevenueChartCard: View {
    let days: [AnalyticsDay]

    private var data: (granularity: AnalyticsChartData.Granularity, points: [AnalyticsChartData.RevenuePoint]) {
        AnalyticsChartData.revenuePoints(days)
    }

    var body: some View {
        let data = data
        let unit: Calendar.Component = data.granularity == .day ? .day : .month
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(
                title: data.granularity == .day ? "Выручка по дням" : "Выручка по месяцам",
                systemImage: "chart.bar.xaxis",
                caption: "Продажи за вычетом возвратов"
            )
            Chart(data.points) { point in
                BarMark(x: .value("Дата", point.date, unit: unit), y: .value("Выручка", point.net))
                    .foregroundStyle(point.net < 0 ? Color.red.gradient : Color.accentColor.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Int.self) { Text(Money.compact(amount)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    if data.granularity == .day {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    } else {
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(data.granularity == .day ? "График выручки по дням" : "График выручки по месяцам")
        }
        .cardStyle()
    }
}

/// «Выручка и возвраты»: sales made, refunds, the result, discounts and the average check.
struct AnalyticsRevenueCard: View {
    let revenue: AnalyticsRevenue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Выручка и возвраты", systemImage: "rublesign.circle")
            AnalyticsMoneyRow(title: "Продажи", amount: revenue.gross, detail: "Чеков: \(revenue.salesCount)")
            AnalyticsMoneyRow(
                title: "Возвраты",
                amount: -revenue.refunds,
                detail: revenue.refundsCount > 0 ? "Чеков: \(revenue.refundsCount)" : nil,
                tint: revenue.refunds > 0 ? .red : nil
            )
            Divider()
            AnalyticsMoneyRow(title: "Выручка", amount: revenue.net, isEmphasized: true)
            AnalyticsMoneyRow(title: "Средний чек", amount: revenue.averageCheck)
            AnalyticsMoneyRow(title: "Скидки", amount: revenue.discounts)
            if revenue.kept != revenue.net {
                AnalyticsHint(text: "Возвраты считаются в день возврата, даже если чек был раньше. Разбивки ниже — по чекам периода без возвратов: \(Money.format(revenue.kept)).")
            }
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AnalyticsRevenueChartCard(days: PreviewData.analytics.byDay)
            AnalyticsRevenueCard(revenue: PreviewData.analytics.revenue)
        }
        .padding()
    }
    .background { AuraBackground() }
}
#endif
