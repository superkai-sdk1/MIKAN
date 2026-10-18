import SwiftUI

/// Everyone who bought a product (or one size of it), newest first, loaded page by page.
struct ProductPurchasesView: View {
    @Environment(APIClient.self) private var api
    let product: Product

    @State private var entries = Remote<[HistoryEntry]>()
    @State private var total = 0
    @State private var isLoadingMore = false
    /// `nil` — all sizes.
    @State private var variantId: Int?
    /// The size the shown entries belong to.
    @State private var loadedVariantId: Int?

    private static let pageSize = 50

    var body: some View {
        List {
            if let items = entries.value, !items.isEmpty {
                Section {
                    ForEach(items) { entry in
                        HistoryEntryLink(entry: entry, showsClient: true)
                    }
                } header: {
                    Text(Plural.count(total, one: "покупка", few: "покупки", many: "покупок"))
                }
                if items.count < total {
                    Section {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Group {
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Text("Показать ещё")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(isLoadingMore)
                    }
                }
            }
        }
        .overlay {
            RemoteStateOverlay(remote: entries, retry: load) {
                ContentUnavailableView(
                    "Покупок пока не было",
                    systemImage: "bag",
                    description: Text(variantId == nil ? "Здесь появятся продажи этого товара." : "Этот размер ещё не покупали.")
                )
            }
        }
        .refreshable { await load() }
        .task(id: variantId) {
            // Coming back from a pushed sale keeps the loaded pages; another size starts over.
            if entries.value != nil && loadedVariantId == variantId { return }
            entries.reset()
            await load()
        }
        .remoteErrorAlert(entries)
        .navigationTitle("Покупки")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if product.hasSeveralSizes {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Размер", selection: $variantId) {
                            Text("Все размеры").tag(Int?.none)
                            ForEach(product.variants) { variant in
                                Text(InventoryText.sizeTitle(variant.name)).tag(Int?.some(variant.id))
                            }
                        }
                    } label: {
                        Label(
                            "Размер",
                            systemImage: variantId == nil
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
        }
    }

    /// «Лабрет», or «Лабрет — 8 мм» while one size is shown.
    private var subtitle: String {
        product.lineName(variant: variantId.flatMap { product.variant(id: $0) })
    }

    private func load() async {
        let id = product.id
        let variantId = variantId
        await entries.load {
            let page = try await api.productHistory(id: id, variantId: variantId, limit: Self.pageSize)
            total = page.total ?? page.items.count
            loadedVariantId = variantId
            return page.items
        }
    }

    private func loadMore() async {
        guard let items = entries.value, items.count < total, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.productHistory(
                id: product.id, variantId: variantId, limit: Self.pageSize, offset: items.count
            )
            let known = Set(items.map(\.id))
            entries.update { $0 + page.items.filter { !known.contains($0.id) } }
            // An empty page means the list shrank since the first load: stop offering more.
            total = page.items.isEmpty ? items.count : (page.total ?? total)
        } catch is CancellationError {
            return
        } catch {
            entries.transientError = error.userMessage
        }
    }
}

/// «Кто покупал» on the product screen: the last buyers with a link to the full list.
struct ProductPurchasesCard: View {
    let product: Product
    let purchases: Remote<[HistoryEntry]>
    let total: Int
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кто покупал").font(.headline)
            if let items = purchases.value {
                if items.isEmpty {
                    Text("Покупок пока не было").foregroundStyle(.secondary)
                }
                ForEach(items) { entry in
                    HistoryEntryLink(entry: entry, showsClient: true)
                        .buttonStyle(.plain)
                    if entry.id != items.last?.id || total > items.count { Divider() }
                }
                if total > items.count {
                    NavigationLink {
                        ProductPurchasesView(product: product)
                    } label: {
                        HStack {
                            Text("Все покупки (\(total))")
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
                Button("Повторить") { Task { await retry() } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .remoteErrorAlert(purchases)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProductPurchasesView(product: PreviewData.labret)
    }
    .previewEnvironment()
}
#endif
