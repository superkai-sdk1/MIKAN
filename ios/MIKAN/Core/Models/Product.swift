import Foundation

nonisolated enum ProductKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jewelry
    case consumable
    /// Other things sold at the POS (aftercare sprays, gift cards…).
    case goods

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jewelry: "Украшения"
        case .consumable: "Расходники"
        case .goods: "Товары"
        }
    }

    var singularTitle: String {
        switch self {
        case .jewelry: "Украшение"
        case .consumable: "Расходник"
        case .goods: "Товар"
        }
    }

    /// Sold at the POS (consumables are only used in procedures).
    var isSold: Bool { self != .consumable }
}

/// How the jewelry's top is fastened.
nonisolated enum ThreadType: String, Codable, CaseIterable, Identifiable, Sendable {
    case internalThread = "internal"
    case externalThread = "external"
    case threadless

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalThread: "Внутренняя резьба"
        case .externalThread: "Внешняя резьба"
        case .threadless: "Безрезьбовое (push-pin)"
        }
    }

    /// For detail lines: «внутр. резьба».
    var shortTitle: String {
        switch self {
        case .internalThread: "внутр. резьба"
        case .externalThread: "внешн. резьба"
        case .threadless: "push-pin"
        }
    }
}

/// Materials the editor suggests (the field itself is free text).
nonisolated enum ProductMaterial {
    static let presets = [
        "Титан ASTM F136",
        "Титан ASTM F1295",
        "Хирургическая сталь 316L",
        "Сталь ASTM F138",
        "Золото 585",
        "Золото 750",
        "Ниобий",
        "Биопласт (PTFE)",
        "Стекло",
    ]
}

/// One size of a product («8 мм») with its own stock. A product without sizes has one variant named "".
nonisolated struct ProductVariant: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    /// Own article; `nil` = the product's.
    var sku: String?
    /// Own selling price; `nil` = the product's.
    var price: Int?
    /// Own cost; `nil` = the product's.
    var cost: Int?
    /// Maintained only through stock movements.
    var quantity: Int
    var minQuantity: Int
    /// Derived: `quantity <= minQuantity`.
    var lowStock: Bool

    var isAvailable: Bool { quantity > 0 }
    /// The size has a name (a product without sizes has one unnamed variant).
    var isNamed: Bool { !name.trimmed.isEmpty }
}

