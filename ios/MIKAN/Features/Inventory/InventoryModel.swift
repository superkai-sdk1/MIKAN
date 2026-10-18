import Observation
import SwiftUI

/// State of the unified warehouse: the chosen section, the filter and the products of each product kind.
@Observable
final class InventoryModel {
    /// Украшения · Услуги · Расходники · Товары.
    private(set) var section: CatalogSection = .jewelry
    var filter = InventoryFilter(kind: .jewelry)
    /// Each kind is loaded whole (inactive included) and filtered on the device; switching sections shows the
    /// last loaded list at once while it refreshes.
    let jewelry = Remote<[Product]>()
    let goods = Remote<[Product]>()
    let consumables = Remote<[Product]>()
    /// Categories seen across loads, offered in the product editor besides the registry.
    private(set) var knownCategories: Set<String> = []
    /// Presence consumables whose status change is on its way to the server.
    private(set) var updatingPresence: Set<Int> = []

    /// The product kind of the section; `nil` on «Услуги».
    var kind: ProductKind? { section.productKind }

    var remote: Remote<[Product]> { remote(for: kind ?? .jewelry) }

    func remote(for kind: ProductKind) -> Remote<[Product]> {
        switch kind {
        case .jewelry: jewelry
        case .goods: goods
        case .consumable: consumables
        }
    }

    /// What the list shows, before grouping.
    var products: [Product] { filter.apply(remote.value ?? []) }

    /// The list by category, in the registry order.
    func groups(categories: [CatalogCategory]) -> [ProductGroup<Product>] {
        WarehouseGrouping.groups(products, section: section, categories: categories)
    }

    func categoryOptions(categories: [CatalogCategory]) -> [String] {
        WarehouseGrouping.categoryOptions(section: section, categories: categories, products: remote.value ?? [])
    }

    var materialOptions: [String] { InventoryFilter.materials(in: remote.value ?? []) }
    var sizeOptions: [String] { InventoryFilter.sizes(in: remote.value ?? []) }
    var offersPresenceFilter: Bool { InventoryFilter.hasPresence(in: remote.value ?? []) }

    /// Facets belong to a section, so switching drops them; search and «Мало» stay.
    func select(_ section: CatalogSection) {
        guard section != self.section else { return }
        self.section = section
        if let kind = section.productKind {
            filter = filter.switching(to: kind)
        }
    }

    func load(api: APIClient) async {
        guard let kind else { return }
        await load(kind, api: api)
    }

    func load(_ kind: ProductKind, api: APIClient) async {
        await remote(for: kind).load { try await api.products(kind: kind, includeInactive: true) }
        knownCategories.formUnion((remote(for: kind).value ?? []).compactMap(\.category.nonEmpty))
    }

    /// Reloads every kind loaded so far (after a stock count or category changes).
    func reloadLoaded(api: APIClient) async {
        for kind in ProductKind.allCases where remote(for: kind).value != nil {
            await load(kind, api: api)
        }
    }

    /// Puts a saved product into the list of its kind (and out of the others, when its kind changed).
    func upsert(_ product: Product) {
        if let category = product.category.nonEmpty { knownCategories.insert(category) }
        for kind in ProductKind.allCases where kind != product.kind {
            remote(for: kind).remove(id: product.id)
        }
        remote(for: product.kind).upsert(product)
    }

    /// Marks the availability of a presence consumable at once and sends it; restores the old status when it fails.
    /// Returns the error message to show.
    func setPresence(_ status: PresenceStatus, of product: Product, api: APIClient) async -> String? {
        guard product.isPresenceTracked, product.presenceStatus != status, !updatingPresence.contains(product.id) else { return nil }
        updatingPresence.insert(product.id)
        defer { updatingPresence.remove(product.id) }
        var marked = product
        marked.presenceStatus = status
        upsert(marked)
        do {
            upsert(try await api.updateProduct(id: product.id, .presence(status, of: product)))
            return nil
        } catch is CancellationError {
            upsert(product)
            return nil
        } catch {
            upsert(product)
            return error.userMessage
        }
    }
}
