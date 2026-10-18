import SwiftUI

/// «Аналитика» (Ещё → Отчёты): the financial picture of the chosen period with deltas against the previous period
/// of the same length, shareable as a CSV table.
struct ReportsView: View {
    @Environment(APIClient.self) private var api
    @State private var period: ReportPeriod = .month
    @State private var customFrom = Calendar.app.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var analytics = Remote<ReportAnalytics>()

    private var interval: DateInterval {
        period.interval(customFrom: customFrom, customTo: customTo)
    }

    private var loadKey: String {
        "\(period.rawValue)-\(Int(interval.start.timeIntervalSince1970))-\(Int(interval.end.timeIntervalSince1970))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // In the content, not a top bar: a horizontal scroll view gets no height of its own in a safe area bar.
                AnalyticsPeriodBar(period: $period)
                    .padding(.horizontal, -16)
                header
                if let value = analytics.value {
                    AnalyticsContent(analytics: value, comparison: ReportPeriod.rangeText(previousInterval(value)))
                } else if let failure = analytics.failure {
                    ErrorStateView(message: failure, retry: load)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(16)
        }
        .background { AuraBackground() }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await load() }
        .task(id: loadKey) {
            analytics.reset()
            await load()
        }
        .remoteErrorAlert(analytics)
        .toolbar {
            if let value = analytics.value {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: AnalyticsExport(value, interval: interval),
                        preview: SharePreview("Аналитика \(ReportPeriod.rangeText(interval))", image: Image(systemName: "tablecells"))
                    ) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Аналитика")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var header: some View {
        if period == .custom {
            VStack(spacing: 8) {
                DatePicker("С", selection: $customFrom, in: ...Date.now, displayedComponents: .date)
                DatePicker("По", selection: $customTo, in: ...Date.now, displayedComponents: .date)
                Text("Не больше \(Plural.days(ReportPeriod.maxDays)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()
        }
        Text(ReportPeriod.rangeText(interval))
            .font(.title2.weight(.bold))
            .contentTransition(.opacity)
            .accessibilityAddTraits(.isHeader)
    }

    private func previousInterval(_ value: ReportAnalytics) -> DateInterval {
        DateInterval(start: value.previousFrom, end: max(value.previousFrom, value.previousTo))
    }

    private func load() async {
        let range = interval
        await analytics.load { try await api.reportAnalytics(from: range.start, to: range.end) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ReportsView()
    }
    .previewEnvironment()
}
#endif
