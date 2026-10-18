import SwiftUI

/// «Совместимые украшения» of the service editor: the linked pieces as a strip of tiles; «Добавить» opens the
/// jewelry picker. The bot offers these pieces to clients who ask about the procedure.
struct ServiceJewelryEditorSection: View {
    @Binding var jewelryIds: [Int]
    /// Jewelry and consumables of the warehouse (`APIClient.serviceLinkProducts`).
    let stock: Remote<[Product]>
    let retry: () async -> Void

    @State private var showsPicker = false

    private var products: [Product] { stock.value ?? [] }
    private var linked: [Product] { ServiceLinkedProducts.resolve(jewelryIds, in: products) }
    private var missing: [Int] { stock.value == nil ? [] : ServiceLinkedProducts.missing(jewelryIds, in: products) }

    var body: some View {
        Section {
            if !jewelryIds.isEmpty {
                ServiceStockState(stock: stock, retry: retry) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(linked) { product in
                                JewelryLinkTile(product: product) {
                                    withAnimation(.snappy) { jewelryIds = ServiceJewelryLinks.removing(product.id, from: jewelryIds) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    if !missing.isEmpty {
                        MissingLinksRow(count: missing.count) {
                            jewelryIds = jewelryIds.filter { !missing.contains($0) }
                        }
                    }
                }
            }
            Button(
                jewelryIds.isEmpty ? "Добавить украшения" : "Изменить список",
                systemImage: jewelryIds.isEmpty ? "plus.circle.fill" : "checklist"
            ) {
                showsPicker = true
            }
            .disabled(stock.value == nil)
            .sheet(isPresented: $showsPicker) {
                ServiceProductPicker(
                    kind: .jewelry,
                    products: products,
                    selected: jewelryIds,
                    title: "Совместимые украшения",
                    footer: "Отметьте украшения, которые ставят на эту процедуру. Скрытые украшения видны здесь, только если уже выбраны.",
                    limit: ServiceLimits.maxJewelry
                ) { ids in
                    jewelryIds = ids
                }
            }
        } header: {
            ServiceCountHeader(title: "Совместимые украшения", count: jewelryIds.count)
        } footer: {
            if let message = ServiceJewelryLinks.validationMessage(jewelryIds) {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Бот предложит эти украшения клиенту, который спрашивает про эту процедуру: к «Хеликсу» — подходящие кольца и лабреты. Крестик на плитке убирает украшение.")
            }
        }
    }
}

/// «Расход на процедуру»: the consumables one procedure uses with their units; presence consumables are only
/// marked as used. Swipe a row to remove it.
struct ServiceNormsEditorSection: View {
    @Binding var consumables: [ServiceConsumable]
    let stock: Remote<[Product]>
    let retry: () async -> Void

    @State private var showsPicker = false

    private var products: [Product] { stock.value ?? [] }

    var body: some View {
        Section {
            if !consumables.isEmpty {
                ServiceStockState(stock: stock, retry: retry) {
                    ForEach(consumables, id: \.productId) { norm in
                        ServiceNormEditorRow(
                            product: products.first { $0.id == norm.productId },
                            quantity: quantityBinding(norm.productId, current: norm.quantity)
                        )
                        .swipeActions(edge: .trailing) {
                            Button("Убрать", systemImage: "trash", role: .destructive) {
                                withAnimation(.snappy) {
                                    consumables = ServiceConsumptionNorms.removing(norm.productId, from: consumables)
                                }
                            }
                        }
                    }
                }
            }
            Button("Добавить расходник", systemImage: "plus.circle.fill") { showsPicker = true }
                .disabled(stock.value == nil)
                .sheet(isPresented: $showsPicker) {
                    ServiceProductPicker(
                        kind: .consumable,
                        products: products,
                        selected: consumables.map(\.productId),
                        title: "Расход на процедуру",
                        footer: "Отметьте расходники, которые уходят на одну процедуру; количество задаётся в карточке услуги.",
                        limit: ServiceLimits.maxConsumables
                    ) { ids in
                        consumables = ServiceConsumptionNorms.applying(selection: Set(ids), to: consumables, catalogOrder: ids)
                    }
                }
        } header: {
            ServiceCountHeader(title: "Расход на процедуру", count: consumables.count)
        } footer: {
            if let message = ServiceConsumptionNorms.validationMessage(consumables) {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Сколько уходит на одну процедуру. При завершении записи норма спишется со склада; расходники с учётом «есть / нет» не списываются, а отмечаются как используемые. Смахните строку влево, чтобы убрать её.")
            }
        }
    }

    private func quantityBinding(_ productId: Int, current: Int) -> Binding<Int> {
        Binding(
            get: { consumables.first { $0.productId == productId }?.quantity ?? current },
            set: { consumables = ServiceConsumptionNorms.settingQuantity($0, of: productId, in: consumables) }
        )
    }
}

/// One consumable of the norm: a stepper of units, or «используется» for a presence consumable.
private struct ServiceNormEditorRow: View {
    /// `nil` when the consumable is gone from the warehouse.
    let product: Product?
    @Binding var quantity: Int

    var body: some View {
        if let product, product.isPresenceTracked {
            HStack(spacing: 12) {
                label(product)
                Spacer(minLength: 8)
                StatusBadge(text: "используется", color: .secondary)
            }
        } else {
            Stepper(value: $quantity, in: ServiceLimits.normQuantityRange) {
                HStack(spacing: 12) {
                    label(product)
                    Spacer(minLength: 8)
                    Text(ServiceLinkText.norm(quantity: quantity, product: product))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(quantity)))
                        .animation(.snappy, value: quantity)
                }
            }
        }
    }