nonisolated struct Product: Hashable, Identifiable, Sendable {
    let id: Int
    var kind: ProductKind
    var name: String
    var sku: String?
    var category: String?
    var material: String?
    var threadType: ThreadType?
    /// Bar / wire thickness, mm.
    var thicknessMm: Double?
    /// Metal / anodizing colour.
    var color: String?
    /// Insert: «Фианит», «Опал».
    var stone: String?
    var supplier: String?
    var description: String?
    var price: Int
    var cost: Int?
    var unit: String?
    /// Server-relative paths; the first is the cover.
    var photos: [String]
    /// Catalog services (piercing zones) the jewelry suits.
    var serviceIds: [Int]
    /// Consumables only: counted, or just «есть / заканчивается / нет».
    var stockMode: StockMode = .quantity
    /// Set in `presence` mode.
    var presenceStatus: PresenceStatus?
    var active: Bool
    /// Sizes with their own stock, in the order staff arranged them (always at least one).
    var variants: [ProductVariant]
    let createdAt: Date
    var updatedAt: Date

    /// `variants: nil` builds the single variant (named `size`) of a product without sizes — also how a server that
    /// predates sizes is read; `photos: nil` takes `photoUrl` as the only photo.
    init(
        id: Int,
        kind: ProductKind,
        name: String,
        sku: String?,
        category: String?,
        material: String?,
        threadType: ThreadType? = nil,
        thicknessMm: Double? = nil,
        color: String? = nil,
        stone: String? = nil,
        supplier: String? = nil,
        size: String?,
        description: String?,
        price: Int,
        cost: Int?,
        quantity: Int,
        minQuantity: Int,
        unit: String?,
        photos: [String]? = nil,
        photoUrl: String?,
        serviceIds: [Int] = [],
        active: Bool,
        lowStock: Bool,
        variants: [ProductVariant]? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sku = sku
        self.category = category
        self.material = material
        self.threadType = threadType
        self.thicknessMm = thicknessMm
        self.color = color
        self.stone = stone
        self.supplier = supplier
        self.description = description
        self.price = price
        self.cost = cost
        self.unit = unit
        self.photos = photos ?? photoUrl.nonEmpty.map { [$0] } ?? []
        self.serviceIds = serviceIds
        self.active = active
        self.variants = variants ?? [ProductVariant(
            id: id, name: size ?? "", sku: nil, price: nil, cost: nil,
            quantity: quantity, minQuantity: minQuantity, lowStock: lowStock
        )]
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Totals (derived from the sizes)

    /// Stock of all sizes.
    var quantity: Int { variants.reduce(0) { $0 + $1.quantity } }
    var minQuantity: Int { variants.reduce(0) { $0 + $1.minQuantity } }
    /// Tracked as «есть / нет» instead of units.
    var isPresenceTracked: Bool { stockMode == .presence }
    /// Needs restocking: a presence consumable not marked «есть», or some size at or below its minimum.
    var lowStock: Bool {
        isPresenceTracked ? presenceStatus != .ok : variants.contains(where: \.lowStock)
    }
    /// Some size can be sold.
    var isAvailable: Bool { variants.contains(where: \.isAvailable) }
    var availableVariants: [ProductVariant] { variants.filter(\.isAvailable) }
    var lowVariants: [ProductVariant] { variants.filter(\.lowStock) }

    // MARK: Sizes

    /// Selling it needs a size choice.
    var hasSeveralSizes: Bool { variants.count > 1 }
    var namedVariants: [ProductVariant] { variants.filter(\.isNamed) }
    /// Size names joined with ", " (what older builds called `size`); `nil` when no size has a name.
    var size: String? {
        let names = namedVariants.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// «6 мм · 8 мм · 10 мм».
    var sizesSummary: String { namedVariants.map(\.name).joined(separator: " · ") }

    func variant(id: Int) -> ProductVariant? { variants.first { $0.id == id } }

    func price(of variant: ProductVariant) -> Int { variant.price ?? price }
    func cost(of variant: ProductVariant) -> Int? { variant.cost ?? cost }
    func sku(of variant: ProductVariant) -> String? { variant.sku.nonEmpty ?? sku.nonEmpty }

    /// Receipt / history name of a size: «Лабрет — 8 мм», just «Лабрет» without a size (as the server names sale items).
    func lineName(variant: ProductVariant?) -> String {
        guard let size = variant?.name.nonEmpty else { return name }
        return "\(name) — \(size)"
    }

    /// Lowest and highest selling price over the sizes.
    var priceRange: ClosedRange<Int> {
        let prices = variants.map(price(of:))
        return (prices.min() ?? price)...(prices.max() ?? price)
    }

    /// «1 500 ₽», or «от 1 500 ₽» when sizes differ in price.
    var priceText: String {
        let range = priceRange
        return Money.format(range.lowerBound, from: range.lowerBound != range.upperBound)
    }

    // MARK: Text

    var unitLabel: String { unit.nonEmpty ?? "шт" }

    /// Server-relative path of the cover photo.
    var photoUrl: String? { photos.first }

    /// «1.2 мм (16G)».
    var thicknessText: String? { thicknessMm.map(Gauge.thicknessText) }

    /// "Титан G23 · 1.2 мм (16G) · 1.2×8 мм" — material, thickness and the size of a single-size product.
    var detailLine: String {
        let singleSize = hasSeveralSizes ? nil : variants.first?.name.nonEmpty
        return [material.nonEmpty, thicknessText, singleSize].compactMap { $0 }.joined(separator: " · ")
    }
}

nonisolated extension Product: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, sku, category, material, threadType, thicknessMm, color, stone, supplier
        case description, price, cost, unit, photos, photoUrl, serviceIds, stockMode, presenceStatus, active, variants
        case size, quantity, minQuantity, lowStock, createdAt, updatedAt
    }

    /// Tolerates a server that predates sizes and jewelry attributes: its single stock becomes one variant.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .id)
        var variants = try c.decodeIfPresent([ProductVariant].self, forKey: .variants) ?? []
        if variants.isEmpty {
            variants = [ProductVariant(
                id: id,
                name: try c.decodeIfPresent(String.self, forKey: .size) ?? "",
                sku: nil, price: nil, cost: nil,
                quantity: try c.decode(Int.self, forKey: .quantity),
                minQuantity: try c.decode(Int.self, forKey: .minQuantity),
                lowStock: try c.decode(Bool.self, forKey: .lowStock)
            )]
        }
        let photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        let stockMode = try c.decodeIfPresent(String.self, forKey: .stockMode).flatMap(StockMode.init(rawValue:)) ?? .quantity
        let presenceStatus = try c.decodeIfPresent(String.self, forKey: .presenceStatus).flatMap(PresenceStatus.init(rawValue:))
        self.init(
            id: id,
            kind: try c.decode(ProductKind.self, forKey: .kind),
            name: try c.decode(String.self, forKey: .name),
            sku: try c.decodeIfPresent(String.self, forKey: .sku),
            category: try c.decodeIfPresent(String.self, forKey: .category),
            material: try c.decodeIfPresent(String.self, forKey: .material),
            threadType: try c.decodeIfPresent(String.self, forKey: .threadType).flatMap(ThreadType.init(rawValue:)),
            thicknessMm: try c.decodeIfPresent(Double.self, forKey: .thicknessMm),
            color: try c.decodeIfPresent(String.self, forKey: .color),
            stone: try c.decodeIfPresent(String.self, forKey: .stone),
            supplier: try c.decodeIfPresent(String.self, forKey: .supplier),
            size: nil,
            description: try c.decodeIfPresent(String.self, forKey: .description),
            price: try c.decode(Int.self, forKey: .price),
            cost: try c.decodeIfPresent(Int.self, forKey: .cost),
            quantity: 0,
            minQuantity: 0,
            unit: try c.decodeIfPresent(String.self, forKey: .unit),
            photos: try c.decodeIfPresent([String].self, forKey: .photos) ?? photoUrl.nonEmpty.map { [$0] } ?? [],
            photoUrl: nil,
            serviceIds: try c.decodeIfPresent([Int].self, forKey: .serviceIds) ?? [],
            active: try c.decode(Bool.self, forKey: .active),
            lowStock: false,
            variants: variants,
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt)
        )
        self.stockMode = stockMode
        self.presenceStatus = stockMode == .presence ? (presenceStatus ?? .ok) : nil
    }

    /// The API shape, derived fields included.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(sku, forKey: .sku)
        try c.encode(category, forKey: .category)
        try c.encode(material, forKey: .material)
        try c.encode(threadType, forKey: .threadType)
        try c.encode(thicknessMm, forKey: .thicknessMm)
        try c.encode(color, forKey: .color)
        try c.encode(stone, forKey: .stone)
        try c.encode(supplier, forKey: .supplier)
        try c.encode(description, forKey: .description)
        try c.encode(price, forKey: .price)
        try c.encode(cost, forKey: .cost)
        try c.encode(unit, forKey: .unit)
        try c.encode(photos, forKey: .photos)
        try c.encode(photoUrl, forKey: .photoUrl)
        try c.encode(serviceIds, forKey: .serviceIds)
        try c.encode(stockMode, forKey: .stockMode)
        try c.encode(presenceStatus, forKey: .presenceStatus)
        try c.encode(active, forKey: .active)
        try c.encode(variants, forKey: .variants)
        try c.encode(size, forKey: .size)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(minQuantity, forKey: .minQuantity)
        try c.encode(lowStock, forKey: .lowStock)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Body-jewelry thickness: millimetres with the American gauge piercers use.
