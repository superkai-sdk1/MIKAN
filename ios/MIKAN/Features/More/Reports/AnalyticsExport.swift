import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The CSV file shared from the analytics screen: UTF-8 with a BOM, so Excel opens Cyrillic correctly.
/// The table is built only when the file is actually shared.
nonisolated struct AnalyticsExport: Sendable {
    static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    let analytics: ReportAnalytics
    let interval: DateInterval
    var calendar: Calendar = .app

    var fileName: String { AnalyticsCSV.fileName(interval, calendar: calendar) }

    var csv: String {
        let previous = DateInterval(start: analytics.previousFrom, end: max(analytics.previousFrom, analytics.previousTo))
        return AnalyticsCSV.make(
            analytics,
            period: ReportPeriod.rangeText(interval, calendar: calendar),
            previousPeriod: ReportPeriod.rangeText(previous, calendar: calendar)
        )
    }

    var data: Data { Data(Self.byteOrderMark) + Data(csv.utf8) }

    init(_ analytics: ReportAnalytics, interval: DateInterval, calendar: Calendar = .app) {
        self.analytics = analytics
        self.interval = interval
        self.calendar = calendar
    }
}

extension AnalyticsExport: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in export.data }
            .suggestedFileName { $0.fileName }
    }
}
