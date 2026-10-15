import Observation
import SwiftUI

@Observable
final class InventoryModel {
    var kind: ProductKind = .jewelry
    var search = ""
    var lowOnly = false
    let remote = Remote<[Product]>()
    /// Categories seen across loads, used as suggestions in the product editor.
    private(set) var knownCategories: Set<String> = []

    var queryKey: String { "\(kind.rawValue)|\(search)|\(lowOnly)" }

    func load(api: APIClient) async {
        let kind = kind
        let search = search
        let lowOnly = lowOnly
        await remote.load {
            try await api.products(kind: kind, search: search, lowStock: lowOnly, includeInactive: true)
        }
        knownCategories.formUnion((remote.value ?? []).compactMap(\.category.nonEmpty))
    }

    func upsert(_ product: Product) {
        if let category = product.category.nonEmpty { knownCategories.insert(category) }
        guard product.kind == kind else {
            remote.remove(id: product.id)
            return
        }
        remote.upsert(product)
    }
}

struct InventoryView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppState.self) private var appState
    @State private var model = InventoryModel()
    @State private var showsEditor = false

    private static let searchDebounce: Duration = .milliseconds(300)

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.remote.value ?? []) { product in
                    NavigationLink {
                        ProductDetailView(product: product, categories: model.knownCategories) { updated in
                            model.upsert(updated)
                            Task { await appState.refreshBadges() }
                        }
                    } label: {
                        ProductRow(product: product)
                    }
                }
            }
            .auraBackground()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) { filterBar }
            // Keep the top chrome a fixed height: a collapsing large title plus an auto-hiding search
            // drawer above the pinned filter bar fed back into the list's insets and made it shake at the top.
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название, артикул, материал")
            .overlay {
                RemoteStateOverlay(remote: model.remote, retry: { await model.load(api: api) }) {
                    emptyState
                }
            }
            .refreshable {
                await model.load(api: api)
                await appState.refreshBadges()
            }
            .task(id: model.queryKey) {
                if !model.search.isEmpty {
                    try? await Task.sleep(for: Self.searchDebounce)
                    guard !Task.isCancelled else { return }
                }
                await model.load(api: api)
            }
            .remoteErrorAlert(model.remote)
            .navigationTitle("Склад")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MovementsListView()
                    } label: {
                        Label("Движения", systemImage: "arrow.left.arrow.right")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить товар", systemImage: "plus") { showsEditor = true }
                }
            }
            .sheet(isPresented: $showsEditor) {
                ProductEditorView(product: nil, defaultKind: model.kind, categories: model.knownCategories) { saved in
                    model.upsert(saved)
                }
            }
        }
    }

    private var filterBar: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Picker("Тип", selection: $model.kind) {
                ForEach(ProductKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $model.lowOnly) {
                Label("Мало", systemImage: "exclamationmark.triangle")
            }
            .toggleStyle(.button)
            .buttonStyle(.glass)
            .accessibilityHint("Показать только товары с низким остатком")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.search.trimmed.isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else if model.lowOnly {
            ContentUnavailableView(
                "Всего достаточно",
                systemImage: "checkmark.seal",
                description: Text("Нет позиций, остаток которых ниже минимального.")
            )
        } else {
            ContentUnavailableView(
                model.kind == .jewelry ? "Украшений пока нет" : "Расходников пока нет",
                systemImage: "shippingbox",
                description: Text("Нажмите «+», чтобы добавить позицию и указать начальный остаток.")
            )
        }
    }
}

struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(path: product.photoUrl, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.headline)
                    .lineLimit(2)
                if !product.detailLine.isEmpty {
                    Text(product.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if product.price > 0 {
                        MoneyText(product.price).font(.subheadline)
                    }
                    if !product.active {
                        StatusBadge(text: "Скрыт", color: .gray)
                    }
                }
            }
            Spacer(minLength: 8)
            QuantityBadge(quantity: product.quantity, unit: product.unitLabel, isLow: product.lowStock)
        }
        .opacity(product.active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    InventoryView()
        .previewEnvironment()
}
#endif