nonisolated enum Gauge {
    /// mm → gauge, as listed in docs/API.md.
    static let table: [(mm: Double, gauge: Int)] = [
        (0.8, 20), (1.0, 18), (1.2, 16), (1.6, 14), (2.0, 12), (2.5, 10),
        (3.2, 8), (4.0, 6), (5.0, 4), (6.0, 2), (8.0, 0),
    ]

    /// «16G» for 1.2 mm; `nil` for a thickness without a standard gauge.
    static func label(forMillimeters mm: Double) -> String? {
        table.first { abs($0.mm - mm) < 0.05 }.map { "\($0.gauge)G" }
    }

    /// "1.2" — at most two decimals, a dot separator (as sizes are written in the studio), no trailing zeros.
    static func millimeters(_ mm: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), mm)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// «1.2 мм (16G)», «1.3 мм» — with no-break spaces, so a wrapped line never splits the thickness.
    static func thicknessText(_ mm: Double) -> String {
        let base = "\(millimeters(mm))\u{00A0}мм"
        guard let gauge = label(forMillimeters: mm) else { return base }
        return "\(base)\u{00A0}(\(gauge))"
    }

    /// Parses "1,2" / "1.2" / "1.2 мм" → 1.2; `nil` when there is no positive number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }
}

/// `DELETE /products/:id`: deleted for good (no history), or archived — hidden everywhere, with sales and movements
/// still naming it.
nonisolated struct ProductDeletionResult: Decodable, Hashable, Sendable {
    var deleted = false
    var archived = false
    /// Units written off first (`?writeOff=true`).
    var writtenOff = 0

    private enum CodingKeys: String, CodingKey { case deleted, archived, writtenOff }

    init(deleted: Bool = false, archived: Bool = false, writtenOff: Int = 0) {
        self.deleted = deleted
        self.archived = archived
        self.writtenOff = writtenOff
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deleted = try c.decode(.deleted, or: false)
        archived = try c.decode(.archived, or: false)
        writtenOff = try c.decode(.writtenOff, or: 0)
    }
}
