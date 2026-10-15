import SwiftUI

struct ProductDetailView: View {
    @Environment(APIClient.self) private var api
    let categories: Set<String>
    let onChange: (Product) -> Void

    @State private var product: Product
    @State private var movements = Remote<[StockMovement]>()
    @State private var purchases = Remote<[HistoryEntry]>()
    @State private var purchasesTotal = 0
    @State private var movementType: MovementType?
    @State private var showsEditor = false

    private static let historyLimit = 30
    private static let purchasesPreviewLimit = 5

    init(product: Product, categories: Set<String>, onChange: @escaping (Product) -> Void) {
        _product = State(initialValue: product)
        self.categories = categories
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProductHero(path: product.photoUrl)
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    quantityCard
                    actions
                    infoCard
                    if showsPurchases { purchasesCard }
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
        .remoteErrorAlert(movements)
        .sheet(item: $movementType) { type in
            MovementSheet(product: product, initialType: type) { result in
                apply(result.product)
                movements.update { [result.movement] + $0 }
            }
        }
        .sheet(isPresented: $showsEditor) {
            ProductEditorView(product: product, defaultKind: product.kind, categories: categories) { saved in
                apply(saved)
            }
        }
    }

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
            if let sku = product.sku.nonEmpty {
                Text("Артикул \(sku)").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private var quantityCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Остаток").font(.subheadline).foregroundStyle(.secondary)
                Text("\(product.quantity) \(product.unitLabel)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(product.lowStock ? Color.red : Color.primary)
                    .contentTransition(.numericText(value: Double(product.quantity)))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if product.lowStock {
                    StatusBadge(text: "Мало", color: .red, systemImage: "exclamationmark.triangle.fill")
                }
                Text("Минимум: \(product.minQuantity) \(product.unitLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MovementType.manual) { type in
                    Button {
                        movementType = type
                    } label: {
                        ActionLabel(title: type.shortTitle, systemImage: type.symbol)
                    }
                    .accessibilityLabel(type.title)
                }
            }
            .buttonStyle(.glass)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("Цена продажи", product.price > 0 ? Money.format(product.price) : nil)
            infoRow("Себестоимость", product.cost.map(Money.format))
            if let cost = product.cost, product.price > 0 {
                infoRow("Наценка", Money.format(product.price - cost))
            }
            infoRow("Материал", product.material.nonEmpty)
            infoRow("Размер", product.size.nonEmpty)
            if let description = product.description.nonEmpty {
                Divider()
                Text(description).font(.subheadline)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value).monospacedDigit()
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("История движений").font(.headline)
            if let items = movements.value {
                if items.isEmpty {
                    Text("Движений пока не было").foregroundStyle(.secondary)
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
    }

    /// Jewelry is sold at the POS; consumables only show buyers when someone actually bought one.
    private var showsPurchases: Bool { product.kind == .jewelry || purchasesTotal > 0 }

    /// Last buyers with a link to the full list.
    private var purchasesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кто покупал").font(.headline)
            if let items = purchases.value {
                if items.isEmpty {
                    Text("Покупок пока не было").foregroundStyle(.secondary)
                }
                ForEach(items) { entry in
                    HistoryEntryLink(entry: entry, showsClient: true)
                        .buttonStyle(.plain)
                    if entry.id != items.last?.id || purchasesTotal > items.count { Divider() }
                }
                if purchasesTotal > items.count {
                    NavigationLink {
                        ProductPurchasesView(product: product)
                    } label: {
                        HStack {
                            Text("Все покупки (\(purchasesTotal))")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                }
            } else if let failure = purchases.failure {
                Text(failure).foregroundStyle(.secondary)
                Button("Повторить") { Task { await loadPurchases() } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .remoteErrorAlert(purchases)
    }

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
        await movements.load { try await api.productMovements(productId: id, limit: Self.historyLimit).items }
    }

    private func loadPurchases() async {
        let id = product.id
        await purchases.load {
            let page = try await api.productHistory(id: id, limit: Self.purchasesPreviewLimit)
            purchasesTotal = page.total ?? page.items.count
            return page.items
        }
    }

    private func apply(_ updated: Product) {
        product = updated
        onChange(updated)
    }
}

/// Top photo that extends under the navigation bar.
private struct ProductHero: View {
    @Environment(APIClient.self) private var api
    let path: String?

    private static let height: CGFloat = 320

    var body: some View {
        Group {
            if let url = api.mediaURL(for: path) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .backgroundExtensionEffect()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.mandarinLight.opacity(0.5), Theme.mandarin.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProductDetailView(product: PreviewData.ring, categories: ["Лабрет", "Кольцо"]) { _ in }
    }
    .previewEnvironment()
}
#endif