    private func label(_ product: Product?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(product?.name ?? "Расходник не найден")
                .foregroundStyle(product == nil ? .secondary : .primary)
            if let product {
                ProductStockLine(product: product)
            }
        }
    }
}

// MARK: - Shared pieces

extension StockAvailability {
    /// Green in stock, orange running low, red out of stock.
    var color: Color {
        switch self {
        case .inStock: .green
        case .low: .orange
        case .out: .red
        }
    }
}

/// Linked piece of jewelry: photo, name, price and the sizes in stock. With `onRemove` it shows a remove button
/// (editor); without it the tile is read-only (card).
struct JewelryLinkTile: View {
    let product: Product
    var onRemove: (() -> Void)?

    static let size: CGFloat = 96
    /// Minimum touch target for the remove button over the photo.
    private static let removeTarget: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProductThumbnail(path: product.photoUrl, size: Self.size, placeholderSymbol: CatalogSection.jewelry.symbol)
                .overlay(alignment: .topTrailing) { removeButton }
            Text(product.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
            Text(product.priceText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Circle()
                    .fill(StockAvailability(product).color)
                    .frame(width: 6, height: 6)
                Text(ServiceLinkText.sizesInStock(product))
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(width: Self.size)
        .opacity(product.active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(product.priceText), \(ServiceLinkText.sizesInStock(product))")
    }

    @ViewBuilder
    private var removeButton: some View {
        if let onRemove {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(3)
                    .frame(width: Self.removeTarget, height: Self.removeTarget, alignment: .topTrailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Убрать «\(product.name)»")
        }
    }
}

/// Section header with the number of linked items on the right.
struct ServiceCountHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)").monospacedDigit()
            }
        }
    }
}

/// The links' content once the warehouse is loaded; a spinner or the error with «Повторить» before that.
struct ServiceStockState<Content: View>: View {
    let stock: Remote<[Product]>
    let retry: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if stock.value != nil {
            content()
        } else if let failure = stock.failure {
            VStack(alignment: .leading, spacing: 8) {
                Text(failure).foregroundStyle(.secondary)
                Button("Повторить") { Task { await retry() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

/// Links to products that are no longer in the warehouse.
private struct MissingLinksRow: View {
    let count: Int
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Label(
                "\(Plural.count(count, one: "украшение", few: "украшения", many: "украшений")) нет на складе",
                systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(.orange)
            Spacer(minLength: 8)
            Button("Убрать", action: onRemove)
                .buttonStyle(.borderless)
        }
    }
}
