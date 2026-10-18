import SwiftUI

/// One size row of the size picker: name, price, stock and how many are already in the receipt.
nonisolated struct SizePickerOption: Identifiable, Equatable, Sendable {
    enum Stock: Equatable, Sendable {
        case inStock
        case low
        case out
    }

    let id: Int
    let title: String
    let price: Int
    let stock: Stock
    /// «4 шт», «Мало: 1 шт», «Нет в наличии».
    let stockText: String
    let inReceipt: Int
    /// Everything in stock is already in the receipt: one more would exceed the stock.
    let isStockInReceipt: Bool

    init(product: Product, variant: ProductVariant, inReceipt: Int) {
        id = variant.id
        title = variant.name.nonEmpty ?? "Без размера"
        price = product.price(of: variant)
        let count = "\(variant.quantity) \(product.unitLabel)"
        if !variant.isAvailable {
            stock = .out
            stockText = "Нет в наличии"
        } else if variant.lowStock {
            stock = .low
            stockText = "Мало: \(count)"
        } else {
            stock = .inStock
            stockText = count
        }
        self.inReceipt = inReceipt
        isStockInReceipt = variant.isAvailable && inReceipt >= variant.quantity
    }

    /// Out-of-stock sizes cannot be picked.
    var isAvailable: Bool { stock != .out }

    /// «В чеке: 2»; `nil` while the size is not in the receipt.
    var inReceiptText: String? { inReceipt > 0 ? "В чеке: \(inReceipt)" : nil }

    /// «8 мм, 1 500 ₽, мало: 1 шт, в чеке: 2».
    var accessibilityLabel: String {
        let parts = [title, Money.format(price), stockText.lowercased(), inReceiptText?.lowercased()]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    static func options(for product: Product, inReceipt: (Int) -> Int) -> [SizePickerOption] {
        product.variants.map { SizePickerOption(product: product, variant: $0, inReceipt: inReceipt($0.id)) }
    }
}

/// Picks the size of a jewelry piece or goods for the receipt: every size with its price and stock.
/// A tap adds one of that size and closes the sheet.
struct SizePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CartStore.self) private var cart
    let product: Product
    let onPick: (ProductVariant) -> Void

    private var options: [SizePickerOption] {
        SizePickerOption.options(for: product) { cart.quantity(ofVariant: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SizePickerHeader(product: product)
                }
                Section {
                    ForEach(options) { option in
                        Button {
                            pick(option)
                        } label: {
                            SizePickerRow(option: option)
                        }
                        .disabled(!option.isAvailable)
                        .accessibilityLabel(option.accessibilityLabel)
                        .accessibilityHint(option.isAvailable ? "Добавить в чек" : "Нет в наличии")
                    }
                } header: {
                    Text(ProductTileText.sizes(product.variants.count))
                } footer: {
                    Text(product.kind == .goods
                        ? "Нажмите на размер — один товар добавится в чек."
                        : "Нажмите на размер — одно украшение добавится в чек.")
                }
            }
            .navigationTitle("Выберите размер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ option: SizePickerOption) {
        guard option.isAvailable, let variant = product.variant(id: option.id) else { return }
        onPick(variant)
        dismiss()
    }
}

private struct SizePickerHeader: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(path: product.photoUrl, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.headline)
                if !product.detailLine.isEmpty {
                    Text(product.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(product.priceText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SizePickerRow: View {
    let option: SizePickerOption

    private var stockColor: Color {
        switch option.stock {
        case .inStock: .secondary
        case .low: .red
        case .out: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(option.stockText)
                        .foregroundStyle(stockColor)
                    if let inReceipt = option.inReceiptText {
                        Text("·").foregroundStyle(.tertiary)
                        Text(inReceipt)
                            .foregroundStyle(option.isStockInReceipt ? Color.orange : Color.accentColor)
                    }
                }
                .font(.caption.weight(.medium))
                .monospacedDigit()
            }
            Spacer(minLength: 8)
            MoneyText(option.price)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Image(systemName: option.isAvailable ? "plus.circle.fill" : "minus.circle")
                .font(.title3)
                .foregroundStyle(option.isAvailable ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .opacity(option.isAvailable ? 1 : 0.5)
    }
}

#if DEBUG
#Preview("Лабрет, 3 размера") {
    let state = PreviewData.appState()
    state.cart.add(product: PreviewData.labret, variant: PreviewData.labret.variants[1])
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            SizePickerSheet(product: PreviewData.labret) { _ in }
        }
        .appEnvironment(state)
}
#endif
