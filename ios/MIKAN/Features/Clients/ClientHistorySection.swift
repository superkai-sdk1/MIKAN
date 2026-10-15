import SwiftUI

/// Client card history: services done, products bought, appointments and receipts.
struct ClientHistorySection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let history: Remote<ClientHistory>
    let retry: () async -> Void

    @State private var tab: Tab = .services

    enum Tab: CaseIterable, Hashable {
        case services
        case products
        case appointments
        case sales

        var title: String {
            switch self {
            case .services: "Услуги"
            case .products: "Покупки"
            case .appointments: "Записи"
            case .sales: "Чеки"
            }
        }
    }

    var body: some View {
        Section {
            tabPicker

            if let value = history.value {
                switch tab {
                case .services: entries(value.items, kind: .service)
                case .products: entries(value.items, kind: .product)
                case .appointments: appointments(value.appointments)
                case .sales: sales(value.sales)
                }
            } else if let failure = history.failure {
                VStack(alignment: .leading, spacing: 8) {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Повторить") { Task { await retry() } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("История")
        }
    }

    /// Four segments truncate at accessibility text sizes, so those get a menu instead.
    @ViewBuilder
    private var tabPicker: some View {
        let picker = Picker("История", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
    }

    @ViewBuilder
    private func entries(_ all: [HistoryEntry], kind: HistoryEntryKind) -> some View {
        let items = all.filter { $0.kind == kind }
        if items.isEmpty {
            Text(kind == .service ? "Услуг пока не было" : "Покупок пока не было").foregroundStyle(.secondary)
        } else {
            Text(HistorySummary(entries: items).text(for: kind))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            ForEach(items) { entry in
                HistoryEntryLink(entry: entry)
            }
        }
    }

    @ViewBuilder
    private func appointments(_ items: [Appointment]) -> some View {
        if items.isEmpty {
            Text("Записей пока не было").foregroundStyle(.secondary)
        }
        ForEach(items) { appointment in
            NavigationLink {
                AppointmentDetailView(appointment: appointment)
            } label: {
                AppointmentCard(appointment: appointment, showsDate: true)
            }
        }
    }

    @ViewBuilder
    private func sales(_ items: [Sale]) -> some View {
        if items.isEmpty {
            Text("Чеков пока не было").foregroundStyle(.secondary)
        }
        ForEach(items) { sale in
            NavigationLink {
                SaleDetailView(sale: sale)
            } label: {
                SaleRow(sale: sale, showsDate: true)
            }
        }
    }
}

/// «12 услуг · 48 000 ₽ · возвратов: 1»: what was done or bought and paid for (refunded entries are left out
/// of both the count and the sum and only counted as returns). Counts are quantities.
nonisolated struct HistorySummary: Equatable, Sendable {
    let count: Int
    let total: Int
    let refundedCount: Int

    init(entries: [HistoryEntry]) {
        let kept = entries.filter { !$0.refunded }
        count = kept.reduce(0) { $0 + $1.quantity }
        total = kept.reduce(0) { $0 + $1.total }
        refundedCount = entries.filter(\.refunded).reduce(0) { $0 + $1.quantity }
    }

    func text(for kind: HistoryEntryKind) -> String {
        let counted = switch kind {
        case .service: Plural.count(count, one: "услуга", few: "услуги", many: "услуг")
        case .product: Plural.count(count, one: "товар", few: "товара", many: "товаров")
        }
        let base = "\(counted) · \(Money.format(total))"
        return refundedCount > 0 ? "\(base) · возвратов: \(refundedCount)" : base
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        List {
            ClientHistorySection(
                history: Remote(ClientHistory(items: PreviewData.historyEntries, appointments: PreviewData.appointments, sales: [PreviewData.sale])),
                retry: {}
            )
        }
    }
    .previewEnvironment()
}
#endif
