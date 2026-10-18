import Foundation

// Pure editor logic of the product card: sizes, jewelry attributes, limits and the API body.

/// Limits of the product card from the API contract.
nonisolated enum ProductLimits {
    static let maxPhotos = 10
    static let maxSizes = 50
    static let maxServices = 30
    /// Colour, stone and supplier.
    static let maxAttributeLength = 100
    static let maxThicknessMm = 30.0
    static let unitSuggestions = ["шт", "пара", "уп", "мл", "г", "м"]
    static let defaultUnit = "шт"
}

// MARK: - Size row

/// Editable size of the product editor.
nonisolated struct SizeDraft: Identifiable, Hashable, Sendable {
    /// Row identity in the editor (a new size has no server id yet).
    let id: UUID
    /// Server id of an existing size; `nil` — a size added in the editor.
    let variantId: Int?
    var name: String
    var sku: String
    /// Own selling price / cost; `nil` — the product's.
    var price: Int?
    var cost: Int?
    var minQuantity: Int
    /// New sizes only: recorded by the server as a receipt «Начальный остаток».
    var initialQuantity: Int
    /// Current stock of an existing size; changes only through stock movements.
    let quantity: Int

    init(
        id: UUID = UUID(),
        variantId: Int? = nil,
        name: String = "",
        sku: String = "",
        price: Int? = nil,
        cost: Int? = nil,
        minQuantity: Int = 0,
        initialQuantity: Int = 0,
        quantity: Int = 0
    ) {
        self.id = id
        self.variantId = variantId
        self.name = name
        self.sku = sku
        self.price = price
        self.cost = cost
        self.minQuantity = minQuantity
        self.initialQuantity = initialQuantity
        self.quantity = quantity
    }

    init(_ variant: ProductVariant) {
        self.init(
            variantId: variant.id,
            name: variant.name,
            sku: variant.sku ?? "",
            price: variant.price,
            cost: variant.cost,
            minQuantity: variant.minQuantity,
            quantity: variant.quantity
        )
    }

    var isNew: Bool { variantId == nil }
    /// Own article, price or cost differ from the product's.
    var hasOwnValues: Bool { sku.nonEmpty != nil || price != nil || cost != nil }

    /// `variants` item: an existing size keeps its id, a new one carries its initial stock.
    var body: ProductVariantBody {
        ProductVariantBody(
            id: variantId,
            name: name.trimmed,
            sku: Nullable(sku.nonEmpty),
            price: Nullable(price.map { max(0, $0) }),
            cost: Nullable(cost.map { max(0, $0) }),
            minQuantity: max(0, minQuantity),
            initialQuantity: isNew && initialQuantity > 0 ? initialQuantity : nil
        )
    }
}

// MARK: - Whole card

