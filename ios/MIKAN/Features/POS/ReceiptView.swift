import SwiftUI

/// «Чек»: the appointment or client it is for, editable lines, the jewelry / service catalog, «Услуга»
/// and «Оплатить · N ₽».
/// Checkout itself is the `CheckoutView` sheet on the POS root (bound to `cart.isCheckoutPresented`).
struct ReceiptView: View {
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference
    /// Owned by the POS hub, so the catalog stays loaded between receipts.
    let catalog: Remote<[Product]>

    @State private var catalogKind = POSCatalog.jewelry
    /// Load state of the service catalog; the services themselves live in `ReferenceStore`.
    @State private var serviceCatalog = Remote<Void>()
    @State private var hint: CatalogHint?
    @State private var search = ""
    @State private var category: String?
    @State private var showsServiceSheet = false
    /// Jewelry with several sizes whose size is being picked.
    @State private var sizePickerProduct: Product?
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
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: catalogKind.searchPrompt)
        .catalogHint($hint)
        .safeAreaBar(edge: .bottom) {
            CartBar { showsServiceSheet = true }
        }
        .refreshable {
            await loadCatalog()
            if catalogKind == .services { await loadServices(force: true) }
        }
        .task { await loadCatalog() }
        .task(id: catalogKind) {
            if catalogKind == .services, serviceCatalog.value == nil { await loadServices() }
        }
        .remoteErrorAlert(catalog)
        .navigationTitle("Чек")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsServiceSheet) {
            AddServiceSheet { text in showHint(text) }
        }
        .sheet(item: $sizePickerProduct) { picked in
            // The latest copy after a catalog refresh, so the stock of every size is current.
            let product = products.first { $0.id == picked.id } ?? picked
            SizePickerSheet(product: product) { variant in add(product, variant: variant) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addCount)
    }

    private var catalogSection: some View {
        Section {
            catalogPicker
            switch catalogKind {
            case .jewelry:
                if !categories.isEmpty {
                    CategoryChips(categories: categories, selection: $category)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                catalogContent
            case .services:
                POSServiceCatalogSection(
                    state: serviceCatalog,
                    search: search,
                    columns: Self.gridColumns,
                    spacing: Self.tileSpacing,
                    load: { await loadServices() }
                ) { text in
                    addCount += 1
                    showHint(text)
                }
            }
        } header: {
            Text(catalogKind.sectionTitle(isSearching: isSearching))
        }
    }

    private var catalogPicker: some View {
        Picker("Каталог", selection: $catalogKind) {
            ForEach(POSCatalog.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Refresh failures of the service catalog while stale services stay on screen.
        .remoteErrorAlert(serviceCatalog)
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
                    select(product)
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

    private func loadServices(force: Bool = false) async {
        await serviceCatalog.load { try await reference.ensureServices(force: force) }
    }

    /// One size goes straight to the receipt; several sizes ask which one first.
    private func select(_ product: Product) {
        if product.hasSeveralSizes {
            sizePickerProduct = product
        } else if cart.add(product: product) {
            addCount += 1
        }
    }

    private func add(_ product: Product, variant: ProductVariant) {
        guard cart.add(product: product, variant: variant) else { return }
        addCount += 1
        showHint(SizePicking.addedHint(product: product, variant: variant))
    }

    private func showHint(_ text: String?) {
        guard let text else { return }
        hint = CatalogHint(text: text)
    }
}

#if DEBUG
#Preview("По записи") {
    let state = PreviewData.appState()
    state.cart.prefill(from: PreviewData.appointments[0])
    state.cart.add(product: PreviewData.labret, variant: PreviewData.labret.variants[1])
    state.cart.add(product: PreviewData.ring)
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
