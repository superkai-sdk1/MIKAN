import SwiftUI

/// «Чек»: the appointment or client it is for, editable lines, the jewelry catalog, «Услуга» and «Оплатить · N ₽».
/// Checkout itself is the `CheckoutView` sheet on the POS root (bound to `cart.isCheckoutPresented`).
struct ReceiptView: View {
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    /// Owned by the POS hub, so the catalog stays loaded between receipts.
    let catalog: Remote<[Product]>

    @State private var search = ""
    @State private var category: String?
    @State private var showsServiceSheet = false
    @State private var addCount = 0

    private static let gridColumns = 2
    private static let tileSpacing: CGFloat = 12

    private var isSearching: Bool { !search.trimmed.isEmpty }
    private var products: [Product] { catalog.value ?? [] }
    private var categories: [String] { ProductCatalogFilter.categories(of: products) }
    private var filtered: [Product] { ProductCatalogFilter.apply(products, query: search, category: category) }

    var body: some View {
        List {
            if !isSearching {
                ReceiptHeaderSection()
                ReceiptLinesSection()
            }
            catalogSection
        }
        .auraBackground()
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Поиск украшений")
        .safeAreaBar(edge: .bottom) {
            CartBar { showsServiceSheet = true }
        }
        .refreshable { await loadCatalog() }
        .task { await loadCatalog() }
        .remoteErrorAlert(catalog)
        .navigationTitle("Чек")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsServiceSheet) {
            AddServiceSheet()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addCount)
    }

    private var catalogSection: some View {
        Section {
            if !categories.isEmpty {
                CategoryChips(categories: categories, selection: $category)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            catalogContent
        } header: {
            Text(isSearching ? "Найдено в каталоге" : "Добавить украшение")
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if catalog.value != nil {
            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(ProductCatalogFilter.rows(filtered, columns: Self.gridColumns), id: \.self) { row in
                    tileRow(row)
                        .listRowInsets(EdgeInsets(top: Self.tileSpacing / 2, leading: 0, bottom: Self.tileSpacing / 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        } else if let failure = catalog.failure {
            ErrorStateView(message: failure, retry: loadCatalog)
                .listRowBackground(Color.clear)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
                .listRowBackground(Color.clear)
        }
    }

    private func tileRow(_ row: [Product]) -> some View {
        HStack(alignment: .top, spacing: Self.tileSpacing) {
            ForEach(row) { product in
                ProductTile(product: product, inCart: cart.quantity(ofProduct: product.id)) {
                    cart.add(product: product)
                    addCount += 1
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(row.count..<Self.gridColumns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView.search(text: search)
        } else if category != nil {
            ContentUnavailableView("В этой категории пусто", systemImage: "sparkles")
        } else {
            ContentUnavailableView(
                "Нет украшений",
                systemImage: "sparkles",
                description: Text("Добавьте украшения на вкладке «Склад» — они появятся здесь. Услугу можно добавить кнопкой «Услуга».")
            )
        }
    }

    private func loadCatalog() async {
        await catalog.load { try await api.products(kind: .jewelry) }
    }
}

#if DEBUG
#Preview("По записи") {
    let state = PreviewData.appState()
    state.cart.prefill(from: PreviewData.appointments[0])
    state.cart.add(product: PreviewData.labret)
    return NavigationStack {
        ReceiptView(catalog: Remote(PreviewData.products.filter { $0.kind == .jewelry }))
    }
    .appEnvironment(state)
}

#Preview("Без записи") {
    NavigationStack {
        ReceiptView(catalog: Remote(PreviewData.products.filter { $0.kind == .jewelry }))
    }
    .previewEnvironment()
}
#endif
