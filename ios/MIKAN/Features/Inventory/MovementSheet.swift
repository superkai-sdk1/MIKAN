import SwiftUI

/// Приход / Списание / Расход / Инвентаризация (adjustment = new absolute count).
struct MovementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let product: Product
    let onDone: (MovementResult) -> Void

    @State private var type: MovementType
    @State private var quantity: Int?
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var movementKey = IdempotencyKey()

    init(product: Product, initialType: MovementType, onDone: @escaping (MovementResult) -> Void) {
        self.product = product
        self.onDone = onDone
        _type = State(initialValue: initialType)
        _quantity = State(initialValue: initialType == .adjustment ? product.quantity : nil)
    }

    private var resulting: Int? {
        guard let quantity else { return nil }
        switch type {
        case .receipt: return product.quantity + quantity
        case .writeoff, .usage: return product.quantity - quantity
        case .adjustment: return quantity
        case .sale, .returned: return nil
        }
    }

    private var isValid: Bool {
        guard let quantity, let resulting else { return false }
        if type == .adjustment { return quantity >= 0 && quantity != product.quantity }
        return quantity > 0 && resulting >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Операция", selection: $type) {
                        ForEach(MovementType.manual) { type in
                            Text(type.shortTitle).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    NumberField.optionalInteger(
                        type == .adjustment ? "Фактически" : "Количество",
                        value: $quantity,
                        unit: product.unitLabel
                    )
                    LabeledContent("Сейчас", value: "\(product.quantity) \(product.unitLabel)")
                    if let resulting {
                        LabeledContent("Станет") {
                            Text("\(resulting) \(product.unitLabel)")
                                .fontWeight(.semibold)
                                .foregroundStyle(resulting < 0 ? Color.red : Color.primary)
                        }
                        .monospacedDigit()
                    }
                } header: {
                    Text(product.name)
                } footer: {
                    if let resulting, resulting < 0 {
                        Text("Нельзя списать больше, чем есть на складе.").foregroundStyle(.red)
                    } else {
                        Text(type.hint)
                    }
                }
                Section("Комментарий") {
                    TextField("Поставщик, причина списания…", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Провести", action: save).disabled(!isValid) }
                }
            }
            .onChange(of: type) { _, newType in
                quantity = newType == .adjustment ? product.quantity : nil
            }
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Операция могла пройти", retry: save)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let quantity else { return }
        let body = MovementBody(type: type, quantity: quantity, note: Nullable(note.nonEmpty))
        let key = movementKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let result = try await api.addMovement(productId: product.id, body, idempotencyKey: key)
                onDone(result)
                dismiss()
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если операция уже прошла, второй раз она не проведётся."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    MovementSheet(product: PreviewData.labret, initialType: .receipt) { _ in }
        .previewEnvironment()
}
#endif
