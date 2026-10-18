import SwiftUI

/// «Чек»: the appointment or client it is for, editable lines, the jewelry / service / goods catalog, «Услуга»
/// and «Оплатить · N ₽»; «Удалить чек» in the menu. Every change is saved to the open receipt on the server.
/// Checkout itself is the `CheckoutView` sheet on the POS root (bound to `cart.isCheckoutPresented`).
struct ReceiptView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(OpenReceiptsStore.self) private var receipts
    @Environment(ReferenceStore.self) private var reference
    /// Jewelry and goods; owned by the POS hub, so the catalog stays loaded between receipts.
    let catalog: Remote<[Product]>

    @State private var catalogKind = POSCatalog.jewelry
    /// Load state of the service catalog; the services themselves live in `ReferenceStore`.
    @State private var serviceCatalog = Remote<Void>()
    @State private var hint: CatalogHint?
    @State private var search = ""
    /// The category chip chosen in each product segment.
    @State private var categories: [ProductKind: String] = [:]
    @State private var showsServiceSheet = false
    /// A product with several sizes whose size is being picked.
    @State private var sizePickerProduct: Product?
    @State private var addCount = 0
    @State private var deletion: ReceiptDeletion?
    @State private var isDeleting = false
    @State private var deleteError: String?

    private static let gridColumns = 2
    private static let tileSpacing: CGFloat = 12

    private var isSearching: Bool { !search.trimmed.isEmpty }
    private var products: [Product] { catalog.value ?? [] }

    private func categoryNames(_ kind: ProductKind) -> [String] {
        ProductCatalogFilter.categories(of: products, kind: kind, registry: reference.categories)
    }

    private func filtered(_ kind: ProductKind) -> [Product] {
        ProductCatalogFilter.apply(products, kind: kind, query: search, category: categories[kind])
    }

    private func categoryBinding(_ kind: ProductKind) -> Binding<String?> {
        Binding(get: { categories[kind] }, set: { categories[kind] = $0 })
    }

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
        // Picks up edits made on another phone; a receipt paid or deleted there is let go.
        .task { await receipts.syncCart() }
        // Only orders the category chips; without it they are alphabetical.
        .task { try? await reference.ensureCategories() }
        .task(id: catalogKind) {
            if catalogKind == .services, serviceCatalog.value == nil { await loadServices() }
        }
        .remoteErrorAlert(catalog)
        .navigationTitle("Чек")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menu }
        .receiptDeletionDialog($deletion, onDelete: delete)
        .errorAlert($deleteError, title: "Чек не удалён")
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

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        if let receiptId = cart.receiptId {
            ToolbarItem(placement: .topBarTrailing) {
                if isDeleting {
                    ProgressView()
                } else {
                    Menu {
                        Button("Удалить чек", systemImage: "trash", role: .destructive) {
                            deletion = ReceiptDeletion(
                                id: receiptId, subtotal: cart.subtotal, itemCount: cart.itemCount,
                                hasAppointment: cart.appointment != nil
                            )
                        }
                    } label: {
                        Label("Действия с чеком", systemImage: "ellipsis")
                    }
                }
            }
        }
    }

    private var catalogSection: some View {
        Section {
            catalogPicker
            switch catalogKind {
            case .jewelry, .goods:
                if let kind = catalogKind.productKind {
                    let names = categoryNames(kind)
                    if !names.isEmpty {
                        CategoryChips(categories: names, selection: categoryBinding(kind))
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    catalogContent(kind)
                }
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
    private func catalogContent(_ kind: ProductKind) -> some View {
        if catalog.value != nil {
            let items = filtered(kind)
            if items.isEmpty {
                emptyState(kind)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(ProductCatalogFilter.rows(items, columns: Self.gridColumns), id: \.self) { row in
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
    private func emptyState(_ kind: ProductKind) -> some View {
        let symbol = CatalogSection(kind: kind).symbol
        if isSearching {
            ContentUnavailableView.search(text: search)
        } else if categories[kind] != nil, !segmentProducts(kind).isEmpty {
            ContentUnavailableView("В этой категории пусто", systemImage: symbol)
        } else if kind == .goods {
            ContentUnavailableView(
                "Нет товаров",
                systemImage: symbol,
                description: Text("Добавьте товары — спреи для ухода, сертификаты — на вкладке «Склад» → «Товары». Они появятся здесь.")
            )
        } else {
            ContentUnavailableView(
                "Нет украшений",
                systemImage: symbol,
                description: Text("Добавьте украшения на вкладке «Склад» — они появятся здесь. Услугу можно добавить кнопкой «Услуга».")
            )
        }
    }

    private func segmentProducts(_ kind: ProductKind) -> [Product] {
        ProductCatalogFilter.products(products, kind: kind)
    }

    /// Jewelry and goods in one go: both segments come from the same catalog.
    private func loadCatalog() async {
        await catalog.load {
            async let jewelry = api.products(kind: .jewelry)
            async let goods = api.products(kind: .goods)
            return try await jewelry + goods
        }
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

    /// Nothing is sold or returned; back to the hub once the server deleted it.
    private func delete(_ deletion: ReceiptDeletion) {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await appState.deleteReceipt(id: deletion.id, hasAppointment: deletion.hasAppointment)
                appState.closeReceipt()
            } catch {
                deleteError = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview("По записи") {
    let state = PreviewData.appState()
    state.cart.prefill(from: PreviewData.appointments[0])
    state.cart.add(product: PreviewData.labret, variant: PreviewData.labret.variants[1])
    state.cart.add(product: PreviewData.ring)
    return NavigationStack {
        ReceiptView(catalog: Remote(PreviewData.products.filter(\.kind.isSold) + [PreviewData.aftercareSpray]))
    }
    .appEnvironment(state)
}

#Preview("Без записи") {
    NavigationStack {
        ReceiptView(catalog: Remote(PreviewData.products.filter(\.kind.isSold) + [PreviewData.aftercareSpray]))
    }
    .previewEnvironment()
}
#endif
