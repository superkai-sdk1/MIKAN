import SwiftUI

struct SaleDetailView: View {
    @State private var sale: Sale
    @State private var showsRefund = false
    var onChange: ((Sale) -> Void)?

    init(sale: Sale, onChange: ((Sale) -> Void)? = nil) {
        _sale = State(initialValue: sale)
        self.onChange = onChange
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Продажа №\(sale.number)").font(.title2.weight(.bold))
                        Spacer()
                        if sale.isRefunded {
                            StatusBadge(text: "Возврат", color: .red, systemImage: "arrow.uturn.backward")
                        }
                    }
                    Text(DateText.dateTime(sale.createdAt)).foregroundStyle(.secondary)
                    Text("Продал(а): \(sale.employee.name)").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if let client = sale.client {
                Section("Клиент") {
                    NavigationLink {
                        ClientDetailView(clientId: client.id)
                    } label: {
                        Label(client.name, systemImage: "person.crop.circle")
                    }
                }
            }
            SaleItemsSection(sale: sale)
            SalePaymentsSection(payments: sale.payments)
            if let note = sale.note.nonEmpty {
                Section("Комментарий") { Text(note) }
            }
            if sale.isRefunded {
                Section("Возврат") {
                    if let refundedAt = sale.refundedAt {
                        LabeledContent("Дата", value: DateText.dateTime(refundedAt))
                    }
                    if let reason = sale.refundReason.nonEmpty {
                        LabeledContent("Причина", value: reason)
                    }
                }
            }
        }
        .navigationTitle("Чек №\(sale.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sale.isRefunded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Возврат", systemImage: "arrow.uturn.backward") { showsRefund = true }
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .sheet(isPresented: $showsRefund) {
            RefundSheet(sale: sale) { refunded in
                sale = refunded
                onChange?(refunded)
            }
        }
    }
}

private struct RefundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ShiftStore.self) private var shift
    let sale: Sale
    let onRefunded: (Sale) -> Void

    @State private var reason = ""
    @State private var restock = true
    @State private var confirms = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var refundKey = IdempotencyKey()
    /// Cash refunds need an open shift; the server answers 409 otherwise.
    @State private var shiftRequiredMessage: String?
    @State private var showsOpenShift = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Сумма возврата") { MoneyText(sale.total).fontWeight(.semibold) }
                    if sale.payments.cash > 0 {
                        LabeledContent("Из кассы наличными") { MoneyText(sale.payments.cash) }
                    }
                }
                Section {
                    TextField("Например, не подошёл размер", text: $reason, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Причина")
                } footer: {
                    if sale.payments.cash > 0 && shift.current == nil {
                        Text("Для возврата наличных нужна открытая смена.").foregroundStyle(.orange)
                    } else {
                        Text("Обязательно укажите причину.")
                    }
                }
                if sale.hasProducts {
                    Section {
                        Toggle("Вернуть украшения на склад", isOn: $restock)
                    } footer: {
                        Text("Выключите, если украшение использовано или повреждено.")
                    }
                }
            }
            .navigationTitle("Возврат №\(sale.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Вернуть") { confirms = true }.disabled(reason.trimmed.isEmpty)
                    }
                }
            }
            .confirmationDialog("Оформить возврат?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Вернуть \(Money.format(sale.total))", role: .destructive, action: refund)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Продажа будет отмечена как возвращённая. Это действие нельзя отменить.")
            }
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Возврат мог пройти", retry: refund)
            .alert("Смена закрыта", isPresented: Binding(
                get: { shiftRequiredMessage != nil },
                set: { if !$0 { shiftRequiredMessage = nil } }
            )) {
                Button("Открыть смену") { showsOpenShift = true }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(shiftRequiredMessage ?? "")
            }
            .sheet(isPresented: $showsOpenShift) {
                OpenShiftSheet()
            }
            .task { if !shift.hasLoaded { await shift.refresh() } }
        }
    }

    private func refund() {
        let body = RefundBody(reason: reason.trimmed, restock: sale.hasProducts && restock)
        let key = refundKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let refunded = try await api.refundSale(id: sale.id, body, idempotencyKey: key)
                onRefunded(refunded)
                await shift.refresh()
                dismiss()
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если возврат уже прошёл, второй раз он не проведётся."
            } catch let error as APIError where error.status == 409 && sale.payments.cash > 0 && shift.current == nil {
                shiftRequiredMessage = error.message
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Loads a sale by id (e.g. from an appointment's `saleId`).
struct SaleLoaderView: View {
    @Environment(APIClient.self) private var api
    let saleId: Int
    @State private var sale = Remote<Sale>()

    var body: some View {
        Group {
            if let value = sale.value {
                SaleDetailView(sale: value)
            } else {
                RemoteStateOverlay(remote: sale, retry: load)
            }
        }
        .task { await load() }
    }

    private func load() async {
        await sale.load { try await api.sale(id: saleId) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SaleDetailView(sale: PreviewData.sale)
    }
    .previewEnvironment()
}
#endif
