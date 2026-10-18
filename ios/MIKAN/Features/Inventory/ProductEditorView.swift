import SwiftUI

/// Product card editor: photos, main fields, jewelry characteristics, sizes, prices, suitable services.
struct ProductEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let product: Product?
    let categories: Set<String>
    let onSaved: (Product) -> Void

    @State private var draft: ProductDraft
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(product: Product?, defaultKind: ProductKind, categories: Set<String>, onSaved: @escaping (Product) -> Void) {
        self.product = product
        self.categories = categories
        self.onSaved = onSaved
        _draft = State(initialValue: ProductDraft(product: product, defaultKind: defaultKind))
    }

    private var canSave: Bool { draft.canSave && !isSaving && !isUploading }

    var body: some View {
        NavigationStack {
            Form {
                ProductPhotosEditorSection(draft: $draft, isUploading: $isUploading, errorMessage: $errorMessage)
                mainSection
                if draft.isJewelry {
                    ProductCharacteristicsSection(draft: $draft)
                }
                if draft.showsSizesEditor {
                    ProductSizesEditor(draft: $draft)
                }
                accountingSection
                if draft.isJewelry {
                    servicesSection
                }
                descriptionSection
                Section {
                    Toggle("Активен", isOn: $draft.active)
                } footer: {
                    Text("Неактивные позиции скрыты из кассы и от бота, но остаются на складе.")
                }
            }
            .disabled(isSaving)
            .safeAreaInset(edge: .bottom) { saveBlockerBanner }
            .navigationTitle(product == nil ? "Новая позиция" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                        .disabled(isSaving || isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving || isUploading)
            // Only names the linked services in the summary row; the picker reports its own load errors.
            .task { try? await reference.ensureServices() }
            .errorAlert($errorMessage)
        }
    }

    // MARK: - Sections

    private var mainSection: some View {
        Section {
            Picker("Тип", selection: $draft.kind.animation()) {
                ForEach(ProductKind.allCases) { kind in
                    Text(kind.singularTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Название", text: $draft.name)
            TextField("Артикул", text: $draft.sku)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            HStack {
                TextField("Категория, например «Лабрет»", text: $draft.category)
                if !categories.isEmpty {
                    Menu {
                        ForEach(categories.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { option in
                            Button(option) { draft.category = option }
                        }
                    } label: {
                        Image(systemName: "list.bullet.circle")
                            .accessibilityLabel("Выбрать категорию")
                    }
                }
            }
            if !draft.isJewelry {
                TextField("Материал", text: $draft.material)
                if !draft.showsSizesEditor {
                    TextField("Размер (необязательно)", text: firstSize(\.name, fallback: ""))
                }
            }
        } header: {
            Text("Основное")
        } footer: {
            // Not red: on a new card an empty name is the starting point, not a mistake.
            if let message = draft.nameMessage {
                Text(message)
            }
        }
    }

    private var accountingSection: some View {
        Section {
            if draft.isJewelry {
                NumberField.money("Цена продажи", value: $draft.price)
            }
            NumberField.optionalMoney("Себестоимость", value: $draft.cost)
            if draft.isJewelry, let markup = ProductMarkup.text(price: draft.price, cost: draft.cost) {
                LabeledContent("Наценка", value: markup).monospacedDigit()
            }
            if !draft.showsSizesEditor {
                singleSizeStockRows
            }
            unitRow
            TextField("Поставщик", text: $draft.supplier)
        } header: {
            Text("Цена и учёт")
        } footer: {
            if let message = draft.unitMessage ?? draft.supplierMessage {
                Text(message).foregroundStyle(.red)
            } else if draft.isJewelry && draft.hasSeveralSizes {
                Text("Цена и себестоимость — для всех размеров; у размера могут быть свои.")
            }
        }
    }

    /// A consumable has one size: its stock fields live here instead of the sizes editor.
    @ViewBuilder
    private var singleSizeStockRows: some View {
        if let size = draft.sizes.first {
            if size.isNew {
                NumberField.integer("Начальный остаток", value: firstSize(\.initialQuantity, fallback: 0), unit: draft.unitLabel)
            } else {
                LabeledContent("На складе", value: InventoryText.quantity(size.quantity, unit: draft.unitLabel))
                    .monospacedDigit()
            }
            NumberField.integer("Минимальный остаток", value: firstSize(\.minQuantity, fallback: 0), unit: draft.unitLabel)
        }
    }

    private var unitRow: some View {
        HStack {
            Text("Единица")
            Spacer()
            TextField(ProductLimits.defaultUnit, text: $draft.unit)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Menu {
                ForEach(ProductLimits.unitSuggestions, id: \.self) { option in
                    Button(option) { draft.unit = option }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityLabel("Выбрать единицу")
            }
        }
    }

    private var servicesSection: some View {
        Section {
            NavigationLink {
                ProductServicesPicker(draft: $draft)
            } label: {
                LabeledContent("Подходит для", value: servicesSummary)
            }
        } header: {
            Text("Подходящие услуги")
        } footer: {
            if let message = draft.servicesMessage {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Зоны прокола, для которых подходит украшение. Бот называет их, когда рассказывает об украшениях.")
            }
        }
    }

    /// «Хеликс, Септум» or «Хеликс, Септум и ещё 3».
    private var servicesSummary: String {
        let names = ProductServiceOptions.names(of: draft.serviceIds, in: reference.services)
        guard !draft.serviceIds.isEmpty else { return "Не выбрано" }
        guard !names.isEmpty else { return Plural.count(draft.serviceIds.count, one: "услуга", few: "услуги", many: "услуг") }
        let shown = names.prefix(2).joined(separator: ", ")
        let rest = draft.serviceIds.count - min(2, names.count)
        return rest > 0 ? "\(shown) и ещё \(rest)" : shown
    }

    private var descriptionSection: some View {
        Section {
            TextField("Описание", text: $draft.description, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Описание")
        } footer: {
            if draft.isJewelry {
                Text("Описание видит бот, когда рассказывает клиентам об украшениях.")
            }
        }
    }

    /// Why «Сохранить» is disabled when the reason is a field the user already touched or cannot see.
    @ViewBuilder
    private var saveBlockerBanner: some View {
        if let message = draft.validationMessage, draft.nameMessage == nil {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .accessibilityLabel("Нельзя сохранить: \(message)")
        }
    }

    // MARK: - Helpers

    /// A field of the only size (consumables and products without sizes).
    private func firstSize<Value>(_ keyPath: WritableKeyPath<SizeDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { draft.sizes.first?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard !draft.sizes.isEmpty else { return }
                draft.sizes[0][keyPath: keyPath] = value
            }
        )
    }

    // MARK: - Save

    private func save() {
        guard draft.canSave else { return }
        let body = draft.body
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = if let product {
                    try await api.updateProduct(id: product.id, body)
                } else {
                    try await api.createProduct(body)
                }
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview("Новое украшение") {
    ProductEditorView(product: nil, defaultKind: .jewelry, categories: ["Лабрет", "Кольцо"]) { _ in }
        .previewEnvironment()
}

#Preview("Лабрет с размерами") {
    ProductEditorView(product: PreviewData.labret, defaultKind: .jewelry, categories: ["Лабрет", "Кольцо"]) { _ in }
        .previewEnvironment()
}
#endif
