import SwiftUI

struct ShiftsHistoryView: View {
    @Environment(APIClient.self) private var api
    @State private var shifts = Remote<[CashShift]>()
    @State private var total = 0
    @State private var isLoadingMore = false

    private static let pageSize = 50

    var body: some View {
        List {
            ForEach(shifts.value ?? []) { shift in
                NavigationLink {
                    ShiftDetailView(shiftId: shift.id)
                } label: {
                    ShiftRow(shift: shift)
                }
                .task { await loadMore(after: shift) }
            }
            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .overlay {
            RemoteStateOverlay(remote: shifts, retry: load) {
                ContentUnavailableView(
                    "Смен ещё не было",
                    systemImage: "tray",
                    description: Text("Откройте первую смену на экране кассы.")
                )
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(shifts)
        .navigationTitle("Смены")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        await shifts.load {
            let page = try await api.shifts(limit: Self.pageSize)
            total = page.total ?? page.items.count
            return page.items
        }
    }

    private func loadMore(after shift: CashShift) async {
        guard let items = shifts.value, shift.id == items.last?.id, items.count < total, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.shifts(limit: Self.pageSize, offset: items.count)
            let known = Set(items.map(\.id))
            shifts.update { $0 + page.items.filter { !known.contains($0.id) } }
        } catch is CancellationError {
            return
        } catch {
            shifts.transientError = error.userMessage
        }
    }
}

private struct ShiftRow: View {
    let shift: CashShift

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DateText.dayMonth(shift.openedAt)).font(.headline)
                Text(timeRange).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if shift.isOpen {
                    StatusBadge(text: "Открыта", color: .green)
                } else if let difference = shift.difference {
                    DifferenceText(amount: difference).font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 16) {
                value("Ожидалось", shift.expectedCash)
                if let closing = shift.closingCash { value("Пересчитано", closing) }
                value("Выручка", shift.summary.revenue)
            }
            Text(shift.openedBy.name).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        guard let closedAt = shift.closedAt else { return "с \(DateText.time(shift.openedAt))" }
        return DateText.timeRange(shift.openedAt, closedAt)
    }

    private func value(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            MoneyText(amount).font(.subheadline)
        }
    }
}

struct ShiftDetailView: View {
    @Environment(APIClient.self) private var api
    let shiftId: Int
    @State private var shift = Remote<CashShift>()

    var body: some View {
        List {
            if let shift = shift.value {
                content(shift)
            }
        }
        .overlay {
            if shift.value == nil { RemoteStateOverlay(remote: shift, retry: load) }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(shift)
        .navigationTitle(shift.value.map { "Смена \(DateText.dayMonth($0.openedAt))" } ?? "Смена")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ shift: CashShift) -> some View {
        Section("Смена") {
            LabeledContent("Открыл(а)", value: "\(shift.openedBy.name), \(DateText.dateTime(shift.openedAt))")
            if let closedAt = shift.closedAt {
                LabeledContent("Закрыл(а)", value: "\(shift.closedBy?.name ?? "—"), \(DateText.dateTime(closedAt))")
            }
            if let note = shift.note.nonEmpty {
                LabeledContent("Комментарий", value: note)
            }
        }
        Section("Продажи") {
            LabeledContent("Выручка") { MoneyText(shift.summary.revenue) }
            LabeledContent("Количество", value: "\(shift.summary.salesCount)")
            LabeledContent("Наличные") { MoneyText(shift.summary.cash) }
            LabeledContent("Карта") { MoneyText(shift.summary.card) }
            LabeledContent("Перевод") { MoneyText(shift.summary.transfer) }
            if shift.summary.qr > 0 {
                LabeledContent("QR-код") { MoneyText(shift.summary.qr) }
            }
            if shift.summary.refunds > 0 {
                LabeledContent("Возвраты") { MoneyText(shift.summary.refunds) }
            }
        }
        Section("Наличные в кассе") {
            LabeledContent("На начало") { MoneyText(shift.openingCash) }
            LabeledContent("Внесения") { MoneyText(shift.summary.cashIn) }
            LabeledContent("Изъятия") { MoneyText(shift.summary.cashOut) }
            LabeledContent("Возвраты наличными") { MoneyText(shift.summary.cashRefunds) }
            LabeledContent("Ожидалось") { MoneyText(shift.expectedCash).fontWeight(.semibold) }
            if let closing = shift.closingCash {
                LabeledContent("Пересчитано") { MoneyText(closing) }
            }
            if let difference = shift.difference {
                LabeledContent("Расхождение") { DifferenceText(amount: difference) }
            }
        }
        if !shift.operations.isEmpty {
            Section("Внесения и изъятия") {
                ForEach(shift.operations) { operation in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(operation.reason.nonEmpty ?? (operation.type == .deposit ? "Внесение" : "Изъятие"))
                            Text("\(operation.employee.name) · \(DateText.time(operation.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((operation.type == .deposit ? "+" : "−") + Money.format(operation.amount))
                            .monospacedDigit()
                            .foregroundStyle(operation.type == .deposit ? Color.green : Color.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func load() async {
        await shift.load { try await api.shift(id: shiftId) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ShiftsHistoryView()
    }
    .previewEnvironment()
}
#endif
