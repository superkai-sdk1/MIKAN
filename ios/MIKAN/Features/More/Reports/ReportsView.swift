import SwiftUI

struct ReportsView: View {
    @Environment(APIClient.self) private var api
    @State private var period: ReportPeriod = .today
    @State private var customFrom = Calendar.app.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var report = Remote<ReportSummary>()

    private var interval: DateInterval {
        period.interval(customFrom: customFrom, customTo: customTo)
    }

    private var loadKey: String {
        "\(period.rawValue)-\(Int(interval.start.timeIntervalSince1970))-\(Int(interval.end.timeIntervalSince1970))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if period == .custom {
                    customRange
                }
                if let summary = report.value {
                    ReportContent(summary: summary)
                } else if let failure = report.failure {
                    ErrorStateView(message: failure, retry: load)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(16)
        }
        .background { AuraBackground() }
        .safeAreaBar(edge: .top) {
            Picker("Период", selection: $period) {
                ForEach(ReportPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable { await load() }
        .task(id: loadKey) {
            report.reset()
            await load()
        }
        .remoteErrorAlert(report)
        .navigationTitle("Отчёты")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customRange: some View {
        VStack(spacing: 8) {
            DatePicker("С", selection: $customFrom, in: ...Date.now, displayedComponents: .date)
            DatePicker("По", selection: $customTo, in: ...Date.now, displayedComponents: .date)
        }
        .cardStyle()
    }

    private func load() async {
        let range = interval
        await report.load { try await api.reportSummary(from: range.start, to: range.end) }
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
