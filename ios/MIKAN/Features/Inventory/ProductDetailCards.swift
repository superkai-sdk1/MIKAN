import SwiftUI

// Cards of the product screen: photo gallery, sizes with their stock, characteristics.

/// Paged photos under the navigation bar; a tap opens the full-screen viewer.
struct ProductGallery: View {
    @Environment(APIClient.self) private var api
    let paths: [String]
    let onOpen: (Int) -> Void

    @State private var selection = 0

    private static let height: CGFloat = 320

    var body: some View {
        Group {
            if paths.isEmpty {
                placeholder
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                        Button {
                            onOpen(index)
                        } label: {
                            page(path)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .accessibilityLabel("Фото \(index + 1) из \(paths.count)")
                        .accessibilityHint("Открыть на весь экран")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: paths.count > 1 ? .always : .never))
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .backgroundExtensionEffect()
        .onChange(of: paths) { _, newPaths in
            selection = min(selection, max(0, newPaths.count - 1))
        }
    }

    private func page(_ path: String) -> some View {
        AsyncImage(url: api.mediaURL(for: path), transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else if phase.error != nil {
                placeholderContent(symbol: "photo.badge.exclamationmark")
            } else {
                placeholderContent(symbol: nil)
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(.rect)
    }

    private var placeholder: some View {
        placeholderContent(symbol: "sparkles")
            .accessibilityHidden(true)
    }

    private func placeholderContent(symbol: String?) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.mandarinLight.opacity(0.5), Theme.mandarin.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                ProgressView()
            }
        }
    }
}

/// «Остаток»: the stock of all sizes with the low badge and the minimum.
struct ProductStockCard: View {
    let product: Product

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.hasSeveralSizes ? "Остаток всех размеров" : "Остаток")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(InventoryText.quantity(product.quantity, unit: product.unitLabel))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(product.lowStock ? Color.red : Color.primary)
                    .contentTransition(.numericText(value: Double(product.quantity)))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if product.lowStock {
                    StatusBadge(text: lowStockTitle, color: .red, systemImage: "exclamationmark.triangle.fill")
                }
                Text("Минимум: \(InventoryText.quantity(product.minQuantity, unit: product.unitLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    /// «Мало», or «Мало: 8 мм, 10 мм» for a product with sizes.
    private var lowStockTitle: String {
        guard product.hasSeveralSizes else { return "Мало" }
        let names = product.lowVariants.map { InventoryText.sizeTitle($0.name) }
        guard names.count > 2 else { return "Мало: " + names.joined(separator: ", ") }
        return "Мало: " + Plural.count(names.count, one: "размер", few: "размера", many: "размеров")
    }
}

/// «Размеры»: stock, minimum and own SKU / price of every size. A tap offers the operations for that size.
struct ProductSizesCard: View {
    let product: Product
    let onOperation: (MovementType, ProductVariant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Размеры").font(.headline)
                Spacer()
                if !product.lowVariants.isEmpty {
                    Text("мало: \(product.lowVariants.count) из \(product.variants.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            ForEach(product.variants) { variant in
                Menu {
                    Section(InventoryText.sizeTitle(variant.name)) {
                        ForEach(MovementType.manual(for: product.kind)) { type in
                            Button(type.title, systemImage: type.symbol) { onOperation(type, variant) }
                        }
                    }
                } label: {
                    ProductSizeStockRow(variant: variant, unit: product.unitLabel)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Приход, списание или пересчёт этого размера")
                if variant.id != product.variants.last?.id { Divider() }
            }
        }
        .cardStyle()
    }
}

/// One size in the «Размеры» card: name with the low / out badge, own article and price, stock and minimum.
struct ProductSizeStockRow: View {
    let variant: ProductVariant
    let unit: String

    var body: some View {
        let level = StockLevel(variant)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(InventoryText.sizeTitle(variant.name))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    switch level {
                    case .out: StatusBadge(text: "Нет", color: .red)
                    case .low: StatusBadge(text: "Мало", color: .orange)
                    case .enough: EmptyView()
                    }
                }
                if let details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(InventoryText.quantity(variant.quantity, unit: unit))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(level == .enough ? Color.primary : level.color)
                Text("мин. \(variant.minQuantity)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// Own article and price of the size: «арт. LB-12-10 · 1 700 ₽».
    private var details: String? {
        let parts = [
            variant.sku.nonEmpty.map { "арт. \($0)" },
            variant.price.map { Money.format($0) },
        ]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

/// Material, fastening, thickness, colour, stone, supplier, suitable services, prices and markup.
struct ProductCharacteristicsCard: View {
    let product: Product
    /// Names of the linked catalog services.
    let serviceNames: [String]

    var body: some View {
        if hasAttributes || hasPrices {
            VStack(alignment: .leading, spacing: 10) {
                Text(hasAttributes ? "Характеристики" : "Цена").font(.headline)
                if hasAttributes {
                    row("Материал", product.material.nonEmpty)
                    row("Резьба", product.threadType?.title)
                    row("Толщина", product.thicknessText)
                    row("Цвет", product.color.nonEmpty)
                    row("Камень", product.stone.nonEmpty)
                    row("Поставщик", product.supplier.nonEmpty)
                    if !serviceNames.isEmpty {
                        row("Подходит для", serviceNames.joined(separator: ", "))
                    }
                    if hasPrices { Divider() }
                }
                row("Цена продажи", product.price > 0 ? Money.format(product.price) : nil)
                row("Себестоимость", product.cost.map(Money.format))
                row("Наценка", ProductMarkup.text(price: product.price, cost: product.cost))
                if !ownPricedSizes.isEmpty {
                    Divider()
                    Text("Цены размеров").font(.subheadline.weight(.semibold))
                    ForEach(ownPricedSizes) { variant in
                        sizePriceRow(variant)
                    }
                }
            }
            .cardStyle()
        }
    }

    private var hasPrices: Bool { product.price > 0 || product.cost != nil || !ownPricedSizes.isEmpty }

    private var hasAttributes: Bool {
        let values: [String?] = [
            product.material.nonEmpty, product.threadType?.title, product.thicknessText,
            product.color.nonEmpty, product.stone.nonEmpty, product.supplier.nonEmpty,
        ]
        return values.contains { $0 != nil } || !serviceNames.isEmpty
    }

    /// Sizes with their own price or cost.
    private var ownPricedSizes: [ProductVariant] {
        product.variants.filter { $0.price != nil || $0.cost != nil }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title) {
                Text(value).multilineTextAlignment(.trailing)
            }
            .monospacedDigit()
        }
    }

    private func sizePriceRow(_ variant: ProductVariant) -> some View {
        let price = product.price(of: variant)
        let cost = product.cost(of: variant)
        let parts = [
            price > 0 ? Money.format(price) : nil,
            cost.map { "себест. \(Money.format($0))" },
            ProductMarkup.text(price: price, cost: cost),
        ]
        return LabeledContent(InventoryText.sizeTitle(variant.name)) {
            Text(parts.compactMap { $0 }.joined(separator: "\n"))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
    }
}
