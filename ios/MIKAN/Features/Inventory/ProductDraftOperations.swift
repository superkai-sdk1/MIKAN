import Foundation

// Pure list operations of the product editor: sizes, photos, suitable services.

// MARK: - Size operations

nonisolated extension ProductDraft {
    /// Why the size cannot be removed, or `nil` when it can.
    func removalBlock(for id: UUID) -> String? {
        guard let size = sizes.first(where: { $0.id == id }) else { return nil }
        if size.quantity > 0 {
            return "На складе \(size.quantity) \(unitLabel) — сначала спишите остаток."
        }
        return sizes.count <= 1 ? "Должен остаться хотя бы один размер." : nil
    }

    /// A new empty size after the others; it starts with the last size's minimum.
    func addingSize() -> ProductDraft {
        var copy = self
        copy.sizes = sizes + [SizeDraft(minQuantity: sizes.last?.minQuantity ?? 0)]
        return copy
    }

    /// Adds sizes by name, skipping the ones the product already has. The only unnamed size of a product
    /// without sizes takes the first name (keeping its stock), so «6, 8, 10 мм» gives exactly three sizes.
    func addingSizes(named names: [String]) -> ProductDraft {
        var known = Set(sizes.map { InventoryFilter.normalized($0.name) })
        var fresh: [String] = []
        for name in names.compactMap(\.nonEmpty) {
            let key = InventoryFilter.normalized(name)
            guard !known.contains(key) else { continue }
            known.insert(key)
            fresh.append(name)
        }
        guard !fresh.isEmpty else { return self }
        var copy = self
        if sizes.count == 1, sizes[0].name.trimmed.isEmpty {
            copy.sizes[0].name = fresh.removeFirst()
        }
        let minimum = copy.sizes.last?.minQuantity ?? 0
        copy.sizes = copy.sizes + fresh.map { SizeDraft(name: $0, minQuantity: minimum) }
        return copy
    }

    /// Leaves the size out of the body; a size with stock (or the last one) stays.
    func removingSize(_ id: UUID) -> ProductDraft {
        guard removalBlock(for: id) == nil else { return self }
        var copy = self
        copy.sizes = sizes.filter { $0.id != id }
        return copy
    }

    /// Moves the size by `offset` positions (−1 = up), clamped to the list bounds.
    func movingSize(_ id: UUID, by offset: Int) -> ProductDraft {
        guard let index = sizes.firstIndex(where: { $0.id == id }) else { return self }
        let target = min(max(0, index + offset), sizes.count - 1)
        guard target != index else { return self }
        var copy = self
        let row = copy.sizes.remove(at: index)
        copy.sizes.insert(row, at: target)
        return copy
    }

    /// Reorders like `List.onMove`.
    func movingSizes(fromOffsets source: IndexSet, toOffset destination: Int) -> ProductDraft {
        var copy = self
        let moving = source.sorted().map { sizes[$0] }
        var rest = sizes.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(0, insertAt), rest.count))
        copy.sizes = rest
        return copy
    }
}

// MARK: - Photo operations

nonisolated extension ProductDraft {
    /// How many more photos may be added.
    var remainingPhotos: Int { max(0, ProductLimits.maxPhotos - photos.count) }

    func addingPhotos(_ paths: [String]) -> ProductDraft {
        var copy = self
        let fresh = paths.filter { !photos.contains($0) }
        copy.photos = photos + fresh.prefix(remainingPhotos)
        return copy
    }

    func removingPhoto(_ path: String) -> ProductDraft {
        var copy = self
        copy.photos = photos.filter { $0 != path }
        return copy
    }

    /// Moves the photo to the front: the first photo is the cover in the list, the POS and the bot.
    func makingCover(_ path: String) -> ProductDraft {
        guard photos.contains(path) else { return self }
        var copy = self
        copy.photos = [path] + photos.filter { $0 != path }
        return copy
    }

    func movingPhoto(_ path: String, by offset: Int) -> ProductDraft {
        guard let index = photos.firstIndex(of: path) else { return self }
        let target = min(max(0, index + offset), photos.count - 1)
        guard target != index else { return self }
        var copy = self
        copy.photos.remove(at: index)
        copy.photos.insert(path, at: target)
        return copy
    }

    // MARK: Services

    func togglingService(_ id: Int) -> ProductDraft {
        var copy = self
        copy.serviceIds = serviceIds.contains(id) ? serviceIds.filter { $0 != id } : serviceIds + [id]
        return copy
    }
}

// MARK: - Availability

nonisolated extension ProductBody {
    /// A PATCH that re-sends the card as it is and changes only the availability of a presence consumable
    /// (the quick status change from the list and the card).
    static func presence(_ status: PresenceStatus, of product: Product) -> ProductBody {
        var draft = ProductDraft(product: product)
        draft.presenceStatus = status
        return draft.body
    }
}
