import SwiftUI

/// Headline numbers of the period with the change against the previous period of the same length.
struct AnalyticsKPIGrid: View {
    let totals: AnalyticsTotals
    let previous: AnalyticsTotals

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            AnalyticsKPITile(title: "Выручка", value: Money.format(totals.net), systemImage: "rublesign.circle",
                             delta: .of(totals.net, previous: previous.net), was: Money.format(previous.net))
            AnalyticsKPITile(title: "Средний чек", value: Money.format(totals.averageCheck), systemImage: "divide.circle",
                             delta: .of(totals.averageCheck, previous: previous.averageCheck), was: Money.format(previous.averageCheck))
            AnalyticsKPITile(title: "Чеков", value: "\(totals.salesCount)", systemImage: "receipt",
                             delta: .of(totals.salesCount, previous: previous.salesCount), was: "\(previous.salesCount)")
            AnalyticsKPITile(title: "Прибыль с товаров", value: Money.format(totals.grossProfit), systemImage: "chart.line.uptrend.xyaxis",
                             delta: .of(totals.grossProfit, previous: previous.grossProfit), was: Money.format(previous.grossProfit))
            AnalyticsKPITile(title: "Новые клиенты", value: "\(totals.newClients)", systemImage: "person.badge.plus",
                             delta: .of(totals.newClients, previous: previous.newClients), was: "\(previous.newClients)")
            AnalyticsKPITile(title: "Записи", value: "\(totals.appointmentsCompleted)", systemImage: "flag.checkered",
                             delta: .of(totals.appointmentsCompleted, previous: previous.appointmentsCompleted),
                             was: "\(previous.appointmentsCompleted)")
            AnalyticsKPITile(title: "Возвраты", value: Money.format(totals.refunds), systemImage: "arrow.uturn.backward.circle",
                             delta: .of(totals.refunds, previous: previous.refunds), was: Money.format(previous.refunds),
                             higherIsBetter: false)
            AnalyticsKPITile(title: "Потери от неявок", value: Money.format(totals.noShowLoss), systemImage: "person.crop.circle.badge.xmark",
                             delta: .of(totals.noShowLoss, previous: previous.noShowLoss), was: Money.format(previous.noShowLoss),
                             higherIsBetter: false)
        }
    }
}

/// A KPI with its delta: «▲ 12 %» in green when the change is good for the studio, red when bad.
struct AnalyticsKPITile: View {
    let title: String
    let value: String
    let systemImage: String
    let delta: AnalyticsDelta
    /// The previous period's value, for VoiceOver and the caption.
    let was: String
    var higherIsBetter = true

    private var tone: AnalyticsDelta.Tone { delta.tone(higherIsBetter: higherIsBetter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.footnote.weight(.medium))
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text(delta.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .monospacedDigit()
                Text("было \(was)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityValue(delta.value == nil ? "не с чем сравнить, было \(was)" : "\(delta.text), было \(was)")
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AnalyticsKPIGrid(totals: PreviewData.analytics.totals, previous: PreviewData.analytics.previous)
            .padding()
    }
    .background { AuraBackground() }
}
#endif
