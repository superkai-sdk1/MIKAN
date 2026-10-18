import SwiftUI

/// Every card of the analytics screen for one loaded period, money first, then stock, cash and people.
struct AnalyticsContent: View {
    let analytics: ReportAnalytics
    /// «Сравнение с 28 сентября – 4 октября».
    let comparison: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Сравнение с \(comparison)")
                .font(.caption)
                .foregroundStyle(.secondary)
            AnalyticsKPIGrid(totals: analytics.totals, previous: analytics.previous)
            if analytics.isEmpty {
                ContentUnavailableView(
                    "За этот период пусто",
                    systemImage: "chart.bar",
                    description: Text("Здесь появятся продажи, записи, движения склада и кассы.")
                )
            } else {
                details
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if analytics.byDay.count > 1 {
            AnalyticsRevenueChartCard(days: analytics.byDay)
        }
        AnalyticsRevenueCard(revenue: analytics.revenue)
        AnalyticsPaymentsCard(payments: analytics.revenue.payments)
        AnalyticsStructureCard(services: analytics.services.revenue, kinds: analytics.products.byKind)
        AnalyticsTimingCard(weekdays: analytics.byWeekday, hours: analytics.byHour)
        if analytics.deposits != .zero {
            ReportDepositsCard(deposits: analytics.deposits)
        }
        if analytics.products.margin.quantity > 0 {
            AnalyticsMarginCard(products: analytics.products)
        }
        AnalyticsStockCard(stock: analytics.stock)
        if analytics.cash.operationsCount > 0 || analytics.cash.shiftsClosed > 0 {
            AnalyticsCashCard(cash: analytics.cash)
        }
        if !analytics.masters.isEmpty {
            AnalyticsMastersCard(masters: analytics.masters)
        }
        if analytics.services.quantity > 0 {
            AnalyticsServicesCard(services: analytics.services)
        }
        if !analytics.products.top.isEmpty {
            AnalyticsProductsCard(products: analytics.products)
        }
        AnalyticsClientsCard(clients: analytics.clients)
        if analytics.appointments.total > 0 {
            AnalyticsAppointmentsCard(appointments: analytics.appointments)
        }
    }
}

/// Period chips over the analytics: Liquid Glass capsules, the selected one tinted with the brand color.
struct AnalyticsPeriodBar: View {
    @Binding var period: ReportPeriod
    @Namespace private var glass

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ReportPeriod.allCases) { option in
                        chip(option)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ option: ReportPeriod) -> some View {
        let isSelected = option == period
        return Button {
            withAnimation(.snappy) { period = option }
        } label: {
            Text(option.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        .glassEffectID(option.id, in: glass)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScrollView {
            AnalyticsContent(analytics: PreviewData.analytics, comparison: "28 сентября – 4 октября")
                .padding()
        }
        .background { AuraBackground() }
    }
    .previewEnvironment()
}
#endif
