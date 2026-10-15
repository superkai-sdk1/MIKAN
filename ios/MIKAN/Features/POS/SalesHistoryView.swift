import SwiftUI

/// Sales of a chosen day.
struct SalesHistoryView: View {
    @Environment(APIClient.self) private var api
    @State private var day = Calendar.app.startOfDay(for: .now)
    @State private var sales = Remote<[Sale]>()

    private static let dayLimit = 200

    private var completedTotal: Int {
        (sales.value ?? []).filter { !$0.isRefunded }.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        List {
            if let items = sales.value, !items.isEmpty {
                Section {
                    ForEach(items) { sale in
                        NavigationLink {
                            SaleDetailView(sale: sale) { updated in sales.upsert(updated) }
                        } label: {
                            SaleRow(sale: sale)
                        }
                    }
                } header: {
                    HStack {
                        Text(Plural.count(items.count, one: "продажа", few: "продажи", many: "продаж"))
                        Spacer()
                        Text(Money.format(completedTotal)).monospacedDigit()
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            DayPickerBar(day: $day)
        }
        .overlay {
            RemoteStateOverlay(remote: sales, retry: load) {
                ContentUnavailableView(
                    "Продаж нет",
                    systemImage: "receipt",
                    description: Text("В этот день продаж не было. Выберите другой день.")
                )
            }
        }
        .refreshable { await load() }
        .task(id: day) {
            sales.reset()
            await load()
        }
        .remoteErrorAlert(sales)
        .navigationTitle("История продаж")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let start = day
        guard let end = Calendar.app.date(byAdding: .day, value: 1, to: start) else { return }
        await sales.load { try await api.sales(from: start, to: end, limit: Self.dayLimit).items }
    }
}

/// ‹ day › selector with a compact date picker.
struct DayPickerBar: View {
    @Binding var day: Date

    var body: some View {
        HStack(spacing: 12) {
            Button("Предыдущий день", systemImage: "chevron.left") { shift(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            DatePicker("День", selection: dayBinding, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button("Следующий день", systemImage: "chevron.right") { shift(1) }
                .labelStyle(.iconOnly)
                .disabled(Calendar.app.isDateInToday(day))
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day }, set: { day = Calendar.app.startOfDay(for: $0) })
    }

    private func shift(_ offset: Int) {
        guard let next = Calendar.app.date(byAdding: .day, value: offset, to: day) else { return }
        withAnimation(.snappy) { day = next }
    }
}

struct SaleRow: View {
    let sale: Sale
    var showsDate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("№\(sale.number)").font(.headline).monospacedDigit()
                    Text(showsDate ? DateText.dateTime(sale.createdAt) : DateText.time(sale.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(sale.client?.name ?? "Без клиента")
                    .font(.subheadline)
                Text(sale.itemsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                MoneyText(sale.total)
                    .font(.headline)
                    .strikethrough(sale.isRefunded)
                    .foregroundStyle(sale.isRefunded ? .secondary : .primary)
                if sale.isRefunded {
                    StatusBadge(text: "Возврат", color: .red)
                } else {
                    PaymentIcons(payments: sale.payments)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaymentIcons: View {
    let payments: Payments

    var body: some View {
        HStack(spacing: 4) {
            if payments.cash > 0 { icon(.cash) }
            if payments.card > 0 { icon(.card) }
            if payments.transfer > 0 { icon(.transfer) }
            if payments.qr > 0 { icon(.qr) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func icon(_ method: PaymentMethod) -> some View {
        Image(systemName: method.symbol).accessibilityLabel(method.title)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SalesHistoryView()
    }
    .previewEnvironment()
}
#endif
