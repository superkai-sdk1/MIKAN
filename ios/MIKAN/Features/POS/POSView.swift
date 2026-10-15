import SwiftUI

/// «Касса»: shift card, jewelry / service catalog, floating glass cart bar.
struct POSView: View {
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ShiftStore.self) private var shift
    @Environment(ReferenceStore.self) private var reference

    @State private var catalogKind = POSCatalog.jewelry
    @State private var catalog = Remote<[Product]>()
    /// Load state of the service catalog; the services themselves live in `ReferenceStore`.
    @State private var serviceCatalog = Remote<Void>()
    @State private var search = ""
    @State private var category: String?
    @State private var showsServiceSheet = false
    @State private var addCount = 0
    @State private var hint: CatalogHint?

    private var categories: [String] {
        Array(Set((catalog.value ?? []).compactMap(\.category.nonEmpty))).sorted()
    }

    private var filtered: [Product] {
        let query = search.trimmed.lowercased()
        return (catalog.value ?? []).filter { product in
            let matchesCategory = category == nil || product.category.nonEmpty == category
            guard matchesCategory else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [product.name, product.sku, product.material, product.size, product.category]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(query)
        }
    }

    var body: some View {
        @Bindable var cart = cart
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ShiftCardView()
                    if let client = cart.client {
                        CartClientBanner(client: client) { cart.client = nil }
                    }
                    catalogSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background { AuraBackground() }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .catalogHint($hint)
            .safeAreaBar(edge: .bottom) {
                CartBar { showsServiceSheet = true }
            }
            .searchable(text: $search, prompt: catalogKind.searchPrompt)
            .refreshable {
                await load()
                if catalogKind == .services { await loadServices(force: true) }
                await shift.refresh()
            }
            .task {
                await load()
                if !shift.hasLoaded { await shift.refresh() }
            }
            .remoteErrorAlert(catalog)
            .navigationTitle("Касса")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SalesHistoryView()
                    } label: {
                        Label("История продаж", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ShiftsHistoryView()
                    } label: {
                        Label("Смены", systemImage: "tray.full")
                    }
                }
            }
            .sheet(isPresented: $cart.isCheckoutPresented) {
                CheckoutView()
            }
            .sheet(isPresented: $showsServiceSheet) {
                AddServiceSheet { text in showHint(text) }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: addCount)
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Каталог", selection: $catalogKind) {
                ForEach(POSCatalog.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            switch catalogKind {
            case .jewelry:
                jewelryCatalog
            case .services:
                POSServiceCatalogSection(state: serviceCatalog, search: search, load: { await loadServices() }) { text in
                    addCount += 1
                    showHint(text)
                }
            }
        }
    }

    private var jewelryCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !categories.isEmpty {
                CategoryChips(categories: categories, selection: $category)
            }
            if catalog.value != nil {
                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { product in
                            ProductTile(product: product, inCart: cart.quantity(ofProduct: product.id)) {
                                cart.add(product: product)
                                addCount += 1
                            }
                        }
                    }
                }
            } else if let failure = catalog.failure {
                ErrorStateView(message: failure, retry: load)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.trimmed.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView(
                "Нет украшений",
                systemImage: "sparkles",
                description: Text("Добавьте украшения на вкладке «Склад» — они появятся здесь. Услугу можно добавить кнопкой «Услуга».")
            )
        }
    }

    private func load() async {
        await catalog.load { try await api.products(kind: .jewelry) }
    }

    private func loadServices(force: Bool = false) async {
        await serviceCatalog.load { try await reference.ensureServices(force: force) }
    }

    private func showHint(_ text: String?) {
        guard let text else { return }
        hint = CatalogHint(text: text)
    }
}

private struct CartClientBanner: View {
    let client: ClientRef
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: client.name, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Продажа клиенту").font(.caption).foregroundStyle(.secondary)
                Text(client.name).font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Убрать клиента", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .cardStyle(padding: 12)
    }
}

#if DEBUG
#Preview {
    POSView()
        .previewEnvironment()
}
#endif
