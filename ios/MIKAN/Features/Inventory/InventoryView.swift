import Observation
import SwiftUI

@Observable
final class InventoryModel {
    var filter = InventoryFilter(kind: .jewelry)
    /// Each kind is loaded whole (inactive included) and filtered on the device; switching kinds shows the
    /// last loaded list at once while it refreshes.
    let jewelry = Remote<[Product]>()
    let consumables = Remote<[Product]>()
    /// Categories seen across loads, used as suggestions in the product editor.
    private(set) var knownCategories: Set<String> = []

    var kind: ProductKind { filter.kind ?? .jewelry }

    var remote: Remote<[Product]> { remote(for: kind) }

    private func remote(for kind: ProductKind) -> Remote<[Product]> {
        kind == .jewelry ? jewelry : consumables
    }

    /// What the list shows.
    var products: [Product] { filter.apply(remote.value ?? []) }

    var categoryOptions: [String] { InventoryFilter.categories(in: remote.value ?? []) }
    var materialOptions: [String] { InventoryFilter.materials(in: remote.value ?? []) }
    var sizeOptions: [String] { InventoryFilter.sizes(in: remote.value ?? []) }

    func load(api: APIClient) async {
        let kind = kind
        await remote(for: kind).load { try await api.products(kind: kind, includeInactive: true) }
        knownCategories.formUnion((remote(for: kind).value ?? []).compactMap(\.category.nonEmpty))
    }

    /// Puts a saved product into the list of its kind (and out of the other one, when its kind changed).
    func upsert(_ product: Product) {
        if let category = product.category.nonEmpty { knownCategories.insert(category) }
        for kind in ProductKind.allCases where kind != product.kind {
            remote(for: kind).remove(id: product.id)
        }
        remote(for: product.kind).upsert(product)
    }
}

struct InventoryView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppState.self) private var appState
    @State private var model = InventoryModel()
    @State private var showsEditor = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                ForEach(model.products) { product in
                    NavigationLink {
                        ProductDetailView(product: product, categories: model.knownCategories) { updated in
                            model.upsert(updated)
                            Task { await appState.refreshBadges() }
                        }
                    } label: {
                        ProductRow(product: product, highlightedSize: model.filter.size)
                    }
                }
            }
            .auraBackground()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) { InventoryFilterBar(model: model) }
            // Keep the top chrome a fixed height: a collapsing large title plus an auto-hiding search
            // drawer above the pinned filter bar fed back into the list's insets and made it shake at the top.
            .searchable(
                text: $model.filter.search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Название, артикул, размер, материал"
            )
            .overlay {
                RemoteStateOverlay(
                    remote: model.remote,
                    isEmpty: { model.filter.apply($0).isEmpty },
                    retry: { await model.load(api: api) }
                ) {
                    emptyState
                }
            }
            .refreshable {
                await model.load(api: api)
                await appState.refreshBadges()
            }
            .task(id: model.kind) { await model.load(api: api) }
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
                    Task { await appState.refreshBadges() }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let filter = model.filter
        if !filter.search.trimmed.isEmpty {
            ContentUnavailableView.search(text: filter.search)
        } else if filter.facetCount > 0 {
            ContentUnavailableView {
                Label("Ничего не найдено", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Нет позиций с такими параметрами.")
            } actions: {
                Button("Сбросить фильтры") {
                    withAnimation(.snappy) { model.filter = filter.cleared }
                }
                .buttonStyle(.glass)
            }
        } else if filter.lowOnly {
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

/// Pinned bar over the list: kind, «Мало», the facet menu and the chips of chosen facets.
private struct InventoryFilterBar: View {
    @Bindable var model: InventoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Тип", selection: kindBinding) {
                    ForEach(ProductKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $model.filter.lowOnly.animation(.snappy)) {
                    Label("Мало", systemImage: "exclamationmark.triangle")
                }
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .accessibilityHint("Показать только товары с низким остатком")
                facetMenu
            }
            if model.filter.facetCount > 0 {
                activeFacets
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var kindBinding: Binding<ProductKind> {
        Binding(
            get: { model.kind },
            set: { kind in model.filter = model.filter.switching(to: kind) }
        )
    }

    private var facetMenu: some View {
        Menu {
            facetPicker("Категория", options: model.categoryOptions, selection: $model.filter.category)
            facetPicker("Материал", options: model.materialOptions, selection: $model.filter.material)
            facetPicker("Размер", options: model.sizeOptions, selection: $model.filter.size)
            if model.filter.facetCount > 0 {
                Divider()
                Button("Сбросить фильтры", systemImage: "xmark.circle", role: .destructive) { resetFacets() }
            }
        } label: {
            Label(
                "Фильтры",
                systemImage: model.filter.facetCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .accessibilityValue(model.filter.facetCount > 0 ? "Выбрано: \(model.filter.facetCount)" : "")
    }

    @ViewBuilder
    private func facetPicker(_ title: String, options: [String], selection: Binding<String?>) -> some View {
        Picker(title, selection: selection.animation(.snappy)) {
            Text("Все").tag(String?.none)
            ForEach(options, id: \.self) { option in
                Text(option).tag(String?.some(option))
            }
        }
        .pickerStyle(.menu)
        .disabled(options.isEmpty)
    }

    private var activeFacets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                facetChip("Категория", value: model.filter.category) { model.filter.category = nil }
                facetChip("Материал", value: model.filter.material) { model.filter.material = nil }
                facetChip("Размер", value: model.filter.size) { model.filter.size = nil }
                if model.filter.facetCount > 1 {
                    Button("Сбросить", action: resetFacets)
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func facetChip(_ title: String, value: String?, remove: @escaping () -> Void) -> some View {
        if let value = value.nonEmpty {
            Button {
                withAnimation(.snappy) { remove() }
            } label: {
                HStack(spacing: 4) {
                    Text(value).lineLimit(1)
                    Image(systemName: "xmark").imageScale(.small)
                }
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel("\(title): \(value)")
            .accessibilityHint("Убрать фильтр")
        }
    }

    private func resetFacets() {
        withAnimation(.snappy) {
            model.filter = model.filter.withoutFacets
        }
    }
}

#if DEBUG
#Preview {
    InventoryView()
        .previewEnvironment()
}
#endif
