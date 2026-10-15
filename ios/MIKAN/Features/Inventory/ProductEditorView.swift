import PhotosUI
import SwiftUI

struct ProductEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api

    let product: Product?
    let categories: Set<String>
    let onSaved: (Product) -> Void

    @State private var kind: ProductKind
    @State private var name: String
    @State private var sku: String
    @State private var category: String
    @State private var material: String
    @State private var size: String
    @State private var price: Int
    @State private var cost: Int?
    @State private var minQuantity: Int
    @State private var unit: String
    @State private var initialQuantity: Int
    @State private var description: String
    @State private var active: Bool
    @State private var photoUrl: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let unitSuggestions = ["шт", "пара", "уп", "мл", "г", "м"]

    init(product: Product?, defaultKind: ProductKind, categories: Set<String>, onSaved: @escaping (Product) -> Void) {
        self.product = product
        self.categories = categories
        self.onSaved = onSaved
        _kind = State(initialValue: product?.kind ?? defaultKind)
        _name = State(initialValue: product?.name ?? "")
        _sku = State(initialValue: product?.sku ?? "")
        _category = State(initialValue: product?.category ?? "")
        _material = State(initialValue: product?.material ?? "")
        _size = State(initialValue: product?.size ?? "")
        _price = State(initialValue: product?.price ?? 0)
        _cost = State(initialValue: product?.cost)
        _minQuantity = State(initialValue: product?.minQuantity ?? 0)
        _unit = State(initialValue: product?.unitLabel ?? "шт")
        _initialQuantity = State(initialValue: 0)
        _description = State(initialValue: product?.description ?? "")
        _active = State(initialValue: product?.active ?? true)
        _photoUrl = State(initialValue: product?.photoUrl)
    }

    private var canSave: Bool { !name.trimmed.isEmpty && !unit.trimmed.isEmpty && !isSaving && !isUploading }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                mainSection
                accountingSection
                Section {
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Описание")
                } footer: {
                    if kind == .jewelry {
                        Text("Описание видит бот, когда рассказывает клиентам об украшениях.")
                    }
                }
                Section {
                    Toggle("Активен", isOn: $active)
                } footer: {
                    Text("Неактивные позиции скрыты из кассы и от бота, но остаются на складе.")
                }
            }
            .navigationTitle(product == nil ? "Новая позиция" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving || isUploading)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
            .errorAlert($errorMessage)
        }
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    ProductThumbnail(path: photoUrl, size: 84)
                    if isUploading {
                        ProgressView()
                            .frame(width: 84, height: 84)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    let pickerTitle = photoUrl == nil ? "Добавить фото" : "Заменить фото"
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    .disabled(isUploading)
                    if photoUrl != nil {
                        Button("Убрать фото", systemImage: "trash", role: .destructive) { photoUrl = nil }
                            .disabled(isUploading)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }

    private var mainSection: some View {
        Section {
            Picker("Тип", selection: $kind) {
                ForEach(ProductKind.allCases) { kind in
                    Text(kind.singularTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Название", text: $name)
            TextField("Артикул", text: $sku)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            HStack {
                TextField("Категория", text: $category)
                if !categories.isEmpty {
                    Menu {
                        ForEach(categories.sorted(), id: \.self) { option in
                            Button(option) { category = option }
                        }
                    } label: {
                        Image(systemName: "list.bullet.circle")
                            .accessibilityLabel("Выбрать категорию")
                    }
                }
            }
            TextField("Материал", text: $material)
            TextField("Размер", text: $size)
        }
    }

    private var accountingSection: some View {
        Section("Цена и учёт") {
            if kind == .jewelry {
                NumberField.money("Цена продажи", value: $price)
            }
            NumberField.optionalMoney("Себестоимость", value: $cost)
            NumberField.integer("Минимальный остаток", value: $minQuantity, unit: unit.nonEmpty ?? "шт")
            HStack {
                Text("Единица")
                Spacer()
                TextField("шт", text: $unit)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Menu {
                    ForEach(Self.unitSuggestions, id: \.self) { option in
                        Button(option) { unit = option }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityLabel("Выбрать единицу")
                }
            }
            if product == nil {
                NumberField.integer("Начальный остаток", value: $initialQuantity, unit: unit.nonEmpty ?? "шт")
            }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImagePreparerError.unreadable
            }
            let jpeg = try await ImagePreparer.jpegInBackground(from: data)
            photoUrl = try await api.uploadImage(jpegData: jpeg).url
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func save() {
        let body = ProductBody(
            kind: kind,
            name: name.trimmed,
            sku: Nullable(sku.nonEmpty),
            category: Nullable(category.nonEmpty),
            material: Nullable(material.nonEmpty),
            size: Nullable(size.nonEmpty),
            description: Nullable(description.nonEmpty),
            price: kind == .jewelry ? price : (product?.price ?? 0),
            cost: Nullable(cost),
            minQuantity: max(0, minQuantity),
            unit: unit.trimmed,
            photoUrl: Nullable(photoUrl),
            active: active,
            initialQuantity: product == nil && initialQuantity > 0 ? initialQuantity : nil
        )
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
#Preview {
    ProductEditorView(product: nil, defaultKind: .jewelry, categories: ["Лабрет", "Кольцо"]) { _ in }
        .previewEnvironment()
}
#endif