/// Everything the product editor edits; validates it like the server does and builds the API body.
nonisolated struct ProductDraft: Hashable, Sendable {
    /// `nil` — a new product.
    let productId: Int?
    var kind: ProductKind
    var name: String
    var sku: String
    var category: String
    var material: String
    var threadType: ThreadType?
    /// As typed: «1.2», «1,2 мм».
    var thicknessText: String
    var color: String
    var stone: String
    var supplier: String
    var description: String
    var price: Int
    var cost: Int?
    var unit: String
    /// Upload paths; the first is the cover.
    var photos: [String]
    var serviceIds: [Int]
    var active: Bool
    /// In the order staff arranged them; a product without sizes has one unnamed row.
    var sizes: [SizeDraft]

    init(product: Product?, defaultKind: ProductKind = .jewelry) {
        productId = product?.id
        kind = product?.kind ?? defaultKind
        name = product?.name ?? ""
        sku = product?.sku ?? ""
        category = product?.category ?? ""
        material = product?.material ?? ""
        threadType = product?.threadType
        thicknessText = product?.thicknessMm.map(Gauge.millimeters) ?? ""
        color = product?.color ?? ""
        stone = product?.stone ?? ""
        supplier = product?.supplier ?? ""
        description = product?.description ?? ""
        price = product?.price ?? 0
        cost = product?.cost
        unit = product?.unitLabel ?? ProductLimits.defaultUnit
        photos = product?.photos ?? []
        serviceIds = product?.serviceIds ?? []
        active = product?.active ?? true
        sizes = product?.variants.map(SizeDraft.init) ?? [SizeDraft()]
    }

    var isNew: Bool { productId == nil }
    var isJewelry: Bool { kind == .jewelry }
    var unitLabel: String { unit.nonEmpty ?? ProductLimits.defaultUnit }

    /// Parsed thickness; `nil` when the field is empty or not a number.
    var thicknessMm: Double? { Self.parseThickness(thicknessText) }

    /// «1.2», «1,2 мм» → 1.2 (`Gauge.parse`); a gauge from the studio's table is accepted too: «16G» → 1.2.
    static func parseThickness(_ text: String) -> Double? {
        let value = text.trimmed
        if let last = value.last, last == "G" || last == "g", let gauge = Int(String(value.dropLast()).trimmed) {
            return Gauge.table.first { $0.gauge == gauge }?.mm
        }
        return Gauge.parse(value)
    }

    /// Live hint under the thickness field: «1.2 мм (16G)».
    var thicknessHint: String? { thicknessMm.map(Gauge.thicknessText) }

    /// Two or more sizes: every one needs a name.
    var hasSeveralSizes: Bool { sizes.count > 1 }

    /// The sizes editor is for jewelry; a consumable shows it only to fix extra sizes left after a kind switch.
    var showsSizesEditor: Bool { isJewelry || hasSeveralSizes }

    // MARK: Validation

    var nameMessage: String? { name.trimmed.isEmpty ? "Укажите название." : nil }
    var unitMessage: String? { unit.trimmed.isEmpty ? "Укажите единицу измерения." : nil }

    var thicknessMessage: String? {
        guard isJewelry, !thicknessText.trimmed.isEmpty else { return nil }
        guard let mm = thicknessMm else { return "Толщина — миллиметры (1.2) или калибр (16G)." }
        return mm > ProductLimits.maxThicknessMm ? "Толщина — не больше 30 мм." : nil
    }

    /// Colour and stone (jewelry only).
    var appearanceMessage: String? {
        guard isJewelry else { return nil }
        return Self.lengthMessage("Цвет", color) ?? Self.lengthMessage("Камень", stone)
    }

    var supplierMessage: String? { Self.lengthMessage("Поставщик", supplier) }

    var attributesMessage: String? { appearanceMessage ?? supplierMessage }

    private static func lengthMessage(_ title: String, _ value: String) -> String? {
        guard value.trimmed.count > ProductLimits.maxAttributeLength else { return nil }
        return "\(title) — не длиннее \(ProductLimits.maxAttributeLength) символов."
    }

    var sizesMessage: String? {
        if sizes.isEmpty { return "Добавьте хотя бы один размер." }
        if !isJewelry && hasSeveralSizes {
            return "У расходника только один размер — удалите лишние или выберите тип «Украшение»."
        }
        if sizes.count > ProductLimits.maxSizes { return "Не больше \(ProductLimits.maxSizes) размеров." }
        if hasSeveralSizes && sizes.contains(where: { $0.name.trimmed.isEmpty }) {
            return "Укажите название у каждого размера."
        }
        if let duplicate = Self.firstDuplicate(sizes.map(\.name)) {
            return "Размер «\(duplicate)» указан дважды."
        }
        return nil
    }

    var photosMessage: String? {
        photos.count > ProductLimits.maxPhotos ? "Не больше \(ProductLimits.maxPhotos) фото." : nil
    }

    var servicesMessage: String? {
        isJewelry && serviceIds.count > ProductLimits.maxServices ? "Не больше \(ProductLimits.maxServices) услуг." : nil
    }

    /// Why «Сохранить» is disabled (the first problem), or `nil` when the card can be saved.
    var validationMessage: String? {
        nameMessage ?? unitMessage ?? thicknessMessage ?? attributesMessage ?? sizesMessage ?? photosMessage ?? servicesMessage
    }

    var canSave: Bool { validationMessage == nil }

    /// The first name that repeats (trimmed, case- and «ё»-insensitive); blank names are not compared.
    private static func firstDuplicate(_ names: [String]) -> String? {
        var seen = Set<String>()
        for name in names {
            let key = InventoryFilter.normalized(name)
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted { return name.trimmed }
        }
        return nil
    }

    // MARK: Body

    /// `POST /products` / `PATCH /products/:id`. Sizes keep the list order; removed ones are simply left out
    /// (the server deletes them, or archives those with history). Jewelry-only fields are cleared for a consumable.
    var body: ProductBody {
        ProductBody(
            kind: kind,
            name: name.trimmed,
            sku: Nullable(sku.nonEmpty),
            category: Nullable(category.nonEmpty),
            material: Nullable(material.nonEmpty),
            threadType: Nullable(isJewelry ? threadType : nil),
            thicknessMm: Nullable(isJewelry ? thicknessMm : nil),
            color: Nullable(isJewelry ? color.nonEmpty : nil),
            stone: Nullable(isJewelry ? stone.nonEmpty : nil),
            supplier: Nullable(supplier.nonEmpty),
            description: Nullable(description.nonEmpty),
            price: max(0, price),
            cost: Nullable(cost.map { max(0, $0) }),
            unit: unit.trimmed,
            photos: photos,
            serviceIds: isJewelry ? serviceIds : [],
            active: active,
            variants: sizes.map(\.body)
        )
    }
}

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
