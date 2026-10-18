import SwiftUI

/// Multi-select of warehouse products for a service: compatible jewelry or the consumables of its norm.
/// Search, category chips in the warehouse order, rows grouped by category with a photo, stock and a checkmark.
/// «Готово» returns the chosen ids: the ones chosen before keep their place, new ones follow in list order.
struct ServiceProductPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReferenceStore.self) private var reference

    let kind: ProductKind
    let title: String
    /// Under the list: what the choice is for.
    let footer: String
    let limit: Int
    let onDone: ([Int]) -> Void

    private let initial: [Int]
    /// Active products of `kind`, plus inactive ones chosen before.
    private let options: [Product]

    @State private var selection: Set<Int>
    @State private var search = ""
    @State private var category: String?
    @State private var showsSelectedOnly = false

    init(
        kind: ProductKind,
        products: [Product],
        selected: [Int],
        title: String,
        footer: String,
        limit: Int,
        onDone: @escaping ([Int]) -> Void
    ) {
        self.kind = kind
        self.title = title
        self.footer = footer
        self.limit = limit
        self.onDone = onDone
        initial = selected
        options = ServiceLinkedProducts.options(products, kind: kind, linked: Set(selected))
        _selection = State(initialValue: Set(selected))
    }

    private var categories: [String] {
        ProductCatalogFilter.categories(of: options, kind: kind, registry: reference.categories)
    }

    private var groups: [ProductCategoryGroup] {
        let base = showsSelectedOnly ? options.filter { selection.contains($0.id) } : options
        let found = ProductCatalogFilter.apply(base, kind: kind, query: search, category: category)
        return ProductCatalogFilter.grouped(found, categories: categories)
    }

    var body: some View {
        NavigationStack {
            List {
                if categories.count > 1 {
                    CategoryChips(categories: categories, selection: $category)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.products) { product in
                            row(product)
                        }
                    }
                }
                Section {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt)
            .overlay { emptyState }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { try? await reference.ensureCategories() }
        }
    }

    // MARK: - Rows

    private func row(_ product: Product) -> some View {
        let isSelected = selection.contains(product.id)
        return Button {
            toggle(product.id)
        } label: {
            HStack(spacing: 12) {
                ProductThumbnail(path: product.photoUrl, size: 52, placeholderSymbol: CatalogSection(kind: kind).symbol)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !product.active {
                            StatusBadge(text: "Скрыто", color: .gray)
                        }
                    }
                    if let details = details(product) {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProductStockLine(product: product)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && selection.count >= limit)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// «Лабрет · Титан ASTM F136 · 1.2 мм (16G)» for jewelry; the category for consumables.
    private func details(_ product: Product) -> String? {
        let parts = kind == .jewelry ? [product.material.nonEmpty, product.thicknessText] : [product.category.nonEmpty]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private var searchPrompt: String {
        kind == .jewelry ? "Название, артикул, материал, размер" : "Название или артикул"
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Отмена", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Готово", action: done)
        }
        ToolbarItem(placement: .bottomBar) {
            Button {
                withAnimation(.snappy) { showsSelectedOnly.toggle() }
            } label: {
                Label(
                    showsSelectedOnly ? "Показать все" : "Выбрано: \(selection.count)",
                    systemImage: showsSelectedOnly ? "list.bullet" : "checkmark.circle"
                )
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
            }
            .disabled(selection.isEmpty && !showsSelectedOnly)
        }
        if !selection.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Снять все", role: .destructive) {
                    withAnimation(.snappy) {
                        selection = []
                        showsSelectedOnly = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if groups.isEmpty {
            if !search.trimmed.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if options.isEmpty {
                ContentUnavailableView(
                    kind == .jewelry ? "Украшений пока нет" : "Расходников пока нет",
                    systemImage: CatalogSection(kind: kind).symbol,
                    description: Text("Добавьте их на складе — они появятся здесь.")
                )
            } else {
                ContentUnavailableView("Ничего не выбрано", systemImage: "checkmark.circle")
            }
        }
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) {
            selection.remove(id)
        } else if selection.count < limit {
            selection.insert(id)
        }
    }

    private func done() {
        onDone(ServiceJewelryLinks.applying(selection: selection, to: initial, catalogOrder: options.map(\.id)))
        dismiss()
    }
}

/// Stock of a product in one line: sizes in stock for jewelry and goods, the count or the marked presence for
/// consumables; a coloured dot shows whether it runs low.
struct ProductStockLine: View {
    let product: Product

    private var color: Color { StockAvailability(product).color }

    private var text: String {
        product.kind == .consumable ? ServiceLinkText.consumableStock(product) : ServiceLinkText.sizesInStock(product)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
            if product.kind.isSold {
                Spacer(minLength: 6)
                Text(product.priceText)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("Украшения") {
    ServiceProductPicker(
        kind: .jewelry, products: PreviewData.products, selected: [1],
        title: "Совместимые украшения", footer: "Бот предложит их клиентам.", limit: 100
    ) { _ in }
    .previewEnvironment()
}
#endif
