import Charts
import SwiftUI

/// When the studio sells: revenue by weekday or by hour of day (studio time), with the busiest one named.
struct AnalyticsTimingCard: View {
    let weekdays: [AnalyticsWeekday]
    let hours: [AnalyticsHour]

    enum Mode: String, CaseIterable, Identifiable {
        case weekday, hour

        var id: String { rawValue }
        var title: String { self == .weekday ? "Дни недели" : "Часы" }
    }

    @State private var mode = Mode.weekday

    private var bars: [AnalyticsChartData.Bar] {
        mode == .weekday ? AnalyticsChartData.weekdayBars(weekdays) : AnalyticsChartData.hourBars(hours)
    }

    private func peakText(_ peak: AnalyticsChartData.Bar) -> String {
        let name = mode == .weekday ? ReportText.weekday(peak.id, full: true) : "\(ReportText.hour(peak.id))–\(ReportText.hour((peak.id + 1) % 24))"
        return "Больше всего: \(name) — \(Money.format(peak.revenue)), чеков: \(peak.salesCount)"
    }

    var body: some View {
        let bars = bars
        let peak = AnalyticsChartData.peak(bars)
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Когда покупают", systemImage: "clock", caption: "Чеки без возвратов, время студии")
            Picker("Разбивка", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let peak {
                Chart(bars) { bar in
                    BarMark(x: .value(mode.title, bar.label), y: .value("Выручка", bar.revenue))
                        .foregroundStyle(bar.id == peak.id ? Color.accentColor.gradient : Color.accentColor.opacity(0.45).gradient)
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
                .frame(height: 180)
                .accessibilityLabel(mode == .weekday ? "Выручка по дням недели" : "Выручка по часам")
                AnalyticsHint(text: peakText(peak), systemImage: "star.fill", tint: .accentColor)
            } else {
                Text("Продаж не было").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AnalyticsTimingCard(weekdays: PreviewData.analytics.byWeekday, hours: PreviewData.analytics.byHour)
            .padding()
    }
    .background { AuraBackground() }
}
#endif
