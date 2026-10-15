import Charts
import SwiftUI

struct ReportContent: View {
    let summary: ReportSummary

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Выручка", value: Money.format(summary.revenue), systemImage: "rublesign.circle")
                StatTile(title: "Продажи", value: "\(summary.salesCount)", systemImage: "receipt")
                StatTile(title: "Средний чек", value: Money.format(summary.averageCheck), systemImage: "divide.circle")
                StatTile(title: "Новые клиенты", value: "\(summary.newClients)", systemImage: "person.badge.plus")
                StatTile(title: "Возвраты", value: Money.format(summary.refunds), systemImage: "arrow.uturn.backward.circle", tint: .red)
                StatTile(
                    title: "Записи",
                    value: "\(summary.appointmentsCompleted)",
                    systemImage: "flag.checkered",
                    footnote: summary.noShows > 0 ? "Неявок: \(summary.noShows)" : nil
                )
            }
            if summary.byDay.count > 1 {
                RevenueChartCard(days: summary.byDay)
            }
            PaymentBreakdownCard(payments: summary.payments, services: summary.servicesRevenue, products: summary.productsRevenue)
            if let deposits = summary.deposits, deposits != .zero {
                ReportDepositsCard(deposits: deposits)
            }
            if !summary.topServices.isEmpty {
                RankingCard(title: "Топ услуг", rows: summary.topServices.map { ($0.id, $0.name, $0.quantity, $0.revenue) })
            }
            if !summary.topProducts.isEmpty {
                RankingCard(title: "Топ украшений", rows: summary.topProducts.map { ("\($0.id)", $0.name, $0.quantity, $0.revenue) })
            }
            if !summary.byMaster.isEmpty {
                MastersCard(masters: summary.byMaster)
            }
        }
    }
}

private struct RevenueChartCard: View {
    let days: [ReportDay]

    private var points: [(date: Date, revenue: Int)] {
        days.compactMap { day in CalendarDay.date(from: day.date).map { ($0, day.revenue) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Выручка по дням").font(.headline)
            Chart(points, id: \.date) { point in
                BarMark(
                    x: .value("День", point.date, unit: .day),
                    y: .value("Выручка", point.revenue)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Int.self) {
                            Text(Money.compact(amount))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .frame(height: 200)
            .accessibilityLabel("График выручки по дням")
        }
        .cardStyle()
    }
}

private struct PaymentBreakdownCard: View {
    let payments: Payments
    let services: Int
    let products: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Способы оплаты").font(.headline)
            // Card is no longer taken and QR may be off: they show only for periods that have them.
            ForEach(PaymentMethod.allCases.filter { ![.card, .qr].contains($0) || PaymentSplit(payments)[$0] > 0 }) { method in
                let amount = PaymentSplit(payments)[method]
                ShareRow(title: method.title, systemImage: method.symbol, amount: amount, total: payments.total)
            }
            // Revenue covered by prepayments received earlier (counted in «Предоплаты» when received).
            if payments.deposit > 0 {
                ShareRow(title: "Из предоплат", systemImage: PaymentLine.depositSymbol, amount: payments.deposit, total: payments.total)
            }
            Divider()
            Text("Структура выручки").font(.headline)
            ShareRow(title: "Услуги", systemImage: "sparkle", amount: services, total: services + products)
            ShareRow(title: "Украшения", systemImage: "shippingbox", amount: products, total: services + products)
        }
        .cardStyle()
    }
}

private struct ShareRow: View {
    let title: String
    let systemImage: String
    let amount: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(amount) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                MoneyText(amount).fontWeight(.semibold)
                Text(fraction.formatted(.percent.precision(.fractionLength(0)).locale(.app)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .font(.subheadline)
            ProgressView(value: fraction)
                .tint(.accentColor)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RankingCard: View {
    let title: String
    let rows: [(id: String, name: String, quantity: Int, revenue: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.subheadline)
                        Text("\(row.quantity) шт.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    MoneyText(row.revenue).font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

private struct MastersCard: View {
    let masters: [MasterStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По мастерам").font(.headline)
            ForEach(masters) { stat in
                HStack {
                    Circle().fill(Color.master(stat.employee.color)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.employee.name).font(.subheadline)
                        Text("Завершено записей: \(stat.appointmentsCompleted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    MoneyText(stat.revenue).font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ReportContent(summary: PreviewData.report)
            .padding()
    }
    .previewEnvironment()
}
#endif
