import SwiftUI

struct ProductDetailView: View {
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference
    let categories: Set<String>
    let onChange: (Product) -> Void

    @State private var product: Product
    @State private var movements = Remote<[StockMovement]>()
    /// History of one size, or of all of them.
    @State private var movementsVariantId: Int?
    /// The size the shown movements belong to.
    @State private var loadedMovementsVariantId: Int?
    @State private var purchases = Remote<[HistoryEntry]>()
    @State private var purchasesTotal = 0
    @State private var movementRequest: StockMovementRequest?
    @State private var showsEditor = false
    @State private var viewer: ServicePhotoViewerItem?
    @State private var isSavingPresence = false
    @State private var errorMessage: String?

    private static let historyLimit = 30
    private static let purchasesPreviewLimit = 5

    init(product: Product, categories: Set<String> = [], onChange: @escaping (Product) -> Void) {
        _product = State(initialValue: product)
        self.categories = categories
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProductGallery(paths: product.photos) { index in
                    viewer = ServicePhotoViewerItem(paths: product.photos, index: index)
                }
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    if product.isPresenceTracked {
                        ProductPresenceCard(status: product.presenceStatus ?? .ok, isSaving: isSavingPresence, onSelect: setPresence)
                    } else {
                        quantityCard
                        actions
                        if showsSizesCard {
                            ProductSizesCard(product: product) { type, variant in
                                movementRequest = StockMovementRequest(type: type, variantId: variant.id)
                            }
                        }
                    }
                    ProductCharacteristicsCard(product: product, serviceNames: serviceNames)
                    if product.kind == .consumable {
                        ConsumableUsageCard(product: product, services: reference.services)
                    }
                    if let description = product.description.nonEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Описание").font(.headline)
                            Text(description).font(.subheadline)
                        }
                        .cardStyle()
                    }
                    if showsPurchases {
                        ProductPurchasesCard(product: product, purchases: purchases, total: purchasesTotal) {
                            await loadPurchases()
                        }
                    }
                    historyCard
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Изменить") { showsEditor = true }
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        // Only names the suitable services; without them the row is simply hidden.
        .task { try? await reference.ensureServices() }
        .remoteErrorAlert(movements)
        .errorAlert($errorMessage)
        .sheet(item: $movementRequest) { request in
            MovementSheet(product: product, initialType: request.type, variantId: request.variantId) { result in
                apply(result.product)
                prependMovements(result.movements)
            }
        }
        .sheet(isPresented: $showsEditor) {
            ProductEditorView(product: product, defaultKind: product.kind, categories: categories) { saved in
                apply(saved)
            }
        }
        .fullScreenCover(item: $viewer) { item in
            ServicePhotoViewer(item: item)
        }
    }

    // MARK: - Header

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusBadge(text: product.kind.singularTitle, color: .accentColor)
                if let category = product.category.nonEmpty {
                    StatusBadge(text: category, color: .secondary)
                }
                if !product.active {
                    StatusBadge(text: "Скрыт", color: .gray, systemImage: "eye.slash")
                }
            }
            Text(product.name)
                .font(.title.weight(.bold))
                .textSelection(.enabled)
            if !product.detailLine.isEmpty {
                Text(product.detailLine).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if product.kind.isSold, product.priceRange.upperBound > 0 {
                    Text(product.priceText)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                if let sku = product.sku.nonEmpty {
                    Text("Артикул \(sku)").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private var quantityCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.hasSeveralSizes ? "Остаток всех размеров" : "Остаток")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(InventoryText.quantity(product.quantity, unit: product.unitLabel))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(product.lowStock ? Color.red : Color.primary)
                    .contentTransition(.numericText(value: Double(product.quantity)))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if product.lowStock {
                    StatusBadge(text: lowStockTitle, color: .red, systemImage: "exclamationmark.triangle.fill")
                }
                Text("Минимум: \(InventoryText.quantity(product.minQuantity, unit: product.unitLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    /// «Мало», or «Мало: 8 мм, 10 мм» for a product with sizes.
    private var lowStockTitle: String {
        guard product.hasSeveralSizes else { return "Мало" }
        let names = product.lowVariants.map { InventoryText.sizeTitle($0.name) }
        guard names.count > 2 else { return "Мало: " + names.joined(separator: ", ") }
        return "Мало: " + Plural.count(names.count, one: "размер", few: "размера", many: "размеров")
    }

    /// The operations for all sizes at once.
    private var actions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MovementType.manual) { type in
                    Button {
                        movementRequest = StockMovementRequest(type: type)
                    } label: {
                        ActionLabel(title: type.shortTitle, systemImage: type.symbol)
                    }
                    .accessibilityLabel(type.title)
                }
            }
            .buttonStyle(.glass)
        }
    }

    /// A product without sizes is covered by the stock card.
    private var showsSizesCard: Bool { product.hasSeveralSizes || !product.namedVariants.isEmpty }

    private var serviceNames: [String] {
        product.kind == .jewelry ? ProductServiceOptions.names(of: product.serviceIds, in: reference.services) : []
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История движений").font(.headline)
                Spacer()
                if product.hasSeveralSizes { sizeFilterMenu }
            }
            if let items = movements.value {
                if items.isEmpty {
                    Text(movementsVariantId == nil ? "Движений пока не было" : "По этому размеру движений не было")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { movement in
                    MovementRow(movement: movement)
                    if movement.id != items.last?.id { Divider() }
                }
            } else if let failure = movements.failure {
                Text(failure).foregroundStyle(.secondary)
                Button("Повторить") { Task { await loadMovements() } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .task(id: movementsVariantId) {
            // The first load runs in `reload()`; another size shows the spinner instead of the previous rows.
            guard loadedMovementsVariantId != movementsVariantId else { return }
            movements.reset()
            await loadMovements()
        }
    }

    private var sizeFilterMenu: some View {
        Menu {
            Picker("Размер", selection: $movementsVariantId) {
                Text("Все размеры").tag(Int?.none)
                ForEach(product.variants) { variant in
                    Text(InventoryText.sizeTitle(variant.name)).tag(Int?.some(variant.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(movementsVariantId.flatMap { product.variant(id: $0) }.map { InventoryText.sizeTitle($0.name) } ?? "Все размеры")
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.subheadline)
        }
        .accessibilityLabel("Размер для истории")
    }

    /// Jewelry and goods are sold at the POS; consumables only show buyers when someone actually bought one.
    private var showsPurchases: Bool { product.kind.isSold || purchasesTotal > 0 }

    // MARK: - Data

    private func reload() async {
        do {
            apply(try await api.product(id: product.id))
        } catch is CancellationError {
            return
        } catch {
            movements.transientError = error.userMessage
        }
        async let movementsLoad: Void = loadMovements()
        async let purchasesLoad: Void = loadPurchases()
        _ = await (movementsLoad, purchasesLoad)
    }

    private func loadMovements() async {
        let id = product.id
        let variantId = movementsVariantId
        await movements.load {
            let items = try await api.productMovements(productId: id, variantId: variantId, limit: Self.historyLimit).items
            loadedMovementsVariantId = variantId
            return items
        }
    }

    private func loadPurchases() async {
        let id = product.id
        await purchases.load {
            let page = try await api.productHistory(id: id, limit: Self.purchasesPreviewLimit)
            purchasesTotal = page.total ?? page.items.count
            return page.items
        }
    }

    /// Batch movements come in line order; the history is newest first.
    private func prependMovements(_ new: [StockMovement]) {
        let shown = new.filter { movementsVariantId == nil || $0.variantId == movementsVariantId }
        movements.update { Array(shown.reversed()) + $0 }
    }

    /// Shows the new status at once and sends it; the old one comes back when the server refuses.
    private func setPresence(_ status: PresenceStatus) {
        guard status != product.presenceStatus, !isSavingPresence else { return }
        let previous = product
        product.presenceStatus = status
        isSavingPresence = true
        Task {
            defer { isSavingPresence = false }
            do {
                apply(try await api.updateProduct(id: previous.id, .presence(status, of: previous)))
            } catch {
                product = previous
                errorMessage = error.userMessage
            }
        }
    }

    private func apply(_ updated: Product) {
        product = updated
        if let id = movementsVariantId, updated.variant(id: id) == nil { movementsVariantId = nil }
        onChange(updated)
    }
}

#if DEBUG
#Preview("Размеры") {
    NavigationStack {
        ProductDetailView(product: PreviewData.labret, categories: ["Лабрет", "Кольцо"]) { _ in }
    }
    .previewEnvironment()
}

#Preview("Без размеров") {
    NavigationStack {
        ProductDetailView(product: PreviewData.needles, categories: ["Иглы"]) { _ in }
    }
    .previewEnvironment()
}

#Preview("Есть / нет") {
    NavigationStack {
        ProductDetailView(product: PreviewData.antiseptic) { _ in }
    }
    .previewEnvironment()
}
#endif
