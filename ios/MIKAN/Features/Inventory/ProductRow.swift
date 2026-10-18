import SwiftUI

/// Stock list row: cover, name, material / thickness, price, size chips with their stock, total stock — or the
/// availability of a consumable tracked as «есть / нет».
struct ProductRow: View {
    let product: Product
    /// The size the list is filtered by; its chip is outlined.
    var highlightedSize: String?

    private static let thumbnailSize: CGFloat = 56
    private static let spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: Self.spacing) {
                ProductThumbnail(path: product.photoUrl, size: Self.thumbnailSize)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.headline)
                        .lineLimit(2)
                    if !product.detailLine.isEmpty {
                        Text(product.detailLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if showsPrice || !product.active {
                        HStack(spacing: 6) {
                            if showsPrice {
                                Text(product.priceText).font(.subheadline).monospacedDigit()
                            }
                            if !product.active {
                                StatusBadge(text: "Скрыт", color: .gray)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                if product.isPresenceTracked {
                    PresenceBadge(status: product.presenceStatus ?? .ok)
                } else {
                    QuantityBadge(quantity: product.quantity, unit: product.unitLabel, isLow: product.lowStock)
                }
            }
            // Under the text column and the stock badge: room for more sizes per line.
            if product.hasSeveralSizes && !product.isPresenceTracked {
                StockSizeChips(product: product, highlightedSize: highlightedSize)
                    .padding(.leading, Self.thumbnailSize + Self.spacing)
            }
        }
        .opacity(product.active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private var showsPrice: Bool { product.priceRange.upperBound > 0 }
}

/// How full a size is: out of stock, at or below its minimum, or enough.
nonisolated enum StockLevel: Hashable, Sendable {
    case out
    case low
    case enough

    init(quantity: Int, isLow: Bool) {
        if quantity <= 0 {
            self = .out
        } else {
            self = isLow ? .low : .enough
        }
    }

    init(_ variant: ProductVariant) {
        self.init(quantity: variant.quantity, isLow: variant.lowStock)
    }
}

extension StockLevel {
    var color: Color {
        switch self {
        case .out: .red
        case .low: .orange
        case .enough: .secondary
        }
    }

    /// Spoken after the size's stock.
    var accessibilityText: String? {
        switch self {
        case .out: "нет в наличии"
        case .low: "мало"
        case .enough: nil
        }
    }
}

/// «6 мм · 4» chips that wrap; empty sizes are red, low ones orange.
struct StockSizeChips: View {
    let product: Product
    var highlightedSize: String?

    private static let maxChips = 12

    var body: some View {
        InventoryFlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(product.variants.prefix(Self.maxChips)) { variant in
                chip(variant)
            }
            if product.variants.count > Self.maxChips {
                Text("+\(product.variants.count - Self.maxChips)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ variant: ProductVariant) -> some View {
        let level = StockLevel(variant)
        let isHighlighted = highlightedSize.map {
            InventoryFilter.normalized($0) == InventoryFilter.normalized(variant.name)
        } ?? false
        return HStack(spacing: 3) {
            Text(InventoryText.sizeTitle(variant.name))
            Text("·").foregroundStyle(.tertiary)
            Text("\(variant.quantity)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(level == .enough ? Color.primary : level.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(level.color.opacity(level == .enough ? 0.12 : 0.15), in: .capsule)
        .overlay {
            if isHighlighted {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [InventoryText.sizeTitle(variant.name), "\(variant.quantity) \(product.unitLabel)", level.accessibilityText]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

/// Wraps its children onto new lines when they do not fit the width.
struct InventoryFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#if DEBUG
#Preview {
    List {
        ProductRow(product: PreviewData.labret, highlightedSize: "8 мм")
        ProductRow(product: PreviewData.ring)
        ProductRow(product: PreviewData.needles)
        ProductRow(product: PreviewData.antiseptic)
        ProductRow(product: PreviewData.spray)
    }
    .previewEnvironment()
}
#endif
