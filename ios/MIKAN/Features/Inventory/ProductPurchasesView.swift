import SwiftUI

/// Everyone who bought a product, newest first, loaded page by page.
struct ProductPurchasesView: View {
    @Environment(APIClient.self) private var api
    let product: Product

    @State private var entries = Remote<[HistoryEntry]>()
    @State private var total = 0
    @State private var isLoadingMore = false

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
                    description: Text("Здесь появятся продажи этого товара.")
                )
            }
        }
        .refreshable { await load() }
        .task { if entries.value == nil { await load() } }
        .remoteErrorAlert(entries)
        .navigationTitle("Покупки")
        .navigationSubtitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let id = product.id
        await entries.load {
            let page = try await api.productHistory(id: id, limit: Self.pageSize)
            total = page.total ?? page.items.count
            return page.items
        }
    }

    private func loadMore() async {
        guard let items = entries.value, items.count < total, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.productHistory(id: product.id, limit: Self.pageSize, offset: items.count)
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

#if DEBUG
#Preview {
    NavigationStack {
        ProductPurchasesView(product: PreviewData.labret)
    }
    .previewEnvironment()
}
#endif
