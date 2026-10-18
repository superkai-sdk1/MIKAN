import SwiftUI

/// «Покупка» of a consumable tracked as «есть / нет»: what was paid (counted as a stock expense in the analytics),
/// a note and the status after the restock.
struct ConsumablePurchaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let product: Product
    let onDone: (MovementResult) -> Void

    @State private var draft = ConsumablePurchaseDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var purchaseKey = IdempotencyKey()

    private var canSave: Bool { draft.canSubmit && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField.optionalMoney("Сколько заплатили", value: $draft.amount, placeholder: "0")
                } header: {
                    Text(product.name)
                } footer: {
                    if let message = draft.validationMessage, !draft.isBlank {
                        Text(message).foregroundStyle(.red)
                    } else {
                        Text("Сумма попадёт в расходы склада в аналитике.")
                    }
                }
                Section("Комментарий") {
                    TextField("Поставщик, сколько упаковок", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Наличие после покупки") {
                    PresenceStatusPicker(selection: draft.status, isEnabled: !isSaving) { draft.status = $0 }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Покупка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Покупка могла сохраниться", retry: save)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let body = draft.body else { return }
        let key = purchaseKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let result = try await api.recordPurchase(
                    productId: product.id,
                    amount: body.amount,
                    note: body.note,
                    presenceStatus: body.presenceStatus,
                    idempotencyKey: key
                )
                onDone(result)
                dismiss()
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если покупка уже записана, второй раз она не сохранится."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    ConsumablePurchaseSheet(product: PreviewData.antiseptic) { _ in }
        .previewEnvironment()
}
#endif
