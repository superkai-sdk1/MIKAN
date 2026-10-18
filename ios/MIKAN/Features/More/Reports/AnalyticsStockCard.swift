import SwiftUI

/// «Расходы склада»: write-offs and consumables used in the period at cost, purchases of presence consumables at what
/// they cost, the biggest of them, and what is on the shelves now.
struct AnalyticsStockCard: View {
    let stock: AnalyticsStock

    private var unitsWithoutCost: Int { stock.writeoffs.unitsWithoutCost + stock.usage.unitsWithoutCost }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Расходы склада", systemImage: "shippingbox", caption: "Списания, расход и покупки расходников")
            AnalyticsMoneyRow(title: "Списания", amount: stock.writeoffs.value, detail: ReportText.units(stock.writeoffs.quantity))
            AnalyticsMoneyRow(title: "Расход на процедуры", amount: stock.usage.value, detail: ReportText.units(stock.usage.quantity))
            AnalyticsMoneyRow(title: "Покупки расходников", amount: stock.purchases.value, detail: ReportText.purchases(stock.purchases.count))
            Divider()
            AnalyticsMoneyRow(title: "Итого расходы", amount: stock.expenses, isEmphasized: true)
            if !stock.top.isEmpty {
                AnalyticsTopList(items: stock.top, collapsedCount: 3) { index, expense in
                    HStack(alignment: .firstTextBaseline) {
                        AnalyticsRank(index: index)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.name).font(.subheadline)
                            Text(ReportText.stockExpenseLine(expense))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        MoneyText(expense.value).font(.subheadline.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let hint = ReportText.missingCostHint(unitsWithoutCost) {
                AnalyticsHint(text: hint, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            Divider()
            onHand
        }
        .cardStyle()
    }

    private var onHand: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsMoneyRow(title: "На складе сейчас", amount: stock.onHand.value, detail: ReportText.units(stock.onHand.units), isEmphasized: true)
            if stock.onHand.byKind.count > 1 {
                ForEach(stock.onHand.byKind) { kind in
                    AnalyticsMoneyRow(title: ReportText.kindTitle(kind.kind), amount: kind.value, detail: ReportText.units(kind.units))
                }
            }
            if stock.onHand.unitsWithoutCost > 0 {
                AnalyticsHint(text: "Без себестоимости: \(ReportText.units(stock.onHand.unitsWithoutCost)) — в сумму не вошли.")
            }
        }
    }
}

/// «Касса»: cash in / out operations and the discrepancies of the shifts closed in the period.
struct AnalyticsCashCard: View {
    let cash: AnalyticsCash

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Касса", systemImage: "banknote", caption: "Закрыто смен: \(cash.shiftsClosed)")
            AnalyticsMoneyRow(title: "Внесения", amount: cash.cashIn)
            AnalyticsMoneyRow(title: "Изъятия", amount: cash.cashOut)
            Divider()
            HStack {
                Text("Расхождения при закрытии")
                Spacer()
                DifferenceText(amount: cash.closingDifference)
            }
            .font(.subheadline.weight(.semibold))
            if cash.shortage != 0 || cash.surplus != 0 {
                AnalyticsMoneyRow(title: "Недостачи", amount: cash.shortage, tint: cash.shortage < 0 ? .red : nil)
                AnalyticsMoneyRow(title: "Излишки", amount: cash.surplus, tint: cash.surplus > 0 ? .orange : nil)
            }
            HStack {
                Text("При открытии смен")
                Spacer()
                DifferenceText(amount: cash.openingDifference)
            }
            .font(.subheadline)
            if !cash.shifts.isEmpty {
                Divider()
                AnalyticsTopList(items: cash.shifts, collapsedCount: 3) { _, shift in
                    ShiftDiscrepancyRow(shift: shift)
                }
            }
            AnalyticsHint(text: "При открытии — разница с тем, что оставила предыдущая смена.")
        }
        .cardStyle()
    }
}

private struct ShiftDiscrepancyRow: View {
    let shift: AnalyticsShift

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.dateTime(shift.closedAt ?? shift.openedAt)).font(.subheadline)
                if let name = shift.closedBy?.name {
                    Text("Закрыл(а): \(name)").font(.caption).foregroundStyle(.secondary)
                }
                if let opening = shift.openingDifference, opening != 0 {
                    Text("При открытии: \(Money.formatSigned(opening))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            DifferenceText(amount: shift.difference).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AnalyticsStockCard(stock: PreviewData.analytics.stock)
            AnalyticsCashCard(cash: PreviewData.analytics.cash)
        }
        .padding()
    }
    .background { AuraBackground() }
}
#endif
