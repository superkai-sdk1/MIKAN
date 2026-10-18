import SwiftUI

/// What the movement sheet opens with: the operation and, from a size row, that size.
struct StockMovementRequest: Identifiable, Hashable {
    let id = UUID()
    let type: MovementType
    var variantId: Int?
}

/// Приход / Списание / Расход / Инвентаризация over one or several sizes, as one operation
/// (`POST /products/:id/movements/batch`; a count takes the new absolute stock of each size).
struct MovementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let productId: Int
    let onDone: (BatchMovementResult) -> Void

    @State private var draft: StockBatchDraft
    @State private var showsAllSizes = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var movementKey = IdempotencyKey()

    init(
        product: Product,
        initialType: MovementType,
        variantId: Int? = nil,
        onDone: @escaping (BatchMovementResult) -> Void
    ) {
        productId = product.id
        self.onDone = onDone
        _draft = State(initialValue: StockBatchDraft(product: product, type: initialType, preselected: variantId))
    }

    private var visibleSizes: [StockSize] { draft.visibleSizes(showingAll: showsAllSizes) }
    private var canSave: Bool { draft.canSubmit && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Операция", selection: typeBinding) {
                        ForEach(draft.availableTypes) { type in
                            Text(type.shortTitle).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if draft.hasSeveralSizes {
                    sizesSection
                } else if let size = draft.sizes.first {
                    singleSizeSection(size)
                }
                if draft.type == .receipt {
                    Section {
                        NumberField.optionalMoney(draft.unitCostTitle, value: $draft.unitCost)
                    } footer: {
                        Text("Сохранится в истории движений и станет новой себестоимостью.")
                    }
                }
                Section("Комментарий") {
                    TextField("Поставщик, причина списания…", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(draft.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Провести", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Операция могла пройти", retry: save)
        }
        .presentationDetents(draft.hasSeveralSizes ? [.large] : [.medium, .large])
    }

    // MARK: - Sections

    /// A product without sizes: one amount, as before sizes existed.
    private func singleSizeSection(_ size: StockSize) -> some View {
        Section {
            NumberField.optionalInteger(
                draft.type == .adjustment ? "Фактически" : "Количество",
                value: amountBinding(for: size),
                unit: draft.unit
            )
            LabeledContent("Сейчас", value: InventoryText.quantity(size.quantity, unit: draft.unit))
                .monospacedDigit()
            if let after = displayedResult(for: size) {
                LabeledContent("Станет") {
                    Text(InventoryText.quantity(after, unit: draft.unit))
                        .fontWeight(.semibold)
                        .foregroundStyle(after < 0 ? Color.red : Color.primary)
                }
                .monospacedDigit()
            }
        } header: {
            Text(size.name.nonEmpty.map { "\(draft.productName) — \($0)" } ?? draft.productName)
        } footer: {
            footer(hint: draft.type.hint)
        }
    }

    private var sizesSection: some View {
        Section {
            ForEach(visibleSizes) { size in
                StockSizeAmountRow(
                    size: size,
                    unit: draft.unit,
                    amount: amountBinding(for: size),
                    resulting: displayedResult(for: size)
                )
            }
            if visibleSizes.count < draft.sizes.count {
                Button("Все размеры (\(draft.sizes.count))", systemImage: "list.bullet") {
                    withAnimation(.snappy) { showsAllSizes = true }
                }
            }
        } header: {
            Text(draft.productName)
        } footer: {
            footer(hint: draft.type.sizesHint)
        }
    }

    @ViewBuilder
    private func footer(hint: String) -> some View {
        if let message = draft.validationMessage, !draft.isBlank {
            Text(message).foregroundStyle(.red)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(hint)
                if draft.hasSeveralSizes, draft.totalDelta != 0 {
                    Text("Итого: \(draft.totalDelta > 0 ? "+" : "")\(draft.totalDelta) \(draft.unit)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Bindings

    private var typeBinding: Binding<MovementType> {
        Binding(get: { draft.type }, set: { draft = draft.switching(to: $0) })
    }

    private func amountBinding(for size: StockSize) -> Binding<Int?> {
        Binding(get: { draft.amount(for: size.id) }, set: { draft = draft.settingAmount($0, for: size.id) })
    }

    /// «Станет»: the result of a touched size; a count shows the typed number even when it equals the stock.
    private func displayedResult(for size: StockSize) -> Int? {
        draft.resulting(for: size) ?? (draft.type == .adjustment ? draft.amount(for: size.id) : nil)
    }

    // MARK: - Save

    private func save() {
        guard draft.canSubmit else { return }
        let body = draft.body
        let key = movementKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let result = try await api.addMovements(productId: productId, body, idempotencyKey: key)
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

/// One size of a several-size operation: the amount field and «Сейчас → Станет».
private struct StockSizeAmountRow: View {
    let size: StockSize
    let unit: String
    @Binding var amount: Int?
    let resulting: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // «0» shows where to type: a several-size sheet starts with every field empty.
            NumberField(title: size.title, value: $amount, suffix: unit, groupsDigits: false, placeholder: "0")
            HStack(spacing: 4) {
                Text("Сейчас \(InventoryText.quantity(size.quantity, unit: unit))")
                if let resulting {
                    Image(systemName: "arrow.right").imageScale(.small)
                    Text("станет \(InventoryText.quantity(resulting, unit: unit))")
                        .fontWeight(.semibold)
                        .foregroundStyle(resultColor(resulting))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func resultColor(_ value: Int) -> Color {
        if value < 0 { return .red }
        return value <= size.minQuantity ? .orange : .primary
    }
}

extension MovementType {
    /// Footer of the several-size sheet.
    var sizesHint: String {
        switch self {
        case .receipt: "Сколько единиц каждого размера поступило. Размеры без количества не меняются."
        case .writeoff: "Брак, потеря, истёк срок — сколько списать по каждому размеру."
        case .usage: "Сколько ушло на процедуры по каждому размеру (не через завершение записи)."
        case .adjustment: "Пересчитайте остатки и исправьте те размеры, где фактическое количество другое."
        case .sale, .returned, .purchase, .other: ""
        }
    }
}

#if DEBUG
#Preview("Несколько размеров") {
    MovementSheet(product: PreviewData.labret, initialType: .receipt) { _ in }
        .previewEnvironment()
}

#Preview("Один размер") {
    MovementSheet(product: PreviewData.needles, initialType: .writeoff) { _ in }
        .previewEnvironment()
}
#endif
