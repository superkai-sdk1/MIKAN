import SwiftUI

struct OpenShiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ShiftStore.self) private var shift
    @State private var openingCash: Int?
    @State private var lastClosing: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField.optionalMoney("Наличные в кассе", value: $openingCash, placeholder: "0")
                } footer: {
                    if let lastClosing {
                        Text("При закрытии прошлой смены было \(Money.format(lastClosing)).")
                    } else {
                        Text("Пересчитайте наличные в кассе перед началом смены.")
                    }
                }
            }
            .navigationTitle("Открыть смену")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Открыть", action: open).disabled(openingCash == nil) }
                }
            }
            .errorAlert($errorMessage)
            .task { await loadLastClosing() }
        }
        .presentationDetents([.medium])
    }

    private func loadLastClosing() async {
        guard let last = try? await api.shifts(limit: 1).items.first, let closing = last.closingCash else { return }
        lastClosing = closing
        if openingCash == nil { openingCash = closing }
    }

    private func open() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await shift.open(openingCash: openingCash ?? 0)
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Внесение / изъятие наличных.
struct CashOperationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShiftStore.self) private var shift
    let type: CashOperationType
    @State private var amount: Int?
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var operationKey = IdempotencyKey()

    private var suggestions: [String] {
        type == .deposit ? ["Размен", "Возврат из сейфа"] : ["Инкассация", "Расходы студии", "Размен"]
    }

    private var title: String { type == .deposit ? "Внести наличные" : "Изъять наличные" }
    private var canSave: Bool { (amount ?? 0) > 0 && !reason.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField.optionalMoney("Сумма", value: $amount, placeholder: "0")
                }
                Section {
                    TextField("Причина", text: $reason)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { reason = suggestion }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                } header: {
                    Text("Причина")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button(type == .deposit ? "Внести" : "Изъять", action: save).disabled(!canSave) }
                }
            }
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Операция могла пройти", retry: save)
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let body = CashOperationBody(type: type, amount: amount ?? 0, reason: reason.trimmed)
        let key = operationKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await shift.addOperation(body, idempotencyKey: key)
                dismiss()
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если операция уже прошла, второй раз она не проведётся."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Closing the shift: counted cash and the difference against the expected amount, confirmed before sending.
struct CloseShiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShiftStore.self) private var shiftStore
    let shift: CashShift
    @State private var counted: Int?
    @State private var note = ""
    @State private var confirms = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var closed: CashShift?

    private var difference: Int? { counted.map { $0 - shift.expectedCash } }

    var body: some View {
        NavigationStack {
            Form {
                if let closed {
                    closedSummary(closed)
                } else {
                    breakdown
                    ShiftDepositsSection(summary: shift.summary)
                    Section {
                        NumberField.optionalMoney("Пересчитано", value: $counted, placeholder: "0")
                        if let difference {
                            LabeledContent("Расхождение") { DifferenceText(amount: difference) }
                        }
                    } header: {
                        Text("Наличные в кассе")
                    } footer: {
                        Text("Пересчитайте наличные и введите фактическую сумму.")
                    }
                    Section("Комментарий") {
                        TextField("Например, причина расхождения", text: $note, axis: .vertical)
                    }
                }
            }
            .navigationTitle(closed == nil ? "Закрыть смену" : "Смена закрыта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if closed == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving { ProgressView() } else { Button("Закрыть") { confirms = true }.disabled(counted == nil) }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Закрыть смену?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Закрыть смену", role: .destructive, action: close)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(confirmationText)
            }
            .errorAlert($errorMessage)
            .sensoryFeedback(.success, trigger: closed != nil)
        }
    }

    private var confirmationText: String {
        guard let counted, let difference else { return "" }
        let diffText = difference == 0 ? "без расхождений" : "расхождение \(Money.formatSigned(difference))"
        return "В кассе \(Money.format(counted)), ожидалось \(Money.format(shift.expectedCash)) — \(diffText)."
    }

    /// Drawer movements (prepayments taken and refunded in cash included); the expected amount is the server's.
    private var breakdown: some View {
        Section("Движение наличных") {
            ShiftDrawerRows(shift: shift)
            LabeledContent("Ожидается") { MoneyText(shift.expectedCash).fontWeight(.semibold) }
        }
    }

    private func closedSummary(_ closed: CashShift) -> some View {
        Section {
            LabeledContent("Выручка за смену") { MoneyText(closed.summary.revenue) }
            LabeledContent("Продаж") { Text("\(closed.summary.salesCount)") }
            LabeledContent("Ожидалось") { MoneyText(closed.expectedCash) }
            LabeledContent("Пересчитано") { MoneyText(closed.closingCash ?? 0) }
            LabeledContent("Расхождение") { DifferenceText(amount: closed.difference ?? 0) }
        } header: {
            Label("Смена закрыта", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        }
    }

    private func close() {
        guard let counted else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let result = try await shiftStore.close(countedCash: counted, note: note.nonEmpty)
                withAnimation { closed = result }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
